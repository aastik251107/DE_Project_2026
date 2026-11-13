# Normalization Explained (Step-by-Step)

**Course:** Database Management Systems (B.Tech 2nd Year)  
**Project:** Uber Ride-Hailing Database System  
**Goes with:** `docs/02_schema_design.md` · `sql/01_schema.sql` · `diagrams/er_diagram.png`

---

## 1. What is Normalization?

**Normalization in one simple sentence:**  
Store every fact **once, in the right table**, so that adding, updating, or deleting data never creates a mess.

### Key Terms You Need (5-Minute Version)
- **Functional Dependency (FD):** "If I know column A, I can look up column B for sure." We write this as **A → B**.  
  *Example:* If I know a student's roll number, I know their name. In Uber: `rider_id → full_name`.
- **Primary Key:** The column (or combination of columns) that uniquely identifies a row.
- **Normal Forms:** Levels of cleanliness for database tables (1NF, 2NF, 3NF, and BCNF). Each level solves a specific kind of mess.

---

## 2. Why Not Put Everything in ONE Big Table?

Suppose we stored all Uber data in one giant spreadsheet where each row is a trip:

```
trip_id | rider_id | rider_name | rider_phone | driver_id | driver_name | driver_phone | city_name | base_fare | distance | fare | rider_stars | driver_stars
```

This single sheet causes three classic database disasters (anomalies):

1. **Update Problem (Update Anomaly):**  
   - A driver changes their phone number. Because that driver completed 100 trips, their phone number appears in 100 different rows.
   - If we update 99 rows and miss one, the driver now has two different phone numbers in the system.
   - If Bengaluru updates its `base_fare`, we would have to update ~30,000 trip rows.

2. **Insert Problem (Insertion Anomaly):**  
   - We sign up a new driver partner or create a new promo code.
   - But we cannot insert them into the database until they complete their first trip, because every row requires a `trip_id`.

3. **Delete Problem (Deletion Anomaly):**  
   - If a rider deletes their only trip, or if we purge old cancelled rides, the rider's personal account and registration details vanish too.

**The cure:** Normalize the data by breaking the giant sheet into separate, clean tables.

---

## 3. Step 1: First Normal Form (1NF)

**The Rule:**  
1. Every cell must contain a single, indivisible value (atomic).
2. No repeating groups of columns.

**What we fixed:**
- **Atomic Values:** Instead of saving `"12.9716, 77.5946"` in one column, we use two separate columns: `pickup_lat` and `pickup_lng`.
- **No Repeating Columns:** In a trip, both the rider and driver can rate each other. In the giant sheet, having `rider_stars` and `driver_stars` is the same concept repeated twice.  
  *The 1NF fix:* Move reviews to their own table (`ratings`), where each rating is its own row with a column `rated_by` ('RIDER' or 'DRIVER').

---

## 4. Step 2: Second Normal Form (2NF)

**The Rule:**  
- The table must be in 1NF.
- If a table has a composite key (a primary key made of 2 or more columns), every non-key column must depend on the **entire** key, not just part of it.

**How our tables pass 2NF:**
- Seven of our tables (`cities`, `promo_codes`, `riders`, `drivers`, `vehicles`, `trips`, `payments`) have a simple 1-column primary key. Because the key has only one column, you cannot depend on a "part" of it. They pass 2NF automatically!
- Only **`ratings`** has a 2-column composite primary key: `(trip_id, rated_by)`.
  - The columns are `stars`, `comment`, and `created_at`.
  - These depend on **both** columns together: the rider's rating and the driver's rating for the same trip have different stars, comments, and timestamps.
  - Therefore, `ratings` has no partial dependencies and satisfies 2NF.

---

## 5. Step 3: Third Normal Form (3NF)

**The Rule:**  
- The table must be in 2NF.
- Every column must depend **only** on the primary key, and not on another non-key column (no "transitive dependencies").

**The "Detour" in the Giant Sheet:**
- In the giant sheet: `trip_id → rider_id`, and `rider_id → rider_name, email, phone`.
- That means `rider_name` depended on `trip_id` only *through* `rider_id`. That middle detour causes duplicate data.

**The 3NF Fix:** Give each entity its own table:
- Rider facts move to **`riders`** (key: `rider_id`).
- Driver facts move to **`drivers`** (key: `driver_id`).
- Vehicle facts move to **`vehicles`** (key: `vehicle_id`).
- City facts move to **`cities`** (key: `city_id`).
- Promo facts move to **`promo_codes`** (key: `promo_code`).
- **`trips`** keeps only facts about the trip event itself and connects to other tables using Foreign Keys.

Now every column depends directly on the table's primary key and nothing else. The tables are in 3NF.

---

## 6. Step 4: Boyce-Codd Normal Form (BCNF)

**The Rule:**  
A stricter version of 3NF: whenever column(s) $X$ determine column $Y$ ($X \to Y$), $X$ **must be a key** (either Primary Key or a UNIQUE column).

**Check for all tables:**
- In `cities`: `city_id` is PK, `city_name` is UNIQUE.
- In `riders`: `rider_id` is PK, `email` and `phone` are UNIQUE.
- In `drivers`: `driver_id` is PK, `phone` and `license_no` are UNIQUE.
- In `vehicles`: `vehicle_id` is PK, `registration_no` is UNIQUE.
- In `promo_codes`: `promo_code` is PK.
- In `payments`: `payment_id` is PK, `trip_id` is UNIQUE.
- In `trips`: `trip_id` is PK.
- In `ratings`: `(trip_id, rated_by)` is PK.

In every case, the determinant on the left side of the arrow is a candidate key. Therefore, all tables are in **BCNF**.

---

## 7. Why Do We Keep 3 Calculated Columns?

A strict theoretical database designer might say: *"Never store any column you can calculate."*  
However, real systems keep a few calculated values for practical reasons:

1. **`driver_rating` and `rider_rating`**:
   - *Can be calculated by:* `AVG(stars)` from the `ratings` table.
   - *Why we keep it:* Every time a trip is requested, dispatch checks the driver's rating. Averaging 300,000+ ratings on every booking would be far too slow.
2. **`trips.fare_amount`**:
   - *Can be calculated by:* formula from distance, duration, surge, and city rates.
   - *Why we keep it:* City rates (`cities.base_fare`) change over time, but the fare paid on a ride receipt is history and must never change. Storing the final charged amount keeps financial records safe.
3. **`trips.duration_min`**:
   - *Can be calculated by:* `dropoff_at - pickup_at`.
   - *Why we keep it:* Allows fast filtering in fraud checks (like finding trips over 150 minutes in Query R24) without calculating timestamps on 300,000 rows every time.
