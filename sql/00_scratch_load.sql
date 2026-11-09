DROP SCHEMA IF EXISTS raw CASCADE;
CREATE SCHEMA raw;
SET search_path TO raw;

CREATE TABLE cities (city_id text, city_name text, state text);
CREATE TABLE categories (category_id text, category_name text, parent_category_id text, is_digital text);
CREATE TABLE sellers (seller_id text, business_name text, gstin text, city_id text, joined_on text, seller_rating text, status text);
CREATE TABLE products (product_id text, asin text, seller_id text, category_id text, title text, brand text, mrp text, price text, stock_qty text, is_prime_eligible text, avg_rating text, review_count text, listed_on text, status text);
CREATE TABLE customers (customer_id text, full_name text, email text, phone text, city_id text, signup_date text, is_prime text, prime_since text);
CREATE TABLE addresses (address_id text, customer_id text, label text, line1 text, city_id text, pincode text, is_default text);
CREATE TABLE orders (order_id text, customer_id text, address_id text, ordered_at text, payment_method text, total_amount text, status text, shipped_at text, delivered_at text);
CREATE TABLE order_items (order_id text, line_no text, product_id text, seller_id text, quantity text, unit_price text);
CREATE TABLE returns (return_id text, order_id text, line_no text, reason text, requested_at text, status text, refund_amount text);
CREATE TABLE product_reviews (review_id text, product_id text, customer_id text, rating text, title text, body text, verified_purchase text, helpful_votes text, created_at text);
CREATE TABLE cart_items (customer_id text, product_id text, quantity text, added_at text);

\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)
\copy categories FROM 'seed_data/categories.csv' WITH (FORMAT csv, HEADER true)
\copy sellers FROM 'seed_data/sellers.csv' WITH (FORMAT csv, HEADER true)
\copy products FROM 'seed_data/products.csv' WITH (FORMAT csv, HEADER true)
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true)
\copy addresses FROM 'seed_data/addresses.csv' WITH (FORMAT csv, HEADER true)
\copy orders FROM 'seed_data/orders.csv' WITH (FORMAT csv, HEADER true)
\copy order_items FROM 'seed_data/order_items.csv' WITH (FORMAT csv, HEADER true)
\copy returns FROM 'seed_data/returns.csv' WITH (FORMAT csv, HEADER true)
\copy product_reviews FROM 'seed_data/product_reviews.csv' WITH (FORMAT csv, HEADER true)
\copy cart_items FROM 'seed_data/cart_items.csv' WITH (FORMAT csv, HEADER true)

SELECT 'cities' t, count(*) FROM cities UNION ALL
SELECT 'categories', count(*) FROM categories UNION ALL
SELECT 'sellers', count(*) FROM sellers UNION ALL
SELECT 'products', count(*) FROM products UNION ALL
SELECT 'customers', count(*) FROM customers UNION ALL
SELECT 'addresses', count(*) FROM addresses UNION ALL
SELECT 'orders', count(*) FROM orders UNION ALL
SELECT 'order_items', count(*) FROM order_items UNION ALL
SELECT 'returns', count(*) FROM returns UNION ALL
SELECT 'product_reviews', count(*) FROM product_reviews UNION ALL
SELECT 'cart_items', count(*) FROM cart_items;
