SET search_path TO amazon;

-- Load data from CSV files
copy cities FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/cities.csv' WITH (FORMAT csv, HEADER true);
copy categories FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/categories.csv' WITH (FORMAT csv, HEADER true);
copy sellers FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/sellers.csv' WITH (FORMAT csv, HEADER true);
copy products FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/products.csv' WITH (FORMAT csv, HEADER true);
copy customers FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/customers.csv' WITH (FORMAT csv, HEADER true);
copy addresses FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/addresses.csv' WITH (FORMAT csv, HEADER true);
copy orders_staging FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/orders.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO orders (
    order_id,
    customer_id,
    address_id,
    ordered_at,
    payment_method,
    total_amount,
    status,
    shipped_at,
    delivered_at
)
SELECT
    order_id,
    customer_id,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM addresses a
            WHERE a.address_id = o.address_id
        )
        THEN o.address_id
        ELSE NULL
    END,
    ordered_at,
    payment_method,
    total_amount,
    status,
    shipped_at,
    delivered_at
FROM orders_staging o;

copy order_items FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/order_items.csv' WITH (FORMAT csv, HEADER true);
copy cart_items FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/cart_items.csv' WITH (FORMAT csv, HEADER true);
copy product_reviews FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/product_reviews.csv' WITH (FORMAT csv, HEADER true);
copy "returns" FROM '/Users/devEnv/Documents/GitHub/DE_Project_2026/sql/seed_data/returns.csv' WITH (FORMAT csv, HEADER true);

-- Analyze all tables
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;
