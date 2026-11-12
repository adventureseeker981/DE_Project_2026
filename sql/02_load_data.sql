SET search_path TO amazon;

-- Load data from CSV files
copy addresses FROM 'DE_Project_2026/sql/seed_data/addresses.csv' WITH (FORMAT csv, HEADER true);
copy cart_items FROM 'DE_Project_2026/sql/seed_data/cart_items.csv' WITH (FORMAT csv, HEADER true);
copy categories FROM 'DE_Project_2026/sql/seed_data/categories.csv' WITH (FORMAT csv, HEADER true);
copy cities FROM 'DE_Project_2026/sql/seed_data/cities.csv' WITH (FORMAT csv, HEADER true);
copy customers FROM 'DE_Project_2026/sql/seed_data/customers.csv' WITH (FORMAT csv, HEADER true);
copy order_items FROM 'DE_Project_2026/sql/seed_data/order_items.csv' WITH (FORMAT csv, HEADER true);
copy orders FROM 'DE_Project_2026/sql/seed_data/orders.csv' WITH (FORMAT csv, HEADER true);
copy products FROM 'DE_Project_2026/sql/seed_data/products.csv' WITH (FORMAT csv, HEADER true);
copy product_reviews FROM 'DE_Project_2026/sql/seed_data/product_reviews.csv' WITH (FORMAT csv, HEADER true);
copy "RETURNS" FROM 'DE_Project_2026/sql/seed_data/returns.csv' WITH (FORMAT csv, HEADER true);
copy sellers FROM 'DE_Project_2026/sql/seed_data/sellers.csv' WITH (FORMAT csv, HEADER true);

-- Analyze all tables
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;