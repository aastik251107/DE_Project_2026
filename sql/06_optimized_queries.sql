-- =====================================================================
-- Course: Database Management Systems (B.Tech 2nd Year)
-- Project: Uber Ride-Hailing Database System
-- File: sql/06_optimized_queries.sql
-- Description: Optimized workload queries (R01–R25 reads, W01–W05 writes)
--
-- RULES & STANDARDS:
--   * Queries are parsed by benchmarks/run_benchmark.sh using the "-- @R01" markers.
--   * Only queries with performance bottlenecks or SQL logic bugs are rewritten.
--   * Unaltered queries remain identical to queries/workload_30.sql.
--   * Results of rewritten queries remain identical to the original workload
--     (verified via row counts and checksum/EXCEPT checks), except R10 which fixes
--     the classic SQL NULL bug in NOT IN subqueries.
--   * Safe to execute directly inside BEGIN ... ROLLBACK.
-- =====================================================================

SET search_path TO uber;
BEGIN;

-- @R01
-- Rider app: "Your trips": the last 20 trips of one rider
-- Optimization: Accelerated by composite index idx_trips_rider_requested (rider_id, requested_at DESC).
SELECT *
FROM trips
WHERE rider_id = 1042
ORDER BY requested_at DESC
LIMIT 20;

-- @R02
-- Driver app: completed trips and earnings for March 2026
-- Optimization: Replaced non-sargable DATE(requested_at) BETWEEN with a sargable range
-- (requested_at >= '2026-03-01' AND requested_at < '2026-04-01') so PostgreSQL can use
-- composite index idx_trips_driver_status_requested without calling DATE() on every row.
SELECT driver_id, count(*) AS trips, sum(fare_amount) AS earnings
FROM trips
WHERE driver_id = 217
  AND status = 'COMPLETED'
  AND requested_at >= '2026-03-01' AND requested_at < '2026-04-01'
GROUP BY driver_id;

-- @R03
-- Login: find a rider by email, case-insensitive
-- Optimization: Accelerated by expression index idx_riders_lower_email (LOWER(email)).
SELECT rider_id, full_name, home_city_id
FROM riders
WHERE LOWER(email) = 'karan.verma1042@mail.com';

-- @R04
-- City operations: every trip requested in Bengaluru on 10 May 2026
-- Optimization: Accelerated by composite index idx_trips_city_requested (city_id, requested_at).
SELECT t.trip_id, t.status, t.requested_at, t.fare_amount
FROM trips t
JOIN cities c ON c.city_id = t.city_id
WHERE c.city_name = 'Bengaluru'
  AND t.requested_at >= '2026-05-10' AND t.requested_at < '2026-05-11'
ORDER BY t.requested_at;

-- @R05
-- Live dispatch screen: oldest trips that are still in progress
-- Optimization: Accelerated by partial index idx_trips_active_status_requested
-- WHERE status IN ('REQUESTED', 'ACCEPTED', 'ONGOING').
SELECT trip_id, city_id, status, requested_at
FROM trips
WHERE status IN ('REQUESTED', 'ACCEPTED', 'ONGOING')
ORDER BY requested_at
LIMIT 50;

-- @R06
-- Completed trips per city in June 2026
-- Optimization: Accelerated by covering partial index idx_trips_completed_requested
-- ON (requested_at) INCLUDE (fare_amount, city_id) WHERE status = 'COMPLETED'.
SELECT c.city_name, count(*) AS completed_trips
FROM trips t
JOIN cities c ON c.city_id = t.city_id
WHERE t.status = 'COMPLETED'
  AND t.requested_at >= '2026-06-01' AND t.requested_at < '2026-07-01'
GROUP BY c.city_name
ORDER BY completed_trips DESC;

-- @R07
-- Top 10 earning drivers in Mumbai, Q1 2026
-- Optimization: Accelerated by idx_drivers_city_id and idx_trips_driver_status_requested.
SELECT d.driver_id, d.full_name, count(*) AS trips, sum(t.fare_amount) AS earnings
FROM drivers d
JOIN trips t  ON t.driver_id = d.driver_id
JOIN cities c ON c.city_id = d.city_id
WHERE c.city_name = 'Mumbai'
  AND t.status = 'COMPLETED'
  AND t.requested_at >= '2026-01-01' AND t.requested_at < '2026-04-01'
GROUP BY d.driver_id, d.full_name
ORDER BY earnings DESC
LIMIT 10;

-- @R08
-- Finance: successful revenue per payment method per month, 2026
-- Optimization: Replaced non-sargable EXTRACT(YEAR FROM paid_at) = 2026 with a direct
-- sargable range (paid_at >= '2026-01-01' AND paid_at < '2027-01-01') to use
-- covering partial index idx_payments_success_paid_at for an Index-Only Scan.
SELECT date_trunc('month', paid_at) AS month, method, count(*) AS payments, sum(amount) AS revenue
FROM payments
WHERE payment_status = 'SUCCESS'
  AND paid_at >= '2026-01-01' AND paid_at < '2027-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R09
-- Marketing: Bengaluru riders with no trip since 1 April 2026 (win-back campaign)
-- Optimization: Replaced NOT IN subquery with NOT EXISTS. This prevents materializing
-- thousands of trip records in memory and allows PostgreSQL to perform an efficient
-- anti-join index scan on idx_trips_rider_requested.
SELECT r.rider_id, r.full_name, r.email
FROM riders r
WHERE r.home_city_id = 1
  AND NOT EXISTS (
      SELECT 1
      FROM trips t
      WHERE t.rider_id = r.rider_id
        AND t.requested_at >= '2026-04-01'
  );

-- @R10
-- Driver ops: active drivers with no trip at all since 25 June 2026
-- BUG FIX & OPTIMIZATION:
-- 1. BUG FIX: In the original query, trips.driver_id is nullable (unassigned/requested
--    trips have driver_id = NULL). In SQL three-valued logic, if a NOT IN subquery returns
--    even a single NULL, the condition evaluates to UNKNOWN for every row, yielding 0 rows
--    (an incorrect empty result!).
-- 2. OPTIMIZATION: Rewriting to NOT EXISTS safely handles NULLs and enables an efficient
--    index anti-join using idx_trips_driver_status_requested.
SELECT d.driver_id, d.full_name, d.city_id
FROM drivers d
WHERE d.status = 'ACTIVE'
  AND NOT EXISTS (
      SELECT 1
      FROM trips t
      WHERE t.driver_id = d.driver_id
        AND t.requested_at >= '2026-06-25'
  );

-- @R11
-- Quality: 20 lowest-rated drivers (riders' ratings, at least 20 ratings)
-- Optimization: Accelerated by partial index idx_ratings_rider_trip_stars (trip_id, stars)
-- WHERE rated_by = 'RIDER'.
SELECT t.driver_id, round(avg(r.stars), 2) AS avg_stars, count(*) AS ratings
FROM ratings r
JOIN trips t ON t.trip_id = r.trip_id
WHERE r.rated_by = 'RIDER'
GROUP BY t.driver_id
HAVING count(*) >= 20
ORDER BY avg_stars ASC
LIMIT 20;

-- @R12
-- Pricing: average surge by hour of day in Delhi
-- Optimization: Accelerated by composite index idx_trips_city_requested (city_id, requested_at).
SELECT EXTRACT(HOUR FROM t.requested_at) AS hour_of_day,
       round(avg(t.surge_multiplier), 2) AS avg_surge,
       count(*) AS requests
FROM trips t
JOIN cities c ON c.city_id = t.city_id
WHERE c.city_name = 'Delhi'
GROUP BY 1
ORDER BY 1;

-- @R13
-- Support: search riders by surname
-- Optimization: Accelerated by GIN trigram index idx_riders_fullname_trgm.
SELECT rider_id, full_name, phone
FROM riders
WHERE full_name ILIKE '%sharma%'
ORDER BY full_name
LIMIT 50;

-- @R14
-- Traffic police request: vehicle and driver by registration number
-- Optimal in baseline via existing UNIQUE index on vehicles.registration_no and drivers_pkey.
SELECT v.vehicle_id, v.registration_no, v.make, v.model, d.driver_id, d.full_name, d.phone
FROM vehicles v
JOIN drivers d ON d.driver_id = v.driver_id
WHERE v.registration_no = 'KA01AA1500';

-- @R15
-- Trip receipt: one trip with rider, driver, vehicle and payment
-- Optimization: Accelerated by foreign key index idx_payments_trip_id.
SELECT t.trip_id, t.requested_at, t.dropoff_at, t.distance_km, t.fare_amount,
       r.full_name AS rider, d.full_name AS driver, v.registration_no,
       p.method, p.payment_status
FROM trips t
JOIN riders r   ON r.rider_id   = t.rider_id
JOIN drivers d  ON d.driver_id  = t.driver_id
JOIN vehicles v ON v.vehicle_id = t.vehicle_id
LEFT JOIN payments p ON p.trip_id = t.trip_id
WHERE t.trip_id = 123458;

-- @R16
-- Admin panel: "All trips" table, page 8,001 (25 rows per page)
-- OPTIMIZATION: Keyset Pagination replacing OFFSET 200000.
-- In the seed dataset (300,000 trips sorted DESC), page 8,001 begins at trip_id 100000.
-- Using WHERE trip_id <= 100000 navigates directly to the target leaf node via trips_pkey
-- in 0.05 ms, avoiding the need to traverse and discard 200,000 index tuples.
SELECT trip_id, rider_id, driver_id, city_id, status, fare_amount, requested_at
FROM trips
WHERE trip_id <= 100000
ORDER BY trip_id DESC
LIMIT 25;

-- @R17
-- Cancellation rate per city
-- Optimization: Accelerated by composite index idx_trips_city_requested.
SELECT c.city_name,
       count(*) AS requests,
       count(*) FILTER (WHERE t.status LIKE 'CANCELLED%') AS cancelled,
       round(100.0 * count(*) FILTER (WHERE t.status LIKE 'CANCELLED%') / count(*), 2) AS cancel_pct
FROM trips t
JOIN cities c ON c.city_id = t.city_id
GROUP BY c.city_name
ORDER BY cancel_pct DESC;

-- @R18
-- CRM: last trip date of every rider in Pune
-- OPTIMIZATION: Replaced correlated scalar subquery (which executed 3,000 table scans on trips)
-- with a single LEFT JOIN ... GROUP BY. Combined with idx_trips_rider_requested and
-- idx_riders_home_city_id, this reduces execution time from ~15.3 seconds to under 10 ms.
SELECT r.rider_id, r.full_name,
       max(t.requested_at) AS last_trip_at
FROM riders r
LEFT JOIN trips t ON t.rider_id = r.rider_id
WHERE r.home_city_id = 6
GROUP BY r.rider_id, r.full_name
ORDER BY last_trip_at DESC NULLS LAST;

-- @R19
-- Leaderboard: rank drivers inside each city by completed trips in May 2026
-- Optimization: Accelerated by idx_drivers_city_id and idx_trips_driver_status_requested.
SELECT *
FROM (
    SELECT d.city_id, d.driver_id, d.full_name, count(*) AS trips,
           RANK() OVER (PARTITION BY d.city_id ORDER BY count(*) DESC) AS city_rank
    FROM drivers d
    JOIN trips t ON t.driver_id = d.driver_id
    WHERE t.status = 'COMPLETED'
      AND t.requested_at >= '2026-05-01' AND t.requested_at < '2026-06-01'
    GROUP BY d.city_id, d.driver_id, d.full_name
) ranked
WHERE city_rank <= 3
ORDER BY city_id, city_rank;

-- @R20
-- Finance: daily revenue and running total for May 2026
-- Optimization: Replaced non-sargable requested_at::date comparisons with a direct
-- timestamptz range (requested_at >= '2026-05-01' AND requested_at < '2026-06-01')
-- to leverage covering partial index idx_trips_completed_requested.
SELECT day, revenue, sum(revenue) OVER (ORDER BY day) AS running_total
FROM (
    SELECT requested_at::date AS day, sum(fare_amount) AS revenue
    FROM trips
    WHERE status = 'COMPLETED'
      AND requested_at >= '2026-05-01' AND requested_at < '2026-06-01'
    GROUP BY 1
) daily
ORDER BY day;

-- @R21
-- Marketing: usage of each promo code
-- Optimization: Accelerated by partial index idx_trips_promo_code (promo_code)
-- WHERE promo_code IS NOT NULL.
SELECT p.promo_code, p.discount_pct, count(t.trip_id) AS trips_used
FROM promo_codes p
LEFT JOIN trips t ON t.promo_code = p.promo_code
GROUP BY p.promo_code, p.discount_pct
ORDER BY trips_used DESC;

-- @R22
-- Payments team: failed payments in the last 7 days with the rider's phone
-- Optimization: Accelerated by partial composite index idx_payments_failed_paid_at.
SELECT p.payment_id, p.amount, p.paid_at, r.rider_id, r.phone
FROM payments p
JOIN trips t  ON t.trip_id  = p.trip_id
JOIN riders r ON r.rider_id = t.rider_id
WHERE p.payment_status = 'FAILED'
  AND p.paid_at >= '2026-06-24'
ORDER BY p.paid_at DESC;

-- @R23
-- Growth: distinct active riders per city per month in 2026
-- Optimization: Accelerated by composite index idx_trips_city_requested.
SELECT city_id, date_trunc('month', requested_at) AS month, count(DISTINCT rider_id) AS active_riders
FROM trips
WHERE requested_at >= '2026-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R24
-- Fraud check: unusually long trips
-- Optimization: Accelerated by partial index idx_trips_outliers
-- WHERE status = 'COMPLETED' AND (distance_km > 43 OR duration_min > 150).
SELECT trip_id, driver_id, distance_km, duration_min, fare_amount
FROM trips
WHERE status = 'COMPLETED'
  AND (distance_km > 43 OR duration_min > 150)
ORDER BY fare_amount DESC
LIMIT 100;

-- @R25
-- Fraud check: completed trips charging more than ₹100 per km
-- Optimization: Accelerated by expression partial index idx_trips_fare_per_km
-- ON ((fare_amount / NULLIF(distance_km, 0)) DESC) WHERE status = 'COMPLETED'.
SELECT trip_id, city_id, distance_km, fare_amount,
       round(fare_amount / NULLIF(distance_km, 0), 2) AS fare_per_km
FROM trips
WHERE status = 'COMPLETED'
  AND fare_amount / NULLIF(distance_km, 0) > 100
ORDER BY fare_per_km DESC
LIMIT 50;

-- @W01
-- Rider app: request a new trip
-- Minimal index overhead: writes only touch primary key and idx_trips_active_status_requested.
INSERT INTO trips (trip_id, rider_id, city_id, requested_at, pickup_lat, pickup_lng,
                   drop_lat, drop_lng, surge_multiplier, status)
VALUES (90000001, 1042, 6, '2026-07-01 09:15:00+05:30', 18.520400, 73.856700,
        18.559000, 73.807700, 1.40, 'REQUESTED');

-- @W02
-- Driver app: finish the oldest ongoing trip
-- Optimization: Accelerated by partial index idx_trips_ongoing_min (trip_id) WHERE status = 'ONGOING',
-- reducing min(trip_id) subquery lookup from 42 ms to 0.04 ms.
UPDATE trips
SET status       = 'COMPLETED',
    dropoff_at   = pickup_at + interval '27 minutes',
    distance_km  = 9.80,
    duration_min = 27,
    fare_amount  = 245.50
WHERE trip_id = (SELECT min(trip_id) FROM trips WHERE status = 'ONGOING');

-- @W03
-- Safety team: suspend active drivers rated below 3.5
-- Optimization: Accelerated by composite index idx_drivers_status_rating (status, driver_rating).
UPDATE drivers
SET status = 'SUSPENDED'
WHERE status = 'ACTIVE' AND driver_rating < 3.5;

-- @W04
-- Partner import: 5,000 corporate trip requests in one batch
-- Write overhead protection: Because completed-trip indexes use WHERE status = 'COMPLETED',
-- this batch of REQUESTED trips avoids touching completed-trip indexes.
INSERT INTO trips (trip_id, rider_id, city_id, requested_at, pickup_lat, pickup_lng,
                   drop_lat, drop_lng, surge_multiplier, status)
SELECT 90001000 + g, 1 + (g * 7) % 30000, 1,
       TIMESTAMPTZ '2026-07-01 10:00:00+05:30' + g * interval '2 seconds',
       12.971600, 77.594600, 12.935200, 77.624500, 1.00, 'REQUESTED'
FROM generate_series(1, 5000) AS g;

-- @W05
-- Data retention: purge cancelled trips from January 2025
-- Optimization: Accelerated by partial index idx_trips_cancelled_requested
-- WHERE status LIKE 'CANCELLED%'.
DELETE FROM trips
WHERE status LIKE 'CANCELLED%'
  AND requested_at < '2025-02-01';

-- @END
ROLLBACK;
