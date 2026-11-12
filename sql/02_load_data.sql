-- =====================================================================
-- Amazon Online Shopping Database: Load Seed Data
-- Phase 2: Data Loading
-- =====================================================================

SET search_path TO amazon;

-- Load tables in order respecting foreign key dependencies
-- Parents before children

\echo 'Loading cities...'
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading categories...'
\copy categories FROM 'seed_data/categories.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading sellers...'
\copy sellers FROM 'seed_data/sellers.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading products...'
\copy products FROM 'seed_data/products.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading customers...'
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading addresses...'
\copy addresses FROM 'seed_data/addresses.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading orders...'
\copy orders FROM 'seed_data/orders.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading order_items...'
\copy order_items FROM 'seed_data/order_items.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading returns...'
\copy returns FROM 'seed_data/returns.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading product_reviews...'
\copy product_reviews FROM 'seed_data/product_reviews.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading cart_items...'
\copy cart_items FROM 'seed_data/cart_items.csv' WITH (FORMAT csv, HEADER true)

-- Collect statistics for query optimizer
ANALYZE;

-- =====================================================================
-- Verification: Row Counts
-- =====================================================================
\echo ''
\echo '=== Row Count Verification ==='
SELECT 'cities' AS table_name, count(*) AS rows FROM cities
UNION ALL SELECT 'categories', count(*) FROM categories
UNION ALL SELECT 'sellers', count(*) FROM sellers
UNION ALL SELECT 'products', count(*) FROM products
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'addresses', count(*) FROM addresses
UNION ALL SELECT 'orders', count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items
UNION ALL SELECT 'returns', count(*) FROM returns
UNION ALL SELECT 'product_reviews', count(*) FROM product_reviews
UNION ALL SELECT 'cart_items', count(*) FROM cart_items
ORDER BY 1;

-- =====================================================================
-- Data Integrity Checks
-- =====================================================================

\echo ''
\echo '=== Integrity Check 1: Order Items Seller Matches Product Seller ==='
-- Verify that order_items.seller_id always matches the product's seller
-- This is a redundant column that should be consistent
SELECT 
    count(*) AS mismatched_sellers,
    CASE 
        WHEN count(*) = 0 THEN '✓ PASS: All order items have correct seller_id'
        ELSE '✗ FAIL: Found order items with mismatched seller_id'
    END AS result
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
WHERE oi.seller_id != p.seller_id;

\echo ''
\echo '=== Integrity Check 2: Digital Products Without Addresses ==='
-- Verify that orders with only digital products can have NULL address_id
-- Physical products must have an address
SELECT 
    o.order_id,
    o.address_id,
    bool_and(c.is_digital) AS all_digital
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.order_id
LEFT JOIN products p ON p.product_id = oi.product_id
LEFT JOIN categories c ON c.category_id = p.category_id
WHERE o.address_id IS NULL
GROUP BY o.order_id, o.address_id
HAVING NOT bool_and(c.is_digital);

\echo ''
SELECT 
    CASE 
        WHEN NOT EXISTS (
            SELECT 1
            FROM orders o
            LEFT JOIN order_items oi ON oi.order_id = o.order_id
            LEFT JOIN products p ON p.product_id = oi.product_id
            LEFT JOIN categories c ON c.category_id = p.category_id
            WHERE o.address_id IS NULL
            GROUP BY o.order_id
            HAVING NOT bool_and(c.is_digital)
        ) THEN '✓ PASS: Orders without address contain only digital products'
        ELSE '✗ WARNING: Some orders without address contain physical products'
    END AS result;

\echo ''
\echo '=== Integrity Check 3: Each Customer Has Exactly One Default Address ==='
-- Verify each customer has at most one default address
WITH default_counts AS (
    SELECT 
        customer_id,
        count(*) AS default_address_count
    FROM addresses
    WHERE is_default = TRUE
    GROUP BY customer_id
    HAVING count(*) > 1
)
SELECT 
    count(*) AS customers_with_multiple_defaults,
    CASE 
        WHEN count(*) = 0 THEN '✓ PASS: No customer has multiple default addresses'
        ELSE '✗ FAIL: Some customers have multiple default addresses'
    END AS result
FROM default_counts;

\echo ''
\echo '=== Integrity Check 4: Prime Membership Consistency ==='
-- Verify is_prime flag matches prime_since column
SELECT 
    count(*) AS inconsistent_prime_records,
    CASE 
        WHEN count(*) = 0 THEN '✓ PASS: All Prime memberships are consistent'
        ELSE '✗ FAIL: Found inconsistent Prime membership records'
    END AS result
FROM customers
WHERE (is_prime = TRUE AND prime_since IS NULL) 
   OR (is_prime = FALSE AND prime_since IS NOT NULL);

\echo ''
\echo '=== Integrity Check 5: Verified Purchase Reviews ==='
-- Check if verified_purchase reviews have corresponding delivered orders
-- This check may find data quality issues (false positives in seed data)
WITH suspicious_reviews AS (
    SELECT r.review_id, r.product_id, r.customer_id
    FROM product_reviews r
    WHERE r.verified_purchase = TRUE
      AND NOT EXISTS (
          SELECT 1
          FROM orders o
          JOIN order_items oi ON oi.order_id = o.order_id
          WHERE o.customer_id = r.customer_id
            AND oi.product_id = r.product_id
            AND o.status IN ('DELIVERED', 'RETURNED')
      )
)
SELECT 
    count(*) AS suspicious_verified_reviews,
    CASE 
        WHEN count(*) = 0 THEN '✓ PASS: All verified reviews have corresponding delivered orders'
        ELSE format('⚠ WARNING: Found %s verified reviews without delivered orders (may indicate fraud or data issue)', count(*))
    END AS result
FROM suspicious_reviews;

\echo ''
\echo '=== Integrity Check 6: Order Total Amount Consistency ==='
-- Sample check: verify order total_amount is close to sum of order items
-- (allowing small rounding differences)
WITH order_totals AS (
    SELECT 
        o.order_id,
        o.total_amount AS recorded_total,
        sum(oi.quantity * oi.unit_price) AS calculated_total,
        abs(o.total_amount - sum(oi.quantity * oi.unit_price)) AS difference
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY o.order_id, o.total_amount
    HAVING abs(o.total_amount - sum(oi.quantity * oi.unit_price)) > 1
)
SELECT 
    count(*) AS orders_with_mismatch,
    CASE 
        WHEN count(*) = 0 THEN '✓ PASS: All order totals match sum of items'
        ELSE format('⚠ INFO: Found %s orders with total amount mismatch (redundant column)', count(*))
    END AS result
FROM order_totals;

\echo ''
\echo '=== Integrity Check 7: Return Refund Amounts ==='
-- Verify refund_amount is only set when status is REFUNDED
SELECT 
    count(*) AS invalid_refunds,
    CASE 
        WHEN count(*) = 0 THEN '✓ PASS: Refund amounts are consistent with status'
        ELSE '✗ FAIL: Found returns with inconsistent refund status'
    END AS result
FROM returns
WHERE (status = 'REFUNDED' AND refund_amount IS NULL)
   OR (status != 'REFUNDED' AND refund_amount IS NOT NULL);

\echo ''
\echo '=== Data Loading Complete ==='
