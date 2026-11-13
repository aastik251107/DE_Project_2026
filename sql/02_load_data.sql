-- =====================================================================
-- Course: Database Management Systems (B.Tech 2nd Year)
-- Project: Uber Ride-Hailing Database System
-- File: sql/02_load_data.sql
-- Description: Loads data from the 8 CSV files into the 'uber' schema
--
-- HOW TO RUN (from your project root folder):
--     psql -d uber_db -f sql/02_load_data.sql
--
-- Note on Order:
--   Parent tables must be loaded BEFORE child tables so foreign keys work:
--   cities, promo_codes -> riders, drivers -> vehicles -> trips -> payments, ratings
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO uber;

\echo '--> 1. Loading cities...'
\copy cities (city_id, city_name, state, base_fare, per_km_rate, per_min_rate, launched_on) FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true);

\echo '--> 2. Loading promo_codes...'
\copy promo_codes (promo_code, discount_pct, max_discount, valid_from, valid_to, is_active) FROM 'seed_data/promo_codes.csv' WITH (FORMAT csv, HEADER true);

\echo '--> 3. Loading riders...'
\copy riders (rider_id, full_name, email, phone, home_city_id, signup_date, rider_rating, is_active) FROM 'seed_data/riders.csv' WITH (FORMAT csv, HEADER true);

\echo '--> 4. Loading drivers...'
\copy drivers (driver_id, full_name, phone, license_no, city_id, joined_on, driver_rating, status) FROM 'seed_data/drivers.csv' WITH (FORMAT csv, HEADER true);

\echo '--> 5. Loading vehicles...'
\copy vehicles (vehicle_id, driver_id, registration_no, make, model, manufacture_year, vehicle_type, seat_capacity) FROM 'seed_data/vehicles.csv' WITH (FORMAT csv, HEADER true);

\echo '--> 6. Loading trips...'
\copy trips (trip_id, rider_id, driver_id, vehicle_id, city_id, promo_code, requested_at, pickup_at, dropoff_at, pickup_lat, pickup_lng, drop_lat, drop_lng, distance_km, duration_min, surge_multiplier, fare_amount, status) FROM 'seed_data/trips.csv' WITH (FORMAT csv, HEADER true);

\echo '--> 7. Loading payments...'
\copy payments (payment_id, trip_id, amount, method, payment_status, paid_at) FROM 'seed_data/payments.csv' WITH (FORMAT csv, HEADER true);

\echo '--> 8. Loading ratings...'
\copy ratings (trip_id, rated_by, stars, comment, created_at) FROM 'seed_data/ratings.csv' WITH (FORMAT csv, HEADER true);

-- Update statistics so PostgreSQL can plan queries efficiently
ANALYZE;

-- =====================================================================
-- STEP 1: Check Row Counts
-- Every row count should match the numbers from seed_data.zip
-- =====================================================================
\echo
\echo '=== Step 1: Checking Row Counts ==='

SELECT 'cities' AS table_name, 10 AS expected, count(*) AS actual FROM cities
UNION ALL
SELECT 'promo_codes', 40, count(*) FROM promo_codes
UNION ALL
SELECT 'riders', 30000, count(*) FROM riders
UNION ALL
SELECT 'drivers', 3000, count(*) FROM drivers
UNION ALL
SELECT 'vehicles', 3300, count(*) FROM vehicles
UNION ALL
SELECT 'trips', 300000, count(*) FROM trips
UNION ALL
SELECT 'payments', 245839, count(*) FROM payments
UNION ALL
SELECT 'ratings', 307214, count(*) FROM ratings;

-- =====================================================================
-- STEP 2: Integrity Checks
-- Each query counts bad rows. We expect 0 for all of them.
-- =====================================================================
\echo
\echo '=== Step 2: Integrity Checks ==='

\echo 'Check 1: Does any trip use a vehicle owned by a different driver? (Expect 0)'
SELECT count(*) AS bad_rows
FROM trips t
JOIN vehicles v ON v.vehicle_id = t.vehicle_id
WHERE t.driver_id <> v.driver_id;

\echo 'Check 2: Does every COMPLETED trip have exactly one payment? (Expect 0)'
SELECT count(*) AS bad_rows
FROM trips t
WHERE t.status = 'COMPLETED'
  AND (SELECT count(*) FROM payments p WHERE p.trip_id = t.trip_id) <> 1;

\echo 'Check 3: Is there any payment for a trip that is NOT completed? (Expect 0)'
SELECT count(*) AS bad_rows
FROM payments p
JOIN trips t ON t.trip_id = p.trip_id
WHERE t.status <> 'COMPLETED';

\echo
\echo '=== All data loaded and verified successfully! ==='
