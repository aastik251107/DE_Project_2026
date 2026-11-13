-- =====================================================================
-- Course: Database Management Systems (B.Tech 2nd Year)
-- Project: Uber Ride-Hailing Database System
-- File: sql/01_schema.sql
-- Description: Creates the 'uber' schema and all 8 tables
-- =====================================================================

-- 1. Create and use the schema named 'uber'
CREATE SCHEMA IF NOT EXISTS uber;
SET search_path TO uber;

-- 2. Drop tables in reverse order so foreign keys don't block dropping
DROP TABLE IF EXISTS ratings CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS trips CASCADE;
DROP TABLE IF EXISTS vehicles CASCADE;
DROP TABLE IF EXISTS drivers CASCADE;
DROP TABLE IF EXISTS riders CASCADE;
DROP TABLE IF EXISTS promo_codes CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

-- ---------------------------------------------------------------------
-- Table 1: cities (10 rows)
-- Stores city names and their base fare rates
-- ---------------------------------------------------------------------
CREATE TABLE cities (
    city_id         SMALLINT PRIMARY KEY,
    city_name       VARCHAR(50) NOT NULL UNIQUE,
    state           VARCHAR(50) NOT NULL,
    base_fare       NUMERIC(6,2) NOT NULL CHECK (base_fare >= 0),
    per_km_rate     NUMERIC(6,2) NOT NULL CHECK (per_km_rate > 0),
    per_min_rate    NUMERIC(6,2) NOT NULL CHECK (per_min_rate >= 0),
    launched_on     DATE NOT NULL
);

-- ---------------------------------------------------------------------
-- Table 2: promo_codes (40 rows)
-- Stores discount coupon codes and active dates
-- ---------------------------------------------------------------------
CREATE TABLE promo_codes (
    promo_code      VARCHAR(20) PRIMARY KEY,
    discount_pct    SMALLINT NOT NULL CHECK (discount_pct BETWEEN 1 AND 100),
    max_discount    NUMERIC(8,2) NOT NULL CHECK (max_discount > 0),
    valid_from      DATE NOT NULL,
    valid_to        DATE NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_promo_dates CHECK (valid_to >= valid_from)
);

-- ---------------------------------------------------------------------
-- Table 3: riders (30,000 rows)
-- Stores customer accounts
-- ---------------------------------------------------------------------
CREATE TABLE riders (
    rider_id        INT PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    email           VARCHAR(254) NOT NULL UNIQUE,
    phone           VARCHAR(10) NOT NULL UNIQUE,
    home_city_id    SMALLINT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    signup_date     DATE NOT NULL,
    rider_rating    NUMERIC(2,1) CHECK (rider_rating BETWEEN 1.0 AND 5.0),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- Table 4: drivers (3,000 rows)
-- Stores driver partner details
-- ---------------------------------------------------------------------
CREATE TABLE drivers (
    driver_id       INT PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    phone           VARCHAR(10) NOT NULL UNIQUE,
    license_no      VARCHAR(30) NOT NULL UNIQUE,
    city_id         SMALLINT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    joined_on       DATE NOT NULL,
    driver_rating   NUMERIC(2,1) CHECK (driver_rating BETWEEN 1.0 AND 5.0),
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED'))
);

-- ---------------------------------------------------------------------
-- Table 5: vehicles (3,300 rows)
-- Stores vehicles registered to drivers
-- ---------------------------------------------------------------------
CREATE TABLE vehicles (
    vehicle_id          INT PRIMARY KEY,
    driver_id           INT NOT NULL REFERENCES drivers(driver_id) ON DELETE RESTRICT,
    registration_no     VARCHAR(15) NOT NULL UNIQUE,
    make                VARCHAR(30) NOT NULL,
    model               VARCHAR(30) NOT NULL,
    manufacture_year    SMALLINT NOT NULL CHECK (manufacture_year BETWEEN 2000 AND 2030),
    vehicle_type        VARCHAR(10) NOT NULL,
    seat_capacity       SMALLINT NOT NULL CHECK (seat_capacity BETWEEN 1 AND 8)
);

-- ---------------------------------------------------------------------
-- Table 6: trips (300,000 rows)
-- Central table: records every trip from request to completion
-- ---------------------------------------------------------------------
CREATE TABLE trips (
    trip_id             BIGINT PRIMARY KEY,
    rider_id            INT NOT NULL REFERENCES riders(rider_id) ON DELETE RESTRICT,
    driver_id           INT REFERENCES drivers(driver_id) ON DELETE RESTRICT,
    vehicle_id          INT REFERENCES vehicles(vehicle_id) ON DELETE RESTRICT,
    city_id             SMALLINT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    promo_code          VARCHAR(20) REFERENCES promo_codes(promo_code) ON DELETE RESTRICT,
    requested_at        TIMESTAMPTZ NOT NULL,
    pickup_at           TIMESTAMPTZ,
    dropoff_at          TIMESTAMPTZ,
    pickup_lat          NUMERIC(9,6) NOT NULL,
    pickup_lng          NUMERIC(9,6) NOT NULL,
    drop_lat            NUMERIC(9,6) NOT NULL,
    drop_lng            NUMERIC(9,6) NOT NULL,
    distance_km         NUMERIC(6,2) CHECK (distance_km >= 0),
    duration_min        SMALLINT CHECK (duration_min >= 0),
    surge_multiplier    NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (surge_multiplier >= 1.0),
    fare_amount         NUMERIC(10,2) CHECK (fare_amount >= 0),
    status              VARCHAR(30) NOT NULL
);

-- ---------------------------------------------------------------------
-- Table 7: payments (245,839 rows)
-- Stores payment transactions for completed trips (1 per trip)
-- ---------------------------------------------------------------------
CREATE TABLE payments (
    payment_id      BIGINT PRIMARY KEY,
    trip_id         BIGINT NOT NULL UNIQUE REFERENCES trips(trip_id) ON DELETE RESTRICT,
    amount          NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    method          VARCHAR(20) NOT NULL CHECK (method IN ('UPI', 'CASH', 'CARD', 'WALLET')),
    payment_status  VARCHAR(20) NOT NULL CHECK (payment_status IN ('SUCCESS', 'FAILED', 'PENDING', 'REFUNDED')),
    paid_at         TIMESTAMPTZ NOT NULL
);

-- ---------------------------------------------------------------------
-- Table 8: ratings (307,214 rows)
-- Stores ratings given by riders and drivers
-- Composite primary key: (trip_id, rated_by)
-- ---------------------------------------------------------------------
CREATE TABLE ratings (
    trip_id         BIGINT NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    rated_by        VARCHAR(6) NOT NULL CHECK (rated_by IN ('RIDER', 'DRIVER')),
    stars           SMALLINT NOT NULL CHECK (stars BETWEEN 1 AND 5),
    comment         TEXT,
    created_at      TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (trip_id, rated_by)
);
