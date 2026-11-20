# Transaction Log Analysis in BigQuery: Demand, Timing & Basket Behaviour

**Business question:** From a raw transaction log (`transaction_id`, `product_id`, `time`), what can we learn about **when** customers buy, **what** they buy, **what they buy together**, and whether the data pipeline itself is healthy?

This project shows how to get product and customer insights from a minimal event table in SQL alone. The same pattern applies to product usage logs (feature events instead of products). The queries are built as a reusable layer that a BI dashboard (Power BI, Looker Studio) can sit on.

**Stack:** BigQuery Standard SQL · window functions (`LAG`, `ROW_NUMBER`) · `APPROX_QUANTILES` · market-basket metrics (support, confidence, lift)

---

## Analysis modules

| Module | Queries | Business use |
|---|---|---|
| **Volume & timing** | Q1–Q3 daily volume, hourly peaks, part of day | Staffing, campaign timing, capacity planning |
| **Monitoring** | Q4 anomaly days (z-score), Q5 time between transactions (mean, median, P95), Q6 longest silent periods | Alerting on outages or tracking breaks before they reach reports |
| **Product performance** | Q7 penetration, Q8 daily trend, Q9 month-over-month growth, Q10 lifecycle | Find rising and declining products for assortment and prioritisation |
| **Repeat behaviour** | Q11 repeat-purchase interval, Q12 time to second purchase | Replenishment reminders, early traction of new products |
| **Basket analysis** | Q13 basket-size distribution, Q14 product pairs with support, confidence and lift | Cross-sell, bundles, recommendations |

## Design decisions

- **Correct grain.** One row in the table is one *product line*, not one transaction. Volume KPIs use `COUNT(DISTINCT transaction_id)`. Gap and interval metrics are computed on one row per transaction, because otherwise lines of the same basket create false 0-minute gaps.
- **Lift, not raw pair counts.** Popular products appear together often just because they are popular. Lift > 1 shows pairs that occur together *more than expected*, which is the signal you can act on for cross-selling.
- **Medians and P95 next to averages.** Time-between-transactions is skewed, so a single mean hides outages.
- **Month-over-month growth with `SAFE_DIVIDE`** avoids divide-by-zero errors for new products.

## How to run

Each query in [`bigquery-transaction-analysis.sql`](bigquery-transaction-analysis.sql) runs on its own in the BigQuery console. To use your own data, replace `main-data-hub.transaction_data.core_table` with any table that has `transaction_id`, `product_id` and a `TIMESTAMP` column named `time`.
