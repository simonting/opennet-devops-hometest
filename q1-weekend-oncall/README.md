# Q1: Make Our Weekend On-Call Sustainable

- [`DECISION.md`](DECISION.md)：一頁決策文件。
- `monitoring/`：第 1 名變更的實際設定。第一個 commit 是題目提供的原樣（rule 節錄只多包了一層 `groups:` 讓 promtool 能解析），第二個 commit 是我的修改：

  ```
  git diff q1-baseline -- q1-weekend-oncall/monitoring
  ```

| 檔案 | 改了什麼 |
|---|---|
| `rules/node-usage.yaml` | 修好 dead 的 `NodeMemoryPressure`；新增 page `NodesUnderMemoryPressure` 並附 runbook |
| `rules/pod-restarts.yaml` | 每個 namespace 一則告警，`for: 15m` |
| `rules/payments-lag.yaml` | 「超過門檻且沒有在下降」取代 3h retention 下的 6h 平均 |
| `alertmanager/alertmanager.yaml` | Media 路由移到最前面；只進 Slack 的告警 repeat 改 24h；記憶體 page 期間 inhibit 症狀告警 |
| `tests/weekend-alerts.test.yaml` | promtool 單元測試，每個 case 對應 8/22 或 ops ticket 的一個情境 |
| `check.sh`、`/.github/workflows/q1-alerting.yml` | 本機與 CI 跑同一支檢查：rule 語法、rule 測試、Alertmanager 設定、路由契約 |

## 怎麼驗證

```
PROMTOOL=/path/to/promtool AMTOOL=/path/to/amtool ./monitoring/check.sh
```

用 promtool 3.5.0 和 amtool 0.28.1（官方 release）實際跑過的結果：

| | 新設定 | 舊設定（baseline commit） |
|---|---|---|
| `promtool check rules` | 通過 | **也通過**：語法檢查抓不到 dead rule |
| `promtool test rules` | 6/6 通過 | 6/6 失敗：記憶體告警不觸發、每個 pod 各一則、消化中的 queue 仍會 page（另外兩個 case 只差 annotation） |
| 路由契約 | 7/7 通過 | `team=media severity=critical` 被送到 `pager,slack-sre-alert`，沒有到 `#media-alerts` |
| `check.sh` exit code | 0 | 1 |

## 這套檢查抓不到什麼

- **只保護有寫測試的 rule。** 其餘約 330 條 rule 還是可能引用不存在的 metric 或 recording rule；`promtool check rules` 只檢查語法，舊的 `NodeMemoryPressure` 照樣通過。要全面防止，需要拿 rule 引用的 metric 去比對實際存在的 series（這是延後項目）。
- **inhibit 規則沒辦法離線測。** amtool 只能測路由，inhibit 要在 staging Alertmanager 上用 `amtool alert add` 手動觸發確認。
- **門檻值沒有經過真實資料回測。** 10000、90%、≥2 個 node 都是假設，merge 前要用遠端長期儲存回測過去幾個週末（本地 Prometheus 只有 3h）。
