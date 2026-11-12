DROP SCHEMA IF EXISTS amazon CASCADE;
CREATE SCHEMA amazon;
SET search_path TO amazon;
DROP TABLE IF EXISTS ADDRESSES;
DROP TABLE IF EXISTS CART_ITEMS;
DROP TABLE IF EXISTS CATEGORIES;
DROP TABLE IF EXISTS CITIES;
DROP TABLE IF EXISTS CUSTOMERS;
DROP TABLE IF EXISTS ORDER_ITEMS;
DROP TABLE IF EXISTS ORDERS;
DROP TABLE IF EXISTS PRODUCT_REVIEWS;
DROP TABLE IF EXISTS PRODUCTS;
DROP TABLE IF EXISTS "RETURNS";
DROP TABLE IF EXISTS SELLERS;

CREATE TABLE cities (
    city_id SERIAL PRIMARY KEY,
    city_name VARCHAR(50) NOT NULL,
    "state" VARCHAR(50) NOT NULL
);

CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    full_name VARCHAR(80) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone CHAR(10) NOT NULL UNIQUE CHECK (phone ~ '^[0-9]{10}$'),
    city_id INT NOT NULL REFERENCES cities (city_id),
    signup_date DATE NOT NULL DEFAULT now(),
    is_prime BOOLEAN NOT NULL DEFAULT FALSE,
    prime_since DATE DEFAULT NULL
);

CREATE TABLE addresses (
    address_id INT PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers (customer_id),
    "label" VARCHAR(20) NOT NULL,
    line1 VARCHAR(100) NOT NULL,
    city_id INT NOT NULL REFERENCES cities (city_id),
    pincode CHAR(6) NOT NULL CHECK (pincode ~ '^[0-9]{6}$'),
    is_default BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers (customer_id),
    address_id INT NOT NULL REFERENCES addresses (address_id),
    ordered_at TIMESTAMP NOT NULL DEFAULT now(),
    payment_method VARCHAR(20) NOT NULL,
    total_amount NUMERIC NOT NULL CONSTRAINT CHK_PRICE CHECK (total_amount > 0),
    "status" VARCHAR(20) NOT NULL CONSTRAINT CHK_STATUS CHECK (
        "status" IN (
            'DELIVERED',
            'CANCELLED',
            'RETURNED',
            'SHIPPED',
            'PROCESSING',
            'PLACED'
        )
    ),
    shipped_at TIMESTAMP DEFAULT NULL,
    delivered_at TIMESTAMP DEFAULT NULL
);

CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(50) NOT NULL,
    parent_category_id INT REFERENCES categories (category_id) DEFAULT NULL,
    is_digital BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE sellers (
    seller_id SERIAL PRIMARY KEY,
    business_name VARCHAR(80) NOT NULL,
    gstin CHAR(15) NOT NULL UNIQUE CHECK (
        gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$'
    ),
    city_id INT NOT NULL REFERENCES cities (city_id),
    joined_on DATE NOT NULL DEFAULT now(),
    seller_rating NUMERIC NOT NULL CONSTRAINT CHK_RATING CHECK (seller_rating BETWEEN 0 AND 5),
    "status" VARCHAR(20) NOT NULL CONSTRAINT CHK_STATUS CHECK (
        "status" IN (
            'ACTIVE',
            'SUSPENDED',
            'CLOSED'
        )
    )
);

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    seller_id INT NOT NULL REFERENCES sellers (seller_id),
    asin CHAR(10) NOT NULL UNIQUE CHECK (asin ~ '^B[0-9A-Z]{9}$'),
    product_name VARCHAR(100) NOT NULL,
    category_id INT NOT NULL REFERENCES categories (category_id),
    price NUMERIC NOT NULL CONSTRAINT CHK_PRICE CHECK (price > 0),
    mrp NUMERIC NOT NULL CONSTRAINT CHK_MRP CHECK (mrp > 0),
    stock_qty INT NOT NULL CONSTRAINT CHK_STOCK CHECK (stock_qty >= 0),
    avg_rating NUMERIC DEFAULT NULL,
    review_count INT NOT NULL DEFAULT 0
);

CREATE TABLE cart_items (
    customer_id INT NOT NULL REFERENCES customers (customer_id),
    product_id INT NOT NULL REFERENCES products (product_id),
    quantity INT NOT NULL CONSTRAINT CHK_QTY CHECK (quantity > 0),
    added_at TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (customer_id, product_id)
);

CREATE TABLE order_items (
    order_id INT NOT NULL REFERENCES orders (order_id),
    line_no INT NOT NULL,
    product_id INT NOT NULL REFERENCES products (product_id),
    seller_id INT NOT NULL REFERENCES sellers (seller_id),
    quantity INT NOT NULL CONSTRAINT CHK_QTY CHECK (quantity > 0),
    unit_price NUMERIC NOT NULL CONSTRAINT CHK_PRICE CHECK (unit_price > 0),
    PRIMARY KEY (order_id, line_no)
);

CREATE TABLE product_reviews (
    review_id SERIAL PRIMARY KEY,
    product_id INT NOT NULL REFERENCES products (product_id),
    customer_id INT NOT NULL REFERENCES customers (customer_id),
    rating INT NOT NULL CONSTRAINT CHK_RATING CHECK (rating BETWEEN 1 AND 5),
    title TEXT DEFAULT NULL,
    "body" TEXT DEFAULT NULL,
    verified_purchase BOOLEAN NOT NULL DEFAULT FALSE,
    helpful_votes INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE "RETURNS" (
    return_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES orders (order_id),
    product_id INT NOT NULL REFERENCES products (product_id),
    quantity INT NOT NULL CONSTRAINT CHK_QTY CHECK (quantity > 0),
    refund_amount NUMERIC NOT NULL CONSTRAINT CHK_PRICE CHECK (refund_amount > 0),
    "status" VARCHAR(20) NOT NULL CONSTRAINT CHK_STATUS CHECK (
        "status" IN (
            'DELIVERED',
            'CANCELLED',
            'RETURNED',
            'SHIPPED',
            'PROCESSING',
            'PLACED'
        )
    ),
    reason VARCHAR(100) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);