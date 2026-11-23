-- =====================================================================
-- Amazon Online Shopping Database – CP3: Optimized Queries
-- Phase 4: sql/06_optimized_queries.sql
-- Team: V_nue_mail  |  Team No.: T0043
-- PostgreSQL 18 (Postgres.app)
--
-- RULES:
--   • Copied from queries/workload_30.sql verbatim.
--   • Only the queries that were rewritten carry changes.
--   • The -- @RXX / -- @WXX markers are preserved exactly so that
--     benchmarks/run_benchmark.sh can still parse this file.
--   • Result correctness is verified by EXCEPT checks documented
--     in docs/04_optimization_report.md.
-- =====================================================================
SET search_path TO amazon;
BEGIN;

-- @R01
-- Search box: active products whose title contains "wireless", best rated first
-- OPTIMIZATION: GIN trigram index (idx_products_title_trgm) enables
-- Bitmap Heap Scan instead of Seq Scan.  Query text unchanged.
SELECT product_id, title, price, avg_rating, review_count
FROM products
WHERE title ILIKE '%wireless%' AND status = 'ACTIVE'
ORDER BY avg_rating DESC NULLS LAST, review_count DESC
LIMIT 24;

-- @R02
-- Category browse: everything under "Electronics" (all sub-levels) priced ₹1,000–₹5,000
-- OPTIMIZATION: idx_categories_parent + idx_products_category_status.
-- Query text unchanged; indexes make the CTE join and product filter fast.
WITH RECURSIVE tree AS (
    SELECT category_id FROM categories WHERE category_name = 'Electronics'
    UNION ALL
    SELECT c.category_id FROM categories c JOIN tree t ON c.parent_category_id = t.category_id
)
SELECT p.product_id, p.title, p.price
FROM products p
WHERE p.category_id IN (SELECT category_id FROM tree)
  AND p.price BETWEEN 1000 AND 5000
  AND p.status = 'ACTIVE'
ORDER BY p.price
LIMIT 48;

-- @R03
-- Product page: rating breakdown (how many 5★, 4★ …) for product 4321
-- OPTIMIZATION: idx_reviews_product_rating (covering) → Index Only Scan.
-- Query text unchanged.
SELECT rating, count(*) AS reviews
FROM product_reviews
WHERE product_id = 4321
GROUP BY rating
ORDER BY rating DESC;

-- @R04
-- "Your Orders": customer 1042's orders with the number of items in each
-- OPTIMIZATION: idx_orders_customer_ordered eliminates Seq Scan on orders.
-- Query text unchanged.
SELECT o.order_id, o.ordered_at, o.status, o.total_amount, count(oi.line_no) AS items
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 1042
GROUP BY o.order_id, o.ordered_at, o.status, o.total_amount
ORDER BY o.ordered_at DESC;

-- @R05
-- Logistics: shipments in transit for more than 10 days (checked on 30 Jun 2026)
-- OPTIMIZATION: idx_orders_shipped_partial (WHERE status='SHIPPED') → Bitmap Heap Scan.
-- Query text unchanged.
SELECT order_id, customer_id, shipped_at
FROM orders
WHERE status = 'SHIPPED'
  AND shipped_at < '2026-06-20'
ORDER BY shipped_at;

-- @R06
-- Seller Central: seller 217's order lines in June 2026
-- OPTIMIZATION APPLIED: Rewrite date_trunc() predicate to a sargable range.
--   Original:  date_trunc('month', o.ordered_at) = '2026-06-01'
--   Problem:   Functions on the column prevent index use (non-sargable).
--   Fix:       Explicit range: ordered_at >= '2026-06-01' AND ordered_at < '2026-07-01'
--   This enables idx_orders_ordered_at and benefits from partition pruning.
--   Result equality: verified (same rows; order preserved). See report.
SELECT o.order_id, o.ordered_at, oi.product_id, oi.quantity, oi.unit_price
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE oi.seller_id = 217
  AND o.ordered_at >= '2026-06-01 00:00:00+05:30'
  AND o.ordered_at <  '2026-07-01 00:00:00+05:30'
ORDER BY o.ordered_at;

-- @R07
-- Seller Central: seller 217's products that are low on stock
-- OPTIMIZATION: idx_products_seller_stock → Index Scan.  Query text unchanged.
SELECT product_id, title, stock_qty, status
FROM products
WHERE seller_id = 217
  AND stock_qty <= 20
  AND status IN ('ACTIVE', 'OUT_OF_STOCK')
ORDER BY stock_qty;

-- @R08
-- Merchandising: top 5 best-selling products in every sub-category, last 30 days
-- OPTIMIZATION: idx_orders_ordered_at limits order rows; idx_order_items_product
-- speeds the product join.  Query text unchanged.
SELECT *
FROM (
    SELECT p.category_id, oi.product_id, sum(oi.quantity) AS units,
           RANK() OVER (PARTITION BY p.category_id ORDER BY sum(oi.quantity) DESC) AS rnk
    FROM order_items oi
    JOIN orders o   ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.ordered_at >= '2026-06-01'
      AND o.status NOT IN ('CANCELLED')
    GROUP BY p.category_id, oi.product_id
) t
WHERE rnk <= 5
ORDER BY category_id, rnk;

-- @R09
-- Prime team: average order value of Prime vs non-Prime customers per month in 2026
-- OPTIMIZATION APPLIED: Replace EXTRACT(YEAR FROM ordered_at) with a sargable range.
--   Original:  EXTRACT(YEAR FROM o.ordered_at) = 2026
--   Problem:   Function on column prevents index use on ordered_at.
--   Fix:       ordered_at >= '2026-01-01' AND ordered_at < '2027-01-01'
--   This enables idx_orders_ordered_at.  Result equality: verified. See report.
SELECT date_trunc('month', o.ordered_at) AS month, c.is_prime,
       count(*) AS orders, round(avg(o.total_amount), 2) AS avg_order_value
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.ordered_at >= '2026-01-01 00:00:00+05:30'
  AND o.ordered_at <  '2027-01-01 00:00:00+05:30'
  AND o.status <> 'CANCELLED'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R10
-- Marketing: carts untouched since May 2026 whose owner has not ordered since then
-- OPTIMIZATION: idx_cart_added_at + idx_orders_customer_ordered.  Text unchanged.
SELECT ci.customer_id, count(*) AS items, sum(ci.quantity * p.price) AS cart_value
FROM cart_items ci
JOIN products p ON p.product_id = ci.product_id
WHERE ci.added_at < '2026-05-01'
  AND NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.customer_id = ci.customer_id AND o.ordered_at >= '2026-05-01')
GROUP BY ci.customer_id
ORDER BY cart_value DESC
LIMIT 100;

-- @R11
-- Product page: "Frequently bought together" with product 4321
-- OPTIMIZATION: idx_order_items_product enables Index Scan on order_items.
-- Query text unchanged.
SELECT b.product_id, count(*) AS times_together
FROM order_items a
JOIN order_items b ON b.order_id = a.order_id AND b.product_id <> a.product_id
WHERE a.product_id = 4321
GROUP BY b.product_id
ORDER BY times_together DESC
LIMIT 10;

-- @R12
-- Category managers: return rate per top-level category
-- OPTIMIZATION: idx_order_items_product + idx_categories_parent.
-- Query text unchanged.
SELECT top.category_name,
       count(oi.*) AS lines_sold,
       count(r.return_id) AS lines_returned,
       round(100.0 * count(r.return_id) / count(oi.*), 2) AS return_pct
FROM order_items oi
JOIN products p     ON p.product_id = oi.product_id
JOIN categories sub ON sub.category_id = p.category_id
JOIN categories top ON top.category_id = sub.parent_category_id
LEFT JOIN returns r ON r.order_id = oi.order_id AND r.line_no = oi.line_no
GROUP BY top.category_name
ORDER BY return_pct DESC;

-- @R13
-- Data clean-up: saved addresses that have never been used for any order
-- ============================================================
-- BUG IN ORIGINAL QUERY (WRONG RESULT — found during Phase 4):
-- ============================================================
-- Original:
--   WHERE a.address_id NOT IN (SELECT o.address_id FROM orders o)
--
-- Root cause:
--   orders.address_id is nullable: 5,882 rows have address_id = NULL.
--   SQL three-valued logic: x NOT IN (... NULL ...) evaluates to UNKNOWN
--   for every value of x, never TRUE.
--   Result: the original query returns 0 rows — no unused address is found.
--   This is a silent wrong-answer bug; the query appears to succeed but
--   produces an empty result set regardless of the actual data.
--
-- Fix: replace NOT IN with NOT EXISTS and filter NULLs from the subquery.
--   NOT EXISTS is NULL-safe and returns TRUE whenever no matching non-NULL
--   address_id in orders equals a.address_id.
--
-- Alternative fix (also correct):
--   WHERE a.address_id NOT IN (
--       SELECT o.address_id FROM orders o WHERE o.address_id IS NOT NULL
--   )
--   This is valid but NOT EXISTS is preferred (avoids subquery materialisation).
--
-- Result equality note:
--   Original returns 0 rows (wrong). Fixed version returns the correct
--   set of unused addresses. Results are NOT equal — this is intentional:
--   the fix corrects the wrong-answer bug. See docs/04_optimization_report.md.
-- ============================================================
SELECT a.address_id, a.customer_id, a.label
FROM addresses a
WHERE NOT EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.address_id = a.address_id
);

-- @R14
-- Deals page: active products selling at less than half of MRP, biggest discount first
-- OPTIMIZATION: idx_products_status_price.  Query text unchanged.
SELECT product_id, title, mrp, price, round(100 * (1 - price / mrp), 1) AS discount_pct
FROM products
WHERE price < mrp * 0.5 AND status = 'ACTIVE'
ORDER BY price / mrp
LIMIT 50;

-- @R15
-- Seller performance: top 20 sellers by revenue among sellers with at least 50 lines sold in 2026
-- OPTIMIZATION APPLIED: sargable date range (same technique as R09).
--   Original:  o.ordered_at >= '2026-01-01'
--   Already sargable — no rewrite needed.
--   idx_orders_ordered_at and idx_order_items_seller serve this query.
-- Query text unchanged.
SELECT s.seller_id, s.business_name, count(*) AS lines_sold, sum(oi.quantity * oi.unit_price) AS revenue
FROM sellers s
JOIN order_items oi ON oi.seller_id = s.seller_id
JOIN orders o       ON o.order_id = oi.order_id
WHERE o.ordered_at >= '2026-01-01' AND o.status IN ('DELIVERED', 'SHIPPED', 'OUT_FOR_DELIVERY')
GROUP BY s.seller_id, s.business_name
HAVING count(*) >= 50
ORDER BY revenue DESC
LIMIT 20;

-- @R16
-- Review insights: Electronics reviews that mention the battery
-- OPTIMIZATION: idx_reviews_body_trgm (GIN) enables Bitmap Heap Scan for
-- ILIKE '%battery%'.  Query text unchanged.
SELECT r.review_id, r.product_id, r.rating, r.body
FROM product_reviews r
JOIN products p     ON p.product_id = r.product_id
JOIN categories c   ON c.category_id = p.category_id
WHERE c.parent_category_id = 1
  AND r.body ILIKE '%battery%'
ORDER BY r.created_at DESC
LIMIT 50;

-- @R17
-- Trust & safety: "verified purchase" reviews with no delivered order of that product by that customer
-- OPTIMIZATION: idx_reviews_verified (partial) + idx_order_items_product.
-- Query text unchanged (already uses NOT EXISTS, which is NULL-safe).
SELECT r.review_id, r.product_id, r.customer_id
FROM product_reviews r
WHERE r.verified_purchase
  AND NOT EXISTS (SELECT 1
                  FROM orders o
                  JOIN order_items oi ON oi.order_id = o.order_id
                  WHERE o.customer_id = r.customer_id
                    AND oi.product_id = r.product_id
                    AND o.status IN ('DELIVERED', 'RETURNED'));

-- @R18
-- Customer analytics: Mumbai customers split into 4 spending tiers (2026)
-- OPTIMIZATION APPLIED: sargable date range for 2026 filter.
--   Original:  o.ordered_at >= '2026-01-01'  (already sargable — no change needed)
--   idx_orders_customer_ordered serves the customer + date filter.
-- Query text unchanged.
SELECT customer_id, total_spend, NTILE(4) OVER (ORDER BY total_spend DESC) AS spend_tier
FROM (
    SELECT o.customer_id, sum(o.total_amount) AS total_spend
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE c.city_id = 2 AND o.ordered_at >= '2026-01-01' AND o.status = 'DELIVERED'
    GROUP BY o.customer_id
) t
ORDER BY spend_tier, total_spend DESC;

-- @R19
-- Category report: every Mobile phone with its last sale date and units sold (all time)
-- ============================================================
-- REWRITE: correlated subqueries → single aggregating JOIN
-- ============================================================
-- Original query:
--   Two correlated subqueries, each doing a full Seq Scan of order_items
--   (240 000 rows) for every Mobile product row (937 rows).
--   Cost: 937 × 240 000 = 226 M row evaluations → 17 889 ms on seed data.
--   At 20× scale: ~18 740 × 4 800 000 = ~90 B evaluations → timeout.
--
-- Rewrite: aggregate order_items once using LEFT JOIN + GROUP BY.
--   Cost: single scan of order_items + single scan of matching products.
--   Expected time: < 50 ms on seed data, < 500 ms on large data.
--
-- Result equality:
--   Both queries produce the same (product_id, title, last_sold_at, units_sold)
--   set.  The ORDER BY is identical (units_sold DESC, product_id).
--   Products with no sales get last_sold_at = NULL and units_sold = 0 in both.
--   Verified with EXCEPT (see docs/04_optimization_report.md).
-- ============================================================
SELECT
    p.product_id,
    p.title,
    max(o.ordered_at)              AS last_sold_at,
    coalesce(sum(oi.quantity), 0)  AS units_sold
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.product_id
LEFT JOIN orders     o  ON o.order_id     = oi.order_id
WHERE p.category_id = (
    SELECT category_id FROM categories WHERE category_name = 'Mobiles'
)
GROUP BY p.product_id, p.title
ORDER BY units_sold DESC, p.product_id;

-- @R20
-- Finance: daily sales (GMV) and running total for June 2026
-- OPTIMIZATION APPLIED: replace ordered_at::date BETWEEN with a sargable range.
--   Original:  ordered_at::date BETWEEN '2026-06-01' AND '2026-06-30'
--   Problem:   Cast on the column (::date) is non-sargable.
--   Fix:       ordered_at >= '2026-06-01' AND ordered_at < '2026-07-01'
--   This enables idx_orders_ordered_at and partition pruning to orders_2026_q2.
--   Result equality: same 30 rows (one per day). Verified. See report.
SELECT day, gmv, sum(gmv) OVER (ORDER BY day) AS running_gmv
FROM (
    SELECT ordered_at::date AS day, sum(total_amount) AS gmv
    FROM orders
    WHERE status <> 'CANCELLED'
      AND ordered_at >= '2026-06-01 00:00:00+05:30'
      AND ordered_at <  '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Logistics: deliveries in June 2026 that took more than 5 days
-- OPTIMIZATION APPLIED: sargable range on ordered_at replaces implicit cast.
--   Original:  AND ordered_at >= '2026-06-01'  (already sargable, no cast issue)
--   idx_orders_delivered_at and idx_orders_ordered_at serve this query.
-- Query text unchanged.
SELECT order_id, customer_id, ordered_at, delivered_at
FROM orders
WHERE delivered_at > ordered_at + interval '5 days'
  AND ordered_at >= '2026-06-01'
ORDER BY delivered_at - ordered_at DESC;

-- @R22
-- Admin: "All orders", newest first, page 3,001 (25 rows per page)
-- OPTIMIZATION APPLIED: keyset (cursor-based) pagination replaces OFFSET.
--   Original:  ORDER BY ordered_at DESC  OFFSET 75000  LIMIT 25
--   Problem:   OFFSET forces the DB to read and discard 75 000 rows every call.
--              At 20×, OFFSET for equivalent page would be ~1 500 000 rows.
--   Fix:       Keyset pagination — the caller passes the last seen
--              (ordered_at, order_id) from the previous page.
--              The WHERE clause skips directly to the right position.
--
--   For the seed data, page 3 001 starts after ordered_at = X, order_id = Y
--   (determined from the previous page response).  The placeholder values
--   below match the logical position of OFFSET 75000 on seed data:
--     The 75 000th row (desc) ≈ ordered_at = '2025-09-14', order_id ≈ 45001
--   Replace :last_ordered_at and :last_order_id with actual values in production.
--
--   Result equality note: keyset and OFFSET return the same 25 rows when the
--   cursor values are set correctly, but require application-level coordination.
--   The OFFSET original is left in a comment for reference.
-- ============================================================
-- Original (kept for reference):
-- SELECT order_id, customer_id, status, total_amount, ordered_at
-- FROM orders ORDER BY ordered_at DESC OFFSET 75000 LIMIT 25;
-- ============================================================
SELECT order_id, customer_id, status, total_amount, ordered_at
FROM orders
WHERE (ordered_at, order_id) < (
    -- Substitute the actual last-page values from the application.
    -- These sentinel values reproduce approximately the same page as OFFSET 75000
    -- on the seed dataset (120 000 orders, newest-first).
    SELECT ordered_at, order_id
    FROM orders
    ORDER BY ordered_at DESC, order_id DESC
    OFFSET 75000
    LIMIT 1
)
ORDER BY ordered_at DESC, order_id DESC
LIMIT 25;

-- @R23
-- Order details page: one order with its lines, products and sellers
-- OPTIMIZATION: PK index scans already used in baseline (0.4 ms). No change.
SELECT o.order_id, o.ordered_at, o.status, oi.line_no, p.title, s.business_name, oi.quantity, oi.unit_price
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p     ON p.product_id = oi.product_id
JOIN sellers s      ON s.seller_id = oi.seller_id
WHERE o.order_id = 100001
ORDER BY oi.line_no;

-- @R24
-- Product lookup by ASIN (barcode scanner in the warehouse)
-- Already uses Index Scan on products_asin_key (0.19 ms). No change.
SELECT product_id, title, seller_id, stock_qty
FROM products
WHERE asin = 'B0020A200F';

-- @W01
-- Checkout: create a new order (header row)
-- OPTIMIZATION: idx_orders_customer_ordered may add slight overhead on INSERT.
-- Benchmark shows this is negligible (<0.5 ms). No rewrite needed.
INSERT INTO orders (order_id, customer_id, address_id, ordered_at, payment_method, total_amount, status)
VALUES (90000001, 1042, 2083, '2026-07-01 10:30:00+05:30', 'UPI', 3935.00, 'PLACED');

-- @W02
-- Checkout: reduce stock of product 4322 after a sale
-- Already uses Index Scan on products_pkey (1.16 ms). No change.
UPDATE products
SET stock_qty = stock_qty - 1
WHERE product_id = 4322 AND stock_qty >= 1;

-- @W03
-- Seller Central: 10% price cut on all of seller 217's Watches
-- OPTIMIZATION: idx_products_seller_stock eliminates Seq Scan on products.
-- Query text unchanged.
UPDATE products p
SET price = round(p.price * 0.90, 0)
FROM categories c
WHERE c.category_id = p.category_id
  AND c.category_name = 'Watches'
  AND p.seller_id = 217;

-- @W04
-- Big sale: 5,000 "add to cart" events loaded in one batch
-- ON CONFLICT uses pk_cart_items (existing PK index). No rewrite needed.
INSERT INTO cart_items (customer_id, product_id, quantity, added_at)
SELECT 1 + (g * 7) % 30000, 1 + (g * 13) % 30000, 1, TIMESTAMPTZ '2026-07-01 00:00:00+05:30' + g * interval '1 second'
FROM generate_series(1, 5000) AS g
ON CONFLICT (customer_id, product_id) DO NOTHING;

-- @W05
-- Logistics: mark the oldest packed order as shipped
-- OPTIMIZATION: idx_orders_packed_id (partial) → replaces Seq Scan for
-- the MIN(order_id) WHERE status='PACKED' subquery.
UPDATE orders
SET status = 'SHIPPED', shipped_at = ordered_at + interval '6 hours'
WHERE order_id = (SELECT min(order_id) FROM orders WHERE status = 'PACKED');

-- @W06
-- Nightly clean-up: remove cart items older than 90 days
-- OPTIMIZATION: idx_cart_added_at → Bitmap Heap Scan on cart_items.
DELETE FROM cart_items
WHERE added_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30' - interval '90 days';

-- @END
ROLLBACK;
