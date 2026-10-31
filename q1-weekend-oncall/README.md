# Q1: Make Our Weekend On-Call Sustainable

- [`DECISION.md`](DECISION.md)：一頁決策文件。
- `monitoring/`：第 1 名的實際設定。tag `q1-baseline` 是題目給的原樣，之後的 commit 是我的修改：

  ```
  git diff q1-baseline -- q1-weekend-oncall/monitoring
  ```

| 檔案 | 改了什麼 |
|---|---|
| `rules/node-usage.yaml` | 修好壞掉的記憶體告警；新增記憶體不足的 page 和處理步驟 |
| `rules/pod-restarts.yaml` | 每個 namespace 一則，持續 15 分鐘才發 |
| `rules/payments-lag.yaml` | 「queue 太長而且沒有在下降」才 page |
| `alertmanager/alertmanager.yaml` | Media 路由移到最前面；Slack 重複提醒改 24 小時；記憶體 page 響時不發重啟告警 |
| `tests/weekend-alerts.test.yaml` | 8/22 的每個情境各一個測試 |
| `check.sh`、`/.github/workflows/q1-alerting.yml` | 本機和 CI 跑同一支檢查 |

## 驗證

```
PROMTOOL=/path/to/promtool AMTOOL=/path/to/amtool ./monitoring/check.sh
```

用官方 promtool 3.5.0、amtool 0.28.1 實際跑過：

| | 新設定 | 舊設定 |
|---|---|---|
| 語法檢查 | 通過 | **也通過**：語法檢查抓不到壞掉的告警 |
| 測試 | 6/6 通過 | 6/6 失敗 |
| 路由檢查 | 7/7 通過 | critical 的 Media 告警被送到 SRE pager |
| `check.sh` | exit 0 | exit 1 |

## 抓不到的東西
- 只保護有寫測試的 rule，其他約 330 條還是可能壞掉而沒人發現。
- inhibit（記憶體 page 響時壓掉重啟告警）沒辦法離線測，要在 staging 手動觸發確認。
- 門檻值（10000、90%、2 個 node）還沒用真實資料回測。
