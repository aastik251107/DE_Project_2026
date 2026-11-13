# Phase 1: Problem Understanding

**Course:** Database Management Systems (B.Tech 2nd Year)  
**Project:** Uber Ride-Hailing Database System  
**Context:** Uber India operating across 10 cities (Bengaluru, Mumbai, Delhi, Hyderabad, Chennai, Pune, Kolkata, Ahmedabad, Jaipur, Lucknow) with 300,000 trips.

---

## 1. Understanding the Problems (P1 to P9)

The previous team set up the database without proper documentation, which caused speed and accuracy issues. Below is our analysis of the complaints reported by different teams:

| # | What the Business Needs (in simple words) | Stakeholder Affected | Category / Workload | Related Queries |
|---|---|---|---|---|
| **P1** | When a rider opens "Your Trips", their latest rides should load instantly, even if they have taken hundreds of rides. | Rider (Rider App Team) | **Customer-Facing / Real-Time** (under 5 ms) | R01, R15 |
| **P2** | Drivers check their daily and monthly earnings multiple times a day. This screen must stay fast and not scan all trips in the database. | Driver (Driver App Team) | **Customer-Facing / Real-Time** (R02), **Reporting / Analytics** (R07, R19) | R02, R07, R19 |
| **P3** | Riders should be able to log in even if they type their email with capital letters (like `User@Mail.com`), and this check must be fast. | Identity / Login Team | **Customer-Facing / Real-Time** (under 5 ms) | R03 |
| **P4** | The city operations screen refreshes every 3 seconds to track ongoing rides. Both the refresh and new ride requests must finish in milliseconds so the screen doesn't freeze. | City Operations | **Customer-Facing / Real-Time** (under 5 ms) | R04, R05, W01, W02 |
| **P5** | Month-end finance reports (total earnings by payment method and daily revenue) must run smoothly and not time out. | Finance & Payments | **Reporting / Analytics** (under 5 seconds) | R08, R20, R22 |
| **P6** | Marketing's list of inactive riders and drivers for win-back offers must give correct results. An empty list was returned because of how SQL handles empty/NULL values in `NOT IN`. | Marketing & Driver Operations | **Reporting / Analytics** (under 5 seconds) | R09, R10, R18 |
| **P7** | Fraud checks for very long trips or unusually high fare per km should find suspicious rides quickly without reading the entire table every time. | Trust & Safety | **Interactive Search / Operations** (under 250 ms) | R24, R25 |
| **P8** | The admin panel showing all trips should be just as fast when opening page 8,000 as it is on page 1. | Admin Team | **Customer-Facing / Real-Time** (under 5 ms) | R16 |
| **P9** | Analytics dashboards (cancellations per city, surge by hour, growth) must run fast now and still work when data grows 10–20× next year. | Leadership & Analytics | **Reporting / Analytics** (under 5 seconds) | R06, R11, R12, R17, R21, R23 |

---

## 2. Query Categories & Performance Goals

We divide queries into two main types so we know how fast they need to run:

1. **Customer-Facing / Real-Time (Operational)**:
   - A real person is waiting on a screen (rider app, driver app, login, live dispatch).
   - Target time: **under 5 ms** (or under 250 ms for interactive searches).
   - Examples: P1, P2 (R02), P3, P4, P8.

2. **Reporting / Analytics**:
   - Background reports, dashboards, and marketing lists.
   - Target time: **under 5,000 ms (5 seconds)**.
   - Examples: P5, P6, P7, P9.

---

## 3. Assumptions

1. **The 8 CSV files are the truth**: The columns, data types, and values in the seed data represent real business rules.
2. **Indian Standard Time (IST)**: All timestamps have `+05:30`. We set the database timezone to `Asia/Kolkata` so date queries do not get shifted.
3. **Currency is in Indian Rupees (INR)**: Money values use exact decimals (`NUMERIC`) so we don't get floating-point rounding errors.
4. **Data will grow 20× next year**: The database must be designed cleanly now so it can handle ~6 million trips in Phase 5.
5. **Keep query results identical**: When we optimize queries later, they must return the exact same rows as the original queries (except fixing the bug in P6).
