# Q1 決策：讓週末 on-call 撐得下去

**判讀**：48h 內 214 則 Slack、9 次 page，真事故只有 2 次，負擔主要來自告警本身。8/22 是縮影：真正的原因（node 記憶體）沒有告警，因為 `NodeMemoryPressure` 依賴的 recording rule 6 月被刪，之後它就不可能觸發；症狀（約 40 則重啟通知）讓值班 14:05 靜音頻道；14:31 才收到 page，又先 rollback 錯方向；15:40 再來一個假 page（`avg_over_time[6h]`，但本地只留 3h，queue 早已在消化）。

## 1. 讓 page 說真話，原因第一個 page（diff 在 `monitoring/`）
- 修好 dead 的 `NodeMemoryPressure`：改用 node-exporter 原始 metric，不再依賴會被改名的 recording rule。
- 新 page `NodesUnderMemoryPressure`（≥2 個 node 處於 kubelet MemoryPressure 達 5 分鐘），runbook 寫明「先擴 node group，不要先 rollback」。
- `PodRestartingTooOften` 改成每個 namespace 一則、持續 15 分鐘才通知；記憶體 page 期間用 inhibit 壓掉同 cluster 的重啟與記憶體 warning。
- `PaymentsQueueBacklogGrowing` 改為「> 10000 且沒有在下降」：消化中不 page，卡住不動仍會 page。
- 只進 Slack 的告警 `repeat_interval` 4h → 24h；page 維持 4h。
- promtool 測試 + `check.sh` + CI：8/22 每個情境各是一個 test case，同一份測試套在舊 rule 上會失敗。

**排第一的理由**：9 次 page 只對應 2 次真事故，214 則 Slack 絕大多數不需要動作，負擔大多在這裡。它完全在 SRE 手上、可回滾、今天就能驗證；不論下個週末出什麼事，值班先收到的都會是一個看得懂、有下一步的 page。

## 2. 移除反覆發生的原因：週六 13:30 的 data team batch job
8 月三次記憶體驅逐都在週末，三張週末 OOM ticket（OPS-311/317/328）也是記憶體。沒有 limits 的 pod 可以用到遠超過 requests 的記憶體，但 scheduler 和 cluster autoscaler 只看 requests，所以不會擴容，只能靠值班手動加 node。做法：先用遠端長期儲存查 8/22 13:30–15:10 各 namespace 的用量，確認假設；data team 依實測值設 requests/limits，並把排程移出比賽日尖峰；platform 在該 namespace 加 LimitRange/ResourceQuota 當預設護欄。本週六保底（SRE 自己能做）：13:00–16:00 對 co-3 node group 排程 +4 nodes（8/22 實際止血的量）。
**排第二的理由**：根因仍是假設，而且要 data team 配合；#1 不必等任何人。

**刻意延後**：API SLO 改 burn-rate（SLO 沒 owner；標準 6h 窗口超過 3h retention；1h/5m 的 14.4× 對 8/22 那種 2.1% 錯誤率要約 41 分鐘才 page，現在約 4 分鐘）、其餘約 330 條 rule 稽核、payments SLO、settlement consumer 卡住（OPS-331/337）、Quovix WAF 白名單（OPS-314/323/334，不在週末）。

**留下來的東西**：#1 的測試、CI 與 runbook。採用者：所有改 `rules/` 的人（PR 由 CI 擋）、週末值班（page 上的 runbook）。維護者：SRE team；在 lead 指派 alerting/SLO owner 前由我負責（`slo.md` 的 owner 是空的）。規則：新增或修改 critical 告警必須附 test case。

## 假設
1. 時間軸寫 10 分鐘約 40 則通知，但 `group_by: [alertname, cluster]` 加 `group_interval: 5m`，同一 cluster 10 分鐘最多約 3 則：要嘛線上設定與檔案不同（週一先用 `amtool config show` 比對），要嘛 40 是訊息裡的告警行數。我以檔案為準；聚合 + inhibit 兩種情況都有效。
2. 沒有 page 紀錄。12 條樣本只有 2 條 critical，我假設假 page 主要來自這兩條在 6 個 cluster 觸發。
3. 214 則的組成不明。24h repeat 的效果是推算（整個週末都在 firing 的 group 約 13 則），要用 Alertmanager log 或 Slack 匯出驗證。
4. `cluster` 標籤來自各 cluster Prometheus 的 external_labels（page 訊息有「cluster co-3」），inhibit 依賴它；kube-state-metrics 與 node-exporter 都有在收。
5. payments 門檻沿用 10000（沒有 payments SLO 可推），merge 前用遠端儲存回測過去 4 個週末。

## 給 Media 主管的回覆
> 每 10 秒一則的通知我不會做。8/22 我們的頻道 10 分鐘收到 40 則，值班同事 14:05 就把它靜音了，結果錯過真事故；20 分鐘的斷線每 10 秒一則就是 120 則，你們的頻道會走上同一條路。上個月的問題是沒有人收到，不是通知不夠多。已經改的：直播告警持續期間每 5 分鐘 @here 一次，恢復時也會通知。需要你決定的：斷線要不要 page 人？我建議 Media 在 paging 工具排自己的 on-call；如果要 SRE 週末接，我們要和 SRE lead 一起談。也請幫我確認上個月那次 `StreamSegmentStale` 有沒有觸發：如果送出這個 metric 的程序整個掛掉，metric 會消失，這條 rule 就不會觸發，那要修的是偵測，我們一起處理。
