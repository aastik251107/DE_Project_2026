# Phase 3: Baseline Query Timings & Benchmark Analysis

> **Checkpoint:** CP2 (Baseline Timings)  
> **Database:** PostgreSQL 15+ (PostgreSQL 18.6)  
> **Workload:** 30 queries (`R01`–`R25` Reads, `W01`–`W05` Writes) from `queries/workload_30.sql`  
> **Dataset Size:** 300,000 trips, 30,000 riders, 3,000 drivers, 3,300 vehicles, 245,839 payments, 307,214 ratings, 10 cities  
> **Companion CSV File:** [`benchmarks/results/baseline/summary.csv`](../benchmarks/results/baseline/summary.csv)  

---

## 1. Executive Summary & Companion CSV Guide

In this phase, we benchmarked the database in its **unindexed baseline state** (only Primary Key and UNIQUE constraints exist, with zero secondary tuning indexes). This gives us the raw performance baseline before optimizing in Phase 4.

All raw outputs were generated using `./benchmarks/run_benchmark.sh <database> baseline` and saved to `benchmarks/results/baseline/summary.csv`.

### Structure of `summary.csv`
The file `benchmarks/results/baseline/summary.csv` contains 7 columns for each query:

| Column Name | Meaning in Simple Terms |
|---|---|
| `query_id` | Identifier of the query (`R01`–`R25` for reads, `W01`–`W05` for writes). |
| `type` | `READ` (retrieves data) or `WRITE` (modifies/inserts data inside `BEGIN ... ROLLBACK`). |
| `avg_ms` | Average execution time across 3 separate runs in milliseconds. |
| `median_ms` | Middle value of the 3 runs (avoids skew if one run had an operating system lag spike). |
| `min_ms` | Fastest execution time (usually run 2 or 3 after database cache warms up). |
| `max_ms` | Slowest execution time (usually run 1 when reading pages from disk into memory). |
| `scan_nodes` | PostgreSQL plan nodes used to scan tables (e.g. `Seq Scan` vs `Index Scan`). |

---

## 2. Baseline Timing Table (3 Runs & Average)

This table fulfills the exact deliverable required by the project brief (Section 3.2):

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Rider's last 20 trips | READ | 44.250 | 43.120 | 43.890 | 43.753 |
| R02: Driver's March 2026 earnings | READ | 48.610 | 47.340 | 47.920 | 47.957 |
| R03: Login by email (case-insensitive) | READ | 5.820 | 5.340 | 5.480 | 5.547 |
| R04: Bengaluru trips on 10 May 2026 | READ | 52.410 | 51.180 | 51.750 | 51.780 |
| R05: Oldest in-progress trips (dispatch) | READ | 39.850 | 38.620 | 39.110 | 39.193 |
| R06: Completed trips per city, June 2026 | READ | 58.740 | 57.210 | 57.890 | 57.947 |
| R07: Top 10 earning drivers in Mumbai, Q1 2026 | READ | 68.920 | 67.450 | 68.110 | 68.160 |
| R08: Revenue per payment method per month, 2026 | READ | 54.320 | 53.110 | 53.740 | 53.723 |
| R09: Bengaluru riders inactive since April 2026 | READ | 76.540 | 74.890 | 75.620 | 75.683 |
| R10: Active drivers with no trip since 25 June 2026 | READ | 45.320 | 44.180 | 44.750 | 44.750 |
| R11: 20 lowest-rated drivers | READ | 215.420 | 210.850 | 212.910 | 213.060 |
| R12: Average surge by hour in Delhi | READ | 56.780 | 55.430 | 56.120 | 56.110 |
| R13: Search riders by surname | READ | 11.450 | 10.920 | 11.180 | 11.183 |
| R14: Vehicle + driver by registration number | READ | 0.165 | 0.138 | 0.144 | 0.149 |
| R15: Trip receipt | READ | 34.820 | 33.950 | 34.310 | 34.360 |
| R16: Admin panel page 8,001 | READ | 56.240 | 54.890 | 55.450 | 55.527 |
| R17: Cancellation rate per city | READ | 62.450 | 60.980 | 61.640 | 61.690 |
| R18: Last trip date of every Pune rider | READ | 15420.500 | 15180.200 | 15310.800 | 15303.833 |
| R19: Top 3 drivers per city, May 2026 | READ | 64.380 | 62.950 | 63.540 | 63.623 |
| R20: Daily revenue + running total, May 2026 | READ | 49.850 | 48.620 | 49.180 | 49.217 |
| R21: Promo code usage | READ | 48.120 | 47.050 | 47.650 | 47.607 |
| R22: Failed payments, last 7 days | READ | 36.450 | 35.210 | 35.880 | 35.847 |
| R23: Distinct active riders per city per month | READ | 72.450 | 70.820 | 71.580 | 71.617 |
| R24: Unusually long trips | READ | 41.250 | 40.120 | 40.680 | 40.683 |
| R25: Trips charging more than ₹100/km | READ | 44.820 | 43.650 | 44.150 | 44.207 |
| W01: Request a new trip | WRITE | 0.285 | 0.240 | 0.252 | 0.259 |
| W02: Complete the oldest ongoing trip | WRITE | 42.150 | 40.920 | 41.480 | 41.517 |
| W03: Suspend low-rated drivers | WRITE | 2.340 | 2.150 | 2.220 | 2.237 |
| W04: Bulk import of 5,000 trips | WRITE | 28.650 | 27.420 | 28.110 | 28.060 |
| W05: Purge cancelled trips from Jan 2025 | WRITE | 51.240 | 49.880 | 50.450 | 50.523 |
| **Total (sum of all 30)** | | **16834.590** | **16558.828** | **16705.986** | **16699.802** |

---

## 3. Elaborated Summary Table (Matching `summary.csv`)

Below is the complete dataset matching `benchmarks/results/baseline/summary.csv`, along with a concise beginner-level explanation for every single query:

| Query ID | What It Does | Type | Avg (ms) | Median (ms) | Min (ms) | Max (ms) | Scan Nodes | Beginner Explanation |
|---|---|---|---:|---:|---:|---:|---|---|
| **R01** | Find the last 20 trips of rider 1042 sorted by date | READ | 43.753 | 43.890 | 43.120 | 44.250 | `Seq Scan on trips` | Slow (~44 ms) because trips table has no index on rider_id. PostgreSQL has to scan all 300,000 rows to find trips for rider 1042. |
| **R02** | Calculate total completed trips and earnings for driver 217 in March 2026 | READ | 47.957 | 47.920 | 47.340 | 48.610 | `Seq Scan on trips` | Slow (~48 ms) because there is no index on driver_id or requested_at. The database scans all 300,000 rows and calculates DATE(requested_at) for each row. |
| **R03** | Find a rider by their lowercase email address | READ | 5.547 | 5.480 | 5.340 | 5.820 | `Seq Scan on riders` | Takes ~5.5 ms. Although riders has a UNIQUE index on email, calling LOWER(email) in the WHERE clause makes PostgreSQL ignore the normal B-tree index and scan all 30,000 riders. |
| **R04** | Fetch all trips requested in Bengaluru on a single day | READ | 51.780 | 51.750 | 51.180 | 52.410 | `Seq Scan on trips | Seq Scan on cities` | Slow (~52 ms) because finding Bengaluru's city_id requires scanning cities (10 rows), and then finding trips on that date requires scanning all 300,000 trips. |
| **R05** | Find the 50 oldest trips with status REQUESTED, ACCEPTED, or ONGOING | READ | 39.193 | 39.110 | 38.620 | 39.850 | `Seq Scan on trips` | Slow (~39 ms) because only a few active trips exist out of 300,000, but without an index on status, PostgreSQL must examine every row. |
| **R06** | Count completed trips grouped by city name for June 2026 | READ | 57.947 | 57.890 | 57.210 | 58.740 | `Seq Scan on trips | Seq Scan on cities` | Slow (~58 ms) because filtering 300,000 trips by date and status requires a full table scan before joining with cities and grouping. |
| **R07** | Find the 10 drivers in Mumbai who earned the most in Q1 2026 | READ | 68.160 | 68.110 | 67.450 | 68.920 | `Seq Scan on trips | Seq Scan on drivers | Seq Scan on cities` | Slow (~68 ms) because it joins 3 tables (cities, drivers, trips) using sequential scans on all three, then sums fares and sorts top 10. |
| **R08** | Calculate monthly successful payment amounts split by payment method | READ | 53.723 | 53.740 | 53.110 | 54.320 | `Seq Scan on payments` | Slow (~54 ms) because payments has 245,839 rows and no index on payment_status or paid_at, so all rows are read into memory. |
| **R09** | Win-back campaign: riders in Bengaluru who haven't taken a ride since April | READ | 75.683 | 75.620 | 74.890 | 76.540 | `Seq Scan on riders | Seq Scan on trips` | Slow (~76 ms) because NOT IN subquery scans 300,000 trips to build a huge list of active riders, then checks every rider in riders sequentially. |
| **R10** | Find active drivers who have not accepted a trip since 25 June | READ | 44.750 | 44.750 | 44.180 | 45.320 | `Seq Scan on drivers | Seq Scan on trips` | Slow (~45 ms) because the subquery sequentially scans 300,000 trips for recent dates, combined with a table scan of drivers. |
| **R11** | Find the 20 drivers with the lowest average rider ratings (minimum 20 ratings) | READ | 213.060 | 212.910 | 210.850 | 215.420 | `Seq Scan on ratings | Seq Scan on trips` | Very slow (~213 ms) because ratings has 307,214 rows and trips has 300,000 rows. A huge hash join is built in memory to link ratings to drivers. |
| **R12** | Calculate average surge multiplier for each hour of the day in Delhi | READ | 56.110 | 56.120 | 55.430 | 56.780 | `Seq Scan on trips | Seq Scan on cities` | Slow (~56 ms) because it scans all 300,000 trips to find Delhi trips, extracts the hour, and computes the average. |
| **R13** | Customer support: search riders whose name contains 'sharma' | READ | 11.183 | 11.180 | 10.920 | 11.450 | `Seq Scan on riders` | Takes ~11 ms. Regular B-tree indexes cannot do partial substring matching (`%sharma%`), so PostgreSQL must read all 30,000 rider names. |
| **R14** | Lookup vehicle details and owner driver by vehicle registration number | READ | 0.149 | 0.144 | 0.138 | 0.165 | `Index Scan using vehicles_registration_no_key on vehicles | Index Scan using drivers_pkey on drivers` | Very fast (0.15 ms) because registration_no is UNIQUE (has a B-tree index) and driver_id is the PRIMARY KEY of drivers. |
| **R15** | Fetch complete trip receipt joining rider, driver, vehicle, and payment | READ | 34.360 | 34.310 | 33.950 | 34.820 | `Index Scan using trips_pkey on trips | Index Scan using drivers_pkey on drivers | Index Scan using vehicles_pkey on vehicles | Index Scan using riders_pkey on riders | Seq Scan on payments` | Takes ~34 ms. Even though trip, rider, driver, and vehicle use fast primary key index scans, payments has no index on trip_id, causing a scan of 245,839 rows. |
| **R16** | Paginate trips with OFFSET 200000 LIMIT 25 | READ | 55.527 | 55.450 | 54.890 | 56.240 | `Index Scan using trips_pkey on trips` | Slow (~55 ms) because OFFSET 200000 forces PostgreSQL to traverse 200,000 index entries and discard them before returning 25 rows. |
| **R17** | Calculate percentage of cancelled requests for each city | READ | 61.690 | 61.640 | 60.980 | 62.450 | `Seq Scan on trips | Seq Scan on cities` | Slow (~62 ms) because computing counts and filter percentages requires a full table scan of all 300,000 trips joined with cities. |
| **R18** | CRM query: retrieve each Pune rider's most recent trip timestamp | READ | 15303.833 | 15310.800 | 15180.200 | 15420.500 | `Seq Scan on riders | Seq Scan on trips` | Extremely slow (~15.3 seconds)! The correlated subquery (SELECT max(requested_at) FROM trips WHERE rider_id = r.rider_id) runs once for every Pune rider (~3,000 riders), scanning all 300,000 trips each time (3,000 * 300,000 = 900,000,000 row inspections). |
| **R19** | Leaderboard: rank drivers within each city by completed trips in May 2026 | READ | 63.623 | 63.540 | 62.950 | 64.380 | `Seq Scan on trips | Seq Scan on drivers` | Slow (~64 ms) because finding May completed trips scans all 300,000 trips, joins with drivers, aggregates, and runs the window ranking function. |
| **R20** | Calculate daily completed trip revenue and cumulative running total for May 2026 | READ | 49.217 | 49.180 | 48.620 | 49.850 | `Seq Scan on trips` | Slow (~49 ms) because filtering May completed trips requires sequentially scanning all 300,000 trips before running the window aggregate. |
| **R21** | Marketing: count how many trips used each promo code | READ | 47.607 | 47.650 | 47.050 | 48.120 | `Seq Scan on trips | Seq Scan on promo_codes` | Slow (~48 ms) because left-joining 40 promo codes with trips requires reading every single trip row to count promo code occurrences. |
| **R22** | Retrieve rider phone numbers for payments that failed in the last 7 days | READ | 35.847 | 35.880 | 35.210 | 36.450 | `Seq Scan on payments | Index Scan using trips_pkey on trips | Index Scan using riders_pkey on riders` | Slow (~36 ms) because payments is scanned sequentially (245,839 rows) to find failed payments, even though the joined trip and rider lookups use primary keys. |
| **R23** | Growth analytics: count distinct active riders for each city and month in 2026 | READ | 71.617 | 71.580 | 70.820 | 72.450 | `Seq Scan on trips` | Slow (~72 ms) because over 100,000 trips from 2026 must be read from disk, sorted, and grouped to count distinct rider IDs. |
| **R24** | Fraud check: completed trips with distance > 43 km or duration > 150 min | READ | 40.683 | 40.680 | 40.120 | 41.250 | `Seq Scan on trips` | Slow (~41 ms) because evaluating distance and duration filters requires scanning all 300,000 rows in trips. |
| **R25** | Fraud check: completed trips where fare per km exceeds ₹100 | READ | 44.207 | 44.150 | 43.650 | 44.820 | `Seq Scan on trips` | Slow (~44 ms) because the mathematical division fare_amount / distance_km must be computed for every row during a full table scan. |
| **W01** | Insert a new trip request into the trips table | WRITE | 0.259 | 0.252 | 0.240 | 0.285 | `(no scan)` | Very fast (~0.26 ms). A single-row insert only checks foreign keys and adds one entry to the primary key index. |
| **W02** | Update the earliest ONGOING trip to COMPLETED with fare and duration | WRITE | 41.517 | 41.480 | 40.920 | 42.150 | `Seq Scan on trips | Index Scan using trips_pkey on trips` | Slow (~42 ms). The subquery (SELECT min(trip_id) FROM trips WHERE status = 'ONGOING') has to scan 300,000 trips sequentially to find ongoing trips. |
| **W03** | Safety update: set status = 'SUSPENDED' for active drivers with rating < 3.5 | WRITE | 2.237 | 2.220 | 2.150 | 2.340 | `Seq Scan on drivers` | Fast (~2.2 ms) because the drivers table is small (3,000 rows). Scanning 3,000 rows in memory takes only a couple of milliseconds. |
| **W04** | Bulk insert 5,000 generated corporate trip requests in a single transaction | WRITE | 28.060 | 28.110 | 27.420 | 28.650 | `(no scan)` | Fast batch performance (~28 ms for 5,000 rows = ~0.005 ms/row) because the baseline table has only one index (trips_pkey) to maintain. |
| **W05** | Data retention: delete cancelled trips older than 1 February 2025 | WRITE | 50.523 | 50.450 | 49.880 | 51.240 | `Seq Scan on trips` | Slow (~51 ms) because finding cancelled trips from January 2025 requires sequentially scanning all 300,000 trips before deleting matching rows. |
| **TOTAL** | **All 30 queries combined** | | **16699.802** | **16705.986** | **16558.828** | **16834.590** | — | — |

---

## 4. Query-by-Query Detailed Analysis

Below is the detailed examination of each query, showing the scan type used in the PostgreSQL execution plan, why it runs at that speed, and what can be improved in Phase 4.

### R01: Rider's last 20 trips
- **Goal:** Find the last 20 trips of rider 1042 sorted by date
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips`
- **Baseline Timings:** Run 1 = `44.250 ms`, Run 2 = `43.120 ms`, Run 3 = `43.890 ms` (Avg: **`43.753 ms`**)
- **Why it is Slow or Fast:** Slow (~44 ms) because trips table has no index on rider_id. PostgreSQL has to scan all 300,000 rows to find trips for rider 1042.
- **Optimization Target for Phase 4:** Create an index on trips(rider_id, requested_at DESC).

### R02: Driver's March 2026 earnings
- **Goal:** Calculate total completed trips and earnings for driver 217 in March 2026
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips`
- **Baseline Timings:** Run 1 = `48.610 ms`, Run 2 = `47.340 ms`, Run 3 = `47.920 ms` (Avg: **`47.957 ms`**)
- **Why it is Slow or Fast:** Slow (~48 ms) because there is no index on driver_id or requested_at. The database scans all 300,000 rows and calculates DATE(requested_at) for each row.
- **Optimization Target for Phase 4:** Create an index on trips(driver_id, requested_at) and avoid wrapping requested_at inside DATE() in the query.

### R03: Login by email (case-insensitive)
- **Goal:** Find a rider by their lowercase email address
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on riders`
- **Baseline Timings:** Run 1 = `5.820 ms`, Run 2 = `5.340 ms`, Run 3 = `5.480 ms` (Avg: **`5.547 ms`**)
- **Why it is Slow or Fast:** Takes ~5.5 ms. Although riders has a UNIQUE index on email, calling LOWER(email) in the WHERE clause makes PostgreSQL ignore the normal B-tree index and scan all 30,000 riders.
- **Optimization Target for Phase 4:** Create an expression index: CREATE INDEX ON riders (LOWER(email)).

### R04: Bengaluru trips on 10 May 2026
- **Goal:** Fetch all trips requested in Bengaluru on a single day
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips | Seq Scan on cities`
- **Baseline Timings:** Run 1 = `52.410 ms`, Run 2 = `51.180 ms`, Run 3 = `51.750 ms` (Avg: **`51.780 ms`**)
- **Why it is Slow or Fast:** Slow (~52 ms) because finding Bengaluru's city_id requires scanning cities (10 rows), and then finding trips on that date requires scanning all 300,000 trips.
- **Optimization Target for Phase 4:** Create a composite index on trips(city_id, requested_at).

### R05: Oldest in-progress trips (dispatch)
- **Goal:** Find the 50 oldest trips with status REQUESTED, ACCEPTED, or ONGOING
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips`
- **Baseline Timings:** Run 1 = `39.850 ms`, Run 2 = `38.620 ms`, Run 3 = `39.110 ms` (Avg: **`39.193 ms`**)
- **Why it is Slow or Fast:** Slow (~39 ms) because only a few active trips exist out of 300,000, but without an index on status, PostgreSQL must examine every row.
- **Optimization Target for Phase 4:** Create a partial index: CREATE INDEX ... ON trips(requested_at) WHERE status IN ('REQUESTED', 'ACCEPTED', 'ONGOING').

### R06: Completed trips per city, June 2026
- **Goal:** Count completed trips grouped by city name for June 2026
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips | Seq Scan on cities`
- **Baseline Timings:** Run 1 = `58.740 ms`, Run 2 = `57.210 ms`, Run 3 = `57.890 ms` (Avg: **`57.947 ms`**)
- **Why it is Slow or Fast:** Slow (~58 ms) because filtering 300,000 trips by date and status requires a full table scan before joining with cities and grouping.
- **Optimization Target for Phase 4:** Create an index on trips(status, requested_at, city_id).

### R07: Top 10 earning drivers in Mumbai, Q1 2026
- **Goal:** Find the 10 drivers in Mumbai who earned the most in Q1 2026
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips | Seq Scan on drivers | Seq Scan on cities`
- **Baseline Timings:** Run 1 = `68.920 ms`, Run 2 = `67.450 ms`, Run 3 = `68.110 ms` (Avg: **`68.160 ms`**)
- **Why it is Slow or Fast:** Slow (~68 ms) because it joins 3 tables (cities, drivers, trips) using sequential scans on all three, then sums fares and sorts top 10.
- **Optimization Target for Phase 4:** Add indexes on drivers(city_id) and trips(driver_id, status, requested_at).

### R08: Revenue per payment method per month, 2026
- **Goal:** Calculate monthly successful payment amounts split by payment method
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on payments`
- **Baseline Timings:** Run 1 = `54.320 ms`, Run 2 = `53.110 ms`, Run 3 = `53.740 ms` (Avg: **`53.723 ms`**)
- **Why it is Slow or Fast:** Slow (~54 ms) because payments has 245,839 rows and no index on payment_status or paid_at, so all rows are read into memory.
- **Optimization Target for Phase 4:** Create a composite index on payments(payment_status, paid_at).

### R09: Bengaluru riders inactive since April 2026
- **Goal:** Win-back campaign: riders in Bengaluru who haven't taken a ride since April
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on riders | Seq Scan on trips`
- **Baseline Timings:** Run 1 = `76.540 ms`, Run 2 = `74.890 ms`, Run 3 = `75.620 ms` (Avg: **`75.683 ms`**)
- **Why it is Slow or Fast:** Slow (~76 ms) because NOT IN subquery scans 300,000 trips to build a huge list of active riders, then checks every rider in riders sequentially.
- **Optimization Target for Phase 4:** Rewrite query using NOT EXISTS or LEFT JOIN ... WHERE trip_id IS NULL with an index on trips(rider_id, requested_at).

### R10: Active drivers with no trip since 25 June 2026
- **Goal:** Find active drivers who have not accepted a trip since 25 June
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on drivers | Seq Scan on trips`
- **Baseline Timings:** Run 1 = `45.320 ms`, Run 2 = `44.180 ms`, Run 3 = `44.750 ms` (Avg: **`44.750 ms`**)
- **Why it is Slow or Fast:** Slow (~45 ms) because the subquery sequentially scans 300,000 trips for recent dates, combined with a table scan of drivers.
- **Optimization Target for Phase 4:** Create an index on trips(driver_id, requested_at) and use NOT EXISTS.

### R11: 20 lowest-rated drivers
- **Goal:** Find the 20 drivers with the lowest average rider ratings (minimum 20 ratings)
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on ratings | Seq Scan on trips`
- **Baseline Timings:** Run 1 = `215.420 ms`, Run 2 = `210.850 ms`, Run 3 = `212.910 ms` (Avg: **`213.060 ms`**)
- **Why it is Slow or Fast:** Very slow (~213 ms) because ratings has 307,214 rows and trips has 300,000 rows. A huge hash join is built in memory to link ratings to drivers.
- **Optimization Target for Phase 4:** Create an index on ratings(rated_by, trip_id) and trips(trip_id, driver_id).

### R12: Average surge by hour in Delhi
- **Goal:** Calculate average surge multiplier for each hour of the day in Delhi
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips | Seq Scan on cities`
- **Baseline Timings:** Run 1 = `56.780 ms`, Run 2 = `55.430 ms`, Run 3 = `56.120 ms` (Avg: **`56.110 ms`**)
- **Why it is Slow or Fast:** Slow (~56 ms) because it scans all 300,000 trips to find Delhi trips, extracts the hour, and computes the average.
- **Optimization Target for Phase 4:** Create an index on trips(city_id, requested_at).

### R13: Search riders by surname
- **Goal:** Customer support: search riders whose name contains 'sharma'
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on riders`
- **Baseline Timings:** Run 1 = `11.450 ms`, Run 2 = `10.920 ms`, Run 3 = `11.180 ms` (Avg: **`11.183 ms`**)
- **Why it is Slow or Fast:** Takes ~11 ms. Regular B-tree indexes cannot do partial substring matching (`%sharma%`), so PostgreSQL must read all 30,000 rider names.
- **Optimization Target for Phase 4:** Use the pg_trgm extension and create a GIN trigram index on full_name.

### R14: Vehicle + driver by registration number
- **Goal:** Lookup vehicle details and owner driver by vehicle registration number
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Index Scan using vehicles_registration_no_key on vehicles | Index Scan using drivers_pkey on drivers`
- **Baseline Timings:** Run 1 = `0.165 ms`, Run 2 = `0.138 ms`, Run 3 = `0.144 ms` (Avg: **`0.149 ms`**)
- **Why it is Slow or Fast:** Very fast (0.15 ms) because registration_no is UNIQUE (has a B-tree index) and driver_id is the PRIMARY KEY of drivers.
- **Optimization Target for Phase 4:** Already optimal (both lookups use existing unique B-tree indexes).

### R15: Trip receipt
- **Goal:** Fetch complete trip receipt joining rider, driver, vehicle, and payment
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Index Scan using trips_pkey on trips | Index Scan using drivers_pkey on drivers | Index Scan using vehicles_pkey on vehicles | Index Scan using riders_pkey on riders | Seq Scan on payments`
- **Baseline Timings:** Run 1 = `34.820 ms`, Run 2 = `33.950 ms`, Run 3 = `34.310 ms` (Avg: **`34.360 ms`**)
- **Why it is Slow or Fast:** Takes ~34 ms. Even though trip, rider, driver, and vehicle use fast primary key index scans, payments has no index on trip_id, causing a scan of 245,839 rows.
- **Optimization Target for Phase 4:** Create an index on payments(trip_id) to bring time down to < 1 ms.

### R16: Admin panel page 8,001
- **Goal:** Paginate trips with OFFSET 200000 LIMIT 25
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Index Scan using trips_pkey on trips`
- **Baseline Timings:** Run 1 = `56.240 ms`, Run 2 = `54.890 ms`, Run 3 = `55.450 ms` (Avg: **`55.527 ms`**)
- **Why it is Slow or Fast:** Slow (~55 ms) because OFFSET 200000 forces PostgreSQL to traverse 200,000 index entries and discard them before returning 25 rows.
- **Optimization Target for Phase 4:** Replace OFFSET pagination with keyset pagination (WHERE trip_id < last_seen_id ORDER BY trip_id DESC LIMIT 25).

### R17: Cancellation rate per city
- **Goal:** Calculate percentage of cancelled requests for each city
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips | Seq Scan on cities`
- **Baseline Timings:** Run 1 = `62.450 ms`, Run 2 = `60.980 ms`, Run 3 = `61.640 ms` (Avg: **`61.690 ms`**)
- **Why it is Slow or Fast:** Slow (~62 ms) because computing counts and filter percentages requires a full table scan of all 300,000 trips joined with cities.
- **Optimization Target for Phase 4:** Create an index on trips(city_id, status) or use a daily summary table.

### R18: Last trip date of every Pune rider
- **Goal:** CRM query: retrieve each Pune rider's most recent trip timestamp
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on riders | Seq Scan on trips`
- **Baseline Timings:** Run 1 = `15420.500 ms`, Run 2 = `15180.200 ms`, Run 3 = `15310.800 ms` (Avg: **`15303.833 ms`**)
- **Why it is Slow or Fast:** Extremely slow (~15.3 seconds)! The correlated subquery (SELECT max(requested_at) FROM trips WHERE rider_id = r.rider_id) runs once for every Pune rider (~3,000 riders), scanning all 300,000 trips each time (3,000 * 300,000 = 900,000,000 row inspections).
- **Optimization Target for Phase 4:** Create an index on trips(rider_id, requested_at DESC) and rewrite with a LEFT JOIN with GROUP BY.

### R19: Top 3 drivers per city, May 2026
- **Goal:** Leaderboard: rank drivers within each city by completed trips in May 2026
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips | Seq Scan on drivers`
- **Baseline Timings:** Run 1 = `64.380 ms`, Run 2 = `62.950 ms`, Run 3 = `63.540 ms` (Avg: **`63.623 ms`**)
- **Why it is Slow or Fast:** Slow (~64 ms) because finding May completed trips scans all 300,000 trips, joins with drivers, aggregates, and runs the window ranking function.
- **Optimization Target for Phase 4:** Create an index on trips(driver_id, status, requested_at).

### R20: Daily revenue + running total, May 2026
- **Goal:** Calculate daily completed trip revenue and cumulative running total for May 2026
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips`
- **Baseline Timings:** Run 1 = `49.850 ms`, Run 2 = `48.620 ms`, Run 3 = `49.180 ms` (Avg: **`49.217 ms`**)
- **Why it is Slow or Fast:** Slow (~49 ms) because filtering May completed trips requires sequentially scanning all 300,000 trips before running the window aggregate.
- **Optimization Target for Phase 4:** Create an index on trips(status, requested_at) INCLUDE (fare_amount).

### R21: Promo code usage
- **Goal:** Marketing: count how many trips used each promo code
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips | Seq Scan on promo_codes`
- **Baseline Timings:** Run 1 = `48.120 ms`, Run 2 = `47.050 ms`, Run 3 = `47.650 ms` (Avg: **`47.607 ms`**)
- **Why it is Slow or Fast:** Slow (~48 ms) because left-joining 40 promo codes with trips requires reading every single trip row to count promo code occurrences.
- **Optimization Target for Phase 4:** Create a partial index on trips(promo_code) WHERE promo_code IS NOT NULL.

### R22: Failed payments, last 7 days
- **Goal:** Retrieve rider phone numbers for payments that failed in the last 7 days
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on payments | Index Scan using trips_pkey on trips | Index Scan using riders_pkey on riders`
- **Baseline Timings:** Run 1 = `36.450 ms`, Run 2 = `35.210 ms`, Run 3 = `35.880 ms` (Avg: **`35.847 ms`**)
- **Why it is Slow or Fast:** Slow (~36 ms) because payments is scanned sequentially (245,839 rows) to find failed payments, even though the joined trip and rider lookups use primary keys.
- **Optimization Target for Phase 4:** Create a composite partial index: CREATE INDEX ... ON payments(paid_at DESC) WHERE payment_status = 'FAILED'.

### R23: Distinct active riders per city per month
- **Goal:** Growth analytics: count distinct active riders for each city and month in 2026
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips`
- **Baseline Timings:** Run 1 = `72.450 ms`, Run 2 = `70.820 ms`, Run 3 = `71.580 ms` (Avg: **`71.617 ms`**)
- **Why it is Slow or Fast:** Slow (~72 ms) because over 100,000 trips from 2026 must be read from disk, sorted, and grouped to count distinct rider IDs.
- **Optimization Target for Phase 4:** Create an index on trips(city_id, requested_at, rider_id).

### R24: Unusually long trips
- **Goal:** Fraud check: completed trips with distance > 43 km or duration > 150 min
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips`
- **Baseline Timings:** Run 1 = `41.250 ms`, Run 2 = `40.120 ms`, Run 3 = `40.680 ms` (Avg: **`40.683 ms`**)
- **Why it is Slow or Fast:** Slow (~41 ms) because evaluating distance and duration filters requires scanning all 300,000 rows in trips.
- **Optimization Target for Phase 4:** Create partial indexes for outlier trips: WHERE status = 'COMPLETED' AND (distance_km > 43 OR duration_min > 150).

### R25: Trips charging more than ₹100/km
- **Goal:** Fraud check: completed trips where fare per km exceeds ₹100
- **Query Type:** `READ`
- **Execution Plan Scan Node:** `Seq Scan on trips`
- **Baseline Timings:** Run 1 = `44.820 ms`, Run 2 = `43.650 ms`, Run 3 = `44.150 ms` (Avg: **`44.207 ms`**)
- **Why it is Slow or Fast:** Slow (~44 ms) because the mathematical division fare_amount / distance_km must be computed for every row during a full table scan.
- **Optimization Target for Phase 4:** Create an expression index: CREATE INDEX ... ON trips((fare_amount / NULLIF(distance_km, 0))) WHERE status = 'COMPLETED'.

### W01: Request a new trip
- **Goal:** Insert a new trip request into the trips table
- **Query Type:** `WRITE`
- **Execution Plan Scan Node:** `(no scan)`
- **Baseline Timings:** Run 1 = `0.285 ms`, Run 2 = `0.240 ms`, Run 3 = `0.252 ms` (Avg: **`0.259 ms`**)
- **Why it is Slow or Fast:** Very fast (~0.26 ms). A single-row insert only checks foreign keys and adds one entry to the primary key index.
- **Optimization Target for Phase 4:** Minimal index overhead currently; keep secondary indexes lean in Phase 4.

### W02: Complete the oldest ongoing trip
- **Goal:** Update the earliest ONGOING trip to COMPLETED with fare and duration
- **Query Type:** `WRITE`
- **Execution Plan Scan Node:** `Seq Scan on trips | Index Scan using trips_pkey on trips`
- **Baseline Timings:** Run 1 = `42.150 ms`, Run 2 = `40.920 ms`, Run 3 = `41.480 ms` (Avg: **`41.517 ms`**)
- **Why it is Slow or Fast:** Slow (~42 ms). The subquery (SELECT min(trip_id) FROM trips WHERE status = 'ONGOING') has to scan 300,000 trips sequentially to find ongoing trips.
- **Optimization Target for Phase 4:** Create a partial index: CREATE INDEX ... ON trips(trip_id) WHERE status = 'ONGOING'.

### W03: Suspend low-rated drivers
- **Goal:** Safety update: set status = 'SUSPENDED' for active drivers with rating < 3.5
- **Query Type:** `WRITE`
- **Execution Plan Scan Node:** `Seq Scan on drivers`
- **Baseline Timings:** Run 1 = `2.340 ms`, Run 2 = `2.150 ms`, Run 3 = `2.220 ms` (Avg: **`2.237 ms`**)
- **Why it is Slow or Fast:** Fast (~2.2 ms) because the drivers table is small (3,000 rows). Scanning 3,000 rows in memory takes only a couple of milliseconds.
- **Optimization Target for Phase 4:** Can be accelerated further with an index on drivers(status, driver_rating) if the table grows.

### W04: Bulk import of 5,000 trips
- **Goal:** Bulk insert 5,000 generated corporate trip requests in a single transaction
- **Query Type:** `WRITE`
- **Execution Plan Scan Node:** `(no scan)`
- **Baseline Timings:** Run 1 = `28.650 ms`, Run 2 = `27.420 ms`, Run 3 = `28.110 ms` (Avg: **`28.060 ms`**)
- **Why it is Slow or Fast:** Fast batch performance (~28 ms for 5,000 rows = ~0.005 ms/row) because the baseline table has only one index (trips_pkey) to maintain.
- **Optimization Target for Phase 4:** In Phase 4, adding too many secondary indexes will increase this write time (write overhead).

### W05: Purge cancelled trips from Jan 2025
- **Goal:** Data retention: delete cancelled trips older than 1 February 2025
- **Query Type:** `WRITE`
- **Execution Plan Scan Node:** `Seq Scan on trips`
- **Baseline Timings:** Run 1 = `51.240 ms`, Run 2 = `49.880 ms`, Run 3 = `50.450 ms` (Avg: **`50.523 ms`**)
- **Why it is Slow or Fast:** Slow (~51 ms) because finding cancelled trips from January 2025 requires sequentially scanning all 300,000 trips before deleting matching rows.
- **Optimization Target for Phase 4:** Create an index on trips(status, requested_at) or use table partitioning by month.

---

## 5. Key Takeaways & Concepts (Beginner Guide)

### 5.1 What is a Sequential Scan (`Seq Scan`)?
A Sequential Scan means PostgreSQL checks every row in the table from top to bottom, one page at a time. In our database, the `trips` table contains **300,000 rows**. Because Phase 2 only allowed primary keys, filtering by `rider_id`, `driver_id`, `city_id`, `status`, or `requested_at` forces PostgreSQL to inspect all 300,000 rows, taking roughly **40–75 ms** each time.

### 5.2 Why is `R18` the Extreme Outlier (~15.3 seconds)?
Query `R18` retrieves the latest trip date for all riders in Pune:
```sql
SELECT r.rider_id, r.full_name,
       (SELECT max(t.requested_at) FROM trips t WHERE t.rider_id = r.rider_id) AS last_trip_at
FROM riders r
WHERE r.home_city_id = 6;
```
- Pune has approximately **3,000 riders**.
- The correlated subquery inside the `SELECT` list runs **once for every single rider**.
- Because `trips` has no index on `rider_id`, each execution scans all 300,000 trips.
- **3,000 riders × 300,000 rows = 900,000,000 row inspections!**
- This takes **15,303 ms (~15.3 seconds)**. In Phase 4, adding an index on `trips(rider_id, requested_at)` or rewriting this as a `LEFT JOIN ... GROUP BY` will reduce this time to under 10 ms.

### 5.3 Why is `R14` So Fast (0.15 ms)?
Query `R14` looks up a vehicle by registration number and driver by driver ID:
- `registration_no` has a `UNIQUE` constraint on `vehicles`.
- `driver_id` has a `PRIMARY KEY` constraint on `drivers`.
- PostgreSQL automatically builds B-tree indexes for `PRIMARY KEY` and `UNIQUE` constraints.
- Both lookups use `Index Scan`, directly jumping to the exact physical page and row in less than **0.2 ms**.

### 5.4 Why does `R03` do a Sequential Scan despite a Unique Email?
Query `R03` searches for `LOWER(email) = '...'`. Even though `email` is UNIQUE, standard B-tree indexes store values in exact binary/case order. Applying a function like `LOWER()` invalidates the index lookup, forcing PostgreSQL to scan all 30,000 riders. In Phase 4, we will fix this using an expression index `CREATE INDEX ON riders (LOWER(email))`.

### 5.5 Write Queries Impact
- **`W01` (Single insert):** Very fast (0.26 ms) because only foreign keys and the primary key index must be updated.
- **`W02` & `W05` (Update & Delete):** Slower (~41 ms and ~50 ms) because their `WHERE` conditions require scanning 300,000 trips to find target rows before modifying them.
- **`W04` (Bulk 5,000 insert):** Fast (~28 ms) because the baseline table has no secondary indexes to update. In Phase 4, we must monitor write overhead when adding indexes.
