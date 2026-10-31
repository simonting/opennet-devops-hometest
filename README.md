# OpenNet DevOps Engineer：Home Test

Simon Ting

| 題目 | 位置 |
|---|---|
| Q1 Make Our Weekend On-Call Sustainable（必答） | [`q1-weekend-oncall/`](q1-weekend-oncall/)：[決策文件](q1-weekend-oncall/DECISION.md)、`monitoring/` 為實際變更 |
| Q6 The Tuesday 502s（選修） | [`q6-tuesday-502s/`](q6-tuesday-502s/) |
| AI 使用附錄（兩題共用） | [`AI-APPENDIX.md`](AI-APPENDIX.md) |

Q1 的變更有 CI（`.github/workflows/q1-alerting.yml`），本機也可以直接跑：

```
PROMTOOL=/path/to/promtool AMTOOL=/path/to/amtool q1-weekend-oncall/monitoring/check.sh
```
