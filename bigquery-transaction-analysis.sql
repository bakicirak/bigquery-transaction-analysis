-- ============================================================================
-- Transaction log analysis (BigQuery Standard SQL)
-- Table: `main-data-hub.transaction_data.core_table`
--   one row = one product line in a transaction
--   transaction_id, product_id, time (TIMESTAMP)
--
-- Grain matters: a transaction with 3 products has 3 rows. Volume metrics
-- therefore count DISTINCT transaction_id, and gap/interval metrics are
-- computed on one row per transaction (otherwise lines of the same basket
-- create artificial 0-minute gaps).
-- product_id is cast to STRING where it is used in PARTITION BY.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. VOLUME & TIMING
-- ---------------------------------------------------------------------------

-- Q1. How many transactions occur per day?
SELECT
  DATE(time)                     AS day,
  COUNT(DISTINCT transaction_id) AS transactions,
  COUNT(*)                       AS product_lines
FROM `main-data-hub.transaction_data.core_table`
GROUP BY day
ORDER BY day;


-- Q2. At which hours of the day do transactions peak?
SELECT
  EXTRACT(HOUR FROM time)        AS hour_of_day,
  COUNT(DISTINCT transaction_id) AS transactions
FROM `main-data-hub.transaction_data.core_table`
GROUP BY hour_of_day
ORDER BY hour_of_day;


-- Q3. Transactions by part of day
SELECT
  CASE
    WHEN EXTRACT(HOUR FROM time) BETWEEN 0  AND 5  THEN '1 Night (00-05)'
    WHEN EXTRACT(HOUR FROM time) BETWEEN 6  AND 11 THEN '2 Morning (06-11)'
    WHEN EXTRACT(HOUR FROM time) BETWEEN 12 AND 17 THEN '3 Afternoon (12-17)'
    ELSE                                                '4 Evening (18-23)'
  END                                                                   AS part_of_day,
  COUNT(DISTINCT transaction_id)                                        AS transactions,
  ROUND(100 * COUNT(DISTINCT transaction_id)
        / SUM(COUNT(DISTINCT transaction_id)) OVER (), 1)               AS pct_of_transactions
FROM `main-data-hub.transaction_data.core_table`
GROUP BY part_of_day
ORDER BY part_of_day;


-- Q4. Which days are unusually high or low? (|z| > 2 against the daily mean)
WITH daily AS (
  SELECT DATE(time) AS day, COUNT(DISTINCT transaction_id) AS transactions
  FROM `main-data-hub.transaction_data.core_table`
  GROUP BY day
),
stats AS (
  SELECT AVG(transactions) AS mean_tx, STDDEV(transactions) AS sd_tx FROM daily
)
SELECT
  d.day,
  d.transactions,
  ROUND(SAFE_DIVIDE(d.transactions - s.mean_tx, s.sd_tx), 2) AS z_score,
  CASE
    WHEN d.transactions > s.mean_tx + 2 * s.sd_tx THEN 'High spike'
    WHEN d.transactions < s.mean_tx - 2 * s.sd_tx THEN 'Low dip'
    ELSE 'Normal'
  END AS anomaly_status
FROM daily d
CROSS JOIN stats s
ORDER BY d.day;


-- Q5. Average and median minutes between consecutive transactions
WITH tx AS (
  SELECT transaction_id, MIN(time) AS tx_time
  FROM `main-data-hub.transaction_data.core_table`
  GROUP BY transaction_id
),
gaps AS (
  SELECT TIMESTAMP_DIFF(tx_time, LAG(tx_time) OVER (ORDER BY tx_time), MINUTE) AS minutes_since_prev
  FROM tx
)
SELECT
  ROUND(AVG(minutes_since_prev), 1)                         AS avg_minutes_between,
  APPROX_QUANTILES(minutes_since_prev, 100)[OFFSET(50)]     AS median_minutes_between,
  APPROX_QUANTILES(minutes_since_prev, 100)[OFFSET(95)]     AS p95_minutes_between
FROM gaps
WHERE minutes_since_prev IS NOT NULL;


-- Q6. Longest periods without any transaction (possible downtime / tracking gaps)
WITH tx AS (
  SELECT transaction_id, MIN(time) AS tx_time
  FROM `main-data-hub.transaction_data.core_table`
  GROUP BY transaction_id
),
gaps AS (
  SELECT
    LAG(tx_time) OVER (ORDER BY tx_time) AS gap_start,
    tx_time                              AS gap_end
  FROM tx
)
SELECT
  gap_start,
  gap_end,
  TIMESTAMP_DIFF(gap_end, gap_start, MINUTE) AS gap_minutes
FROM gaps
WHERE gap_start IS NOT NULL
  AND TIMESTAMP_DIFF(gap_end, gap_start, MINUTE) > 60
ORDER BY gap_minutes DESC
LIMIT 20;


-- ---------------------------------------------------------------------------
-- 2. PRODUCT PERFORMANCE
-- ---------------------------------------------------------------------------

-- Q7. Which products appear in the most transactions?
SELECT
  product_id,
  COUNT(DISTINCT transaction_id)                                         AS transactions,
  ROUND(100 * COUNT(DISTINCT transaction_id)
        / (SELECT COUNT(DISTINCT transaction_id)
           FROM `main-data-hub.transaction_data.core_table`), 2)         AS penetration_pct
FROM `main-data-hub.transaction_data.core_table`
GROUP BY product_id
ORDER BY transactions DESC;


-- Q8. Daily transaction volume per product (trend input for a BI chart)
SELECT
  DATE(time)                     AS day,
  product_id,
  COUNT(DISTINCT transaction_id) AS transactions
FROM `main-data-hub.transaction_data.core_table`
GROUP BY day, product_id
ORDER BY day, product_id;


-- Q9. Which products are gaining or losing popularity? (month-over-month)
WITH monthly AS (
  SELECT
    DATE_TRUNC(DATE(time), MONTH)  AS month,
    CAST(product_id AS STRING)     AS product_id,
    COUNT(DISTINCT transaction_id) AS transactions
  FROM `main-data-hub.transaction_data.core_table`
  GROUP BY month, product_id
),
growth AS (
  SELECT
    product_id,
    month,
    transactions,
    LAG(transactions) OVER (PARTITION BY product_id ORDER BY month) AS prev_transactions
  FROM monthly
)
SELECT
  product_id,
  month,
  transactions,
  prev_transactions,
  ROUND(100 * SAFE_DIVIDE(transactions - prev_transactions, prev_transactions), 1) AS mom_change_pct
FROM growth
WHERE prev_transactions IS NOT NULL
ORDER BY mom_change_pct DESC;


-- Q10. First and last time each product was bought (product lifecycle)
SELECT
  product_id,
  MIN(time)                                   AS first_seen,
  MAX(time)                                   AS last_seen,
  TIMESTAMP_DIFF(MAX(time), MIN(time), DAY)   AS active_days
FROM `main-data-hub.transaction_data.core_table`
GROUP BY product_id
ORDER BY first_seen;


-- Q11. Repeat-purchase interval per product (average days between transactions)
WITH product_tx AS (
  SELECT
    CAST(product_id AS STRING) AS product_id,
    transaction_id,
    MIN(time)                  AS tx_time
  FROM `main-data-hub.transaction_data.core_table`
  GROUP BY product_id, transaction_id
),
intervals AS (
  SELECT
    product_id,
    TIMESTAMP_DIFF(tx_time, LAG(tx_time) OVER (PARTITION BY product_id ORDER BY tx_time), DAY) AS days_between
  FROM product_tx
)
SELECT
  product_id,
  ROUND(AVG(days_between), 2) AS avg_days_between_purchases,
  COUNT(days_between)         AS repeat_purchases
FROM intervals
WHERE days_between IS NOT NULL
GROUP BY product_id
ORDER BY avg_days_between_purchases;


-- Q12. Time from a product's first to its second purchase (early traction of new products)
WITH product_tx AS (
  SELECT
    CAST(product_id AS STRING) AS product_id,
    transaction_id,
    MIN(time)                  AS tx_time
  FROM `main-data-hub.transaction_data.core_table`
  GROUP BY product_id, transaction_id
),
ranked AS (
  SELECT
    product_id,
    tx_time,
    ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY tx_time, transaction_id) AS rn
  FROM product_tx
)
SELECT
  product_id,
  MIN(IF(rn = 1, tx_time, NULL))                                                       AS first_purchase,
  MIN(IF(rn = 2, tx_time, NULL))                                                       AS second_purchase,
  TIMESTAMP_DIFF(MIN(IF(rn = 2, tx_time, NULL)), MIN(IF(rn = 1, tx_time, NULL)), DAY)  AS days_to_second_purchase
FROM ranked
WHERE rn <= 2
GROUP BY product_id
ORDER BY days_to_second_purchase;   -- NULL = never bought a second time


-- ---------------------------------------------------------------------------
-- 3. BASKET ANALYSIS
-- ---------------------------------------------------------------------------

-- Q13. Basket size: average distinct products per transaction, and distribution
WITH baskets AS (
  SELECT transaction_id, COUNT(DISTINCT product_id) AS products
  FROM `main-data-hub.transaction_data.core_table`
  GROUP BY transaction_id
)
SELECT
  products                                              AS basket_size,
  COUNT(*)                                              AS transactions,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)      AS pct_of_transactions,
  ROUND(SUM(products * COUNT(*)) OVER () / SUM(COUNT(*)) OVER (), 2) AS overall_avg_basket_size
FROM baskets
GROUP BY basket_size
ORDER BY basket_size;


-- Q14. Which product pairs are bought together? (support, confidence, lift)
WITH tx_products AS (
  SELECT DISTINCT transaction_id, CAST(product_id AS STRING) AS product_id
  FROM `main-data-hub.transaction_data.core_table`
),
n AS (SELECT COUNT(DISTINCT transaction_id) AS total_tx FROM tx_products),
product_freq AS (
  SELECT product_id, COUNT(*) AS tx_with_product FROM tx_products GROUP BY product_id
),
pairs AS (
  SELECT a.product_id AS product_a, b.product_id AS product_b, COUNT(*) AS tx_with_both
  FROM tx_products a
  JOIN tx_products b
    ON a.transaction_id = b.transaction_id
   AND a.product_id < b.product_id
  GROUP BY product_a, product_b
)
SELECT
  p.product_a,
  p.product_b,
  p.tx_with_both,
  ROUND(p.tx_with_both / n.total_tx, 4)                                            AS support,
  ROUND(p.tx_with_both / fa.tx_with_product, 3)                                    AS confidence_a_to_b,
  ROUND((p.tx_with_both / n.total_tx)
        / ((fa.tx_with_product / n.total_tx) * (fb.tx_with_product / n.total_tx)), 2) AS lift
FROM pairs p
CROSS JOIN n
JOIN product_freq fa ON fa.product_id = p.product_a
JOIN product_freq fb ON fb.product_id = p.product_b
WHERE p.tx_with_both > 1
ORDER BY lift DESC, p.tx_with_both DESC
LIMIT 50;
