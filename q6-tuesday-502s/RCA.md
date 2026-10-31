# Q6 RCA：checkout 間歇性 502

## 結論
3 週前 PLAT-1204 把 nginx sidecar 的 keep-alive 從 75 秒改成 5 秒，比 LB 的 60 秒短。結果變成 pod 先把閒置連線關掉，LB 剛好在那一刻送請求進來，就收到 reset，自己回 502。請求根本沒進 app，所以 app 指標和 SLO 面板都看不到。

## 因果鏈
| 步驟 | 證據 |
|---|---|
| 1. 3 週前 keep-alive 從 75s 改成 5s，全 fleet 套用，標為無風險 | change-history。症狀也是約 3 週前開始，比 v2.41、v2.42 都早，所以不是這兩次 deploy |
| 2. 原本 75s 比 60s 長，閒置連線一定由 LB 先關；改成 5s 後變成 pod 先關 | lb-metrics：LB idle timeout 60s，有開 keep-alive |
| 3. LB 剛好在 pod 關閉時送出請求 → 連線被 reset → LB 回 502 | app-logs：14:21:03.112 關閉閒置超過 5s 的連線，6ms 後就有一筆失敗請求，而且沒有進 app。lb-metrics：502 由 LB 產生，約 90% 是 connection reset |
| 4. 中等負載、流量剛上升時最常發生：連線剛好閒置 5 秒左右的機會最多 | 「中等負載下略為惡化」、「跟著請求量上升」；CPU 沒超過 40%，不是資源不夠 |
| 5. 使用者重試會換一條連線，所以會成功 | 題目背景 |
| 6. 請求沒進 app → app 的 5xx 是平的 → SLO 面板只看 app 指標，一直顯示 99.98% → 服務團隊查了三週找不到 | dashboards；app-logs：失敗的請求完全沒有 app log |

假設：那行「closing idle connection」是 pod 端關掉 LB 那一側的連線（5s 正是新設定的值）。如果不是，第 3 步改用 LB access log 對時間來證明。

## 另一個也說得通的解釋
**pod 啟動或關閉時沒處理好**：擴縮容或重啟時，pod 還在 LB 名單裡就被關掉，或還沒準備好就開始收流量。一樣是 LB 回 502、請求沒進 app，也一樣跟流量變化有關。

先驗證 keep-alive，因為時間點吻合、log 裡的 5s 就是新值，而且改回去成本最低。分辨方法：
1. **對時間**：把 LB log 裡每筆 502 對上該 pod 的「關閉閒置連線」log。如果是 keep-alive 問題，大多數 502 在幾 ms 前都有關閉紀錄，各種 pod 都會有；如果是 pod 生命週期問題，502 會集中在剛啟動或正在關閉的 pod。
2. **canary**：只把一部分 checkout pod 改回 75s。如果是 keep-alive 問題，這批 pod 的 502 一小時內會接近 0；如果是 pod 生命週期問題，不會有差別。

已排除：
- **資源不夠**（隊友貼的 AI 答案）：CPU 沒超過 40%，失敗的請求根本沒進 app，錯誤是 reset 不是 timeout。加 replica 沒用，放寬 liveness 只會讓真的故障更晚被發現。
- **v2.41 / v2.42**：時間對不上。

剩下約 10% 的 502 不是 reset。修完之後如果還有，再用同樣方法檢查是不是 pod 生命週期的問題。

## 修法
1. **今天**：checkout 的 keep-alive 改回 75 秒（規則：一定要比 LB 的 60 秒長）。先 canary 再全部改。成功標準：502 回到 3 週前的水準。
2. **本週**：PLAT-1204 是全 fleet 改的，所有服務都要改回來。先查每個 LB 這三週的 502，找出其他沒人發現的受害服務。服務之間互相呼叫也可能有一樣的問題（例如 Go client 預設閒置 90 秒才關連線）。
3. **SLO 改從 LB 量**：把 LB 自己產生的錯誤也算進去，重算這三週真實的可用率。

## 怎麼避免再發生
- **CI 檢查 timeout 規則**：自動檢查 sidecar 的 keep-alive 一定比 LB idle timeout 長。PLAT-1204 在 PR 階段就會被擋下。
- **共用設定的改動不可能「無風險」**：base chart 的改動先上一個服務、一個 cluster，確認 LB 的 5xx 沒變化再全面上。
- **從使用者的角度量**：每個對外服務都要看 LB 層的錯誤率，不能只看 app 自己的指標。
