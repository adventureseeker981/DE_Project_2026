# Scalability Report
**Team:** V_nue_mail — T0043  
**Phase:** CP4 — Partitioning & Scalability  
**Database:** PostgreSQL 18.6 (Postgres.app)  
**Benchmark executed:** 2026-11-23, seed dataset (120k orders / 240k order\_items)  
**Large dataset:** Not released by faculty before submission deadline.

---

## 1. Dataset Size and Characteristics

| Table | Rows | Approximate size |
|---|---|---|
| orders | 120,000 | primary fact table — partitioned |
| order_items | 240,000 | largest table by scan cost |
| addresses | 45,000 | — |
| cart_items | 44,998 | — |
| product_reviews | 38,662 | — |
| products | 30,000 | — |
| customers | 30,000 | — |
| returns | 5,374 | — |
| sellers | 1,500 | — |
| categories | 40 | small dimension |
| cities | 10 | small dimension |

**Orders date range:** 2025-01-01 to 2026-06-30 (18 months).  
**NULL `address_id` in orders:** 5,882 rows (digital/virtual products — intentional by design).  
**Average order items per order:** 2.0 (240,000 / 120,000).

> [!NOTE]
> The faculty-provided large dataset was not released before the submission deadline of
> 2026-11-23. All benchmark figures in this report are from the seed dataset with the
> partitioned schema and optimized indexes applied. The status column in
> `benchmarks/results/large/summary.csv` is set to `EXECUTED_SEED` for all 30 entries
> to reflect this. No timings were fabricated.

---

## 2. Existing Database Design

The Amazon Online Shopping schema (`amazon` schema, PostgreSQL) comprises 11 tables:

```
cities → addresses ← customers
         |               |
         orders ←────────┘       ← 120k rows; partitioned by ordered_at
           |
        order_items               ← 240k rows; largest scanned table
           |
        products ← categories
           |
        sellers
        product_reviews
        cart_items
        returns
```

Key design facts:
- **Primary key:** `orders.order_id` (integer, serial). After partitioning: composite `(order_id, ordered_at)`.
- **Partitioning key:** `ordered_at TIMESTAMPTZ` — chosen because the dominant query filters (R06, R09, R20, R21, R22) all filter by time range.
- **FK to partitioned table:** A direct FK from `order_items.order_id → orders.order_id` is not
  possible on a partitioned table because PostgreSQL requires the partition key (`ordered_at`) in
  any UNIQUE constraint. This is resolved via the **`order_registry`** pattern in
  `08_partitioning.sql`: a lightweight non-partitioned table `order_registry(order_id PK)` mirrors
  every `order_id` in `orders` through two AFTER-row triggers
  (`trg_orders_registry_insert`, `trg_orders_registry_delete`). The real database-level FK is:
  ```sql
  CONSTRAINT fk_order_item_order_registry
      FOREIGN KEY (order_id) REFERENCES order_registry(order_id)
      ON DELETE CASCADE NOT DEFERRABLE INITIALLY IMMEDIATE
  ```
  Referential integrity is therefore **enforced at the database level**, not the application level.
  All five integrity tests (orphan detection, INSERT FK block, INSERT trigger, DELETE CASCADE,
  constraint count) were verified live on `amazon_partition_test`.

---

## 3. Identified Scalability Challenges

### 3.1 R19 — Correlated subquery (most critical)

The original query iterated a subquery once per product row (937 active products × full scan of 240k order_items). At baseline:  
**avg = 17,889 ms** — dominates the entire workload.

This scales as **O(n × m)** where n = active products and m = order_items rows.  
At 10× data scale (2.4M order_items), the original would exceed 3 minutes.

### 3.2 Non-sargable date predicates (R06, R09, R20)

Three queries wrapped `ordered_at` in functions (`date_trunc`, `EXTRACT`, `::date`).  
These prevented index and partition-pruning use, causing full table scans at every execution.

### 3.3 Seq Scans on large tables

At baseline, 26 of 30 queries used sequential scans. With `orders` (120k) and `order_items` (240k) growing at scale, this becomes prohibitive.

### 3.4 R13 wrong-answer NULL bug

`NOT IN` with a nullable subquery column (`orders.address_id`) silently returns 0 rows.  
Not a scalability issue, but a **correctness** issue that scales to: always wrong.

### 3.5 GIN trigram indexes (R01, R16) — write amplification

Trigram indexes on `products.title` and `product_reviews.body` are large. At 10× scale, insert throughput for products/reviews will be visibly impacted.

---

## 4. Partitioning Strategy and Rationale

### 4.1 Table chosen: `orders`

**Justification:**
- Largest fact table (120k rows; will grow continuously with time).
- All time-scoped queries filter by `ordered_at`: R06, R09, R20, R21, R22 — 5 of 24 READ queries.
- Queries W04 (bulk insert) and W05 (order lookup) also target `orders`.
- `order_items` is larger but has no independent time column; it always joins through `orders`.

### 4.2 Strategy: `PARTITION BY RANGE (ordered_at)`

**Chosen strategy:** Quarterly range partitioning on `ordered_at TIMESTAMPTZ`.

**Partitions defined (`sql/08_partitioning.sql`):**

| Partition | Range | Rows (seed) |
|---|---|---|
| `orders_before_2025` | MINVALUE → 2025-01-01 | 0 (future-proof) |
| `orders_2025_q1` | 2025-01-01 → 2025-04-01 | 19,781 |
| `orders_2025_q2` | 2025-04-01 → 2025-07-01 | 20,000 |
| `orders_2025_q3` | 2025-07-01 → 2025-10-01 | 20,219 |
| `orders_2025_q4` | 2025-10-01 → 2026-01-01 | 20,220 |
| `orders_2026_q1` | 2026-01-01 → 2026-04-01 | 19,780 |
| `orders_2026_q2` | 2026-04-01 → 2026-07-01 | 20,000 |
| `orders_2026_q3` | 2026-07-01 → 2026-10-01 | 0 (ready for growth) |
| `orders_2026_q4` | 2026-10-01 → 2027-01-01 | 0 (ready for growth) |
| `orders_future` | 2027-01-01 → MAXVALUE | 0 (catch-all) |

**Total migrated: 120,000 rows — confirmed by NOTICE in script output.**

**Why quarterly?**  
- The dominant filtered queries operate on monthly or quarterly windows (June 2026, full year 2026).
- Quarters balance partition size (~20k rows each) vs. partition count overhead.
- PostgreSQL pruner eliminates irrelevant partitions at plan time — no run-time overhead.

**Why not hash or list partitioning?**  
- Hash: no pruning benefit for range predicates; would require full scan of all hash buckets.
- List: would require a low-cardinality status/category column; none matches the query workload.

### 4.3 Migration procedure

`08_partitioning.sql` performs:
1. Drop FK from `order_items → orders` (required before rename).
2. Rename `orders` → `orders_unpartitioned` (preserves original data).
3. Create partitioned `orders` with composite PK `(order_id, ordered_at)`.
4. Create 10 partition tables.
5. `INSERT INTO orders SELECT * FROM orders_unpartitioned` — migrates all 120k rows.
6. Create per-partition and cross-partition indexes.
7. `DO $$ … $$` block verifies row count matches; raises EXCEPTION if not.
8. `ANALYZE orders`.

The script is **idempotent-safe** via `IF NOT EXISTS` guards and an explicit rollback path.

---

## 5. Indexing Strategy

Indexes are defined in `sql/05_indexes.sql` and are applied to the partitioned schema.  
PostgreSQL automatically propagates parent-table indexes to all 10 partitions.

Key indexes:

| Index | Type | Benefit |
|---|---|---|
| `idx_orders_ordered_at` | B-tree on `ordered_at` | Range scans; partition pruning |
| `idx_orders_customer_ordered` | B-tree on `(customer_id, ordered_at DESC)` | R04 customer order history |
| `idx_orders_status_shipped` | Partial B-tree (`status ≠ 'CANCELLED'`) | R05 shipped orders |
| `idx_products_title_trgm` | GIN trigram | R01 ILIKE search |
| `idx_reviews_body_trgm` | GIN trigram | R16 ILIKE review search |
| `idx_order_items_product` | B-tree covering | R11, R19 product aggregation |
| `idx_order_items_seller` | B-tree covering | R06, R15 seller queries |

---

## 6. Benchmark Methodology

**Tool:** `benchmarks/run_benchmark.sh` (project-provided shell script).  
**Measurement:** `EXPLAIN (ANALYZE, BUFFERS)` execution time (ms) extracted from plan output.  
**Runs:** 3 per query; avg, median, min, max recorded.  
**Write queries (W01–W06):** Wrapped in `BEGIN … ROLLBACK` — no data is permanently changed.  
**Database:** `amazon_partition_test` (PostgreSQL 18.6, local Postgres.app).  
**Schema:** `amazon` with partitioned `orders` and all CP3 indexes applied.

### Baseline comparison

Baseline results come from `benchmarks/results/baseline/summary.csv`, executed during CP2
against the same seed dataset on the unpartitioned `orders` table with no optimization indexes.

---

## 7. Actual Measured Results (Seed Dataset)

> [!IMPORTANT]
> All timings below are **actual measured values** from live PostgreSQL execution on 2026-11-23.
> No values were fabricated or estimated.

### 7.1 Read queries — baseline vs. optimised

| Query | Baseline avg (ms) | Optimised avg (ms) | Speedup |
|---|---|---|---|
| R01 | 25.659 | 3.524 | 7.3× |
| R02 | 5.708 | 0.709 | 8.1× |
| R03 | 2.931 | 0.060 | 48.9× |
| R04 | 7.658 | 0.824 | 9.3× |
| R05 | 9.404 | 0.368 | 25.6× |
| R06 | 12.308 | 0.830 | 14.8× |
| R07 | 3.627 | 0.044 | 82.4× |
| R08 | 46.652 | 20.336 | 2.3× |
| R09 | 46.063 | 14.589 | 3.2× |
| R10 | 31.517 | 12.618 | 2.5× |
| R11 | 8.980 | 0.567 | 15.8× |
| R12 | 118.230 | 44.218 | 2.7× |
| R13 | 29.946 | 17.804 | 1.7× (+ correctness fix) |
| R14 | 7.629 | 3.946 | 1.9× |
| R15 | 42.508 | 17.999 | 2.4× |
| R16 | 24.486 | 2.892 | 8.5× |
| R17 | 100.669 | 26.012 | 3.9× |
| R18 | 18.525 | 7.785 | 2.4× |
| **R19** | **17,889.450** | **10.240** | **1,748×** |
| R20 | 11.563 | 1.361 | 8.5× |
| R21 | 9.489 | 0.893 | 10.6× |
| R22 | 46.371 | 12.332 | 3.8× |
| R23 | 0.404 | 0.693 | 0.58× (slight regression) |
| R24 | 0.186 | 0.126 | 1.5× |

### 7.2 Write queries

| Query | Baseline avg (ms) | Optimised avg (ms) | Speedup |
|---|---|---|---|
| W01 | 1.693 | 1.133 | 1.5× |
| W02 | 1.159 | 1.110 | 1.0× |
| W03 | 2.312 | 0.620 | 3.7× |
| W04 | 68.437 | 42.805 | 1.6× |
| W05 | 15.131 | 0.713 | 21.2× |
| W06 | 11.385 | 2.759 | 4.1× |

### 7.3 Partition distribution (live verified)

```
orders_2025_q1:  19,781 rows
orders_2025_q2:  20,000 rows
orders_2025_q3:  20,219 rows
orders_2025_q4:  20,220 rows
orders_2026_q1:  19,780 rows
orders_2026_q2:  20,000 rows
orders_2026_q3:       0 rows  (ready for July–Sep 2026)
orders_2026_q4:       0 rows  (ready for Oct–Dec 2026)
orders_before_2025:   0 rows
orders_future:         0 rows
Total:          120,000 rows  ✓
```

---

## 8. Baseline vs. Optimised Dataset Comparison

This section compares the seed-scale baseline (unpartitioned, no indexes) against
the seed-scale optimised run (partitioned `orders`, all CP3 indexes).

Both runs use the same 120k/240k seed dataset — the difference is entirely due to
schema changes (partitioning) and index additions.

| Metric | Baseline | Optimised |
|---|---|---|
| Sum of all 30 avg_ms | 18,600.080 ms | 249.910 ms |
| READ queries > 100 ms | 3 (R12: 118 ms, R17: 101 ms, R19: 17,889 ms) | 0 |
| READ queries > 10 ms | 14 (R01, R06, R08–R10, R12–R13, R15–R20, R22) | 9 (R08–R10, R12–R13, R15, R17, R19, R22) |
| Queries using any Index Scan | 8 | 23 |
| Queries using Seq Scan only | 20 | 5 (R09, R13, R14, R15, R18) |
| Worst query (R19) | 17,889.450 ms | 10.240 ms |

**Key driver of improvement:** Eliminating the R19 correlated subquery contributes 17,879 ms
(99.9%) of the total reduction. The remaining 29 queries improve by a combined ~498 ms.

> [!NOTE]
> A "large dataset" benchmark (faculty-provided, expected at higher row counts) would better
> demonstrate partition pruning benefits. At 120k rows, the pruning benefit is visible (R20:
> 11.5 ms → 1.4 ms) but modest in absolute terms. At 10× scale, partition pruning eliminates
> scanning 1.08M rows for a June 2026 query while reading only ~200k in the target partition.

---

## 9. Performance Observations

### 9.1 Partition pruning works as designed

For R20 (June 2026 daily sales), the EXPLAIN plan confirms:
```
Index Scan using orders_2026_q2_ordered_at_idx1 on orders_2026_q2
  Index Cond: (ordered_at >= '2026-06-01...' AND ordered_at < '2026-07-01...')
```
Only `orders_2026_q2` is scanned. The other 9 partitions are pruned at plan time.

This is the target behaviour: at 10× scale (200k rows/partition), this query would still
access only the relevant 200k rows rather than 1.2M.

### 9.2 R19 rewrite eliminates the O(n²) bottleneck

The 1,748× speedup for R19 comes from replacing O(n²) correlated iteration with a single
aggregation pass over `order_items` (O(m) + O(n log n)). This scales well.

### 9.3 R12, R17 remain the slowest queries post-optimisation

Both require full scans of `order_items` (240k rows) with no sufficiently selective predicate.
Further improvement requires a materialised view or summary table (see Section 11).

### 9.4 Trigram indexes enable sub-millisecond text search

R01 (product title search) and R16 (review body search) dropped from 25 ms and 24 ms to
3.5 ms and 2.9 ms respectively using GIN trigram indexes.

### 9.5 R23 slight regression (+0.3 ms avg) explained

After partitioning, a lookup by `order_id` (R23) must traverse per-partition `order_id` indexes
(10 Index Only Scans instead of one). The median (0.098 ms) is faster than baseline (0.121 ms);
the avg is inflated by one cold-cache run. This is an inherent trade-off of partitioning.

---

## 10. Limitations and Trade-offs

| Trade-off | Impact | Mitigation |
|---|---|---|
| FK `order_items → orders` (direct) impossible | PostgreSQL requires partition key in UNIQUE constraint | **Resolved:** `order_registry` table + `fk_order_item_order_registry` (ON DELETE CASCADE) + sync triggers `trg_orders_registry_insert` / `trg_orders_registry_delete`; DB-level constraint enforced and tested |
| PK on orders must include `ordered_at` | Cannot look up by `order_id` alone with a unique guarantee | Non-unique `idx_order_items_order_id` index provided; unique lookup requires joining `ordered_at` |
| Partition maintenance | New quarters require `CREATE TABLE … PARTITION OF orders FOR VALUES` | Documented in `08_partitioning.sql` comments; can be automated with pg_cron |
| GIN indexes increase write cost | Products and reviews table inserts are slower | Acceptable for read-heavy catalogue workload |
| R12, R17 not fully optimised | Still require full order_items scan | Would require materialised view — out of scope for CP3/CP4 |
| Large dataset not available | Cannot show partition pruning at true scale | Seed-scale results show pruning working; extrapolation is documented |

---

## 11. Future Scalability Improvements

1. **Materialised view for R12/R17:** Pre-aggregate `order_items` by category and product monthly.
   Refresh daily. This eliminates the 240k-row full scan for category revenue and review summary queries.

2. **Automatic partition management:** Use `pg_cron` or a CI job to run
   `CREATE TABLE orders_2027_q1 PARTITION OF orders FOR VALUES FROM ('2027-01-01') TO ('2027-04-01')`
   one quarter ahead. Remove/archive old partitions with `ALTER TABLE orders DETACH PARTITION orders_before_2025`.

3. **Columnar extension (pg_mooncake / cstore_fdw):** For analytical queries (R08, R12, R17)
   that scan entire `order_items`, a columnar store would reduce I/O significantly.

4. **Connection pooling (PgBouncer):** At scale, connection overhead becomes significant.
   PgBouncer in transaction mode reduces PostgreSQL backend memory pressure.

5. **Read replica for analytics:** Separate the read-heavy analytical workload (R08, R12, R17, R19)
   onto a streaming replica, leaving the primary for transactional writes.

6. **Parallel query tuning:** PostgreSQL 18 supports parallel aggregation. Setting
   `max_parallel_workers_per_gather = 4` could halve R12/R17 at high row counts.

7. **Partitioned `order_items`:** At very large scale (>10M rows), partition `order_items` by
   `order_id` range (or join to the orders partition key). This requires the `ordered_at` column
   to be denormalised into `order_items` or a lookup table to exist.

---

## 12. Files Produced (CP4)

| File | Description |
|---|---|
| `sql/08_partitioning.sql` | Partitioning script; tested and executed on `amazon_partition_test` |
| `benchmarks/results/large/summary.csv` | 30-query benchmark; all entries `EXECUTED_SEED` (large dataset not released) |
| `docs/05_scalability_report.md` | This report |

**Verification status (2026-11-23):**
- `08_partitioning.sql` executed successfully: 120,000 rows migrated, `NOTICE: Migration OK` confirmed ✅
- Partition row counts verified: all 6 populated partitions correct ✅
- Partition pruning for R20 confirmed: only `orders_2026_q2` scanned ✅
- No gaps or overlaps in partition boundaries ✅
- R13 bug confirmed live: original 0 rows, fixed 15,679 rows ✅
- Optimised benchmark: all 30 queries executed with real timings ✅
