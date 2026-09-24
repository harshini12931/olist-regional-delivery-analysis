/* ============================================================
   OLIST REGIONAL DELIVERY & REVIEW PERFORMANCE ANALYSIS
   Dataset: Olist Brazilian E-Commerce (~99K orders, 2016-2018)
   Author: K Harshini
   ============================================================
   Business question:
   Why do some Brazilian states have consistently lower review
   scores, and is it a product/seller quality issue or something
   else? What should the business fix first?
   ============================================================ */


/* ------------------------------------------------------------
   QUERY 1 — NAIVE VIEW: Average review score by state
   This is the query most analysts would stop at. It ranks
   states from worst to best average review score and, on its
   own, suggests a product/seller-quality problem concentrated
   in a handful of states (AL, MA, PA, SE, BA).
------------------------------------------------------------ */
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)         AS orders,
    ROUND(AVG(r.review_score), 2)      AS avg_review_score
FROM orders o
JOIN customers c      ON o.customer_id = c.customer_id
JOIN order_reviews r  ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
HAVING COUNT(DISTINCT o.order_id) > 200   -- drop tiny-sample states
ORDER BY avg_review_score ASC;


/* ------------------------------------------------------------
   QUERY 2 — DIGGING DEEPER: Add delivery-time metrics to the
   same states. Does delivery performance line up with the
   review-score ranking above?
------------------------------------------------------------ */
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(AVG(julianday(o.order_delivered_customer_date)
             - julianday(o.order_estimated_delivery_date)), 2) AS avg_days_late_vs_promise,
    ROUND(AVG(julianday(o.order_delivered_customer_date)
             - julianday(o.order_purchase_timestamp)), 1)      AS avg_delivery_days,
    ROUND(AVG(r.review_score), 2)                               AS avg_review_score
FROM orders o
JOIN customers c      ON o.customer_id = c.customer_id
JOIN order_reviews r  ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(DISTINCT o.order_id) > 200
ORDER BY avg_review_score ASC;

-- Finding: correlation(avg_delivery_days, avg_review_score) = -0.775
-- Long absolute delivery time predicts low review scores far more
-- strongly than "lateness relative to the promised date."


/* ------------------------------------------------------------
   QUERY 3 — DOSE-RESPONSE CHECK: Bucket every order by delivery
   speed (regardless of state) and check review score directly.
   This isolates delivery time as the driver, independent of
   geography, confirming it's not just a state-level artifact.
------------------------------------------------------------ */
SELECT
    CASE
        WHEN julianday(o.order_delivered_customer_date)
           - julianday(o.order_purchase_timestamp) <= 7  THEN '0-7 days'
        WHEN julianday(o.order_delivered_customer_date)
           - julianday(o.order_purchase_timestamp) <= 14 THEN '8-14 days'
        WHEN julianday(o.order_delivered_customer_date)
           - julianday(o.order_purchase_timestamp) <= 21 THEN '15-21 days'
        WHEN julianday(o.order_delivered_customer_date)
           - julianday(o.order_purchase_timestamp) <= 30 THEN '22-30 days'
        ELSE '30+ days'
    END AS delivery_bucket,
    COUNT(DISTINCT o.order_id)     AS orders,
    ROUND(AVG(r.review_score), 2)  AS avg_review_score
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_bucket
ORDER BY MIN(julianday(o.order_delivered_customer_date)
            - julianday(o.order_purchase_timestamp));

-- Finding: review score drops from 4.41 (0-7 days) to 2.24 (30+ days).
-- A clean, monotonic dose-response relationship — strong evidence
-- of a causal link, not just correlation/confounding.


/* ------------------------------------------------------------
   QUERY 4 — LATE VS ON-TIME: Binary split + revenue exposure.
   How many orders actually miss the promised delivery date,
   and how much revenue do they represent?
------------------------------------------------------------ */
SELECT
    CASE WHEN julianday(o.order_delivered_customer_date)
            > julianday(o.order_estimated_delivery_date)
         THEN 'Late' ELSE 'On-time/Early' END AS delivery_status,
    COUNT(DISTINCT o.order_id)                AS orders,
    ROUND(100.0 * COUNT(DISTINCT o.order_id) /
          (SELECT COUNT(*) FROM orders
           WHERE order_status = 'delivered'
             AND order_delivered_customer_date IS NOT NULL), 1) AS pct_of_orders,
    ROUND(AVG(r.review_score), 2)             AS avg_review_score,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue
FROM orders o
JOIN order_reviews r  ON o.order_id = r.order_id
JOIN order_items oi   ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status;

-- Finding: 8.1% of orders arrive late. Their avg review score is
-- 2.55 vs. 4.28 for on-time orders. Late orders represent
-- ~$1.35M of the ~$15.4M in analyzed revenue (~8.8% of revenue
-- tied to the highest-risk delivery experience).


/* ------------------------------------------------------------
   QUERY 5 — HONESTY CHECK: Does a bad review actually reduce
   repeat purchases? (Tests the assumption before using it in
   a business recommendation — this is the step most portfolio
   projects skip.)
------------------------------------------------------------ */
WITH cust_orders AS (
    SELECT c.customer_unique_id, o.order_id
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
cust_purchase_counts AS (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS total_orders
    FROM cust_orders
    GROUP BY customer_unique_id
),
cust_review AS (
    SELECT co.customer_unique_id, r.review_score
    FROM cust_orders co
    JOIN order_reviews r ON co.order_id = r.order_id
    GROUP BY co.customer_unique_id
)
SELECT
    CASE WHEN cr.review_score <= 2 THEN '1-2 (Bad)'
         WHEN cr.review_score = 3 THEN '3 (Neutral)'
         ELSE '4-5 (Good)' END AS review_bucket,
    COUNT(*) AS customers,
    ROUND(100.0 * SUM(CASE WHEN pc.total_orders > 1 THEN 1 ELSE 0 END)
          / COUNT(*), 2) AS repeat_purchase_rate_pct
FROM cust_review cr
JOIN cust_purchase_counts pc ON cr.customer_unique_id = pc.customer_unique_id
GROUP BY review_bucket
ORDER BY review_bucket;

-- Finding (important, and NOT the result I expected going in):
-- Repeat purchase rate is ~flat (~3%) across all review buckets.
-- Olist is a low-repeat marketplace model (most customers buy once
-- across many independent sellers), so "bad reviews kill retention"
-- does NOT hold here. The real business case for fixing delivery
-- is DIRECT REVENUE AT RISK on the order itself (query 4), plus
-- platform reputation/seller-churn risk — not a retention argument.
-- This is exactly the kind of assumption-check a senior analyst
-- runs before putting a number in front of a stakeholder.


/* ------------------------------------------------------------
   QUERY 6 — ROOT CAUSE: Why do certain states have long
   delivery times? (Geography check)
------------------------------------------------------------ */
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(AVG(julianday(o.order_delivered_customer_date)
             - julianday(o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(100.0 * SUM(CASE WHEN julianday(o.order_delivered_customer_date)
                             > julianday(o.order_estimated_delivery_date)
                        THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_late
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
HAVING orders > 200
ORDER BY avg_delivery_days DESC
LIMIT 8;

-- Finding: the worst-performing states (AL, PA, MA, SE, CE) are
-- Brazil's North/Northeast region — geographically farthest from
-- São Paulo, where the majority of Olist sellers are based. This
-- is a logistics/distance problem, not a seller-quality problem.


/* ------------------------------------------------------------
   QUERY 7 — MONTHLY REVENUE TREND WITH WINDOW FUNCTION
   (rolling 3-month average, for the dashboard's trend view)
------------------------------------------------------------ */
WITH monthly_revenue AS (
    SELECT
        strftime('%Y-%m', o.order_purchase_timestamp) AS order_month,
        SUM(oi.price + oi.freight_value) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY order_month
)
SELECT
    order_month,
    ROUND(revenue, 2) AS revenue,
    ROUND(AVG(revenue) OVER (
        ORDER BY order_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_3mo_avg_revenue
FROM monthly_revenue
ORDER BY order_month;
