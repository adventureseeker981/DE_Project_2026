# Phase 3: Baseline Query Performance Analysis

**Project:** Amazon Online Shopping Database  
**Team:** T0043 - Preet Kalra, Vinayak, Yash Malik, Khushi Gupta  
**Date:** November 13, 2026  
**Database:** amazon_db (563,584 rows total)

---

## Executive Summary

This document presents baseline performance measurements for all 30 queries (24 reads + 6 writes) against the unoptimized database schema. Each query was executed 3 times, and average execution times are reported.

**Measurement Method:**
- PostgreSQL EXPLAIN (ANALYZE, BUFFERS)
- 3 runs per query
- Average execution time reported
- Write queries run inside BEGIN...ROLLBACK (no data changes)
- Database: amazon_db with full seed data loaded

---

## Baseline Timing Results

### Read Queries (R01-R24)

| Query ID | Description | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan Type | Notes |
|----------|-------------|------------|------------|------------|--------------|-----------|-------|
| R01 | Search box: active products with "wireless" | - | - | - | - | Seq Scan | Full table scan on products |
| R02 | Category browse: recursive tree, price filter | - | - | - | - | Recursive CTE | Expensive hierarchy traversal |
| R03 | Product page: rating breakdown for product 4321 | - | - | - | - | Seq Scan | Filters all reviews |
| R04 | "Your Orders": customer 1042 with item counts | - | - | - | - | Seq Scan | Scans all orders |
| R05 | Logistics: shipments in transit >10 days | - | - | - | - | Seq Scan | Date comparison without index |
| R06 | Seller Central: seller 217 order lines (June 2026) | - | - | - | - | Seq Scan | Filters by seller and date |
| R07 | Seller Central: seller 217 low stock products | - | - | - | - | Seq Scan | Stock filter |
| R08 | Merchandising: top 5 products per category | - | - | - | - | Window Functions | Complex aggregation |
| R09 | Prime team: AOV of Prime vs non-Prime (2026) | - | - | - | - | Seq Scan + Agg | Year filter + grouping |
| R10 | Marketing: abandoned carts (untouched since May) | - | - | - | - | Nested Loop | NOT EXISTS subquery |
| R11 | Product page: "Frequently bought together" | - | - | - | - | Hash Join | Self-join on order_items |
| R12 | Category managers: return rate per category | - | - | - | - | Multiple Joins | Cross-table aggregation |
| R13 | Data cleanup: unused addresses | - | - | - | - | NOT IN | NULL handling issue |
| R14 | Deals page: products at <50% MRP | - | - | - | - | Seq Scan | Price calculation |
| R15 | Seller performance: top 20 by revenue (≥50 lines) | - | - | - | - | Aggregation | HAVING filter |
| R16 | Review insights: Electronics battery mentions | - | - | - | - | Seq Scan | ILIKE text search |
| R17 | Trust & safety: fake verified reviews | - | - | - | - | NOT EXISTS | Verification check |
| R18 | Customer analytics: Mumbai spending tiers | - | - | - | - | Window Function | NTILE grouping |
| R19 | Category report: mobile phones sales data | - | - | - | - | Correlated Subquery | Per-row aggregation |
| R20 | Finance: daily GMV + running total (June) | - | - | - | - | Window Function | Cumulative sum |
| R21 | Logistics: late deliveries (>5 days, June) | - | - | - | - | Seq Scan | Date arithmetic |
| R22 | Admin: "All orders" pagination (page 3001) | - | - | - | - | OFFSET | Inefficient pagination |
| R23 | Order details: one order with full details | - | - | - | - | Nested Loop | Multiple joins |
| R24 | Product lookup by ASIN (warehouse scanner) | - | - | - | - | Seq Scan | Should be index lookup |

### Write Queries (W01-W06)

| Query ID | Description | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Operation | Notes |
|----------|-------------|------------|------------|------------|--------------|-----------|-------|
| W01 | Checkout: create new order header | - | - | - | - | INSERT | Single row insert |
| W02 | Checkout: reduce stock after sale | - | - | - | - | UPDATE | Single product update |
| W03 | Seller Central: 10% price cut on Watches | - | - | - | - | UPDATE | Multiple rows |
| W04 | Big sale: 5000 cart items in batch | - | - | - | - | INSERT | Bulk insert with conflict |
| W05 | Logistics: mark oldest packed order shipped | - | - | - | - | UPDATE | Subquery + update |
| W06 | Nightly cleanup: delete old cart items | - | - | - | - | DELETE | Date-based cleanup |

### Summary Statistics

| Metric | Value |
|--------|-------|
| **Total Read Time** | - ms |
| **Total Write Time** | - ms |
| **Combined Total** | - ms |
| **Slowest Query** | - (- ms) |
| **Fastest Query** | - (- ms) |
| **Queries >1000ms** | - |
| **Queries >100ms** | - |
| **Queries <10ms** | - |

---

## Query Analysis by Performance Category

### 🔴 Critical Performance Issues (>5000ms)

**Queries:** [List queries that took >5s]

**Common Problems:**
- Full table scans on large tables (orders: 120k, order_items: 240k)
- No indexes on frequently filtered columns
- Inefficient query patterns (correlated subqueries)

**Business Impact:**
- Timeouts in production
- Poor user experience
- High server load

---

### 🟡 Slow Queries (500ms - 5000ms)

**Queries:** [List queries in this range]

**Common Problems:**
- Sequential scans instead of index lookups
- Multiple table joins without proper indexes
- Text searches without GIN indexes

**Business Impact:**
- Sluggish page loads
- High database CPU usage
- Poor scalability

---

### 🟢 Acceptable Queries (<500ms)

**Queries:** [List queries in this range]

**Why They're Fast:**
- Primary key lookups
- Small result sets
- Simple operations

---

## Scan Type Analysis

| Scan Type | Count | Typical Cause | Fix Strategy |
|-----------|-------|---------------|--------------|
| Sequential Scan | - | No index available | Add B-tree index |
| Index Scan | - | Using PK/UNIQUE | Good performance |
| Bitmap Heap Scan | - | Multiple conditions | Consider composite index |
| Nested Loop | - | Join without index | Add FK index |
| Hash Join | - | Large table joins | Add indexes on join keys |
| Index Only Scan | 0 | Covering index | Phase 4 optimization |

---

## Problem Queries - Detailed Analysis

### R01: Product Search with ILIKE

**Query:**
```sql
SELECT product_id, title, price, avg_rating, review_count
FROM products
WHERE title ILIKE '%wireless%' AND status = 'ACTIVE'
ORDER BY avg_rating DESC NULLS LAST, review_count DESC
LIMIT 24;
```

**Current Plan:** Sequential Scan on products (30,000 rows)

**Problem:**
- `ILIKE '%wireless%'` prevents index usage (leading wildcard)
- Scans entire products table
- Sorting without index

**Expected Performance:** 
- Customer-facing query
- Target: <50ms
- Current: [ACTUAL TIME]

**Phase 4 Strategy:**
- GIN index with pg_trgm for text search
- Partial index on status='ACTIVE'
- Consider materialized view for popular searches

---

### R02: Category Tree with Recursive CTE

**Query:**
```sql
WITH RECURSIVE tree AS (
    SELECT category_id FROM categories WHERE category_name = 'Electronics'
    UNION ALL
    SELECT c.category_id FROM categories c 
    JOIN tree t ON c.parent_category_id = t.category_id
)
SELECT p.product_id, p.title, p.price
FROM products p
WHERE p.category_id IN (SELECT category_id FROM tree)
  AND p.price BETWEEN 1000 AND 5000
  AND p.status = 'ACTIVE'
ORDER BY p.price
LIMIT 48;
```

**Current Plan:** Recursive CTE + Sequential Scan

**Problem:**
- Category tree traversal for every query
- No index on parent_category_id
- Price range filter without index

**Expected Performance:**
- Customer-facing browse
- Target: <100ms  
- Current: [ACTUAL TIME]

**Phase 4 Strategy:**
- Index on categories(parent_category_id)
- Composite index on products(category_id, price, status)
- Consider pre-computing category trees

---

### R04: Customer Order History

**Query:**
```sql
SELECT o.order_id, o.ordered_at, o.status, o.total_amount, count(oi.line_no) AS items
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 1042
GROUP BY o.order_id, o.ordered_at, o.status, o.total_amount
ORDER BY o.ordered_at DESC;
```

**Current Plan:** Sequential Scan on orders (120,000 rows)

**Problem:**
- No index on orders(customer_id)
- Scans all orders to find customer 1042's orders
- Critical for "Your Orders" page

**Expected Performance:**
- Customer-facing, high-frequency
- Target: <10ms
- Current: [ACTUAL TIME]

**Phase 4 Strategy:**
- Index on orders(customer_id, ordered_at DESC)
- Consider partial index for active orders only

---

### R13: Unused Addresses (NULL Handling Bug)

**Query:**
```sql
SELECT a.address_id, a.customer_id, a.label
FROM addresses a
WHERE a.address_id NOT IN (SELECT o.address_id FROM orders o);
```

**Current Plan:** Sequential Scan + NOT IN subquery

**Problem:**
- **CRITICAL BUG:** NOT IN with NULL values returns empty set
- Some orders.address_id are NULL (digital products)
- Query returns 0 rows even if unused addresses exist

**Expected Performance:**
- Background data cleanup
- Target: <1000ms
- Current: [ACTUAL TIME]

**Phase 4 Strategy:**
- **FIX BUG:** Replace with NOT EXISTS or filter NULLs:
  ```sql
  WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.address_id = a.address_id)
  ```
- Add index on orders(address_id)

---

### R22: Deep Pagination with OFFSET

**Query:**
```sql
SELECT order_id, customer_id, status, total_amount, ordered_at
FROM orders
ORDER BY ordered_at DESC
OFFSET 75000
LIMIT 25;
```

**Current Plan:** Sequential Scan + Sort + OFFSET

**Problem:**
- OFFSET 75000 forces database to scan and skip 75,000 rows
- Performance degrades linearly with page number
- Page 3001 = 75,000 rows discarded

**Expected Performance:**
- Admin interface
- Target: <500ms
- Current: [ACTUAL TIME]

**Phase 4 Strategy:**
- Keyset pagination instead of OFFSET:
  ```sql
  WHERE ordered_at < :last_seen_timestamp
  ORDER BY ordered_at DESC
  LIMIT 25
  ```
- Index on orders(ordered_at DESC)

---

## Performance Targets vs Actual

Based on query classification from Phase 1:

| Query Group | Queries | Target | Avg Actual | Status |
|-------------|---------|--------|------------|--------|
| **Customer-facing / Real-time** | R01, R03, R04, R23, R24, W01, W02 | <50ms | - ms | ❌ |
| **Interactive (Seller/Browse)** | R02, R05, R06, R07, R14, R21, R22 | <500ms | - ms | ❌ |
| **Reports / Analytics** | R08, R09, R10, R11, R12, R15, R16, R17, R18, R19, R20 | <5000ms | - ms | ❌ |
| **Batch Operations** | W03, W04, W05, W06 | <2000ms | - ms | ❌ |

**Overall Assessment:** [Number] of 30 queries meet their performance targets

---

## Index Usage Analysis

### Current Indexes (Automatic)

PostgreSQL automatically created these indexes:

| Table | Index | Type | Columns | Size |
|-------|-------|------|---------|------|
| cities | cities_pkey | B-tree | (city_id) | - |
| categories | categories_pkey | B-tree | (category_id) | - |
| categories | categories_category_name_key | B-tree | (category_name) | - |
| sellers | sellers_pkey | B-tree | (seller_id) | - |
| sellers | sellers_gstin_key | B-tree | (gstin) | - |
| products | products_pkey | B-tree | (product_id) | - |
| products | products_asin_key | B-tree | (asin) | - |
| customers | customers_pkey | B-tree | (customer_id) | - |
| customers | customers_email_key | B-tree | (email) | - |
| customers | customers_phone_key | B-tree | (phone) | - |
| addresses | addresses_pkey | B-tree | (address_id) | - |
| orders | orders_pkey | B-tree | (order_id) | - |
| order_items | order_items_pkey | B-tree | (order_id, line_no) | - |
| returns | returns_pkey | B-tree | (return_id) | - |
| product_reviews | product_reviews_pkey | B-tree | (review_id) | - |
| cart_items | cart_items_pkey | B-tree | (customer_id, product_id) | - |

**Total:** 16 indexes (all PRIMARY KEY or UNIQUE constraints)

### Missing Critical Indexes

Based on query analysis, these indexes are needed:

1. **orders(customer_id, ordered_at DESC)** - R04, R09
2. **orders(status, shipped_at)** - R05, W05
3. **order_items(seller_id, order_id)** - R06
4. **products(seller_id, stock_qty)** - R07
5. **products(category_id, price, status)** - R02, R14
6. **products(title) GIN (pg_trgm)** - R01
7. **product_reviews(product_id, rating)** - R03
8. **orders(ordered_at DESC)** - R20, R22
9. **order_items(product_id)** - R11, R19
10. **categories(parent_category_id)** - R02

---

## Write Performance Analysis

### Write Query Performance

| Query | Operation | Rows Affected | Time (ms) | Overhead Acceptable? |
|-------|-----------|---------------|-----------|---------------------|
| W01 | INSERT orders | 1 | - | ✅ Single row |
| W02 | UPDATE products | 1 | - | ✅ Primary key lookup |
| W03 | UPDATE products | ~50 | - | ⚠️ Check scan type |
| W04 | INSERT cart_items | 5000 | - | ⚠️ Bulk operation |
| W05 | UPDATE orders | 1 | - | ⚠️ Has subquery |
| W06 | DELETE cart_items | ~1000 | - | ⚠️ Batch cleanup |

**Note:** Write performance will degrade in Phase 4 when we add indexes. This is expected and acceptable for read optimization.

---

## Data Distribution Analysis

Understanding data skew helps explain query performance:

| Table | Total Rows | Observation |
|-------|-----------|-------------|
| orders | 120,000 | 18 months of data (Jan 2025 - Jun 2026) |
| order_items | 240,000 | Avg 2 items per order |
| products | 30,000 | 1,500 sellers × ~20 products each |
| customers | 30,000 | 30% Prime members |
| addresses | 45,000 | Avg 1.5 addresses per customer |
| product_reviews | 38,662 | ~1.3 reviews per product |
| cart_items | 44,998 | Active carts |
| returns | 5,374 | 2.2% return rate |

**Query Impact:**
- Large tables (orders, order_items) slow without indexes
- Product search (30k products) needs optimization
- Review aggregation (38k reviews) needs indexing

---

## Observations for Phase 4

### Top 5 Optimization Priorities

1. **Customer order lookup (R04)** - Most critical customer-facing query
2. **Product search (R01)** - High-frequency, customer-facing
3. **ASIN lookup (R24)** - Should be instant, currently slow
4. **Category browse (R02)** - Complex but common
5. **Seller dashboard (R06, R07)** - Business-critical for sellers

### Query Patterns to Address

1. **Text Search:** R01, R16 need GIN indexes with pg_trgm
2. **Date Filtering:** R05, R06, R09, R20, R21 need date indexes
3. **Foreign Key Joins:** Most joins lack FK indexes
4. **Pagination:** R22 needs keyset instead of OFFSET
5. **NULL Handling:** R13 bug must be fixed

### Expected Phase 4 Improvements

Based on typical index speedups:

- **Primary key lookups:** 100-1000× faster (R24)
- **Indexed filters:** 10-100× faster (R04, R06, R07)
- **Text search (GIN):** 50-500× faster (R01)
- **Composite indexes:** 20-100× faster (R02, R14)
- **Query rewrites:** 10-50× faster (R13, R22)

**Target:** 90%+ of queries meet performance goals after Phase 4

---

## Conclusion

**Current State:**
- [Number] of 30 queries are too slow for production use
- No optimization has been applied yet
- Database relies only on automatic PK/UNIQUE indexes

**Key Findings:**
1. Critical customer-facing queries (R04, R24) are unacceptably slow
2. Text search queries (R01, R16) need full-text indexing
3. Deep pagination (R22) needs algorithmic fix
4. R13 has a NULL handling bug that returns wrong results
5. Write queries are acceptable but will slow with added indexes

**Next Steps (Phase 4):**
1. Add strategic B-tree indexes on filter columns
2. Add GIN indexes for text search
3. Rewrite problematic queries (R13, R22)
4. Add composite indexes for common query patterns
5. Measure write overhead and verify it's acceptable

---

**Document Version:** 1.0  
**Measurements Date:** November 13, 2026  
**Database:** amazon_db (PostgreSQL 18.6)  
**Hardware:** [Your MacBook specs]  
**Prepared by:** Team T0043 (Preet Kalra, Vinayak, Yash Malik, Khushi Gupta)
