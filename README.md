# 🧾 BigQuery Transaction Data Analysis

This repository contains a comprehensive collection of BigQuery SQL scripts designed to analyze transactional data at multiple levels — temporal patterns, product behavior, co-purchases, inactivity, and trends over time.

The dataset assumed in all queries includes at least the following fields:

- `transaction_id`
- `product_id`
- `time` (as a TIMESTAMP)

---

## 🔍 Questions Answered

1. **How many transactions occur per day?**  
   Determine daily transaction volume to identify active and inactive days.

2. **Are there specific times of day when transactions peak?**  
   Extract hourly transaction data to detect traffic peaks (e.g. morning, evening).

3. **Which products are involved in the most transactions?**  
   Rank products based on how frequently they appear in transactions.

4. **Which product pairs are frequently purchased together, and how often?**  
   Analyze co-occurrence of product pairs within the same transaction.

5. **How has the transaction volume for each product changed over time?**  
   Monitor product trends and demand changes day by day.

6. **What’s the average time between transactions?**  
   Measure the average duration (in minutes) between consecutive transactions.

7. **Are there downtimes or inactive periods in transactions?**  
   Identify unusually long gaps between transaction timestamps.

8. **When was each product first and last involved in a transaction?**  
   Capture the first and last usage of each product across the dataset.

9. **Are there days with unusually high or low numbers of transactions?**  
   Detect anomalies by comparing daily transaction volumes against average and standard deviation.

10. **What is the reorder interval (in days) for each product?**  
    Calculate how frequently a product is reordered over time.

11. **What is the average number of unique products per transaction?**  
    Understand basket size and diversity by counting unique products in each transaction.

12. **Identify time gaps between transactions that may indicate system downtime or inactivity.**  
    List long periods of transactional silence using hourly gaps.

13. **What are the most popular product purchase sequences?**  
    Uncover frequent item-to-item transitions within transactions.

14. **Which products are gaining or losing popularity over time?**  
    Track month-over-month changes in product purchase frequency.

15. **Cluster transactions based on their time of day.**  
    Classify transactions into Morning, Afternoon, Evening, or Night buckets.

16. **Detect first-time appearances of each product and how long it took for the next purchase.**  
    Evaluate how soon a product is purchased again after its introduction.

---

## 🗂 Structure

You can copy and run each query directly in the BigQuery console using Standard SQL.

```bash
├── bigquery-transaction-analysis.sql
