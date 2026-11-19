-- =====================================================================
-- Course: Database Management Systems (B.Tech 2nd Year)
-- Project: Uber Ride-Hailing Database System
-- File: sql/05_indexes.sql
-- Description: Secondary indexes for optimizing the 30 workload queries
--
-- HOW TO RUN (from project root):
--     psql -d uber_db -f sql/05_indexes.sql
--
-- DESIGN PRINCIPLES:
-- 1. B-Tree Indexes: Equality columns first, then range/sorting columns.
-- 2. Partial Indexes: Index only rows needed (e.g. rare status or non-nulls)
--    to keep index size small and protect INSERT/UPDATE write performance.
-- 3. Expression Indexes: Index exact functions used in WHERE (LOWER, division).
-- 4. Covering Indexes: Use INCLUDE (...) so PostgreSQL can perform Index-Only
--    Scans without visiting table heap pages.
-- 5. Trigram Indexes: GIN index for partial substring matches (ILIKE '%...%').
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO uber;

-- Enable trigram extension for substring text searches (ILIKE '%text%')
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =====================================================================
-- TABLE 1: riders (30,000 rows)
-- Primary key: riders_pkey (rider_id)
-- Unique keys: riders_email_key (email), riders_phone_key (phone)
-- =====================================================================

-- Index 1.1: Case-insensitive email search
-- Serves: R03 (Login: find a rider by email, case-insensitive)
-- Type: B-tree Expression Index
-- Why: The standard UNIQUE index on email cannot be used when the query evaluates
-- LOWER(email). This expression index precomputes and indexes lowercase emails,
-- converting a 30,000-row sequential scan into an instant 0.1 ms Index Scan.
CREATE INDEX IF NOT EXISTS idx_riders_lower_email
    ON riders (LOWER(email));

-- Index 1.2: Rider home city lookup
-- Serves: R09 (Win-back campaign in Bengaluru), R18 (CRM last trip date in Pune)
-- Type: B-tree Single-column Index
-- Why: home_city_id is a foreign key. Indexing it allows PostgreSQL to directly
-- fetch riders of a specific city (e.g. Pune riders in R18, Bengaluru riders in R09)
-- instead of performing a sequential scan across all 30,000 riders.
CREATE INDEX IF NOT EXISTS idx_riders_home_city_id
    ON riders (home_city_id);

-- Index 1.3: Trigram substring search on rider full name
-- Serves: R13 (Support: search riders by surname ILIKE '%sharma%')
-- Type: GIN (Generalized Inverted Index) Trigram Index
-- Why: Standard B-tree indexes cannot do partial matching with leading wildcards
-- ('%sharma%'). GIN trigram indexing breaks strings into 3-character slices,
-- enabling Bitmap Index Scan to find matching substrings in under 1 ms.
CREATE INDEX IF NOT EXISTS idx_riders_fullname_trgm
    ON riders USING gin (full_name gin_trgm_ops);


-- =====================================================================
-- TABLE 2: drivers (3,000 rows)
-- Primary key: drivers_pkey (driver_id)
-- Unique keys: drivers_phone_key (phone), drivers_license_no_key (license_no)
-- =====================================================================

-- Index 2.1: Driver city lookup
-- Serves: R07 (Top 10 earning drivers in Mumbai), R19 (Top 3 drivers per city)
-- Type: B-tree Foreign Key Index
-- Why: Speeds up filtering drivers by city and joining drivers with cities and trips.
CREATE INDEX IF NOT EXISTS idx_drivers_city_id
    ON drivers (city_id);

-- Index 2.2: Driver status and rating lookup
-- Serves: R10 (Active drivers check), W03 (Suspend low-rated active drivers)
-- Type: B-tree Composite Index
-- Why: Equality column (status) first, range column (driver_rating) second.
-- Allows instant filtering of active drivers with driver_rating < 3.5 for safety updates.
CREATE INDEX IF NOT EXISTS idx_drivers_status_rating
    ON drivers (status, driver_rating);


-- =====================================================================
-- TABLE 3: vehicles (3,300 rows)
-- Primary key: vehicles_pkey (vehicle_id)
-- Unique keys: vehicles_registration_no_key (registration_no)
-- =====================================================================

-- Index 3.1: Vehicle owner driver foreign key
-- Serves: R14 (Vehicle and driver by reg no), R15 (Trip receipt joins)
-- Type: B-tree Foreign Key Index
-- Why: Standard foreign key index to optimize joins and cascading integrity checks.
CREATE INDEX IF NOT EXISTS idx_vehicles_driver_id
    ON vehicles (driver_id);


-- =====================================================================
-- TABLE 4: payments (245,839 rows)
-- Primary key: payments_pkey (payment_id)
-- Unique key: payments_trip_id_key (trip_id)
-- =====================================================================

-- Index 4.1: Trip ID lookup
-- Serves: R15 (Trip receipt: join payment details for completed trip)
-- Type: B-tree Foreign Key Index
-- Why: Allows instant 1-to-1 lookup for payment details by trip_id in < 0.1 ms.
CREATE INDEX IF NOT EXISTS idx_payments_trip_id
    ON payments (trip_id);

-- Index 4.2: Successful payments by date and payment method
-- Serves: R08 (Finance: successful revenue per method per month)
-- Type: B-tree Partial Covering Index
-- Why: Only successful payments are indexed (filters out FAILED/PENDING/REFUNDED).
-- Stores paid_at for date range filtering, and includes (method, amount) so
-- PostgreSQL can compute monthly revenue via an Index-Only Scan without reading heap pages.
CREATE INDEX IF NOT EXISTS idx_payments_success_paid_at
    ON payments (paid_at) INCLUDE (method, amount)
    WHERE payment_status = 'SUCCESS';

-- Index 4.3: Recent failed payments
-- Serves: R22 (Payments team: failed payments in the last 7 days)
-- Type: B-tree Partial Composite Index
-- Why: Failed payments represent only a tiny fraction of total transactions (< 5%).
-- Filtering WHERE payment_status = 'FAILED' keeps this index tiny. Columns ordered
-- by paid_at DESC for sorting, including trip_id and amount for instant join with trips.
CREATE INDEX IF NOT EXISTS idx_payments_failed_paid_at
    ON payments (paid_at DESC, trip_id, amount)
    WHERE payment_status = 'FAILED';


-- =====================================================================
-- TABLE 5: ratings (307,214 rows)
-- Primary key: ratings_pkey (trip_id, rated_by)
-- =====================================================================

-- Index 5.1: Rider ratings lookup
-- Serves: R11 (Quality: lowest-rated drivers from rider ratings)
-- Type: B-tree Partial Index
-- Why: Primary key is (trip_id, rated_by). Filtering on rated_by = 'RIDER' cannot
-- efficiently use the primary key because rated_by is the second column. This partial
-- index stores only rider ratings and includes stars to accelerate aggregation.
CREATE INDEX IF NOT EXISTS idx_ratings_rider_trip_stars
    ON ratings (trip_id, stars)
    WHERE rated_by = 'RIDER';


-- =====================================================================
-- TABLE 6: trips (300,000 rows - largest table)
-- Primary key: trips_pkey (trip_id)
-- =====================================================================

-- Index 6.1: Rider trips ordered by request time
-- Serves: R01 (Rider's last 20 trips), R09 (Win-back inactive riders), R18 (CRM last trip date)
-- Type: B-tree Composite Index
-- Why: Equality column (rider_id) first, sorting column (requested_at DESC) second.
-- Allows finding a specific rider's trips and fetching the latest 20 trips in order
-- directly from the index in < 0.1 ms without any heap sort.
CREATE INDEX IF NOT EXISTS idx_trips_rider_requested
    ON trips (rider_id, requested_at DESC);

-- Index 6.2: Driver trips by status and request time
-- Serves: R02 (Driver March earnings), R07 (Top earning drivers), R10 (Active drivers check), R19 (Top drivers leaderboard)
-- Type: B-tree Composite Index
-- Why: Equality columns (driver_id, status) first, range column (requested_at) third.
-- Allows instant range scanning for a driver's completed trips in a date range.
CREATE INDEX IF NOT EXISTS idx_trips_driver_status_requested
    ON trips (driver_id, status, requested_at);

-- Index 6.3: City trips by request time
-- Serves: R04 (Bengaluru trips on 10 May), R12 (Delhi surge by hour), R17 (City cancellation rate), R23 (Active riders per city)
-- Type: B-tree Composite Index
-- Why: Equality column (city_id) first, range/sorting column (requested_at) second.
-- Quickly narrows down the 300,000 trips table to trips in a single city on given dates.
CREATE INDEX IF NOT EXISTS idx_trips_city_requested
    ON trips (city_id, requested_at);

-- Index 6.4: Active trips dispatch queue
-- Serves: R05 (Live dispatch screen: oldest active trips)
-- Type: B-tree Partial Index
-- Why: Active trips ('REQUESTED', 'ACCEPTED', 'ONGOING') account for less than 0.5%
-- of all trips. A partial index contains only active rows, keeping the index size
-- tiny (~50 KB) and allowing instant retrieval sorted by requested_at.
-- Write overhead note: Only new or active trips touch this index; completed trips do not.
CREATE INDEX IF NOT EXISTS idx_trips_active_status_requested
    ON trips (requested_at)
    WHERE status IN ('REQUESTED', 'ACCEPTED', 'ONGOING');

-- Index 6.5: Completed trips by request time with fare and city
-- Serves: R06 (Completed trips per city in June), R20 (Daily revenue and running total in May)
-- Type: B-tree Partial Covering Index
-- Why: Indexes completed trips by requested_at. Adding INCLUDE (fare_amount, city_id)
-- allows PostgreSQL to calculate monthly trip counts and daily running revenue entirely
-- through an Index-Only Scan without reading table heap blocks.
CREATE INDEX IF NOT EXISTS idx_trips_completed_requested
    ON trips (requested_at) INCLUDE (fare_amount, city_id)
    WHERE status = 'COMPLETED';

-- Index 6.6: Promo code usage
-- Serves: R21 (Marketing: promo code usage)
-- Type: B-tree Partial Index
-- Why: Most trips do not use promo codes (promo_code IS NULL). Filtering out NULLs
-- avoids indexing over 80% of rows, saving disk space and speeding up the promo code join.
CREATE INDEX IF NOT EXISTS idx_trips_promo_code
    ON trips (promo_code)
    WHERE promo_code IS NOT NULL;

-- Index 6.7: Unusually long trips (fraud detection)
-- Serves: R24 (Fraud check: unusually long trips)
-- Type: B-tree Partial Index
-- Why: Outlier trips (distance > 43 km OR duration > 150 min) are very rare (< 0.2%).
-- This partial index indexes only outlier trips pre-sorted by fare_amount DESC,
-- returning the top 100 instantly without scanning 300,000 rows.
CREATE INDEX IF NOT EXISTS idx_trips_outliers
    ON trips (fare_amount DESC)
    WHERE status = 'COMPLETED' AND (distance_km > 43 OR duration_min > 150);

-- Index 6.8: High fare-per-km trips (fraud detection)
-- Serves: R25 (Fraud check: completed trips charging > ₹100/km)
-- Type: B-tree Expression Partial Index
-- Why: Precomputes the mathematical expression (fare_amount / NULLIF(distance_km, 0))
-- for completed trips. Allows an Index Scan on the expression instead of calculating
-- division for every single row in the 300,000-row table.
CREATE INDEX IF NOT EXISTS idx_trips_fare_per_km
    ON trips ((fare_amount / NULLIF(distance_km, 0)) DESC)
    WHERE status = 'COMPLETED';

-- Index 6.9: Oldest ongoing trip lookup
-- Serves: W02 (Driver app: finish the oldest ongoing trip)
-- Type: B-tree Partial Index
-- Why: The subquery (SELECT min(trip_id) FROM trips WHERE status = 'ONGOING') previously
-- scanned all 300,000 trips. This partial index allows min(trip_id) to be found in
-- O(1) time (0.04 ms) via an index scan.
CREATE INDEX IF NOT EXISTS idx_trips_ongoing_min
    ON trips (trip_id)
    WHERE status = 'ONGOING';

-- Index 6.10: Cancelled trips retention purge
-- Serves: W05 (Data retention: purge cancelled trips from Jan 2025)
-- Type: B-tree Partial Index
-- Why: Only cancelled trips are indexed. Allows PostgreSQL to instantly find
-- matching records by requested_at for deletion instead of scanning 300,000 rows.
CREATE INDEX IF NOT EXISTS idx_trips_cancelled_requested
    ON trips (requested_at)
    WHERE status LIKE 'CANCELLED%';


-- =====================================================================
-- STEP 7: Refresh Statistics
-- Update query planner statistics so PostgreSQL immediately knows about
-- the new indexes and their distribution.
-- =====================================================================
ANALYZE;
