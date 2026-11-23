-- =====================================================================
-- Amazon Online Shopping Database – CP3: Indexes
-- Phase 4: Performance optimization
-- Team: V_nue_mail  |  Team No.: T0043
-- PostgreSQL 18 (Postgres.app)
--
-- Run after 01_schema.sql + 02_load_data.sql, before benchmarking.
-- Usage: psql -d <database> -f sql/05_indexes.sql
--
-- Every index below carries:
--   • Which queries it serves
--   • Why this index type and column order
--   • Expected plan change (Seq Scan → Index/Bitmap/Index Only Scan)
-- =====================================================================

SET search_path TO amazon;

-- =====================================================================
-- 1. products table
-- =====================================================================

-- R01: title ILIKE '%wireless%' AND status = 'ACTIVE'
-- GIN trigram index enables ILIKE '%text%' to use Bitmap Heap Scan
-- instead of a 30 000-row Seq Scan.  Requires pg_trgm extension.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_products_title_trgm
    ON products USING GIN (title gin_trgm_ops);
-- Serves: R01, R16 (body ILIKE '%battery%' handled by idx_reviews_body_trgm)
-- Plan change: Seq Scan on products (30k) → Bitmap Heap Scan

-- R02: category_id IN (...) AND status = 'ACTIVE' AND price BETWEEN ...
-- R07: seller_id = 217 AND stock_qty <= 20 AND status IN (...)
-- R14: price < mrp * 0.5 AND status = 'ACTIVE'
CREATE INDEX IF NOT EXISTS idx_products_status_price
    ON products (status, price)
    INCLUDE (product_id, title, mrp, category_id, seller_id, stock_qty);
-- Column order: equality (status) first, then range (price).
-- INCLUDE avoids a heap fetch for queries that only need these columns.
-- Serves: R02, R14
-- Plan change: Seq Scan → Index Only Scan

CREATE INDEX IF NOT EXISTS idx_products_seller_stock
    ON products (seller_id, stock_qty)
    INCLUDE (product_id, title, status);
-- Equality on seller_id first, then range on stock_qty.
-- Serves: R07, W02 (stock decrement), W03 (price update by seller+category)
-- Plan change: Seq Scan on products → Index Scan

CREATE INDEX IF NOT EXISTS idx_products_category_status
    ON products (category_id, status)
    INCLUDE (product_id, title, price, is_prime_eligible);
-- Serves: R02 (after CTE resolves category ids), R16 (category filter)
-- Plan change: Seq Scan → Index Scan

-- =====================================================================
-- 2. orders table
-- =====================================================================

-- R04: customer_id = 1042  ORDER BY ordered_at DESC
-- Equality first, then range/sort column.
CREATE INDEX IF NOT EXISTS idx_orders_customer_ordered
    ON orders (customer_id, ordered_at DESC)
    INCLUDE (order_id, status, total_amount);
-- Serves: R04, R10 (anti-join on customer), R18 (Mumbai customers 2026)
-- Plan change: Seq Scan on 120k orders → Index Scan (few rows per customer)

-- R05: status = 'SHIPPED' AND shipped_at < '2026-06-20'
-- Partial index: only 877 SHIPPED rows exist → tiny, fast index.
CREATE INDEX IF NOT EXISTS idx_orders_shipped_partial
    ON orders (shipped_at)
    WHERE status = 'SHIPPED';
-- Serves: R05
-- Plan change: Seq Scan 120k → Index Scan 877 rows

-- R06: date_trunc('month', ordered_at) = '2026-06-01'
-- Note: date_trunc() on the column is NOT sargable with a plain B-tree.
-- A partial index on the month range is sargable.
-- The optimized query in 06_optimized_queries.sql rewrites the predicate
-- to ordered_at >= '2026-06-01' AND ordered_at < '2026-07-01'.
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at
    ON orders (ordered_at)
    INCLUDE (order_id, customer_id, status, total_amount);
-- Serves: R06 (with rewrite), R08, R20, R21, R22
-- Plan change: Seq Scan → Index Scan / Bitmap Heap Scan

-- R21: delivered_at > ordered_at + interval '5 days' AND ordered_at >= '2026-06-01'
CREATE INDEX IF NOT EXISTS idx_orders_delivered_at
    ON orders (ordered_at, delivered_at)
    WHERE delivered_at IS NOT NULL;
-- Serves: R21
-- Plan change: Seq Scan → Bitmap Heap Scan

-- R22: ORDER BY ordered_at DESC OFFSET 75000 LIMIT 25
-- Index scan desc avoids sort; OFFSET still costly — keyset pagination
-- recommended for large offsets (documented in 06_optimized_queries.sql).
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at_desc
    ON orders (ordered_at DESC)
    INCLUDE (order_id, customer_id, status, total_amount);
-- Serves: R22

-- W05: UPDATE orders SET status='SHIPPED' WHERE order_id = (SELECT min(order_id) WHERE status='PACKED')
CREATE INDEX IF NOT EXISTS idx_orders_packed_id
    ON orders (order_id)
    WHERE status = 'PACKED';
-- Serves: W05 (only 59 PACKED rows on seed → trivially small index)

-- =====================================================================
-- 3. order_items table
-- =====================================================================

-- R06, R15: seller_id = 217 ... JOIN orders
CREATE INDEX IF NOT EXISTS idx_order_items_seller
    ON order_items (seller_id, order_id)
    INCLUDE (product_id, quantity, unit_price, line_no);
-- Equality on seller_id, then order_id for joining.
-- Serves: R06, R15, W03 (implicit via products join)
-- Plan change: Seq Scan on 240k → Index Scan

-- R08, R11, R12, R17, R19: product_id lookups and self-joins
CREATE INDEX IF NOT EXISTS idx_order_items_product
    ON order_items (product_id, order_id)
    INCLUDE (quantity, unit_price, seller_id, line_no);
-- Serves: R08, R11, R12, R17, R19
-- Plan change: Seq Scan 240k → Index Scan per product

-- =====================================================================
-- 4. product_reviews table
-- =====================================================================

-- R03: product_id = 4321 GROUP BY rating
CREATE INDEX IF NOT EXISTS idx_reviews_product_rating
    ON product_reviews (product_id, rating)
    INCLUDE (review_id, customer_id, verified_purchase);
-- Covering index: avoids heap fetch for R03 aggregation.
-- Serves: R03, R16 (product_id + category filter)
-- Plan change: Seq Scan on 38k → Index Only Scan

-- R16: body ILIKE '%battery%'
CREATE INDEX IF NOT EXISTS idx_reviews_body_trgm
    ON product_reviews USING GIN (body gin_trgm_ops);
-- Serves: R16
-- Plan change: Seq Scan 38k with ILIKE → Bitmap Heap Scan

-- R17: verified_purchase = TRUE AND NOT EXISTS (...)
CREATE INDEX IF NOT EXISTS idx_reviews_verified
    ON product_reviews (customer_id, product_id)
    WHERE verified_purchase = TRUE;
-- Partial index: only verified reviews. customer_id + product_id used in NOT EXISTS.
-- Serves: R17
-- Plan change: Seq Scan 38k → Partial Index Scan

-- =====================================================================
-- 5. cart_items table
-- =====================================================================

-- R10, W06: added_at < '2026-05-01'
CREATE INDEX IF NOT EXISTS idx_cart_added_at
    ON cart_items (added_at)
    INCLUDE (customer_id, product_id, quantity);
-- Serves: R10, W06
-- Plan change: Seq Scan on 44k → Bitmap Heap Scan

-- =====================================================================
-- 6. categories table
-- =====================================================================

-- R02: recursive CTE joins on parent_category_id
CREATE INDEX IF NOT EXISTS idx_categories_parent
    ON categories (parent_category_id)
    INCLUDE (category_id, category_name, is_digital);
-- Serves: R02 (recursive CTE), R12 (category hierarchy join)
-- Plan change: Seq Scan 40 rows → Index Scan (40 rows, negligible but correct)

-- =====================================================================
-- 7. addresses table
-- =====================================================================

-- R13 (NULL-safe rewrite): NOT EXISTS (SELECT 1 FROM orders WHERE address_id = a.address_id)
CREATE INDEX IF NOT EXISTS idx_orders_address_id
    ON orders (address_id)
    WHERE address_id IS NOT NULL;
-- Partial index: excludes the 5882 NULL address_id rows, keeps only the
-- rows that can actually match the anti-join.
-- Serves: R13 (optimized version)

-- =====================================================================
-- Collect statistics after index creation
-- =====================================================================
ANALYZE;
