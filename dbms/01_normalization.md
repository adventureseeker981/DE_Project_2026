# Database Normalization: Amazon Online Shopping System

**Project:** Amazon Online Shopping Database  
**Team:** T0043 - Preet Kalra, Vinayak, Yash Malik, Khushi Gupta  
**Date:** November 12, 2026

---

## Table of Contents
1. [Introduction](#introduction)
2. [Unnormalized Form (UNF)](#unnormalized-form-unf)
3. [First Normal Form (1NF)](#first-normal-form-1nf)
4. [Second Normal Form (2NF)](#second-normal-form-2nf)
5. [Third Normal Form (3NF)](#third-normal-form-3nf)
6. [Boyce-Codd Normal Form (BCNF)](#boyce-codd-normal-form-bcnf)
7. [Summary](#summary)

---

## Introduction

This document demonstrates the normalization process for the Amazon Online Shopping database, taking the data from Unnormalized Form (UNF) through 1NF, 2NF, 3NF, and where applicable, BCNF. The normalization process eliminates data redundancy, ensures data integrity, and optimizes the database structure.

### Original Data Structure

The database manages:
- **Cities** where customers and sellers operate
- **Categories** of products (hierarchical)
- **Sellers** listing products
- **Products** available for purchase
- **Customers** placing orders
- **Addresses** for delivery
- **Orders** with multiple items
- **Order Items** (products in orders)
- **Returns** of purchased items
- **Reviews** by customers
- **Shopping Cart** items

---

## Unnormalized Form (UNF)

### Initial Data Structure (Before Normalization)

In the unnormalized form, we might have a single flat table with repeating groups:

**ORDER_DATA (Unnormalized)**

| order_id | customer_name | customer_email | customer_city | customer_prime | ordered_at | address_label | address_line | delivery_city | product_ids | product_titles | product_prices | quantities | sellers | categories | payment_method | total_amount | status |
|----------|---------------|----------------|---------------|----------------|------------|---------------|--------------|---------------|-------------|----------------|----------------|------------|---------|------------|----------------|--------------|--------|
| 1 | Aditya Sharma | aditya@email.com | Mumbai | Yes | 2025-01-01 | HOME | Flat 102 | Mumbai | 101, 205 | Laptop, Mouse | 45000, 500 | 1, 2 | TechCorp, AccessoriesInc | Electronics, Electronics | CARD | 45500 | DELIVERED |
| 2 | Priya Singh | priya@email.com | Delhi | No | 2025-01-02 | WORK | Office 5A | Delhi | 350 | Book | 299 | 1 | BookStore | Books | UPI | 299 | SHIPPED |

**Problems with UNF:**
- ❌ **Repeating groups:** Multiple products in single order stored as comma-separated values
- ❌ **Data redundancy:** Customer and address information repeated for each order
- ❌ **Update anomalies:** Changing customer email requires updating multiple rows
- ❌ **Insertion anomalies:** Cannot add a customer without an order
- ❌ **Deletion anomalies:** Deleting an order loses customer information
- ❌ **Difficult queries:** Finding all products in orders requires string parsing

---

## First Normal Form (1NF)

**Definition:** A table is in 1NF if:
1. Each column contains atomic (indivisible) values
2. Each column contains values of a single type
3. Each row is unique (has a primary key)
4. No repeating groups or arrays

### Applying 1NF

We eliminate repeating groups by creating separate rows for each order item:

**ORDERS (1NF)**

| order_id | customer_name | customer_email | customer_city | customer_prime | ordered_at | address_label | address_line | delivery_city | payment_method | total_amount | status |
|----------|---------------|----------------|---------------|----------------|------------|---------------|--------------|---------------|----------------|--------------|--------|
| 1 | Aditya Sharma | aditya@email.com | Mumbai | Yes | 2025-01-01 | HOME | Flat 102 | Mumbai | CARD | 45500 | DELIVERED |
| 2 | Priya Singh | priya@email.com | Delhi | No | 2025-01-02 | WORK | Office 5A | Delhi | UPI | 299 | SHIPPED |

**ORDER_ITEMS (1NF)**

| order_id | product_id | product_title | product_price | quantity | seller_name | category_name |
|----------|------------|---------------|---------------|----------|-------------|---------------|
| 1 | 101 | Laptop | 45000 | 1 | TechCorp | Electronics |
| 1 | 205 | Mouse | 500 | 2 | AccessoriesInc | Electronics |
| 2 | 350 | Book | 299 | 1 | BookStore | Books |

**Improvements:**
- ✅ All values are atomic (no comma-separated lists)
- ✅ Each row is unique
- ✅ Easier to query individual order items

**Remaining Issues:**
- ❌ Still significant redundancy (customer info repeated)
- ❌ Product details repeated in every order item
- ❌ Partial dependencies exist

---

## Second Normal Form (2NF)

**Definition:** A table is in 2NF if:
1. It is in 1NF
2. All non-key attributes are fully functionally dependent on the entire primary key (no partial dependencies)

### Identifying Functional Dependencies

**In ORDER_ITEMS:**
- Primary Key: `{order_id, product_id}`
- Partial dependencies detected:
  - `order_id → customer_name, customer_email, ordered_at, payment_method` (depends only on order_id)
  - `product_id → product_title, product_price, seller_name, category_name` (depends only on product_id)

### Applying 2NF

We decompose tables to remove partial dependencies:

**CUSTOMERS (2NF)**

| customer_id | customer_name | customer_email | city_id | city_name | is_prime | prime_since | signup_date |
|-------------|---------------|----------------|---------|-----------|----------|-------------|-------------|
| 1001 | Aditya Sharma | aditya@email.com | 2 | Mumbai | TRUE | 2024-01-15 | 2023-06-10 |
| 1002 | Priya Singh | priya@email.com | 3 | Delhi | FALSE | NULL | 2024-03-22 |

**ADDRESSES (2NF)**

| address_id | customer_id | label | line1 | city_id | city_name | pincode | is_default |
|------------|-------------|-------|-------|---------|-----------|---------|------------|
| 5001 | 1001 | HOME | Flat 102 | 2 | Mumbai | 400001 | TRUE |
| 5002 | 1002 | WORK | Office 5A | 3 | Delhi | 110001 | TRUE |

**PRODUCTS (2NF)**

| product_id | title | price | seller_id | seller_name | category_id | category_name | stock_qty | status |
|------------|-------|-------|-----------|-------------|-------------|---------------|-----------|--------|
| 101 | Laptop | 45000 | 201 | TechCorp | 10 | Electronics | 50 | ACTIVE |
| 205 | Mouse | 500 | 202 | AccessoriesInc | 10 | Electronics | 200 | ACTIVE |
| 350 | Book | 299 | 203 | BookStore | 20 | Books | 100 | ACTIVE |

**ORDERS (2NF)**

| order_id | customer_id | address_id | ordered_at | payment_method | total_amount | status |
|----------|-------------|------------|------------|----------------|--------------|--------|
| 1 | 1001 | 5001 | 2025-01-01 | CARD | 45500 | DELIVERED |
| 2 | 1002 | 5002 | 2025-01-02 | UPI | 299 | SHIPPED |

**ORDER_ITEMS (2NF)**

| order_id | product_id | quantity | unit_price | seller_id |
|----------|------------|----------|------------|-----------|
| 1 | 101 | 1 | 45000 | 201 |
| 1 | 205 | 2 | 500 | 202 |
| 2 | 350 | 1 | 299 | 203 |

**Improvements:**
- ✅ Eliminated partial dependencies
- ✅ Customer information stored once
- ✅ Product information stored once
- ✅ No partial key dependencies

**Remaining Issues:**
- ❌ Transitive dependencies still exist
- ❌ `city_name` depends on `city_id`, not on primary key
- ❌ `seller_name` depends on `seller_id`, not on primary key

---

## Third Normal Form (3NF)

**Definition:** A table is in 3NF if:
1. It is in 2NF
2. No transitive dependencies (non-key attributes depend only on the primary key, not on other non-key attributes)

### Identifying Transitive Dependencies

**In CUSTOMERS:**
- `customer_id → city_id → city_name` (transitive dependency)
- `customer_id → is_prime → prime_since` (functional dependency)

**In PRODUCTS:**
- `product_id → seller_id → seller_name` (transitive dependency)
- `product_id → category_id → category_name` (transitive dependency)

**In ADDRESSES:**
- `address_id → city_id → city_name` (transitive dependency)

### Applying 3NF

We create separate tables for entities causing transitive dependencies:

**CITIES (3NF)**

| city_id | city_name | state |
|---------|-----------|-------|
| 1 | Bengaluru | Karnataka |
| 2 | Mumbai | Maharashtra |
| 3 | Delhi | Delhi |

**SELLERS (3NF)**

| seller_id | business_name | gstin | city_id | joined_on | seller_rating | status |
|-----------|---------------|-------|---------|-----------|---------------|--------|
| 201 | TechCorp | 27AAAAA0000A1Z5 | 2 | 2020-01-15 | 4.5 | ACTIVE |
| 202 | AccessoriesInc | 09BBBBB0000B1Z6 | 1 | 2019-06-20 | 4.2 | ACTIVE |
| 203 | BookStore | 07CCCCC0000C1Z7 | 3 | 2021-03-10 | 4.8 | ACTIVE |

**CATEGORIES (3NF)**

| category_id | category_name | parent_category_id | is_digital |
|-------------|---------------|-------------------|------------|
| 1 | Electronics | NULL | FALSE |
| 10 | Mobiles | 1 | FALSE |
| 20 | Books | NULL | FALSE |
| 21 | E-Books | 20 | TRUE |

**CUSTOMERS (3NF) - Cleaned**

| customer_id | full_name | email | phone | city_id | signup_date | is_prime | prime_since |
|-------------|-----------|-------|-------|---------|-------------|----------|-------------|
| 1001 | Aditya Sharma | aditya@email.com | 9876543210 | 2 | 2023-06-10 | TRUE | 2024-01-15 |
| 1002 | Priya Singh | priya@email.com | 9876543211 | 3 | 2024-03-22 | FALSE | NULL |

**ADDRESSES (3NF) - Cleaned**

| address_id | customer_id | label | line1 | city_id | pincode | is_default |
|------------|-------------|-------|-------|---------|---------|------------|
| 5001 | 1001 | HOME | Flat 102, Park Street | 2 | 400001 | TRUE |
| 5002 | 1002 | WORK | Office 5A, Central Avenue | 3 | 110001 | TRUE |

**PRODUCTS (3NF) - Cleaned**

| product_id | asin | seller_id | category_id | title | brand | mrp | price | stock_qty | is_prime_eligible | avg_rating | review_count | listed_on | status |
|------------|------|-----------|-------------|-------|-------|-----|-------|-----------|-------------------|------------|--------------|-----------|--------|
| 101 | B00001ABCD | 201 | 10 | HP Laptop Pro | HP | 50000 | 45000 | 50 | TRUE | 4.5 | 120 | 2024-01-01 | ACTIVE |
| 205 | B00002EFGH | 202 | 10 | Wireless Mouse | Logitech | 600 | 500 | 200 | TRUE | 4.0 | 85 | 2024-02-15 | ACTIVE |
| 350 | B00003IJKL | 203 | 20 | Data Structures Book | O'Reilly | 399 | 299 | 100 | FALSE | 4.7 | 230 | 2023-12-10 | ACTIVE |

**ORDERS (3NF) - No change needed**

| order_id | customer_id | address_id | ordered_at | payment_method | total_amount | status | shipped_at | delivered_at |
|----------|-------------|------------|------------|----------------|--------------|--------|------------|--------------|
| 1 | 1001 | 5001 | 2025-01-01 10:00:00 | CARD | 45500 | DELIVERED | 2025-01-01 18:00:00 | 2025-01-04 15:00:00 |
| 2 | 1002 | 5002 | 2025-01-02 14:30:00 | UPI | 299 | SHIPPED | 2025-01-02 20:00:00 | NULL |

**ORDER_ITEMS (3NF) - No change needed**

| order_id | line_no | product_id | seller_id | quantity | unit_price |
|----------|---------|------------|-----------|----------|------------|
| 1 | 1 | 101 | 201 | 1 | 45000 |
| 1 | 2 | 205 | 202 | 2 | 500 |
| 2 | 1 | 350 | 203 | 1 | 299 |

**Additional Tables:**

**PRODUCT_REVIEWS (3NF)**

| review_id | product_id | customer_id | rating | title | body | verified_purchase | helpful_votes | created_at |
|-----------|------------|-------------|--------|-------|------|-------------------|---------------|------------|
| 1 | 101 | 1001 | 5 | Excellent laptop | Great performance and battery life | TRUE | 45 | 2025-01-05 |
| 2 | 205 | 1001 | 4 | Good mouse | Works well but battery drains fast | TRUE | 12 | 2025-01-06 |

**RETURNS (3NF)**

| return_id | order_id | line_no | reason | requested_at | status | refund_amount |
|-----------|----------|---------|--------|--------------|--------|---------------|
| 1 | 1 | 2 | QUALITY_ISSUE | 2025-01-10 | APPROVED | 1000 |

**CART_ITEMS (3NF)**

| customer_id | product_id | quantity | added_at |
|-------------|------------|----------|----------|
| 1002 | 101 | 1 | 2025-01-03 |
| 1002 | 205 | 2 | 2025-01-03 |

**Improvements:**
- ✅ All transitive dependencies eliminated
- ✅ Each non-key attribute depends only on the primary key
- ✅ Minimal redundancy
- ✅ Easy to maintain and update

**Note on Derived Attributes:**
- `products.avg_rating` and `review_count` are derived from `product_reviews` table but kept for performance (denormalization for read optimization)
- `orders.total_amount` is derived from `order_items` but kept for historical accuracy and performance

---

## Boyce-Codd Normal Form (BCNF)

**Definition:** A table is in BCNF if:
1. It is in 3NF
2. For every functional dependency X → Y, X must be a superkey

### Analyzing for BCNF

Let's check each table:

**1. CITIES**
- FD: `city_id → city_name, state`
- `city_id` is the primary key (superkey) ✅
- **Status:** BCNF ✅

**2. CATEGORIES**
- FD1: `category_id → category_name, parent_category_id, is_digital`
- FD2: `category_name → category_id` (UNIQUE constraint)
- Both are candidate keys ✅
- **Status:** BCNF ✅

**3. SELLERS**
- FD1: `seller_id → all other attributes`
- FD2: `gstin → seller_id` (UNIQUE constraint)
- Both are candidate keys ✅
- **Status:** BCNF ✅

**4. PRODUCTS**
- FD1: `product_id → all attributes`
- FD2: `asin → product_id` (UNIQUE constraint)
- Derived attributes: `avg_rating`, `review_count`
- **Status:** 3NF (not BCNF due to derived attributes)
- **Justification:** Performance optimization - acceptable denormalization

**5. CUSTOMERS**
- FD1: `customer_id → all attributes`
- FD2: `email → customer_id` (UNIQUE)
- FD3: `phone → customer_id` (UNIQUE)
- All are candidate keys ✅
- **Status:** BCNF ✅

**6. ADDRESSES**
- FD: `address_id → all attributes`
- `address_id` is superkey ✅
- **Status:** BCNF ✅

**7. ORDERS**
- FD: `order_id → all attributes`
- Derived attribute: `total_amount`
- **Status:** 3NF (not BCNF due to derived attribute)
- **Justification:** Historical accuracy and performance

**8. ORDER_ITEMS**
- FD: `{order_id, line_no} → product_id, seller_id, quantity, unit_price`
- Redundant attribute: `seller_id` (can be derived from `product_id`)
- **Status:** 3NF (not BCNF due to redundancy)
- **Justification:** Performance (seller queries) and historical accuracy

**9. RETURNS**
- FD: `return_id → all attributes`
- `return_id` is superkey ✅
- **Status:** BCNF ✅

**10. PRODUCT_REVIEWS**
- FD: `review_id → all attributes`
- `review_id` is superkey ✅
- **Status:** BCNF ✅

**11. CART_ITEMS**
- FD: `{customer_id, product_id} → quantity, added_at`
- Composite key is superkey ✅
- **Status:** BCNF ✅

---

## Summary

### Normalization Achievements

| Table | 1NF | 2NF | 3NF | BCNF | Notes |
|-------|-----|-----|-----|------|-------|
| cities | ✅ | ✅ | ✅ | ✅ | Fully normalized |
| categories | ✅ | ✅ | ✅ | ✅ | Self-referencing hierarchy |
| sellers | ✅ | ✅ | ✅ | ✅ | Fully normalized |
| products | ✅ | ✅ | ✅ | ⚠️ | Derived columns for performance |
| customers | ✅ | ✅ | ✅ | ✅ | Multiple candidate keys |
| addresses | ✅ | ✅ | ✅ | ✅ | Fully normalized |
| orders | ✅ | ✅ | ✅ | ⚠️ | Derived total_amount |
| order_items | ✅ | ✅ | ✅ | ⚠️ | Redundant seller_id |
| returns | ✅ | ✅ | ✅ | ✅ | Fully normalized |
| product_reviews | ✅ | ✅ | ✅ | ✅ | Fully normalized |
| cart_items | ✅ | ✅ | ✅ | ✅ | Fully normalized |

### Functional Dependencies Summary

**Key Functional Dependencies:**

1. **cities:** `city_id → city_name, state`
2. **categories:** `category_id → category_name, parent_category_id, is_digital`
3. **sellers:** `seller_id → business_name, gstin, city_id, joined_on, seller_rating, status`
4. **products:** `product_id → asin, seller_id, category_id, title, brand, mrp, price, stock_qty, is_prime_eligible, listed_on, status`
5. **customers:** `customer_id → full_name, email, phone, city_id, signup_date, is_prime, prime_since`
6. **addresses:** `address_id → customer_id, label, line1, city_id, pincode, is_default`
7. **orders:** `order_id → customer_id, address_id, ordered_at, payment_method, status, shipped_at, delivered_at`
8. **order_items:** `{order_id, line_no} → product_id, seller_id, quantity, unit_price`
9. **returns:** `return_id → order_id, line_no, reason, requested_at, status, refund_amount`
10. **product_reviews:** `review_id → product_id, customer_id, rating, title, body, verified_purchase, helpful_votes, created_at`
11. **cart_items:** `{customer_id, product_id} → quantity, added_at`

### Justified Denormalizations

**1. products.avg_rating and review_count**
- **Why:** Displayed in every search result and product listing
- **Impact:** Recomputing from product_reviews table for every query would be too expensive
- **Trade-off:** Accept slight staleness for massive performance gain
- **Maintenance:** Updated via triggers or batch jobs

**2. orders.total_amount**
- **Why:** Shown in every order list and used in aggregations
- **Impact:** Recomputing from order_items on every access is expensive
- **Trade-off:** Historical accuracy (preserves amount even if items change) + performance
- **Maintenance:** Calculated at order creation time

**3. order_items.seller_id**
- **Why:** Seller-specific queries (R06) need to filter by seller without joining products
- **Impact:** Performance optimization for seller dashboards
- **Trade-off:** Redundancy vs query performance + historical accuracy
- **Maintenance:** Must match products.seller_id (verified by integrity check)

### Benefits Achieved

✅ **Reduced Redundancy:** Each fact stored in one place  
✅ **Data Integrity:** Constraints ensure consistency  
✅ **Update Efficiency:** Changes made in single location  
✅ **Insertion Flexibility:** Can add entities independently  
✅ **Deletion Safety:** No loss of unrelated information  
✅ **Query Optimization:** Proper indexing on normalized tables  
✅ **Scalability:** Structure supports future growth  

### Final Database Statistics

- **Total Tables:** 11
- **Tables in BCNF:** 8 (73%)
- **Tables in 3NF:** 11 (100%)
- **Justified Denormalizations:** 3
- **Foreign Key Relationships:** 17
- **Composite Primary Keys:** 2 (order_items, cart_items)
- **Self-Referencing Tables:** 1 (categories)

---

**Document Version:** 1.0  
**Last Updated:** November 12, 2026  
**Prepared by:** Team T0043 (Preet Kalra, Vinayak, Yash Malik, Khushi Gupta)  
**Course:** Database Management Systems · B.Tech 2nd Year
