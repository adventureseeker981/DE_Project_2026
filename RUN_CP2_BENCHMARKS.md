# CP2 - Baseline Benchmarks Instructions

## Step 1: Start PostgreSQL

Open **Postgres.app** from Applications (ya menubar se start karo)

Verify it's running:
```bash
pg_isready
# Should show: /tmp:5432 - accepting connections
```

## Step 2: Verify Database

```bash
cd /Users/preetkalra/DE_Project_2026-1
psql amazon_db -c "SET search_path TO amazon; SELECT count(*) FROM orders;"
# Should show: 120000
```

## Step 3: Run Baseline Benchmarks

```bash
./benchmarks/run_benchmark.sh amazon_db baseline
```

This will:
- Run all 30 queries (R01-R24, W01-W06)
- Each query runs 3 times
- Calculates average, median, min, max execution times
- Saves raw EXPLAIN plans to `benchmarks/results/baseline/`
- Creates summary CSV at `benchmarks/results/baseline/summary.csv`

**Expected time:** 5-10 minutes (some queries are intentionally slow)

## Step 4: Check Results

```bash
# View summary
cat benchmarks/results/baseline/summary.csv | column -t -s,

# View individual query plans
ls benchmarks/results/baseline/
# Should show: R01.txt, R02.txt, ... W06.txt, summary.csv
```

## Step 5: Create Baseline Timings Document

Once benchmarks complete, run:
```bash
# I'll create docs/03_baseline_timings.md automatically from the results
```

## Troubleshooting

**If PostgreSQL won't start:**
1. Open Postgres.app manually
2. Click on database icon in menubar
3. Select "Start" if not running

**If database not found:**
```bash
# Recreate database
dropdb amazon_db 2>/dev/null
createdb amazon_db
psql amazon_db -f sql/01_schema.sql
psql amazon_db -f sql/02_load_data.sql
```

**If queries fail:**
- Check search_path is set to `amazon`
- Verify all 30 queries in `queries/workload_30.sql` exist
- Check for typos in table/column names

---

**Next:** After benchmarks complete, I'll create `docs/03_baseline_timings.md` with the analysis!
