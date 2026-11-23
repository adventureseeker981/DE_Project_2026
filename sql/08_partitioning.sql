-- =====================================================================
-- 08_partitioning.sql : Phase 5, Architecture for 100x
-- Author : Vinayak Agrawal (2501010508), Team 0043
-- Target : PostgreSQL 15+
--
-- What this file does
--   Builds a RANGE-partitioned copy of `orders` (partition key: ordered_at,
--   one partition per month), loads it from the live table, proves the copy is
--   identical, and shows partition pruning with EXPLAIN.
--
-- Why a copy and not ALTER TABLE
--   PostgreSQL cannot turn an existing table into a partitioned one in place.
--   Building `orders_part` next to `orders` keeps order_items (FK) and every
--   benchmark query working untouched. A real cut-over plan is at the bottom.
--
-- Run:  psql -d <database> -f sql/08_partitioning.sql
-- Safe to re-run (drops and rebuilds orders_part only).
-- =====================================================================

SET search_path TO amazon;

-- ordered_at is TIMESTAMPTZ and the data is in IST (+05:30). Partition bounds
-- given as plain dates are read in the session time zone, so pin it to IST.
-- Without this a "June" partition would start at 05:30 IST on 1 June or similar.
SET TIME ZONE 'Asia/Kolkata';

-- ---------------------------------------------------------------------
-- 1. Why orders, and why ordered_at
-- ---------------------------------------------------------------------
-- * orders is the table that grows 20x (120,000 -> ~2.4M) and 100x (~12M).
-- * Almost every heavy query filters on a time window: R05, R08, R09, R10,
--   R15, R18, R20, R21 and the admin list R22. RANGE on ordered_at lets the
--   planner skip whole months (partition pruning).
-- * Old months are never updated, so they can be archived (DETACH) cheaply.
-- * HASH(customer_id) would help R04 only, and would give no pruning for any
--   time-window report. LIST(status) is a poor key because status changes, and
--   an UPDATE that changes the key moves the row between partitions.

-- ---------------------------------------------------------------------
-- 2. Primary-key rule for partitioned tables
-- ---------------------------------------------------------------------
-- A PRIMARY KEY or UNIQUE constraint on a partitioned table MUST contain every
-- partition-key column. PostgreSQL enforces uniqueness per partition, so it
-- can only guarantee global uniqueness if the partition key is part of the key.
-- Therefore:
--     orders      : PRIMARY KEY (order_id)               -- not allowed here
--     orders_part : PRIMARY KEY (order_id, ordered_at)   -- required
-- Consequences (also discussed in docs/05_scalability_report.md):
--   a) order_id alone is no longer enforced unique by the database. The order
--      service must keep generating unique ids (we keep the sequence/ids).
--   b) order_items(order_id) cannot keep a FOREIGN KEY to orders_part, because
--      a FK needs a unique constraint on exactly the referenced columns. To keep
--      the FK, order_items would have to carry ordered_at as well.
--   c) A lookup by order_id only (R23, W05's subquery) cannot prune and probes
--      every partition's index. Look-ups that also know ordered_at do prune.

DROP TABLE IF EXISTS orders_part CASCADE;

CREATE TABLE orders_part (
    order_id        INTEGER        NOT NULL,
    customer_id     INTEGER        NOT NULL,
    address_id      INTEGER,
    ordered_at      TIMESTAMPTZ    NOT NULL,
    payment_method  VARCHAR(20)    NOT NULL,
    total_amount    NUMERIC(10,2)  NOT NULL,
    status          VARCHAR(20)    NOT NULL DEFAULT 'PLACED',
    shipped_at      TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ,

    CONSTRAINT pk_orders_part PRIMARY KEY (order_id, ordered_at),

    CONSTRAINT fk_orders_part_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_orders_part_address FOREIGN KEY (address_id)
        REFERENCES addresses(address_id) ON DELETE SET NULL,

    -- same business rules as amazon.orders
    CONSTRAINT chk_op_order_id_positive CHECK (order_id > 0),
    CONSTRAINT chk_op_payment_method CHECK (payment_method IN
        ('CARD','UPI','NET_BANKING','NETBANKING','COD','WALLET','GIFT_CARD','EMI')),
    CONSTRAINT chk_op_total_positive CHECK (total_amount > 0),
    CONSTRAINT chk_op_status CHECK (status IN
        ('PLACED','PACKED','SHIPPED','OUT_FOR_DELIVERY','DELIVERED','CANCELLED','RETURNED')),
    CONSTRAINT chk_op_shipped_after_ordered CHECK (shipped_at IS NULL OR shipped_at >= ordered_at),
    CONSTRAINT chk_op_delivered_after_ordered CHECK (delivered_at IS NULL OR delivered_at >= ordered_at),
    CONSTRAINT chk_op_status_delivered CHECK (
        (status IN ('DELIVERED','RETURNED') AND delivered_at IS NOT NULL)
        OR (status NOT IN ('DELIVERED','RETURNED')))
) PARTITION BY RANGE (ordered_at);

-- ---------------------------------------------------------------------
-- 3. Monthly partitions: Jan 2025 .. Dec 2026, plus a DEFAULT safety net
-- ---------------------------------------------------------------------
-- The seed data covers 1 Jan 2025 - 30 Jun 2026. Partitions run to Dec 2026 so
-- new orders (W01 inserts on 1 Jul 2026) have a home. Month-sized partitions at
-- ~2.4M rows are roughly 130k rows each, which is small enough to prune well
-- and large enough to keep the partition count manageable.
DO $$
DECLARE
    m date := DATE '2025-01-01';
BEGIN
    WHILE m < DATE '2027-01-01' LOOP
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF orders_part FOR VALUES FROM (%L) TO (%L)',
            'orders_p' || to_char(m, 'YYYY_MM'),
            m::text,
            (m + INTERVAL '1 month')::date::text);
        m := (m + INTERVAL '1 month')::date;
    END LOOP;
END $$;

-- Rows outside every range (back-dated or far-future data) land here instead of
-- failing the INSERT. Watch it: a default partition with rows blocks creating a
-- new partition that overlaps them, so it should normally stay empty.
CREATE TABLE orders_p_default PARTITION OF orders_part DEFAULT;

-- ---------------------------------------------------------------------
-- 4. Indexes (created on the parent, so every partition gets its own copy)
-- ---------------------------------------------------------------------
-- R04 "Your Orders": equality on customer, newest first.
CREATE INDEX idx_orders_part_customer_time ON orders_part (customer_id, ordered_at DESC);
-- R22 admin list / keyset paging: newest first inside the surviving partitions.
CREATE INDEX idx_orders_part_time_desc     ON orders_part (ordered_at DESC);
-- R05 / W05: only a small share of orders is in these states at any moment.
CREATE INDEX idx_orders_part_open_status   ON orders_part (status, ordered_at)
    WHERE status IN ('PLACED','PACKED','SHIPPED','OUT_FOR_DELIVERY');
-- Adjust these to match sql/05_indexes.sql so that the comparison against
-- `orders` is like for like.

-- ---------------------------------------------------------------------
-- 5. Load from the live table and prove the copy is identical
-- ---------------------------------------------------------------------
INSERT INTO orders_part
    (order_id, customer_id, address_id, ordered_at, payment_method,
     total_amount, status, shipped_at, delivered_at)
SELECT order_id, customer_id, address_id, ordered_at, payment_method,
       total_amount, status, shipped_at, delivered_at
FROM orders;

ANALYZE orders_part;

-- 5a. Row counts must match
SELECT (SELECT count(*) FROM orders)      AS orders_rows,
       (SELECT count(*) FROM orders_part) AS orders_part_rows;

-- 5b. Zero rows expected in both directions
SELECT count(*) AS only_in_orders FROM (
    SELECT order_id, customer_id, address_id, ordered_at, payment_method, total_amount, status, shipped_at, delivered_at FROM orders
    EXCEPT
    SELECT order_id, customer_id, address_id, ordered_at, payment_method, total_amount, status, shipped_at, delivered_at FROM orders_part
) x;
SELECT count(*) AS only_in_orders_part FROM (
    SELECT order_id, customer_id, address_id, ordered_at, payment_method, total_amount, status, shipped_at, delivered_at FROM orders_part
    EXCEPT
    SELECT order_id, customer_id, address_id, ordered_at, payment_method, total_amount, status, shipped_at, delivered_at FROM orders
) x;

-- 5c. Distribution across partitions (the default partition should show 0 rows)
SELECT tableoid::regclass AS partition, count(*) AS orders
FROM orders_part
GROUP BY 1
ORDER BY 1;

-- Size of each partition vs the original table
SELECT c.relname AS partition,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'amazon.orders_part'::regclass
ORDER BY c.relname;

SELECT pg_size_pretty(pg_total_relation_size('amazon.orders')) AS orders_total_size,
       pg_size_pretty(sum(pg_total_relation_size(i.inhrelid))) AS orders_part_total_size
FROM pg_inherits i WHERE i.inhparent = 'amazon.orders_part'::regclass;

-- ---------------------------------------------------------------------
-- 6. Partition pruning with EXPLAIN
-- ---------------------------------------------------------------------
-- Read the plan: only the partitions that can contain matching rows should
-- appear. The others are removed at plan time ("Subplans Removed" appears only
-- for run-time pruning; plan-time pruning simply leaves them out).

-- 6a. One month (R20 / R21 style). Expect ONE partition: orders_p2026_06.
--     Written as a half-open range on the raw column so pruning can work.
EXPLAIN (ANALYZE, BUFFERS)
SELECT ordered_at::date AS day, sum(total_amount) AS gmv
FROM orders_part
WHERE status <> 'CANCELLED'
  AND ordered_at >= '2026-06-01' AND ordered_at < '2026-07-01'
GROUP BY 1
ORDER BY 1;

-- 6b. Contrast: the ORIGINAL R20 filter wraps the column in a cast
--     (ordered_at::date BETWEEN ...). That hides the column from the planner,
--     so ALL partitions are scanned. Partitioning does not rescue a
--     non-sargable predicate; the rewrite in 06_optimized_queries.sql is still needed.
EXPLAIN (ANALYZE, BUFFERS)
SELECT ordered_at::date AS day, sum(total_amount) AS gmv
FROM orders_part
WHERE status <> 'CANCELLED'
  AND ordered_at::date BETWEEN '2026-06-01' AND '2026-06-30'
GROUP BY 1;

-- 6c. A calendar year (R09 style). Expect only the 2026 partitions.
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', ordered_at) AS month, count(*) AS orders
FROM orders_part
WHERE ordered_at >= '2026-01-01' AND ordered_at < '2027-01-01'
  AND status <> 'CANCELLED'
GROUP BY 1;

-- 6d. Keyset page for the admin list (R22). Expect the newest partitions only,
--     with an ordered Index Scan per partition (Merge Append), instead of
--     sorting everything that OFFSET would have to skip.
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, status, total_amount, ordered_at
FROM orders_part
WHERE ordered_at < '2026-03-01'
ORDER BY ordered_at DESC
LIMIT 25;

-- 6e. The PRIMARY KEY RULE in action: lookup by order_id only (R23 style).
--     No partition key in the predicate, so nothing can be pruned and the
--     planner probes the PK index of EVERY partition. Still fast, but the cost
--     grows with the partition count.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_part WHERE order_id = 100001;

-- 6f. Same lookup when the application also knows ordered_at (for example it
--     was shown on the order list page). Expect ONE partition.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders_part
WHERE order_id = 100001
  AND ordered_at >= '2025-01-01' AND ordered_at < '2025-02-01';
-- On the LARGE data, order 100001 was placed on 2025-01-23, so January 2025 is right.
-- On the seed data order 100001 is a different order: find its month first with
--   SELECT ordered_at FROM orders WHERE order_id = 100001;

-- ---------------------------------------------------------------------
-- 7. Maintenance operations that partitioning makes cheap
-- ---------------------------------------------------------------------
-- 7a. Add next month's partition BEFORE it is needed (run from a monthly job).
--     Example for January 2027 is already created above; for January 2028:
--     CREATE TABLE orders_p2028_01 PARTITION OF orders_part
--         FOR VALUES FROM ('2028-01-01') TO ('2028-02-01');

-- 7b. Archive an old month without a slow DELETE and without table bloat:
--     ALTER TABLE orders_part DETACH PARTITION orders_p2025_01;
--     -- then dump it to cold storage and drop it:
--     -- DROP TABLE orders_p2025_01;
--     For zero blocking on a busy system use DETACH PARTITION ... CONCURRENTLY.

-- 7c. Per-partition autovacuum: old months are read-only, so vacuum them once
--     and leave them alone; only the current month needs aggressive settings.
--     ALTER TABLE orders_p2026_06 SET (autovacuum_vacuum_scale_factor = 0.02,
--                                      autovacuum_analyze_scale_factor = 0.01);

-- ---------------------------------------------------------------------
-- 8. Cut-over plan for production (not executed here)
-- ---------------------------------------------------------------------
-- 1. Add ordered_at to order_items (or keep a small order_id -> ordered_at map)
--    so that its FK to orders_part(order_id, ordered_at) is possible.
-- 2. Create orders_part and load it as above, then catch up on new rows.
-- 3. In one transaction: rename orders -> orders_old and orders_part -> orders,
--    then repoint the FKs. Keep orders_old for a rollback window.
-- 4. Run the benchmark on the new table:
--    ./benchmarks/run_benchmark.sh <db> large 3 sql/06_optimized_queries.sql
-- No part of this section changes any data when this file is run.
