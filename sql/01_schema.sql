-- =====================================================================
-- Amazon Online Shopping Database Schema
-- Phase 2: Schema Design
-- =====================================================================

DROP SCHEMA IF EXISTS amazon CASCADE;
CREATE SCHEMA amazon;
SET search_path TO amazon;

-- =====================================================================
-- 1. CITIES (Master table for locations)
-- =====================================================================
CREATE TABLE cities (
    city_id INTEGER PRIMARY KEY,
    city_name VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    CONSTRAINT chk_city_id_positive CHECK (city_id > 0)
);

-- =====================================================================
-- 2. CATEGORIES (Hierarchical product categories)
-- =====================================================================
CREATE TABLE categories (
    category_id INTEGER PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    parent_category_id INTEGER,
    is_digital BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_parent_category FOREIGN KEY (parent_category_id) 
        REFERENCES categories(category_id) ON DELETE RESTRICT,
    CONSTRAINT chk_category_id_positive CHECK (category_id > 0),
    CONSTRAINT chk_not_self_parent CHECK (category_id != parent_category_id)
);

-- =====================================================================
-- 3. SELLERS (Business entities selling on Amazon)
-- =====================================================================
CREATE TABLE sellers (
    seller_id INTEGER PRIMARY KEY,
    business_name VARCHAR(200) NOT NULL,
    gstin VARCHAR(15) NOT NULL UNIQUE,
    city_id INTEGER NOT NULL,
    joined_on DATE NOT NULL,
    seller_rating NUMERIC(2,1),
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_seller_city FOREIGN KEY (city_id) 
        REFERENCES cities(city_id) ON DELETE RESTRICT,
    CONSTRAINT chk_seller_id_positive CHECK (seller_id > 0),
    CONSTRAINT chk_gstin_format CHECK (gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[0-9A-Z]{1}[Z]{1}[0-9A-Z]{1}$'),
    CONSTRAINT chk_seller_rating CHECK (seller_rating BETWEEN 1.0 AND 5.0),
    CONSTRAINT chk_seller_status CHECK (status IN ('ACTIVE', 'SUSPENDED', 'INACTIVE', 'CLOSED')),
    CONSTRAINT chk_joined_date CHECK (joined_on <= CURRENT_DATE)
);

-- =====================================================================
-- 4. PRODUCTS (Product listings)
-- =====================================================================
CREATE TABLE products (
    product_id INTEGER PRIMARY KEY,
    asin VARCHAR(10) NOT NULL UNIQUE,
    seller_id INTEGER NOT NULL,
    category_id INTEGER NOT NULL,
    title VARCHAR(500) NOT NULL,
    brand VARCHAR(100),
    mrp NUMERIC(10,2) NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    stock_qty INTEGER NOT NULL DEFAULT 0,
    is_prime_eligible BOOLEAN NOT NULL DEFAULT FALSE,
    avg_rating NUMERIC(2,1),
    review_count INTEGER NOT NULL DEFAULT 0,
    listed_on DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_product_seller FOREIGN KEY (seller_id) 
        REFERENCES sellers(seller_id) ON DELETE RESTRICT,
    CONSTRAINT fk_product_category FOREIGN KEY (category_id) 
        REFERENCES categories(category_id) ON DELETE RESTRICT,
    CONSTRAINT chk_product_id_positive CHECK (product_id > 0),
    CONSTRAINT chk_asin_format CHECK (asin ~ '^B[0-9A-Z]{9}$'),
    CONSTRAINT chk_mrp_positive CHECK (mrp > 0),
    CONSTRAINT chk_price_positive CHECK (price > 0),
    CONSTRAINT chk_price_lte_mrp CHECK (price <= mrp),
    CONSTRAINT chk_stock_non_negative CHECK (stock_qty >= 0),
    CONSTRAINT chk_product_rating CHECK (avg_rating IS NULL OR avg_rating BETWEEN 1.0 AND 5.0),
    CONSTRAINT chk_review_count_non_negative CHECK (review_count >= 0),
    CONSTRAINT chk_product_status CHECK (status IN ('ACTIVE', 'OUT_OF_STOCK', 'DISCONTINUED', 'INACTIVE')),
    CONSTRAINT chk_listed_date CHECK (listed_on <= CURRENT_DATE)
);

-- =====================================================================
-- 5. CUSTOMERS (Shoppers)
-- =====================================================================
CREATE TABLE customers (
    customer_id INTEGER PRIMARY KEY,
    full_name VARCHAR(200) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(10) NOT NULL UNIQUE,
    city_id INTEGER NOT NULL,
    signup_date DATE NOT NULL,
    is_prime BOOLEAN NOT NULL DEFAULT FALSE,
    prime_since DATE,
    CONSTRAINT fk_customer_city FOREIGN KEY (city_id) 
        REFERENCES cities(city_id) ON DELETE RESTRICT,
    CONSTRAINT chk_customer_id_positive CHECK (customer_id > 0),
    CONSTRAINT chk_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_phone_format CHECK (phone ~ '^[6-9][0-9]{9}$'),
    CONSTRAINT chk_signup_date CHECK (signup_date <= CURRENT_DATE),
    CONSTRAINT chk_prime_consistency CHECK (
        (is_prime = FALSE AND prime_since IS NULL) OR 
        (is_prime = TRUE AND prime_since IS NOT NULL)
    ),
    CONSTRAINT chk_prime_since_after_signup CHECK (prime_since IS NULL OR prime_since >= signup_date)
);

-- =====================================================================
-- 6. ADDRESSES (Customer delivery addresses)
-- =====================================================================
CREATE TABLE addresses (
    address_id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    label VARCHAR(20) NOT NULL,
    line1 VARCHAR(500) NOT NULL,
    city_id INTEGER NOT NULL,
    pincode VARCHAR(6) NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_address_customer FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id) ON DELETE CASCADE,
    CONSTRAINT fk_address_city FOREIGN KEY (city_id) 
        REFERENCES cities(city_id) ON DELETE RESTRICT,
    CONSTRAINT chk_address_id_positive CHECK (address_id > 0),
    CONSTRAINT chk_address_label CHECK (label IN ('HOME', 'WORK', 'OTHER')),
    CONSTRAINT chk_pincode_format CHECK (pincode ~ '^[1-9][0-9]{5}$')
);

-- Ensure each customer has at most one default address
CREATE UNIQUE INDEX idx_one_default_address_per_customer 
    ON addresses(customer_id) WHERE is_default = TRUE;

-- =====================================================================
-- 7. ORDERS (Order headers)
-- =====================================================================
CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    address_id INTEGER,
    ordered_at TIMESTAMPTZ NOT NULL,
    payment_method VARCHAR(20) NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PLACED',
    shipped_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_address FOREIGN KEY (address_id) 
        REFERENCES addresses(address_id) ON DELETE RESTRICT,
    CONSTRAINT chk_order_id_positive CHECK (order_id > 0),
    CONSTRAINT chk_payment_method CHECK (payment_method IN ('CARD', 'UPI', 'NET_BANKING', 'NETBANKING', 'COD', 'WALLET', 'GIFT_CARD', 'EMI')),
    CONSTRAINT chk_total_amount_positive CHECK (total_amount > 0),
    CONSTRAINT chk_order_status CHECK (status IN ('PLACED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'RETURNED')),
    CONSTRAINT chk_shipped_after_ordered CHECK (shipped_at IS NULL OR shipped_at >= ordered_at),
    CONSTRAINT chk_delivered_after_shipped CHECK (delivered_at IS NULL OR delivered_at >= ordered_at),
    CONSTRAINT chk_status_delivered_consistency CHECK (
        (status IN ('DELIVERED', 'RETURNED') AND delivered_at IS NOT NULL) OR
        (status NOT IN ('DELIVERED', 'RETURNED'))
    )
);

-- =====================================================================
-- 8. ORDER_ITEMS (Order line items)
-- =====================================================================
CREATE TABLE order_items (
    order_id INTEGER NOT NULL,
    line_no INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    seller_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    CONSTRAINT pk_order_items PRIMARY KEY (order_id, line_no),
    CONSTRAINT fk_order_item_order FOREIGN KEY (order_id) 
        REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_order_item_product FOREIGN KEY (product_id) 
        REFERENCES products(product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_item_seller FOREIGN KEY (seller_id) 
        REFERENCES sellers(seller_id) ON DELETE RESTRICT,
    CONSTRAINT chk_line_no_positive CHECK (line_no > 0),
    CONSTRAINT chk_quantity_positive CHECK (quantity > 0),
    CONSTRAINT chk_unit_price_positive CHECK (unit_price > 0)
);

-- =====================================================================
-- 9. RETURNS (Product return requests)
-- =====================================================================
CREATE TABLE returns (
    return_id INTEGER PRIMARY KEY,
    order_id INTEGER NOT NULL,
    line_no INTEGER NOT NULL,
    reason VARCHAR(50) NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'REQUESTED',
    refund_amount NUMERIC(10,2),
    CONSTRAINT fk_return_order_item FOREIGN KEY (order_id, line_no) 
        REFERENCES order_items(order_id, line_no) ON DELETE CASCADE,
    CONSTRAINT chk_return_id_positive CHECK (return_id > 0),
    CONSTRAINT chk_return_reason CHECK (reason IN ('QUALITY_ISSUE', 'WRONG_ITEM', 'NOT_NEEDED', 'DAMAGED', 'DEFECTIVE', 'OTHER', 'NO_LONGER_NEEDED', 'NOT_AS_DESCRIBED', 'SIZE_ISSUE')),
    CONSTRAINT chk_return_status CHECK (status IN ('REQUESTED', 'APPROVED', 'REJECTED', 'REFUNDED', 'PICKED_UP')),
    CONSTRAINT chk_refund_consistency CHECK (
        (status = 'REFUNDED' AND refund_amount IS NOT NULL AND refund_amount > 0) OR
        (status != 'REFUNDED' AND refund_amount IS NULL)
    )
);

-- =====================================================================
-- 10. PRODUCT_REVIEWS (Customer product reviews)
-- =====================================================================
CREATE TABLE product_reviews (
    review_id INTEGER PRIMARY KEY,
    product_id INTEGER NOT NULL,
    customer_id INTEGER NOT NULL,
    rating INTEGER NOT NULL,
    title VARCHAR(200),
    body TEXT,
    verified_purchase BOOLEAN NOT NULL DEFAULT FALSE,
    helpful_votes INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_review_product FOREIGN KEY (product_id) 
        REFERENCES products(product_id) ON DELETE CASCADE,
    CONSTRAINT fk_review_customer FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id) ON DELETE CASCADE,
    CONSTRAINT chk_review_id_positive CHECK (review_id > 0),
    CONSTRAINT chk_rating_range CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT chk_helpful_votes_non_negative CHECK (helpful_votes >= 0)
);

-- =====================================================================
-- 11. CART_ITEMS (Shopping cart items)
-- =====================================================================
CREATE TABLE cart_items (
    customer_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    added_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT pk_cart_items PRIMARY KEY (customer_id, product_id),
    CONSTRAINT fk_cart_customer FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id) ON DELETE CASCADE,
    CONSTRAINT fk_cart_product FOREIGN KEY (product_id) 
        REFERENCES products(product_id) ON DELETE CASCADE,
    CONSTRAINT chk_cart_quantity_positive CHECK (quantity > 0)
);

-- =====================================================================
-- Analyze all tables for query planning
-- =====================================================================
ANALYZE;
