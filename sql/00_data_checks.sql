SET search_path TO raw;

\echo '=== A. DISTINCT VALUES ==='
SELECT 'orders.status' col, status val, count(*) FROM orders GROUP BY 2 ORDER BY 3 DESC;
SELECT 'orders.payment_method' col, payment_method val, count(*) FROM orders GROUP BY 2 ORDER BY 3 DESC;
SELECT 'addresses.label' col, label val, count(*) FROM addresses GROUP BY 2;
SELECT 'returns.reason' col, reason val, count(*) FROM returns GROUP BY 2;
SELECT 'returns.status' col, status val, count(*) FROM returns GROUP BY 2;
SELECT 'products.status' col, status val, count(*) FROM products GROUP BY 2;
SELECT 'sellers.status' col, status val, count(*) FROM sellers GROUP BY 2;
SELECT 'categories.is_digital' col, is_digital val, count(*) FROM categories GROUP BY 2;
SELECT 'reviews.rating' col, rating val, count(*) FROM product_reviews GROUP BY 2 ORDER BY 2;

\echo '=== B. NULL RULES ==='
SELECT 'orders null address' chk, count(*) FROM orders WHERE address_id IS NULL;
SELECT 'null-address orders with a non-digital item' chk, count(DISTINCT o.order_id)
FROM orders o JOIN order_items oi ON oi.order_id=o.order_id
JOIN products p ON p.product_id=oi.product_id::text
JOIN categories c ON c.category_id=p.category_id
WHERE o.address_id IS NULL AND c.is_digital='f';
SELECT 'prime vs prime_since' chk, is_prime, (prime_since IS NULL) since_null, count(*) FROM customers GROUP BY 2,3;
SELECT 'orders status vs shipped/delivered null' chk, status, (shipped_at IS NULL) ship_null, (delivered_at IS NULL) del_null, count(*) FROM orders GROUP BY 2,3,4 ORDER BY 2;
SELECT 'returns status vs refund null' chk, status, (refund_amount IS NULL) refund_null, count(*) FROM returns GROUP BY 2,3 ORDER BY 2;
SELECT 'products avg_rating null vs review_count' chk, (avg_rating IS NULL) r_null, (review_count='0') zero, count(*) FROM products GROUP BY 2,3;

\echo '=== C. FORMATS ==='
SELECT 'gstin bad' chk, count(*) FROM sellers WHERE gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$';
SELECT 'asin bad' chk, count(*) FROM products WHERE asin !~ '^B[0-9A-Z]{9}$';
SELECT 'pincode bad' chk, count(*) FROM addresses WHERE pincode !~ '^[0-9]{6}$';
SELECT 'phone bad' chk, count(*) FROM customers WHERE phone !~ '^[0-9]{10}$';
SELECT 'dup email' chk, count(*) FROM (SELECT lower(email) FROM customers GROUP BY 1 HAVING count(*)>1) x;
SELECT 'dup phone' chk, count(*) FROM (SELECT phone FROM customers GROUP BY 1 HAVING count(*)>1) x;
SELECT 'dup asin' chk, count(*) FROM (SELECT asin FROM products GROUP BY 1 HAVING count(*)>1) x;
SELECT 'dup gstin' chk, count(*) FROM (SELECT gstin FROM sellers GROUP BY 1 HAVING count(*)>1) x;

\echo '=== D. BUSINESS RULES ==='
SELECT 'price > mrp' chk, count(*) FROM products WHERE price::numeric > mrp::numeric;
SELECT 'price <= 0' chk, count(*) FROM products WHERE price::numeric <= 0;
SELECT 'stock < 0' chk, count(*) FROM products WHERE stock_qty::int < 0;
SELECT 'qty <= 0 (items)' chk, count(*) FROM order_items WHERE quantity::int <= 0;
SELECT 'cart qty <= 0' chk, count(*) FROM cart_items WHERE quantity::int <= 0;
SELECT 'seller_rating out of 0-5' chk, count(*) FROM sellers WHERE seller_rating::numeric NOT BETWEEN 0 AND 5;
SELECT 'order_items.seller_id <> product seller' chk, count(*) FROM order_items oi JOIN products p ON p.product_id=oi.product_id WHERE p.seller_id<>oi.seller_id;
SELECT 'total_amount <> sum(lines)' chk, count(*) FROM orders o
JOIN (SELECT order_id, sum(quantity::int*unit_price::numeric) s FROM order_items GROUP BY 1) x ON x.order_id=o.order_id
WHERE o.total_amount::numeric <> x.s;
SELECT 'customers w/o exactly 1 default addr' chk, count(*) FROM customers c
LEFT JOIN (SELECT customer_id, count(*) n FROM addresses WHERE is_default='t' GROUP BY 1) d ON d.customer_id=c.customer_id
WHERE coalesce(d.n,0)<>1;
SELECT 'delivered_at < shipped_at' chk, count(*) FROM orders WHERE delivered_at::timestamptz < shipped_at::timestamptz;
SELECT 'shipped_at < ordered_at' chk, count(*) FROM orders WHERE shipped_at::timestamptz < ordered_at::timestamptz;
SELECT 'order address belongs to other customer' chk, count(*) FROM orders o JOIN addresses a ON a.address_id=o.address_id WHERE a.customer_id<>o.customer_id;

\echo '=== E. ORPHANS (FK checks) ==='
SELECT 'orders->customers' chk, count(*) FROM orders o LEFT JOIN customers c USING(customer_id) WHERE c.customer_id IS NULL;
SELECT 'order_items->orders' chk, count(*) FROM order_items oi LEFT JOIN orders o USING(order_id) WHERE o.order_id IS NULL;
SELECT 'order_items->products' chk, count(*) FROM order_items oi LEFT JOIN products p USING(product_id) WHERE p.product_id IS NULL;
SELECT 'returns->order_items' chk, count(*) FROM returns r LEFT JOIN order_items oi ON oi.order_id=r.order_id AND oi.line_no=r.line_no WHERE oi.order_id IS NULL;
SELECT 'reviews->customers' chk, count(*) FROM product_reviews r LEFT JOIN customers c USING(customer_id) WHERE c.customer_id IS NULL;
SELECT 'cart->products' chk, count(*) FROM cart_items ci LEFT JOIN products p USING(product_id) WHERE p.product_id IS NULL;
SELECT 'dup cart (customer,product)' chk, count(*) FROM (SELECT 1 FROM cart_items GROUP BY customer_id, product_id HAVING count(*)>1) x;
SELECT 'dup review (product,customer)' chk, count(*) FROM (SELECT 1 FROM product_reviews GROUP BY product_id, customer_id HAVING count(*)>1) x;
SELECT 'categories parent orphan' chk, count(*) FROM categories c LEFT JOIN categories p ON p.category_id=c.parent_category_id WHERE c.parent_category_id IS NOT NULL AND p.category_id IS NULL;
