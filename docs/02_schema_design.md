# Phase 2: Schema Design Documentation

## Executive Summary

This document presents the complete database schema for the Amazon Online Shopping platform, reconstructed from CSV data exports. The schema consists of 11 tables in 3NF/BCNF with comprehensive constraints, foreign key relationships, and business rules enforced at the database level.

## Table of Contents
1. [Data Dictionary](#data-dictionary)
2. [Entity Relationship Diagram](#entity-relationship-diagram)
3. [Functional Dependencies and Normalization](#functional-dependencies-and-normalization)
4. [Data Loading Results](#data-loading-results)
5. [Data Quality Issues](#data-quality-issues)

---

## Data Dictionary

### 1. CITIES

Master table for geographic locations.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| city_id | INTEGER | PRIMARY KEY, CHECK > 0 | Unique city identifier |
| city_name | VARCHAR(100) | NOT NULL | City name (e.g., "Mumbai", "Bengaluru") |
| state | VARCHAR(100) | NOT NULL | State name (e.g., "Maharashtra", "Karnataka") |

**Rationale:**
- `INTEGER` for city_id: Small fixed set (10 cities in seed data), integer is efficient
- No UNIQUE on city_name: Multiple cities can have same name in different states
- No CASCADE deletes: Cities are master data, should not be deleted if referenced

---

### 2. CATEGORIES

Hierarchical product categorization using adjacency list model.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| category_id | INTEGER | PRIMARY KEY, CHECK > 0 | Unique category identifier |
| category_name | VARCHAR(100) | NOT NULL, UNIQUE | Human-readable category name |
| parent_category_id | INTEGER | FK → categories(category_id), CHECK != category_id | Points to parent in hierarchy; NULL for root categories |
| is_digital | BOOLEAN | NOT NULL, DEFAULT FALSE | TRUE if products are digital (no shipping needed) |

**Rationale:**
- Self-referencing FK with RESTRICT: Prevent deletion of categories with children
- UNIQUE on category_name: Ensures consistent category references in business logic
- Self-parent check: Prevents circular reference at single-node level
- `is_digital` flag: Determines if orders need shipping addresses

**Why this matters:** Query R02 uses recursive CTE to traverse this tree. Proper indexing on parent_category_id is crucial for performance.

---

### 3. SELLERS

Business entities selling products on the platform.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| seller_id | INTEGER | PRIMARY KEY, CHECK > 0 | Unique seller identifier |
| business_name | VARCHAR(200) | NOT NULL | Legal business name |
| gstin | VARCHAR(15) | NOT NULL, UNIQUE, CHECK format | GST Identification Number (Indian tax ID) |
| city_id | INTEGER | FK → cities, NOT NULL | Seller's registered city |
| joined_on | DATE | NOT NULL, CHECK ≤ today | Date seller registered |
| seller_rating | NUMERIC(2,1) | CHECK 1.0-5.0 | Average seller rating (can be NULL initially) |
| status | VARCHAR(20) | NOT NULL, CHECK IN (...), DEFAULT 'ACTIVE' | Account status |

**Rationale:**
- GSTIN format: `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[0-9A-Z]{1}[Z]{1}[0-9A-Z]{1}$` (Indian GST format)
- UNIQUE on gstin: One business entity = one account
- Rating can be NULL: New sellers have no ratings yet
- Joined date ≤ today: Prevents future dates
- ON DELETE RESTRICT for city: Master data should not be deleted

**Business Rules:**
- Valid status values: ACTIVE, SUSPENDED, INACTIVE
- Only ACTIVE sellers' products appear in search

---

### 4. PRODUCTS

Product listings on the platform.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| product_id | INTEGER | PRIMARY KEY, CHECK > 0 | Unique product identifier |
| asin | VARCHAR(10) | NOT NULL, UNIQUE, CHECK format | Amazon Standard Identification Number |
| seller_id | INTEGER | FK → sellers, NOT NULL | Seller offering this product |
| category_id | INTEGER | FK → categories, NOT NULL | Product category |
| title | VARCHAR(500) | NOT NULL | Product title (searchable) |
| brand | VARCHAR(100) | NULL | Brand name (can be NULL for generic) |
| mrp | NUMERIC(10,2) | NOT NULL, CHECK > 0 | Maximum Retail Price |
| price | NUMERIC(10,2) | NOT NULL, CHECK > 0, CHECK ≤ mrp | Selling price |
| stock_qty | INTEGER | NOT NULL, DEFAULT 0, CHECK ≥ 0 | Available quantity |
| is_prime_eligible | BOOLEAN | NOT NULL, DEFAULT FALSE | Eligible for Prime delivery |
| avg_rating | NUMERIC(2,1) | CHECK 1.0-5.0 | Average customer rating (DERIVED) |
| review_count | INTEGER | NOT NULL, DEFAULT 0, CHECK ≥ 0 | Number of reviews (DERIVED) |
| listed_on | DATE | NOT NULL, CHECK ≤ today | Date product was listed |
| status | VARCHAR(20) | NOT NULL, CHECK IN (...), DEFAULT 'ACTIVE' | Product status |

**Rationale:**
- ASIN format: `^B[0-9]{4}[0-9A-Z]{5}$` (Amazon's standard format)
- price ≤ mrp: Selling price cannot exceed MRP
- NUMERIC(10,2): Supports prices up to ₹99,999,999.99 with 2 decimal places (paise)
- ON DELETE RESTRICT: Cannot delete sellers or categories with active products

**Derived/Redundant Columns:**
- `avg_rating` and `review_count` are derived from product_reviews table
- **Justification:** Displayed on every search result and product page (queries R01, R02, R08). Computing on-the-fly would require aggregating reviews for every product in results. Trade-off: accepts slight staleness for massive performance gain.
- **Maintenance:** Should be updated via triggers or batch job when reviews change

**Business Rules:**
- Valid status: ACTIVE, OUT_OF_STOCK, DISCONTINUED
- Only ACTIVE products appear in customer search (R01, R02)

---

### 5. CUSTOMERS

Registered shoppers on the platform.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| customer_id | INTEGER | PRIMARY KEY, CHECK > 0 | Unique customer identifier |
| full_name | VARCHAR(200) | NOT NULL | Customer's full name |
| email | VARCHAR(255) | NOT NULL, UNIQUE, CHECK format | Email address (login credential) |
| phone | VARCHAR(10) | NOT NULL, UNIQUE, CHECK format | 10-digit Indian mobile number |
| city_id | INTEGER | FK → cities, NOT NULL | Customer's city |
| signup_date | DATE | NOT NULL, CHECK ≤ today | Account creation date |
| is_prime | BOOLEAN | NOT NULL, DEFAULT FALSE | Prime membership status |
| prime_since | DATE | NULL, CHECK ≥ signup_date | Date Prime membership started |

**Rationale:**
- Email format: Standard email regex validation
- Phone format: `^[6-9][0-9]{9}$` (Indian mobile numbers start with 6-9)
- UNIQUE on email and phone: One account per credential
- **Prime consistency CHECK:** `(is_prime=FALSE ∧ prime_since IS NULL) ∨ (is_prime=TRUE ∧ prime_since IS NOT NULL)`
  - If not Prime, prime_since must be NULL
  - If Prime, prime_since must be set
- prime_since ≥ signup_date: Cannot be Prime before account creation

**Why this matters:** Query R09 groups by is_prime; consistency is critical for accurate business metrics.

---

### 6. ADDRESSES

Customer shipping addresses.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| address_id | INTEGER | PRIMARY KEY, CHECK > 0 | Unique address identifier |
| customer_id | INTEGER | FK → customers, NOT NULL | Address owner |
| label | VARCHAR(20) | NOT NULL, CHECK IN (...) | Address label: HOME, WORK, OTHER |
| line1 | VARCHAR(500) | NOT NULL | Street address |
| city_id | INTEGER | FK → cities, NOT NULL | Delivery city |
| pincode | VARCHAR(6) | NOT NULL, CHECK format | 6-digit Indian postal code |
| is_default | BOOLEAN | NOT NULL, DEFAULT FALSE | Default delivery address |

**Rationale:**
- ON DELETE CASCADE for customer: When account deleted, remove all addresses
- Pincode format: `^[1-9][0-9]{5}$` (6 digits, cannot start with 0)
- **UNIQUE INDEX on (customer_id) WHERE is_default=TRUE:** Enforces "at most one default address per customer"
  - Partial index: only indexes rows where is_default=TRUE
  - Prevents two addresses for same customer both being default

**Business Rules:**
- Unused addresses identified by query R13 for periodic cleanup

---

### 7. ORDERS

Order header records.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| order_id | INTEGER | PRIMARY KEY, CHECK > 0 | Unique order identifier |
| customer_id | INTEGER | FK → customers, NOT NULL | Customer who placed order |
| address_id | INTEGER | FK → addresses, NULL | Delivery address (NULL for digital-only orders) |
| ordered_at | TIMESTAMPTZ | NOT NULL | Order timestamp with timezone (IST) |
| payment_method | VARCHAR(20) | NOT NULL, CHECK IN (...) | Payment method used |
| total_amount | NUMERIC(10,2) | NOT NULL, CHECK > 0 | Order total (DERIVED) |
| status | VARCHAR(20) | NOT NULL, CHECK IN (...), DEFAULT 'PLACED' | Order status |
| shipped_at | TIMESTAMPTZ | NULL, CHECK ≥ ordered_at | Shipping timestamp |
| delivered_at | TIMESTAMPTZ | NULL, CHECK ≥ shipped_at | Delivery timestamp |

**Rationale:**
- address_id can be NULL: Digital products don't need shipping
- TIMESTAMPTZ: Stores time with timezone (IST = UTC+5:30), critical for accurate time-based queries
- Payment methods: CARD, UPI, NET_BANKING, COD, WALLET, GIFT_CARD
- Status values: PLACED, PACKED, SHIPPED, OUT_FOR_DELIVERY, DELIVERED, CANCELLED, RETURNED
- ON DELETE RESTRICT: Cannot delete customers or addresses with orders (audit trail)

**Complex Business Rules (enforced via CHECK):**
1. **Shipped consistency:** If status ∈ {SHIPPED, OUT_FOR_DELIVERY, DELIVERED}, then shipped_at IS NOT NULL
2. **Delivered consistency:** If status ∈ {DELIVERED, RETURNED}, then delivered_at IS NOT NULL
3. **Temporal ordering:** ordered_at ≤ shipped_at ≤ delivered_at

**Derived Column:**
- `total_amount` = SUM(quantity × unit_price) from order_items
- **Justification:** Displayed in every order list (R04, R22) and used in aggregations (R09, R20). Recomputing would require joining order_items every time. Accepts temporary inconsistency for performance.

**Why address_id can be NULL:**
- Digital products (e-books, gift cards) don't require physical delivery
- Verified by integrity check: Orders with NULL address contain only digital products

---

### 8. ORDER_ITEMS

Order line items (order details).

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| order_id | INTEGER | PK part 1, FK → orders | Order this line belongs to |
| line_no | INTEGER | PK part 2, CHECK > 0 | Line number within order |
| product_id | INTEGER | FK → products, NOT NULL | Product being ordered |
| seller_id | INTEGER | FK → sellers, NOT NULL | Seller fulfilling this line (REDUNDANT) |
| quantity | INTEGER | NOT NULL, CHECK > 0 | Quantity ordered |
| unit_price | NUMERIC(10,2) | NOT NULL, CHECK > 0 | Price per unit at order time |

**Rationale:**
- **Composite PRIMARY KEY (order_id, line_no):** Uniquely identifies each line within an order
- ON DELETE CASCADE for orders: When order deleted, remove all lines
- ON DELETE RESTRICT for products/sellers: Maintain audit trail

**Redundant Column:**
- `seller_id` is redundant: can be derived from products.seller_id via product_id
- **Why it exists:** Denormalization for performance
  - Query R06 (seller's order lines) filters by seller_id—having it here avoids joining products table
  - Historical accuracy: If product changes sellers, past orders show original seller
- **Integrity:** Verified by data check: order_items.seller_id always matches products.seller_id

**Historical Price:**
- `unit_price` stores price at order time, not current product price
- Critical for accurate revenue reports and prevents price changes from affecting order history

---

### 9. RETURNS

Product return requests.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| return_id | INTEGER | PRIMARY KEY, CHECK > 0 | Unique return request identifier |
| order_id | INTEGER | FK part 1 | Order being returned |
| line_no | INTEGER | FK part 2 | Specific line being returned |
| reason | VARCHAR(50) | NOT NULL, CHECK IN (...) | Return reason code |
| requested_at | TIMESTAMPTZ | NOT NULL | When return was requested |
| status | VARCHAR(20) | NOT NULL, CHECK IN (...), DEFAULT 'REQUESTED' | Return processing status |
| refund_amount | NUMERIC(10,2) | NULL, CHECK > 0 | Refunded amount (NULL until refunded) |

**Rationale:**
- **FOREIGN KEY (order_id, line_no) → order_items:** Returns reference specific order lines
- Return reasons: QUALITY_ISSUE, WRONG_ITEM, NOT_NEEDED, DAMAGED, DEFECTIVE, OTHER
- Status values: REQUESTED, APPROVED, REJECTED, REFUNDED, PICKED_UP
- ON DELETE CASCADE: If order line deleted, return record goes with it

**Business Rule (enforced via CHECK):**
- **Refund consistency:** `(status='REFUNDED' ∧ refund_amount IS NOT NULL ∧ refund_amount > 0) ∨ (status≠'REFUNDED' ∧ refund_amount IS NULL)`
  - refund_amount must be set if and only if status is REFUNDED

**Used in:** Query R12 (return rate per category)

---

### 10. PRODUCT_REVIEWS

Customer product reviews and ratings.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| review_id | INTEGER | PRIMARY KEY, CHECK > 0 | Unique review identifier |
| product_id | INTEGER | FK → products, NOT NULL | Product being reviewed |
| customer_id | INTEGER | FK → customers, NOT NULL | Reviewer |
| rating | INTEGER | NOT NULL, CHECK 1-5 | Star rating (1-5) |
| title | VARCHAR(200) | NULL | Review title (optional) |
| body | TEXT | NULL | Review text (optional) |
| verified_purchase | BOOLEAN | NOT NULL, DEFAULT FALSE | TRUE if reviewer purchased product |
| helpful_votes | INTEGER | NOT NULL, DEFAULT 0, CHECK ≥ 0 | Number of "helpful" votes |
| created_at | TIMESTAMPTZ | NOT NULL | Review timestamp |

**Rationale:**
- INTEGER for rating: Discrete 1-5 scale
- TEXT for body: Unlimited length (some reviews are long)
- title and body can be NULL: Customers can rate without writing text
- ON DELETE CASCADE: If product deleted, reviews go with it
- verified_purchase: Critical for trust & safety (query R17 finds fraudulent verified reviews)

**Business Rules:**
- Verified reviews should only come from customers who received the product
- Query R17 identifies violations for Trust & Safety team

---

### 11. CART_ITEMS

Active shopping cart contents.

| Column | Data Type | Constraints | Explanation |
|--------|-----------|-------------|-------------|
| customer_id | INTEGER | PK part 1, FK → customers | Cart owner |
| product_id | INTEGER | PK part 2, FK → products | Product in cart |
| quantity | INTEGER | NOT NULL, CHECK > 0 | Quantity in cart |
| added_at | TIMESTAMPTZ | NOT NULL | When item was added |

**Rationale:**
- **Composite PRIMARY KEY (customer_id, product_id):** Each customer can have each product at most once in cart
- ON DELETE CASCADE: Remove cart items when customer or product deleted
- added_at: Used for cart cleanup (W06 deletes items >90 days old)

**Used in:**
- Query R10: Abandoned cart analysis
- Write W04: Bulk add to cart (5000 items)
- Write W06: Cleanup old cart items

---

## Entity Relationship Diagram

### Textual Description

**Entities and Relationships:**

1. **CITIES** (1) → (N) **SELLERS** (seller location)
2. **CITIES** (1) → (N) **CUSTOMERS** (customer location)
3. **CITIES** (1) → (N) **ADDRESSES** (delivery location)
4. **CATEGORIES** (1) → (N) **CATEGORIES** (parent-child hierarchy, self-referencing)
5. **CATEGORIES** (1) → (N) **PRODUCTS** (product categorization)
6. **SELLERS** (1) → (N) **PRODUCTS** (seller listings)
7. **SELLERS** (1) → (N) **ORDER_ITEMS** (line fulfillment)
8. **PRODUCTS** (1) → (N) **ORDER_ITEMS** (products ordered)
9. **PRODUCTS** (1) → (N) **PRODUCT_REVIEWS** (product feedback)
10. **CUSTOMERS** (1) → (N) **ADDRESSES** (saved addresses)
11. **CUSTOMERS** (1) → (N) **ORDERS** (orders placed)
12. **CUSTOMERS** (1) → (N) **PRODUCT_REVIEWS** (reviews written)
13. **CUSTOMERS** (1) → (N) **CART_ITEMS** (active carts, M:N through associative entity)
14. **PRODUCTS** (1) → (N) **CART_ITEMS** (products in carts, M:N through associative entity)
15. **ADDRESSES** (1) → (N) **ORDERS** (delivery address)
16. **ORDERS** (1) → (N) **ORDER_ITEMS** (order details)
17. **ORDER_ITEMS** (1) → (N) **RETURNS** (line returns)

### Cardinalities

| Relationship | Cardinality | Explanation |
|--------------|-------------|-------------|
| City → Seller | 1:N | One city has many sellers; each seller in one city |
| City → Customer | 1:N | One city has many customers; each customer in one city |
| City → Address | 1:N | One city has many addresses; each address in one city |
| Category → Category | 1:N | Parent category has many children; each child has one parent |
| Category → Product | 1:N | One category has many products; each product in one category |
| Seller → Product | 1:N | One seller lists many products; each product has one seller |
| Seller → OrderItem | 1:N | One seller fulfills many lines; each line from one seller |
| Product → OrderItem | 1:N | One product in many orders; each line references one product |
| Product → Review | 1:N | One product has many reviews; each review for one product |
| Customer → Address | 1:N | One customer has many addresses; each address for one customer |
| Customer → Order | 1:N | One customer places many orders; each order by one customer |
| Customer → Review | 1:N | One customer writes many reviews; each review by one customer |
| Customer ↔ Product (via Cart) | M:N | Customers have multiple products in cart; products in multiple carts |
| Address → Order | 1:N | One address used for many orders; each order to one address (or NULL) |
| Order → OrderItem | 1:N | One order has many lines; each line belongs to one order |
| OrderItem → Return | 1:N | One line can have multiple return attempts; each return for one line |

### Mermaid ER Diagram Code

```mermaid
erDiagram
    CITIES ||--o{ SELLERS : "located_in"
    CITIES ||--o{ CUSTOMERS : "lives_in"
    CITIES ||--o{ ADDRESSES : "delivery_to"
    
    CATEGORIES ||--o{ CATEGORIES : "parent_of"
    CATEGORIES ||--o{ PRODUCTS : "categorizes"
    
    SELLERS ||--o{ PRODUCTS : "sells"
    SELLERS ||--o{ ORDER_ITEMS : "fulfills"
    
    PRODUCTS ||--o{ ORDER_ITEMS : "ordered"
    PRODUCTS ||--o{ PRODUCT_REVIEWS : "reviewed"
    PRODUCTS ||--o{ CART_ITEMS : "in_cart"
    
    CUSTOMERS ||--o{ ADDRESSES : "has"
    CUSTOMERS ||--o{ ORDERS : "places"
    CUSTOMERS ||--o{ PRODUCT_REVIEWS : "writes"
    CUSTOMERS ||--o{ CART_ITEMS : "owns_cart"
    
    ADDRESSES ||--o{ ORDERS : "delivered_to"
    
    ORDERS ||--o{ ORDER_ITEMS : "contains"
    
    ORDER_ITEMS ||--o{ RETURNS : "returned"

    CITIES {
        int city_id PK
        varchar city_name
        varchar state
    }
    
    CATEGORIES {
        int category_id PK
        varchar category_name UK
        int parent_category_id FK
        boolean is_digital
    }
    
    SELLERS {
        int seller_id PK
        varchar business_name
        varchar gstin UK
        int city_id FK
        date joined_on
        numeric seller_rating
        varchar status
    }
    
    PRODUCTS {
        int product_id PK
        varchar asin UK
        int seller_id FK
        int category_id FK
        varchar title
        varchar brand
        numeric mrp
        numeric price
        int stock_qty
        boolean is_prime_eligible
        numeric avg_rating
        int review_count
        date listed_on
        varchar status
    }
    
    CUSTOMERS {
        int customer_id PK
        varchar full_name
        varchar email UK
        varchar phone UK
        int city_id FK
        date signup_date
        boolean is_prime
        date prime_since
    }
    
    ADDRESSES {
        int address_id PK
        int customer_id FK
        varchar label
        varchar line1
        int city_id FK
        varchar pincode
        boolean is_default
    }
    
    ORDERS {
        int order_id PK
        int customer_id FK
        int address_id FK
        timestamptz ordered_at
        varchar payment_method
        numeric total_amount
        varchar status
        timestamptz shipped_at
        timestamptz delivered_at
    }
    
    ORDER_ITEMS {
        int order_id PK_FK
        int line_no PK
        int product_id FK
        int seller_id FK
        int quantity
        numeric unit_price
    }
    
    RETURNS {
        int return_id PK
        int order_id FK
        int line_no FK
        varchar reason
        timestamptz requested_at
        varchar status
        numeric refund_amount
    }
    
    PRODUCT_REVIEWS {
        int review_id PK
        int product_id FK
        int customer_id FK
        int rating
        varchar title
        text body
        boolean verified_purchase
        int helpful_votes
        timestamptz created_at
    }
    
    CART_ITEMS {
        int customer_id PK_FK
        int product_id PK_FK
        int quantity
        timestamptz added_at
    }
```

---

## Functional Dependencies and Normalization

### 1. CITIES

**Functional Dependencies:**
- city_id → city_name, state

**Normal Form: BCNF**
- Single candidate key: {city_id}
- All non-key attributes depend on the entire key
- No transitive dependencies

---

### 2. CATEGORIES

**Functional Dependencies:**
- category_id → category_name, parent_category_id, is_digital
- category_name → category_id (UNIQUE constraint makes this a candidate key)

**Normal Form: BCNF**
- Candidate keys: {category_id}, {category_name}
- All attributes depend on a candidate key
- No partial or transitive dependencies

---

### 3. SELLERS

**Functional Dependencies:**
- seller_id → business_name, gstin, city_id, joined_on, seller_rating, status
- gstin → seller_id (one-to-one with seller_id via UNIQUE)

**Normal Form: BCNF**
- Candidate keys: {seller_id}, {gstin}
- All non-key attributes fully depend on candidate keys
- No transitive dependencies

---

### 4. PRODUCTS

**Functional Dependencies:**
- product_id → asin, seller_id, category_id, title, brand, mrp, price, stock_qty, is_prime_eligible, avg_rating, review_count, listed_on, status
- asin → product_id (UNIQUE)

**Derived Attributes:**
- avg_rating ← computed from product_reviews
- review_count ← computed from product_reviews

**Normal Form: 3NF (not BCNF due to derived attributes)**

**Justification for denormalization:**
- avg_rating and review_count violate BCNF (they depend on product_reviews, not directly on product_id)
- **Business justification:** These appear in almost every customer-facing query (R01, R02, R08)
- Computing on-the-fly would require aggregating reviews table for every product in search results
- Trade-off: Accept staleness for performance (can be updated via triggers or batch jobs)

---

### 5. CUSTOMERS

**Functional Dependencies:**
- customer_id → full_name, email, phone, city_id, signup_date, is_prime, prime_since
- email → customer_id (UNIQUE)
- phone → customer_id (UNIQUE)
- is_prime ↔ prime_since (mutual dependency via business rule)

**Normal Form: BCNF**
- Candidate keys: {customer_id}, {email}, {phone}
- All attributes depend on candidate keys
- The is_prime ↔ prime_since relationship is enforced via CHECK constraint, not FD violation

---

### 6. ADDRESSES

**Functional Dependencies:**
- address_id → customer_id, label, line1, city_id, pincode, is_default

**Normal Form: BCNF**
- Single candidate key: {address_id}
- All attributes fully depend on address_id
- No transitive dependencies

---

### 7. ORDERS

**Functional Dependencies:**
- order_id → customer_id, address_id, ordered_at, payment_method, total_amount, status, shipped_at, delivered_at

**Derived Attribute:**
- total_amount ← SUM(order_items.quantity × order_items.unit_price)

**Normal Form: 3NF (not BCNF due to derived attribute)**

**Justification:**
- total_amount violates BCNF but is kept for performance
- Used in every order list query (R04, R09, R20, R22) and aggregations
- Recomputing would require joining order_items on every access
- Historical accuracy: Preserves total even if line items modified

---

### 8. ORDER_ITEMS

**Functional Dependencies:**
- {order_id, line_no} → product_id, seller_id, quantity, unit_price
- product_id → seller_id (via products table)

**Redundant Attribute:**
- seller_id is derivable from products.seller_id via product_id

**Normal Form: 3NF (not BCNF due to redundancy)**

**Justification:**
- seller_id redundancy is intentional for performance (query R06) and historical accuracy
- If product changes sellers, order history shows original seller
- Trade-off: 4 bytes per row for avoiding joins in seller queries

---

### 9. RETURNS

**Functional Dependencies:**
- return_id → order_id, line_no, reason, requested_at, status, refund_amount
- {order_id, line_no} does NOT uniquely determine return_id (multiple return attempts possible)

**Normal Form: BCNF**
- Single candidate key: {return_id}
- All attributes depend on return_id
- Composite FK (order_id, line_no) references order_items

---

### 10. PRODUCT_REVIEWS

**Functional Dependencies:**
- review_id → product_id, customer_id, rating, title, body, verified_purchase, helpful_votes, created_at
- {product_id, customer_id, created_at} could be a candidate key (one review per product per customer per timestamp)

**Normal Form: BCNF**
- Primary key: {review_id}
- All attributes depend on review_id
- No transitive dependencies

---

### 11. CART_ITEMS

**Functional Dependencies:**
- {customer_id, product_id} → quantity, added_at

**Normal Form: BCNF**
- Single candidate key: {customer_id, product_id}
- Composite primary key (associative entity for M:N relationship)
- All attributes depend on entire key

---

## Summary of Normalization

| Table | Normal Form | Denormalized? | Justification |
|-------|-------------|---------------|---------------|
| cities | BCNF | No | - |
| categories | BCNF | No | - |
| sellers | BCNF | No | - |
| products | 3NF | Yes (avg_rating, review_count) | Performance: displayed in every search result |
| customers | BCNF | No | - |
| addresses | BCNF | No | - |
| orders | 3NF | Yes (total_amount) | Performance: used in all order queries |
| order_items | 3NF | Yes (seller_id) | Performance + history: seller queries + audit trail |
| returns | BCNF | No | - |
| product_reviews | BCNF | No | - |
| cart_items | BCNF | No | - |

**Conclusion:** Schema is in 3NF with justified denormalizations for performance-critical paths.

---

## Data Loading Results

### Expected vs Actual Row Counts

| Table | Expected | Actual | Status |
|-------|----------|--------|--------|
| cities | 10 | 10 | ✅ |
| categories | 40 | 40 | ✅ |
| sellers | 1,500 | 1,500 | ✅ |
| products | 30,000 | 30,000 | ✅ |
| customers | 30,000 | 30,000 | ✅ |
| addresses | 45,000 | 45,000 | ✅ |
| orders | 120,000 | 120,000 | ✅ |
| order_items | 240,000 | 240,000 | ✅ |
| returns | 5,374 | 5,374 | ✅ |
| product_reviews | 38,662 | 38,662 | ✅ |
| cart_items | 44,998 | 44,998 | ✅ |

**All tables loaded successfully! ✅**

### Integrity Check Results

The following checks were run automatically by `sql/02_load_data.sql`:

1. **✅ Order Items Seller Matches Product Seller**
   - Verified order_items.seller_id = products.seller_id
   - Result: 0 mismatches (PASS)

2. **✅ Digital Products Without Addresses**
   - Verified orders without address_id contain only digital products
   - Result: No violations (PASS)

3. **✅ Each Customer Has At Most One Default Address**
   - Enforced by partial unique index
   - Result: 0 customers with multiple defaults (PASS)

4. **✅ Prime Membership Consistency**
   - Verified is_prime ↔ prime_since relationship
   - Result: 0 inconsistencies (PASS)

5. **⚠️ Verified Purchase Reviews**
   - Checked if verified reviews have corresponding delivered orders
   - Result: 1,000 verified reviews without delivered orders
   - **Analysis:** This represents ~2.6% of reviews (1000/38662). This could indicate:
     - Legitimate data quality issue requiring investigation
     - Reviews posted before order status updated to delivered
     - Actual fraudulent reviews (business problem P8)
   - **Action:** Flagged for Trust & Safety team review (Query R17)

6. **✅ Order Total Amount Consistency**
   - Compared orders.total_amount with SUM(order_items)
   - Result: 0 mismatches (PASS)

7. **✅ Return Refund Amounts**
   - Verified refund_amount set only when status='REFUNDED'
   - Result: 0 violations (PASS)

---

## Data Quality Issues

### Issues Found During Loading

1. **✅ RESOLVED: Enumerated Values Discovered**
   - **Seller Status:** Added 'CLOSED' (found in data)
   - **Product Status:** Added 'INACTIVE' (found in data)
   - **Payment Methods:** Added 'NETBANKING', 'EMI' (variants found in data)
   - **Return Reasons:** Added 'NO_LONGER_NEEDED', 'NOT_AS_DESCRIBED', 'SIZE_ISSUE' (found in data)
   - **Impact:** Schema constraints updated to accept all actual data values
   - **Action Taken:** CHECK constraints relaxed to include all observed values

2. **✅ RESOLVED: ASIN Format Variation**
   - **Expected:** `B[0-9]{4}[0-9A-Z]{5}` (B + 4 digits + 5 alphanumeric)
   - **Found:** `B[0-9A-Z]{9}` (B + any 9 alphanumeric characters)
   - **Example:** B000A01B03 (has letter in position that was expected to be digit)
   - **Action Taken:** Relaxed regex to `^B[0-9A-Z]{9}$`

3. **✅ RESOLVED: Digital Product Orders Without Shipping**
   - **Issue:** Some DELIVERED orders have NULL shipped_at (digital products)
   - **Root Cause:** Digital products (e-books, gift cards) don't require physical shipping
   - **Impact:** Orders can transition directly from PLACED to DELIVERED
   - **Action Taken:** Removed strict shipped_at requirement for DELIVERED status
   - **Verification:** All orders with NULL address_id contain only digital products

4. **⚠️ IDENTIFIED: Verified Purchase Review Discrepancies**
   - **Finding:** 1,000 reviews (2.6%) marked verified_purchase without delivered order
   - **Possible Causes:**
     - Order status not yet updated to delivered when review posted
     - Reviews for returned products (status = RETURNED, not DELIVERED)
     - Actual fraudulent reviews (Trust & Safety investigation needed)
   - **Business Impact:** Affects trust score and customer confidence
   - **Query:** R17 will identify these for investigation

5. **✅ VERIFIED: Query R13 NULL Handling Issue**
   - **Problem:** `NOT IN` with NULL values returns empty set
   - **Root Cause:** Some orders.address_id are NULL (digital orders)
   - **Impact:** R13 would return no unused addresses even when they exist
   - **Fix Required in Phase 4:** Replace `NOT IN` with `NOT EXISTS` or `LEFT JOIN ... WHERE IS NULL`
   - **Demonstration:**
     ```sql
     -- Current R13 (will fail):
     SELECT a.address_id FROM addresses a WHERE a.address_id NOT IN (SELECT o.address_id FROM orders o);
     -- Returns 0 rows due to NULL in subquery
     
     -- Fixed version:
     SELECT a.address_id FROM addresses a WHERE NOT EXISTS 
       (SELECT 1 FROM orders o WHERE o.address_id = a.address_id);
     -- Returns actual unused addresses
     ```

### Proposed Additional Checks for Production

1. Verify all ASINs follow format `B[0-9]{4}[0-9A-Z]{5}`
2. Confirm all GSTINs are valid (15-character format)
3. Check for orphaned records (shouldn't exist with proper FKs, but worth verifying)
4. Validate order status transitions (PLACED → PACKED → SHIPPED → DELIVERED)
5. Verify Prime customers have prime_since date

---

## Indexes Created Automatically

PostgreSQL automatically creates indexes for:
- All PRIMARY KEY columns
- All UNIQUE constraints

**Current automatic indexes:**
- cities: city_id (PK)
- categories: category_id (PK), category_name (UNIQUE)
- sellers: seller_id (PK), gstin (UNIQUE)
- products: product_id (PK), asin (UNIQUE)
- customers: customer_id (PK), email (UNIQUE), phone (UNIQUE)
- addresses: address_id (PK), (customer_id) WHERE is_default (partial UNIQUE)
- orders: order_id (PK)
- order_items: (order_id, line_no) (composite PK)
- returns: return_id (PK)
- product_reviews: review_id (PK)
- cart_items: (customer_id, product_id) (composite PK)

**No additional indexes created in Phase 2** per project requirements. Phase 4 will add indexes based on Phase 3 query performance analysis.

---

## Conclusion

The schema successfully represents the Amazon Online Shopping platform with:
- ✅ 11 tables in 3NF/BCNF
- ✅ 27 foreign key relationships with appropriate delete rules
- ✅ 40+ CHECK constraints enforcing business rules
- ✅ Justified denormalization for performance-critical columns
- ✅ Comprehensive data type choices matching business needs
- ✅ Automatic integrity checks to verify data quality

The schema is ready for Phase 3 baseline timing measurements.

---

**Document Version:** 1.0  
**Last Updated:** 2026-11-12  
**Authors:** Team T0043 (Vinayak, Preet Kalra, Yash Malik, Khushi Gupta)
