# Phase 5: Scalability Report

**Project:** Amazon Online Shopping Database · **Team:** 0043 · **Database:** PostgreSQL 15+
**Author of this report:** Vinayak Agrawal (2501010508), group lead
**Partitioning DDL:** [`sql/08_partitioning.sql`](../sql/08_partitioning.sql) · **Raw results:** [`benchmarks/results/`](../benchmarks/results/)

> **How to finish this file.** Cells marked `TBD` need numbers from the large-dataset run.
> Do not type them by hand. Run `./benchmarks/run_benchmark.sh <db> large 3 sql/06_optimized_queries.sql`,
> then `python3 benchmarks/make_scalability_table.py` and paste its output into section 1.
> Every number that is not `TBD` below is copied from `benchmarks/results/baseline/summary.csv`
> or is a clearly labelled projection from it. Delete this note before the final commit.

---

## 0. Setup used for the large run

| Item | Value |
|------|-------|
| Dataset | `large_data/`, loaded unchanged. Row counts (counted from the CSV files): orders 2,400,000 · order_items 4,800,000 · products 600,000 · customers 600,000 · addresses 900,000 · cart_items 900,000 · product_reviews 777,147 · returns 106,493 · sellers 30,000 · categories 40 · cities 10 |
| Schema / load | `sql/01_schema.sql`, `sql/02_load_data.sql` (folder name changed only), then `sql/05_indexes.sql`, then `ANALYZE` |
| Queries run | `sql/06_optimized_queries.sql` (the original 30 were **not** run on the large data) |
| Method | `EXPLAIN (ANALYZE, BUFFERS)`, 3 runs per query, average reported; writes inside `BEGIN … ROLLBACK` |
| PostgreSQL version / laptop | `TBD` (also fill `postgres_version` and `laptop_used_for_benchmarks` in `team.json`) |

**Profile of the large `orders` file** (computed from `large_data/orders.csv`, before loading):

- Order dates run from 2025-01-01 to 2026-06-30 (IST), the same 18 months as the seed data, so the large
  data is denser, not longer. No row falls outside the monthly partitions in `sql/08_partitioning.sql`.
- Each month holds between 123,077 (February) and 136,264 orders, about 131k on average, so the partitions
  are evenly sized. Orders per month in the seed data are about 20× smaller.
- 120,216 orders (5.0%) have no `address_id` (digital-only orders). This is the NULL that breaks `NOT IN` in R13.
- Statuses: DELIVERED 2,107,684 · CANCELLED 161,423 · RETURNED 106,493 · SHIPPED 17,057 · OUT_FOR_DELIVERY 5,080 ·
  PLACED 1,133 · PACKED 1,130. Only about 1% of orders are in an open state, which is why the partial
  index on open statuses for R05 / W05 stays small.
- Payment methods are `UPI, CARD, COD, GIFT_CARD, EMI, NETBANKING` (no `NET_BANKING`), all accepted by the
  `chk_payment_method` constraint. No duplicate order ids, no order without items, no order item without an order.
- For R22 keyset pagination: the row at `OFFSET 75000` is order 2325000 placed at `2026-06-13 22:29:40+05:30`, so the
  "last seen" pair for the first-page-equivalent call is `(ordered_at, order_id) = ('2026-06-13 22:30:00+05:30', 2325001)`.

---

## 1. Results table

Optimized-on-seed comes from `benchmarks/results/optimized/summary.csv`, large from
`benchmarks/results/large/summary.csv`. Generate the table with
`python3 benchmarks/make_scalability_table.py` and paste it here:

```
TBD: paste the generated table (30 rows + total)
```

For orientation, here is the **unoptimized baseline on the seed data** (120,000 orders) that the
optimized numbers are compared against. These come from `benchmarks/results/baseline/summary.csv`.
The 30-query total was **18,586.75 ms**, and one query dominates it:

| Query | What it does | Baseline avg (ms) | Plan at baseline |
|-------|--------------|------------------:|------------------|
| R19 | Mobile phones with last sale date and units sold | 17,889.450 | correlated subqueries, Seq Scan on `order_items` |
| R12 | Return rate per top-level category | 118.230 | Seq Scans on 4 tables |
| R17 | Unverified "verified purchase" reviews | 100.669 | Seq Scans on reviews, orders, order_items |
| W04 | 5,000 cart inserts | 68.437 | batch insert |
| R08 | Top 5 products per sub-category | 46.652 | Seq Scans on 3 tables |
| R22 | Admin page 3,001 with `OFFSET` | 46.371 | Seq Scan + sort on `orders` |
| R09 | Prime vs non-Prime AOV | 46.063 | Seq Scans on orders, customers |

For every query that misses its target on the large data, record why and what was changed
(section 3). If a query is explained instead of fixed, say so in the "If not" column.

---

## 2. Growth analysis

The data grew about 20×. Queries fall into three groups. The *expected* behaviour is listed
here from how each plan is built; **confirm each against the measured growth column** and move
a query if the measurement disagrees.

### 2.1 Stayed about the same (growth < ~4×)

Primary-key and B-tree lookups cost O(log n). A 20× larger table adds only a few levels to the
index, so the work barely changes.

Expected members: **R23, R24, R03, R04, R07, R11, W01, W02, W05** once indexed
(single customer / product / order / ASIN lookups).
Measured on the large data: `TBD`.

### 2.2 Grew about 20×

These read a fixed *share* of a table, so the rows touched grow with the table. An index does not
help when the query needs a constant fraction of the rows.

Expected members: **R08, R09, R12, R15, R18, R20** (reports over a time window or over all lines),
plus **W04** (bulk insert) and **W06** (clean-up delete) if they touch a proportional number of rows.
Measured on the large data: `TBD`.

### 2.3 Grew more than 20×

Super-linear growth comes from join strategy or memory spill, not just row count.

Likely members: **R19** (the baseline already spends 17.9 s in correlated subqueries; per-product
subqueries multiply the cost), **R17** (anti-join between reviews and order lines), **R10** and **R13**
(`NOT EXISTS` / `NOT IN` against a large `orders`), **R22** if it still uses `OFFSET`
(cost grows with the offset, and a "page 3,001" of 25 rows becomes a much deeper page on 20× data).
Measured on the large data: `TBD`, with the cause for each taken from its `EXPLAIN` plan
(e.g. a Sort or Hash that spills to disk: "Sort Method: external merge", "Batches: > 1").

---

## 3. What broke at scale and how it was fixed

Fill one entry per query that missed its target. Keep the plans before and after under
`benchmarks/results/large/` and quote the key lines here.

| Query | Symptom on large data | Cause (from plan) | Fix | Before (ms) | After (ms) |
|-------|-----------------------|-------------------|-----|------------:|-----------:|
| `TBD` | | | | | |

Issues to check first, because they are known to appear only at scale:

1. **`OFFSET` pagination (R22).** `OFFSET 75000` must produce and discard 75,000 rows. On large data the
   same page number sits deeper. Replace it with keyset pagination:
   `WHERE (ordered_at, order_id) < (:last_ordered_at, :last_order_id) ORDER BY ordered_at DESC, order_id DESC LIMIT 25`.
   For the benchmark, choose the "last seen" pair as the 75,000th row of the large data
   (`SELECT ordered_at, order_id FROM orders ORDER BY ordered_at DESC, order_id DESC OFFSET 74999 LIMIT 1`),
   so that the page returned is comparable with the seed run. In `large_data` that row is order 2325001 at
   `2026-06-13 22:30:00+05:30` (verified from the CSV; re-check it against the loaded table).
2. **Hash / sort spill.** A plan that worked in memory on 120k orders can spill on 2.4M. Look for
   `Batches:` greater than 1 or `external merge`. Fix with a better index or a narrower query, not by
   raising `work_mem` (not allowed by the rules).
3. **Stale statistics.** After loading, run `ANALYZE`. A plan chosen from outdated statistics can be
   orders of magnitude slower.
4. **Correctness of `NOT IN` (R13).** Orders for digital products have `address_id = NULL`. With
   `NOT IN (SELECT address_id FROM orders)`, a single NULL makes the whole predicate unknown, so no
   address is ever reported as unused. This is the wrong result behind problem P6. The fix is
   `NOT EXISTS`, which is also faster. This holds at any scale.

---

## 4. Storage

Collect with the queries below and paste the numbers. Seed and large must be measured the same way.

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;

SELECT c.relname AS table_name,
       pg_size_pretty(pg_table_size(c.oid))   AS table_size,
       pg_size_pretty(pg_indexes_size(c.oid)) AS index_size,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'amazon' AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;
```

| Dataset | Database size | `orders` table / indexes | `order_items` table / indexes | All indexes combined |
|---------|--------------:|-------------------------:|------------------------------:|---------------------:|
| Seed (≈ 120k orders) | `TBD` | `TBD` | `TBD` | `TBD` |
| Large (≈ 2.4M orders) | `TBD` | `TBD` | `TBD` | `TBD` |

Things to comment on once the numbers are in: whether indexes grew about 20× like the tables, whether
the total index size now exceeds the table size (a cost for every write), and which single index is
the biggest.

---

## 5. Architecture for 100×

At 100× the system holds roughly **12 million orders and 24 million order lines**. The reasoning below
uses the **measured baseline** numbers from this repository. Projections are labelled as such: they are
straight-line extrapolations of the *unoptimized* baseline and exist only to show which queries must not
stay as they are, not to claim a measured result.

### 5.1 Partitioning

**Table:** `orders`. **Column:** `ordered_at`. **Method:** RANGE, one partition per month.
DDL, a row-for-row equality check, and the pruning demonstrations are in
[`sql/08_partitioning.sql`](../sql/08_partitioning.sql).

**Why `orders` and `ordered_at`.**
- `orders` is the largest header table and the one `order_items`, `returns`, R05, R08, R09, R10, R15,
  R18, R20, R21 and R22 all lead with.
- Eight of the nine reporting queries filter on a time window. A monthly range key lets the planner skip
  every month outside the window. Example: June 2026 only needs one partition of 18 seed months.
- Old months are never updated, so they can be archived with `DETACH PARTITION` instead of a slow
  `DELETE` that bloats the table.

**Why not the alternatives.**
- *HASH(customer_id)* spreads R04 well but gives **no pruning** for any time-window report.
- *LIST(status)* is a poor key because `status` is updated (PLACED → PACKED → SHIPPED …), and an update
  that changes the partition key physically moves the row between partitions.
- *Partitioning `order_items`* is the next step (by `order_id` HASH), but only after `orders` has been
  proven; it is the table whose join cost dominates R08, R12, R15, R17 and R19.

**Primary-key rule.** In a partitioned table every `PRIMARY KEY` / `UNIQUE` constraint must include the
partition key. So `orders (order_id)` becomes `orders_part (order_id, ordered_at)`. This has three
consequences that we accept and design around:

1. `order_id` alone is no longer enforced unique by the database. The order service must keep issuing
   unique ids (it already does, W01 supplies the id).
2. `order_items.order_id` can no longer reference `orders(order_id)`. To keep a foreign key, `order_items`
   must also store `ordered_at`, or the FK is replaced by an application check.
3. A lookup by `order_id` alone (R23) cannot be pruned. It probes the PK index of every partition. With
   monthly partitions this is about 24 small index probes at two years of data, still sub-millisecond per
   probe but growing with the partition count. The fix is to pass `ordered_at` from the order list page,
   or to encode the month in the order id.

**What the `EXPLAIN` runs in `08_partitioning.sql` show.** Paste the measured results here:

| Check | Expected | Measured |
|-------|----------|----------|
| Range predicate on one month (6a) | exactly 1 partition scanned | `TBD` |
| `ordered_at::date BETWEEN …` as in original R20 (6b) | all partitions scanned (no pruning) | `TBD` |
| One calendar year (6c) | only that year's partitions | `TBD` |
| Keyset page (6d) | newest partitions only, ordered index scans | `TBD` |
| `order_id` only (6e) vs `order_id` + `ordered_at` (6f) | all partitions vs 1 partition | `TBD` |

Item 6b matters for the argument: partitioning does **not** fix a non-sargable predicate, so the query
rewrites from Phase 4 are still required.

**Baseline-based projection (not a measurement).** The unoptimized R12 (118.230 ms) and R08 (46.652 ms)
read most or all of `order_items`. A pure linear extrapolation gives about 2.4 s and 0.9 s at 20×, and
about 11.8 s and 4.7 s at 100×, against a 5 s target for reports. Without pruning or a summary table,
R12 alone would miss the target at 100×.

### 5.2 Sharding

**Shard key: `customer_id`.** Orders, order items, carts, addresses, returns and reviews-by-customer all
follow the customer. The customer-facing real-time queries then stay on **one shard**:

| Query | Shard behaviour with customer sharding |
|-------|----------------------------------------|
| R04 "Your Orders" | single shard (filter on `customer_id`) |
| W01, W04, W06 (cart/checkout writes) | single shard per customer |
| R10 abandoned carts | per shard, then merge top 100 |
| R23 order details | single shard **if** the order id embeds the shard (or a small lookup table maps order → customer) |

**What becomes cross-shard.** The seller view is the mirror image of R04:

| Query | Why it crosses shards | How to handle it |
|-------|-----------------------|------------------|
| R06 seller's order lines | one seller's lines come from customers on every shard | keep a seller-keyed copy of order lines (async event stream) on a seller read store, or scatter-gather with a per-seller index on each shard |
| R15 top sellers by revenue | needs all shards | scatter-gather, or read a pre-aggregated revenue-by-seller table |
| R08, R09, R12, R18, R20 | global aggregates over all orders | compute per shard and merge partial aggregates, or serve from a warehouse / summary tables |
| R11 frequently bought together | pairs of products across all customers | precompute offline into a `product_pairs` table, refreshed nightly |
| R17 fake-verified-review check | joins reviews to a customer's orders | co-locate reviews by `customer_id`, then run per shard |
| R03, R16 reviews by product | reviews are read per product | keep a product-keyed copy of reviews; reviews are write-light, so this is cheap |

**Reference data** (`cities`, `categories`, `sellers`, `products`) is small relative to orders and read by
every shard. Replicate it to all shards rather than sharding it. R01, R02, R07, R14, R24 then run on any
shard or on a replica.

Why not shard by seller or by order: sharding by seller would make R04, the most frequent customer query,
cross-shard. Sharding by order id spreads load evenly but makes **both** R04 and R06 cross-shard.
Customer is the key with the best fit to the high-volume, latency-sensitive workload.

### 5.3 Read replicas and caching

| Send to a replica or cache | Queries | Reason |
|----------------------------|---------|--------|
| Replica, results may be a few seconds stale | R01, R02, R14, R16 (search / browse) | read-only, tolerate small staleness |
| Replica or cache with short TTL | R03, R11, R24 (product page, ASIN lookup) | the same product is read by many users; TTL of minutes |
| Replica | R07, R13, R21 | dashboards and clean-up lists |
| Replica / warehouse, summary table | R08, R09, R12, R15, R18, R19, R20 | heavy analytics; must not compete with checkout |
| Replica with "read your writes" care | R04, R06, R23 | a customer who just ordered expects to see the order; route to the primary for a short window after a write, or read from the primary |
| **Primary only** | W01–W06, R05 (live logistics state), R10 and R17 when used to trigger actions | writes, and reads that must see the latest status |

### 5.4 Maintenance

- **Autovacuum on `orders`.** Status updates (W05 and the logistics flow) create dead tuples in recent
  months only. Use aggressive per-partition settings for the current month
  (`autovacuum_vacuum_scale_factor` around 0.02, `autovacuum_analyze_scale_factor` around 0.01) and leave
  old, read-only partitions at defaults. With partitioning, vacuum work is bounded by partition size.
- **Archiving.** Detach monthly partitions older than the retention window
  (`ALTER TABLE … DETACH PARTITION … CONCURRENTLY`), dump them to cold storage, then drop. This is a
  metadata operation, not a row-by-row delete.
- **Summary tables.** Materialized views for R08, R12, R15, R20, refreshed nightly
  (`REFRESH MATERIALIZED VIEW CONCURRENTLY`, which needs a unique index on the view). State the staleness
  to the business (reports are "as of last night").
- **Statistics.** Run `ANALYZE` on the parent and on the partitions after each bulk load; consider extended
  statistics if the planner misestimates correlated columns (status and shipped_at).
- **Carts.** W06 deletes old cart rows nightly; at scale run it in batches so that one transaction does not
  hold a long lock or create a large dead-tuple spike.

---

## 6. Conclusion

**Is the database ready for next year's 20× growth?** `TBD`. Decide after the large run:
- *Yes* only if every group target in the README (real-time under 5 ms, interactive under 250 ms,
  reports under 5,000 ms, batch under 2,000 ms) is met or the miss is explained in section 3.

**Remaining risks to review and keep or edit:**
1. **R19 / R17 style queries** scale worst; confirm their large-data times are inside the report target.
2. **Index write overhead.** More indexes slow W01, W02, W04. Compare the large-data write times with the
   baseline (W01 1.693 ms, W04 68.437 ms) and state whether the overhead is acceptable.
3. **Single-node limit.** One PostgreSQL server holds everything. Partitioning delays the problem; at 100×
   sharding by customer plus replicas (section 5) is the plan.
4. **Partitioning side effects.** The PK rule (5.1) weakens `order_id` uniqueness and forces a change to
   `order_items`' foreign key; this needs a migration plan before cut-over (`sql/08_partitioning.sql`, section 8).
5. **Data-quality assumptions.** Constraints such as `chk_payment_method` accept both `NET_BANKING` and
   `NETBANKING`; the large data may contain other variants. Check that the large load succeeds with no rejected rows.
