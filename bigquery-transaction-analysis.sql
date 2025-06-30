1. How many transactions occur per day?

-- Per day
SELECT 
  DATE_TRUNC(DATE(time), DAY) AS day_start,
  COUNT(*) AS transaction_count
FROM 
  `main-data-hub.transaction_data.core_table`
GROUP BY 
  day_start
ORDER BY 
  day_start;

2. Are there specific times of day when transactions peak?

SELECT
  EXTRACT(HOUR
  FROM
    time) AS hour_of_day,
  COUNT(*) AS transaction_count
FROM
  `main-data-hub.transaction_data.core_table`
GROUP BY
  hour_of_day
ORDER BY
  hour_of_day;

3. Which products are involved in the most transactions?

SELECT
  product_id,
  COUNT(*) AS transaction_count
FROM
  `main-data-hub.transaction_data.core_table`
GROUP BY
  product_id
ORDER BY
  transaction_count DESC;

4. Which product pairs are frequently purchased together, and how often?

SELECT
  t1.product_id AS product_a,
  t2.product_id AS product_b,
  COUNT(*) AS frequency
FROM
  `main-data-hub.transaction_data.core_table` t1
JOIN
  `main-data-hub.transaction_data.core_table` t2
ON
  t1.transaction_id = t2.transaction_id
  AND t1.product_id < t2.product_id
GROUP BY
  product_a,
  product_b
HAVING
  COUNT(*) > 1
ORDER BY
  frequency DESC;

5. How has the transaction volume for each product changed over time?

SELECT
  DATE(time) AS day,
  product_id,
  COUNT(*) AS transaction_count
FROM
  `main-data-hub.transaction_data.core_table`
GROUP BY
  day,
  product_id
ORDER BY
  day,
  product_id;


6. What’s the average time between transactions?

WITH
  ordered_times AS (
  SELECT
    time,
    LAG(time) OVER (ORDER BY time) AS previous_time
  FROM
    `main-data-hub.transaction_data.core_table` )
SELECT
  AVG(TIMESTAMP_DIFF(time, previous_time, MINUTE)) AS avg_minutes_between
FROM
  ordered_times
WHERE
  previous_time IS NOT NULL;

7. Are there downtimes or inactive periods in transactions?

WITH
  gaps AS (
  SELECT
    time,
    LAG(time) OVER (ORDER BY time) AS previous_time
  FROM
    `main-data-hub.transaction_data.core_table` )
SELECT
  time,
  previous_time,
  TIMESTAMP_DIFF(time, previous_time, HOUR) AS hours_between
FROM
  gaps
WHERE
  previous_time IS NOT NULL
ORDER BY
  hours_between DESC
LIMIT
  10;


8. When was each product first and last involved in a transaction?

SELECT
  product_id,
  MIN(time) AS first_transaction,
  MAX(time) AS last_transaction
FROM
  `main-data-hub.transaction_data.core_table`
GROUP BY
  product_id
ORDER BY
  product_id;

9. Are there days with unusually high or low numbers of transactions?

WITH
  daily_counts AS (
  SELECT
    DATE(time) AS day,
    COUNT(*) AS transaction_count
  FROM
    `main-data-hub.transaction_data.core_table`
  GROUP BY
    day ),
  stats AS (
  SELECT
    AVG(transaction_count) AS avg_count,
    STDDEV(transaction_count) AS std_dev
  FROM
    daily_counts )
SELECT
  d.day,
  d.transaction_count,
  CASE
    WHEN d.transaction_count > s.avg_count + 2 * s.std_dev THEN 'High Spike'
    WHEN d.transaction_count < s.avg_count - 2 * s.std_dev THEN 'Low Dip'
    ELSE 'Normal'
END
  AS anomaly_status
FROM
  daily_counts d,
  stats s
ORDER BY
  d.day;



10. What is the reorder interval (in days) for each product?

WITH
  product_orders AS (
  SELECT
    CAST(product_id AS STRING) AS product_id,
    time,
    LAG(time) OVER (PARTITION BY CAST(product_id AS STRING)
    ORDER BY
      time) AS prev_time
  FROM
    `main-data-hub.transaction_data.core_table` ),
  intervals AS (
  SELECT
    product_id,
    TIMESTAMP_DIFF(time, prev_time, DAY) AS days_between
  FROM
    product_orders
  WHERE
    prev_time IS NOT NULL )
SELECT
  product_id,
  ROUND(AVG(days_between), 2) AS avg_days_between_orders,
  COUNT(*) AS reorder_count
FROM
  intervals
GROUP BY
  product_id
ORDER BY
  avg_days_between_orders;


11. What is the average number of unique products per transaction?

SELECT
  AVG(product_count) AS avg_products_per_transaction
FROM (
  SELECT
    transaction_id,
    COUNT(DISTINCT product_id) AS product_count
  FROM
    `main-data-hub.transaction_data.core_table`
  GROUP BY
    transaction_id ) t;


12. Identify time gaps between transactions that may indicate system downtime or inactivity.

WITH
  time_gaps AS (
  SELECT
    time,
    LAG(time) OVER (ORDER BY time) AS prev_time,
    TIMESTAMP_DIFF(time, LAG(time) OVER (ORDER BY time), HOUR) AS hours_between
  FROM
    `main-data-hub.transaction_data.core_table` )
SELECT
  time,
  prev_time,
  hours_between
FROM
  time_gaps
WHERE
hours_between > 1
ORDER BY
  hours_between DESC;


13. What are the most popular product purchase sequences?

WITH ordered AS (
  SELECT transaction_id, product_id, ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY product_id) AS rn
  FROM `main-data-hub.transaction_data.core_table`
),
pairs AS (
  SELECT t1.product_id AS first_product, t2.product_id AS second_product, COUNT(*) AS count
  FROM ordered t1
  JOIN ordered t2 ON t1.transaction_id = t2.transaction_id AND t1.rn + 1 = t2.rn
  GROUP BY first_product, second_product
)
SELECT * FROM pairs
ORDER BY count DESC
LIMIT 10;


14. Which products are gaining or losing popularity over time?

WITH
  daily_counts AS (
  SELECT
    DATE_TRUNC(DATE(time), Day) AS day,
    product_id,
    COUNT(*) AS count
  FROM
    `main-data-hub.transaction_data.core_table`
  GROUP BY
    day,
    product_id ),
  growth AS (
  SELECT
    product_id,
    day,
    count,
    LAG(count) OVER (PARTITION BY cast(product_id as string) ORDER BY day) AS prev_count
  FROM
    daily_counts )
SELECT
  product_id,
  day,
  count,
  prev_count,
  ROUND((count - prev_count) * 100.0 / NULLIF(prev_count, 0), 2) AS percent_change
FROM
  growth
WHERE
  prev_count IS NOT NULL
ORDER BY
  percent_change DESC;


15. Cluster transactions based on their time of day.

SELECT
  CASE
    WHEN EXTRACT(HOUR FROM time) BETWEEN 0 AND 5 THEN 'Night'
    WHEN EXTRACT(HOUR FROM time) BETWEEN 6 AND 11 THEN 'Morning'
    WHEN EXTRACT(HOUR FROM time) BETWEEN 12 AND 17 THEN 'Afternoon'
    ELSE 'Evening'
END
  AS time_of_day,
  COUNT(*) AS transaction_count
FROM
  `main-data-hub.transaction_data.core_table`
GROUP BY
  time_of_day
ORDER BY
  transaction_count DESC;


16. Detect first-time appearances of each product and how long it took for the next purchase.

WITH
  ranked AS (
  SELECT
    product_id,
    time,
    ROW_NUMBER() OVER (PARTITION BY CAST(product_id AS String) ORDER BY time) AS rn
  FROM
    `main-data-hub.transaction_data.core_table` )
SELECT
  p1.product_id,
  p1.time AS first_seen,
  p2.time AS second_seen,
  TIMESTAMP_DIFF(p2.time, p1.time, DAY) AS days_between_first_and_second
FROM
  ranked p1
JOIN
  ranked p2
ON
  p1.product_id = p2.product_id
  AND p1.rn = 1
  AND p2.rn = 2;