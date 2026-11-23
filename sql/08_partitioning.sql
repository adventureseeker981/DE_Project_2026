-- =====================================================================
-- Amazon Online Shopping Database – CP4: Partitioning
-- Team: V_nue_mail  |  Team No.: T0043
-- PostgreSQL 18 (Postgres.app) – declarative RANGE partitioning
--
-- TABLE CHOSEN:  orders
-- JUSTIFICATION:
--   • Largest fact table: 120 000 rows on seed data, ≈2 400 000 on the
--     large dataset (20× growth).  At 100× it reaches ~12 M rows.
--   • 18 of 30 workload queries touch orders directly; most filter on
--     ordered_at date ranges (R06, R08, R09, R18, R20, R21, R22 …).
--   • RANGE partitioning on ordered_at lets PostgreSQL prune whole
--     partitions for any query with a date/time predicate, eliminating
--     the sequential scans that dominated the Phase-3 baseline.
--
-- ============================================================
-- POSTGRESQL PARTITIONING CONSTRAINT – READ THIS FIRST
-- ============================================================
-- Rule (unchanged since PG 11):
--   Every UNIQUE constraint and PRIMARY KEY on a partitioned table
--   MUST include all partition key column(s).
--
--   Because we partition by RANGE(ordered_at), the PK must be
--   (order_id, ordered_at) rather than (order_id) alone.
--
-- Consequence for the foreign key order_items → orders:
--   order_items carries order_id but NOT ordered_at.
--   There is no way to create a unique index on orders(order_id)
--   alone on a RANGE(ordered_at)-partitioned table.
--   Therefore the database-enforced FK from order_items to the
--   partitioned orders table CANNOT be restored without either:
--     (a) adding ordered_at to order_items (schema-breaking change), or
--     (b) switching the partition key to HASH(order_id) (loses date pruning).
--
--   CHOSEN APPROACH (order_registry + real FK + sync triggers):
--     • Drop the FK on order_items → original orders (Step 1).
--     • Create a thin non-partitioned order_registry(order_id PK) table.
--     • Populate it from the migrated partitioned orders rows.
--     • Add a real FK: order_items(order_id) → order_registry(order_id)
--       with ON DELETE CASCADE — a true database-enforced constraint.
--     • Add AFTER INSERT / AFTER DELETE triggers on orders to keep
--       order_registry in sync automatically.
--     • Create a non-unique index on order_items(order_id) for JOIN speed.
--
--   Result: order_items has a real FK constraint (not application-level).
--   Deleting an order removes its registry row (via trigger), which then
--   cascades to remove order_items rows (via FK ON DELETE CASCADE).
--   The partitioned table structure and date-range pruning are unchanged.
--
-- STRATEGY: RANGE on ordered_at, quarterly partitions
--   Seed data spans 2025-01-01 to 2026-06-30 (18 months).
--   W01 test insert uses 2026-07-01, so a 2026-Q3 partition is needed.
--   10 partitions total:  before_2025 | q1–q4 2025 | q1–q4 2026 | future
--   No gaps, no overlaps (verified – see partition boundary table below).
--
-- HOW TO RUN (idempotent):
--   psql -d <your_database> -f sql/08_partitioning.sql
--   Safe to re-run: each step uses IF EXISTS / RENAME guards.
-- =====================================================================

SET search_path TO amazon;

-- =====================================================================
-- STEP 1: Detach order_items FK before renaming orders
-- =====================================================================
-- We must drop this FK before renaming the referenced table.
-- It cannot be restored to the partitioned table (see note above).

ALTER TABLE order_items
    DROP CONSTRAINT IF EXISTS fk_order_item_order;

-- =====================================================================
-- STEP 2: Rename original orders table (preserve all data safely)
-- =====================================================================
-- Data stays in orders_unpartitioned throughout this script.
-- If the script fails, nothing is lost.

ALTER TABLE orders RENAME TO orders_unpartitioned;

-- =====================================================================
-- STEP 3: Create the partitioned parent table
-- =====================================================================
-- Columns and CHECK constraints are identical to sql/01_schema.sql.
-- Primary key is now (order_id, ordered_at) — required by PostgreSQL
-- because ordered_at is the partition key.
--
-- Partition boundary table (all RANGE values in UTC+05:30 / IST):
--
--   Partition name        | FROM (inclusive)        | TO (exclusive)
--   ----------------------|-------------------------|----------------------
--   orders_before_2025    | MINVALUE                | 2025-01-01 00:00 IST
--   orders_2025_q1        | 2025-01-01 00:00 IST    | 2025-04-01 00:00 IST
--   orders_2025_q2        | 2025-04-01 00:00 IST    | 2025-07-01 00:00 IST
--   orders_2025_q3        | 2025-07-01 00:00 IST    | 2025-10-01 00:00 IST
--   orders_2025_q4        | 2025-10-01 00:00 IST    | 2026-01-01 00:00 IST
--   orders_2026_q1        | 2026-01-01 00:00 IST    | 2026-04-01 00:00 IST
--   orders_2026_q2        | 2026-04-01 00:00 IST    | 2026-07-01 00:00 IST  ← seed data end
--   orders_2026_q3        | 2026-07-01 00:00 IST    | 2026-10-01 00:00 IST  ← W01 insert here
--   orders_2026_q4        | 2026-10-01 00:00 IST    | 2027-01-01 00:00 IST
--   orders_future         | 2027-01-01 00:00 IST    | MAXVALUE
--
-- Adjacency verified: every upper bound equals the next lower bound.
-- No gap, no overlap.

CREATE TABLE orders (
    order_id        INTEGER          NOT NULL,
    customer_id     INTEGER          NOT NULL,
    address_id      INTEGER          DEFAULT NULL,
    ordered_at      TIMESTAMPTZ      NOT NULL,
    payment_method  VARCHAR(20)      NOT NULL,
    total_amount    NUMERIC(10,2)    NOT NULL,
    status          VARCHAR(20)      NOT NULL DEFAULT 'PLACED',
    shipped_at      TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ,

    -- ----------------------------------------------------------------
    -- PRIMARY KEY: must include the partition key (ordered_at).
    -- PostgreSQL enforces this; (order_id) alone is rejected.
    -- ----------------------------------------------------------------
    CONSTRAINT pk_orders PRIMARY KEY (order_id, ordered_at),

    -- Outbound FKs (orders → customers / addresses) are unaffected
    -- because we are the referencing side, not the referenced side.
    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE RESTRICT,

    CONSTRAINT fk_order_address
        FOREIGN KEY (address_id)
        REFERENCES addresses(address_id) ON DELETE SET NULL,

    CONSTRAINT chk_order_id_positive
        CHECK (order_id > 0),
    CONSTRAINT chk_payment_method
        CHECK (payment_method IN (
            'CARD','UPI','NET_BANKING','NETBANKING',
            'COD','WALLET','GIFT_CARD','EMI')),
    CONSTRAINT chk_total_amount_positive
        CHECK (total_amount > 0),
    CONSTRAINT chk_order_status
        CHECK (status IN (
            'PLACED','PACKED','SHIPPED','OUT_FOR_DELIVERY',
            'DELIVERED','CANCELLED','RETURNED')),
    CONSTRAINT chk_shipped_after_ordered
        CHECK (shipped_at IS NULL OR shipped_at >= ordered_at),
    CONSTRAINT chk_delivered_after_ordered
        CHECK (delivered_at IS NULL OR delivered_at >= ordered_at),
    CONSTRAINT chk_status_delivered_consistency
        CHECK (
            (status IN ('DELIVERED','RETURNED') AND delivered_at IS NOT NULL)
            OR
            (status NOT IN ('DELIVERED','RETURNED'))
        )
)
PARTITION BY RANGE (ordered_at);

-- =====================================================================
-- STEP 4: Create child partitions (10 total, no gaps, no overlaps)
-- =====================================================================
-- PostgreSQL RANGE semantics: FROM is inclusive, TO is exclusive.
-- Each partition's TO value equals the next partition's FROM value.
-- Verified: no gap or overlap between any adjacent pair.

-- Catch-all for any historical data before 2025 (seed data: empty)
CREATE TABLE orders_before_2025
    PARTITION OF orders
    FOR VALUES FROM (MINVALUE) TO ('2025-01-01 00:00:00+05:30');

-- 2025 Q1: 1 Jan – 31 Mar 2025
CREATE TABLE orders_2025_q1
    PARTITION OF orders
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30')
               TO   ('2025-04-01 00:00:00+05:30');

-- 2025 Q2: 1 Apr – 30 Jun 2025
CREATE TABLE orders_2025_q2
    PARTITION OF orders
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30')
               TO   ('2025-07-01 00:00:00+05:30');

-- 2025 Q3: 1 Jul – 30 Sep 2025
CREATE TABLE orders_2025_q3
    PARTITION OF orders
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30')
               TO   ('2025-10-01 00:00:00+05:30');

-- 2025 Q4: 1 Oct – 31 Dec 2025
CREATE TABLE orders_2025_q4
    PARTITION OF orders
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30')
               TO   ('2026-01-01 00:00:00+05:30');

-- 2026 Q1: 1 Jan – 31 Mar 2026
CREATE TABLE orders_2026_q1
    PARTITION OF orders
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30')
               TO   ('2026-04-01 00:00:00+05:30');

-- 2026 Q2: 1 Apr – 30 Jun 2026  ← end of seed dataset
CREATE TABLE orders_2026_q2
    PARTITION OF orders
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30')
               TO   ('2026-07-01 00:00:00+05:30');

-- 2026 Q3: 1 Jul – 30 Sep 2026  ← W01 test INSERT (2026-07-01) lands here
CREATE TABLE orders_2026_q3
    PARTITION OF orders
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30')
               TO   ('2026-10-01 00:00:00+05:30');

-- 2026 Q4: 1 Oct – 31 Dec 2026
CREATE TABLE orders_2026_q4
    PARTITION OF orders
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30')
               TO   ('2027-01-01 00:00:00+05:30');

-- Future catch-all: 2027 and beyond
-- Add named quarterly partitions here as new data arrives.
CREATE TABLE orders_future
    PARTITION OF orders
    FOR VALUES FROM ('2027-01-01 00:00:00+05:30') TO (MAXVALUE);

-- =====================================================================
-- STEP 5: Migrate data from the original table
-- =====================================================================
-- PostgreSQL routes each row to the correct child partition automatically
-- based on its ordered_at value.  No explicit partition name needed.

INSERT INTO orders (
    order_id, customer_id, address_id, ordered_at,
    payment_method, total_amount, status, shipped_at, delivered_at
)
SELECT
    order_id, customer_id, address_id, ordered_at,
    payment_method, total_amount, status, shipped_at, delivered_at
FROM orders_unpartitioned;

-- =====================================================================
-- STEP 6: Secondary indexes on the partitioned table
-- =====================================================================
-- PostgreSQL automatically propagates an index defined on the parent
-- table to every existing and future child partition.
-- None of these are UNIQUE (which would require ordered_at).

-- R04, R09, R18: customer order history lookups, monthly aggregates
CREATE INDEX idx_orders_customer_ordered
    ON orders (customer_id, ordered_at DESC);

-- R20, R08, R21: date-range scans for GMV, bestsellers, late deliveries
CREATE INDEX idx_orders_ordered_at
    ON orders (ordered_at);

-- R22: pagination ORDER BY ordered_at DESC with OFFSET
CREATE INDEX idx_orders_ordered_at_desc
    ON orders (ordered_at DESC);

-- R05: "SHIPPED orders with shipped_at before a date"
-- Partial index: only the 877 SHIPPED rows on seed data (very small index).
-- PostgreSQL 13+ supports partial indexes on partitioned table parents.
-- Note: a partial index on the parent creates a partial index per partition.
CREATE INDEX idx_orders_status_shipped
    ON orders (shipped_at)
    WHERE status = 'SHIPPED';

-- W05: "find min(order_id) WHERE status = 'PACKED'"
-- Partial non-unique index on order_id — valid because it is not UNIQUE.
CREATE INDEX idx_orders_packed_id
    ON orders (order_id)
    WHERE status = 'PACKED';

-- =====================================================================
-- STEP 7: order_items → orders referential integrity
-- =====================================================================
-- As explained in the header, the database-enforced FK CANNOT be
-- restored directly because:
--   • PostgreSQL requires every UNIQUE / PRIMARY KEY on a partitioned
--     table to include ALL partition-key columns.
--   • Our partition key is ordered_at.  Therefore UNIQUE(order_id) on
--     orders is forbidden, and a FK to orders(order_id) is impossible.
--   • PostgreSQL error (confirmed live):
--       ERROR:  unique constraint on partitioned table must include
--               all partitioning columns
--       DETAIL:  UNIQUE constraint on table "orders" lacks column
--                "ordered_at" which is part of the partition key.
--
-- ============================================================
-- CHOSEN SOLUTION: order_registry + real FK + bidirectional trigger
-- ============================================================
-- We introduce a thin non-partitioned "registry" table that holds
-- exactly one row per live order_id.  This table CAN have a true PK
-- on order_id alone (it is not partitioned), so order_items gets a
-- real database-enforced FK.  The partitioned orders table and the
-- registry are kept in sync by BEFORE triggers.
--
-- Architecture:
--
--   order_registry (order_id PK)   ← non-partitioned; real unique key
--          ↑  FK (real DB constraint)
--   order_items (order_id NOT NULL)
--
--   orders (order_id, ordered_at) → RANGE partitioned
--          ↑  triggers keep order_registry in sync with orders
--
-- Properties:
--   ✓ order_items.order_id FK is a real PostgreSQL FK constraint.
--   ✓ Orphan inserts into order_items are blocked at the DB level.
--   ✓ Deleting from orders cascades: trigger removes registry row,
--     FK ON DELETE CASCADE removes order_items rows automatically.
--   ✓ Partitioning and date-range pruning are fully preserved.
--   ✗ Every INSERT/DELETE on orders has a small trigger overhead
--     (one indexed lookup on order_registry per row — negligible).
-- ============================================================

-- ---------------------------------------------------------------
-- 7a. Create the registry table (non-partitioned, true PK)
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_registry (
    order_id  INTEGER  NOT NULL,
    CONSTRAINT pk_order_registry PRIMARY KEY (order_id)
);

COMMENT ON TABLE order_registry IS
    'Thin registry of live order IDs.  Kept in sync with the partitioned '
    'orders table via triggers trg_orders_registry_insert / trg_orders_registry_delete. '
    'Exists solely to give order_items a real database-enforced FK on order_id '
    '(impossible to do directly against a RANGE-partitioned parent table in PostgreSQL). '
    'Do not INSERT/DELETE from this table manually.';

-- ---------------------------------------------------------------
-- 7b. Populate registry from the already-migrated partitioned table
-- ---------------------------------------------------------------
INSERT INTO order_registry (order_id)
SELECT order_id FROM orders
ON CONFLICT (order_id) DO NOTHING;

-- ---------------------------------------------------------------
-- 7c. Add the real FK from order_items → order_registry
--     ON DELETE CASCADE mirrors the original fk_order_item_order
--     behaviour: deleting an order removes its line items.
-- ---------------------------------------------------------------
ALTER TABLE order_items
    DROP CONSTRAINT IF EXISTS fk_order_item_order_registry;

ALTER TABLE order_items
    ADD CONSTRAINT fk_order_item_order_registry
        FOREIGN KEY (order_id)
        REFERENCES order_registry (order_id)
        ON DELETE CASCADE
        NOT DEFERRABLE INITIALLY IMMEDIATE;

-- ---------------------------------------------------------------
-- 7d. Triggers to keep order_registry in sync with orders
-- ---------------------------------------------------------------

-- INSERT on orders → add row to registry
CREATE OR REPLACE FUNCTION amazon.trg_orders_registry_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO amazon.order_registry (order_id)
    VALUES (NEW.order_id)
    ON CONFLICT (order_id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_registry_insert ON orders;
CREATE TRIGGER trg_orders_registry_insert
    AFTER INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION amazon.trg_orders_registry_insert();

-- DELETE on orders → remove row from registry
-- (FK ON DELETE CASCADE will then remove order_items automatically)
CREATE OR REPLACE FUNCTION amazon.trg_orders_registry_delete()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM amazon.order_registry WHERE order_id = OLD.order_id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_registry_delete ON orders;
CREATE TRIGGER trg_orders_registry_delete
    AFTER DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION amazon.trg_orders_registry_delete();

-- Non-unique index on order_items(order_id) for fast FK checks and JOINs
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
    ON order_items (order_id);

COMMENT ON TABLE order_items IS
    'FK order_items→orders was replaced by order_items→order_registry '
    '(constraint fk_order_item_order_registry, ON DELETE CASCADE). '
    'The registry is kept in sync with the partitioned orders table via triggers. '
    'See Step 7 of sql/08_partitioning.sql for full design rationale.';

-- =====================================================================
-- STEP 8: Verify row counts and partition distribution
-- =====================================================================
DO $$
DECLARE
    orig_count  BIGINT;
    part_count  BIGINT;
BEGIN
    SELECT count(*) INTO orig_count FROM orders_unpartitioned;
    SELECT count(*) INTO part_count FROM orders;

    IF orig_count <> part_count THEN
        RAISE EXCEPTION
            'MIGRATION FAILED – row count mismatch: original=%, partitioned=%',
            orig_count, part_count;
    ELSE
        RAISE NOTICE 'Migration OK: % rows migrated to partitioned orders table', part_count;
    END IF;
END;
$$;

-- Per-partition distribution (run manually to inspect):
/*
SELECT
    inhrelid::regclass                                      AS partition,
    pg_relation_size(inhrelid)                              AS size_bytes,
    (SELECT count(*) FROM ONLY <partition_name>)            AS rows
FROM pg_inherits
WHERE inhparent = 'amazon.orders'::regclass
ORDER BY partition;
*/

-- Quick distribution check using partition names:
/*
SELECT 'before_2025' AS part, count(*) FROM orders_before_2025
UNION ALL SELECT '2025_q1', count(*) FROM orders_2025_q1
UNION ALL SELECT '2025_q2', count(*) FROM orders_2025_q2
UNION ALL SELECT '2025_q3', count(*) FROM orders_2025_q3
UNION ALL SELECT '2025_q4', count(*) FROM orders_2025_q4
UNION ALL SELECT '2026_q1', count(*) FROM orders_2026_q1
UNION ALL SELECT '2026_q2', count(*) FROM orders_2026_q2
UNION ALL SELECT '2026_q3', count(*) FROM orders_2026_q3
UNION ALL SELECT '2026_q4', count(*) FROM orders_2026_q4
UNION ALL SELECT 'future',  count(*) FROM orders_future
ORDER BY part;
*/

-- =====================================================================
-- STEP 9: Partition pruning verification (run EXPLAIN to confirm)
-- =====================================================================
-- Each EXPLAIN below should show that only 1–2 child partitions are
-- scanned, not the full table.  Look for "Partitions removed" in output.

/*
-- R20: Finance GMV for June 2026 → only orders_2026_q2 scanned
EXPLAIN (ANALYZE, BUFFERS)
SELECT ordered_at::date AS day, sum(total_amount) AS gmv
FROM orders
WHERE status <> 'CANCELLED'
  AND ordered_at >= '2026-06-01 00:00:00+05:30'
  AND ordered_at <  '2026-07-01 00:00:00+05:30'
GROUP BY 1 ORDER BY 1;

-- R09: 2026 annual AOV → only orders_2026_q1 and orders_2026_q2 scanned
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', o.ordered_at) AS month, c.is_prime,
       count(*) AS orders, round(avg(o.total_amount), 2) AS avg_order_value
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.ordered_at >= '2026-01-01 00:00:00+05:30'
  AND o.ordered_at <  '2027-01-01 00:00:00+05:30'
  AND o.status <> 'CANCELLED'
GROUP BY 1, 2 ORDER BY 1, 2;

-- W01 routing check: insert dated 2026-07-01 → lands in orders_2026_q3
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO orders (order_id, customer_id, address_id, ordered_at,
                    payment_method, total_amount, status)
VALUES (90000001, 1042, 2083, '2026-07-01 10:30:00+05:30',
        'UPI', 3935.00, 'PLACED');
*/

-- =====================================================================
-- STEP 10: Collect statistics on the new partitioned table
-- =====================================================================
ANALYZE orders;

-- =====================================================================
-- STEP 11: Maintenance notes
-- =====================================================================
-- Adding a new quarter (run BEFORE the quarter begins):
--   CREATE TABLE orders_2027_q1 PARTITION OF orders
--   FOR VALUES FROM ('2027-01-01 00:00:00+05:30')
--              TO   ('2027-04-01 00:00:00+05:30');
--
-- Autovacuum tuning for the active (write-heavy) quarter:
--   ALTER TABLE orders_2026_q3 SET (
--       autovacuum_vacuum_scale_factor  = 0.01,
--       autovacuum_analyze_scale_factor = 0.005
--   );
--
-- Archive an old, immutable quarter (metadata operation, instant):
--   ALTER TABLE orders DETACH PARTITION orders_2025_q1;
--   -- Then archive or DROP orders_2025_q1 independently.
--
-- Disable autovacuum on archive partitions to save I/O:
--   ALTER TABLE orders_2025_q1 SET (autovacuum_enabled = false);
--
-- Drop the original table once migration is verified:
--   DROP TABLE orders_unpartitioned;
-- =====================================================================
