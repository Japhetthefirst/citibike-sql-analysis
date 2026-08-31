/* =========================================================================
   CITI BIKE OPERATIONS ANALYSIS - April (Dominick Tribone / Operated Markets)
   =========================================================================
   Source  : Citi Bike Trip Histories (https://citibikenyc.com/system-data)
   Author  : [Japhet Olusegun](https://www.linkedin.com/in/japhetolusegun/)
   Date    : 2024-06-05
   ========================================================================= */


-- =========================================================================
-- SECTION 1: EDA - Schema Check
-- Look at column names, data types, and nullability for the trips table.
-- =========================================================================
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'citibike_trips'
ORDER BY ordinal_position;


-- =========================================================================
-- SECTION 2: EDA - Data Quality Check
-- Count missing (NULL) values per column that matters for station-level
-- and geographic analysis.
-- =========================================================================
SELECT
    COUNT(*) FILTER (WHERE start_station_name IS NULL) AS start_station_name_missing,
    COUNT(*) FILTER (WHERE start_station_id   IS NULL) AS start_station_id_missing,
    COUNT(*) FILTER (WHERE start_lat          IS NULL) AS start_lat_missing,
    COUNT(*) FILTER (WHERE start_lng          IS NULL) AS start_lng_missing,
    COUNT(*) FILTER (WHERE end_station_name   IS NULL) AS end_station_name_missing,
    COUNT(*) FILTER (WHERE end_lat            IS NULL) AS end_lat_missing,
    COUNT(*) FILTER (WHERE end_lng            IS NULL) AS end_lng_missing,
    COUNT(*) FILTER (WHERE end_station_id     IS NULL) AS end_station_id_missing
FROM citibike_trips;


-- =========================================================================
-- SECTION 3: EDA - Volume Check
-- Total rides, total distinct stations, and total distinct bikes/rideable
-- types before any cleaning is applied.
-- =========================================================================
SELECT
    COUNT(*)                                                    AS total_rides,
    COUNT(DISTINCT start_station_id)                            AS total_start_stations,
    COUNT(DISTINCT end_station_id)                              AS total_end_stations,
    COUNT(DISTINCT rideable_type)                                AS total_bike_types
FROM citibike_trips;


-- =========================================================================
-- SECTION 4: Reusable cleaned-rides definition
-- Context Boundaries:
--   1. Drop rides under 2 minutes  (likely broken bike / instant return)
--   2. Drop rides over 120 minutes (likely lost/stolen/forgotten return,
--      subject to Citi Bike's $1,200 fee)
--
-- IMPORTANT: duration filter uses INTERVAL comparison, not EXTRACT(EPOCH...).
-- =========================================================================
-- Reference CTE pattern used throughout this file:
--
-- WITH clean_rides AS (
--     SELECT *
--     FROM citibike_trips
--     WHERE (ended_at - started_at)
--           BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
-- )


-- =========================================================================
-- SECTION 5: Core Metric 1 - Volume & Time
-- Total rides, average/shortest/longest ride duration (in minutes) after
-- applying the 2-120 minute context boundary.
-- =========================================================================
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
          BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
)
SELECT
    COUNT(*)                                                              AS total_rides,
    ROUND(AVG(EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0), 2)     AS avg_ride_duration,
    ROUND(MIN(EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0), 2)     AS shortest_ride_duration,
    ROUND(MAX(EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0), 2)     AS longest_ride_duration
FROM clean_rides;

-- Rides by hour of day (supports "total rides by hour of day")
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
          BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
)
SELECT
    EXTRACT(HOUR FROM started_at)::int AS ride_hour,
    COUNT(*)                           AS total_rides
FROM clean_rides
GROUP BY ride_hour
ORDER BY ride_hour;


-- =========================================================================
-- SECTION 6: Core Metric 2 - Net Station Flow
-- Stations that empty out or fill up during morning rush (7-10 AM) and
-- evening rush (4-7 PM).
--
-- Note: start_station_id has more distinct values than start_station_name
-- (2,237 vs 2,234) - resolved by grouping on station_id and taking
-- MAX(station_name) as the representative label.
-- =========================================================================

-- 7 AM - 10 AM Rush
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
          BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
),
starts AS (
    SELECT
        start_station_id  AS station_id,
        MAX(start_station_name) AS station_name,
        COUNT(*)          AS trips_started
    FROM clean_rides
    WHERE EXTRACT(HOUR FROM started_at) BETWEEN 7 AND 9  -- 7:00-9:59 AM
    GROUP BY start_station_id
),
ends AS (
    SELECT
        end_station_id AS station_id,
        MAX(end_station_name) AS station_name,
        COUNT(*) AS trips_ended
    FROM clean_rides
    WHERE EXTRACT(HOUR FROM ended_at) BETWEEN 7 AND 9
    GROUP BY end_station_id
)
SELECT
    COALESCE(s.station_id, e.station_id) AS station_id,
    COALESCE(s.station_name, e.station_name) AS station_name,
    COALESCE(s.trips_started, 0) AS trips_started,
    COALESCE(e.trips_ended, 0) AS trips_ended,
    COALESCE(e.trips_ended, 0) - COALESCE(s.trips_started, 0) AS net_flow
FROM starts s
FULL OUTER JOIN ends e ON s.station_id = e.station_id
ORDER BY net_flow DESC
LIMIT 5;

-- 4 PM - 7 PM Rush
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
        BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
),
starts AS (
    SELECT
        start_station_id  AS station_id,
        MAX(start_station_name) AS station_name,
        COUNT(*) AS trips_started
    FROM clean_rides
    WHERE EXTRACT(HOUR FROM started_at) BETWEEN 16 AND 18  -- 4:00-6:59 PM
    GROUP BY start_station_id
),
ends AS (
    SELECT
        end_station_id AS station_id,
        MAX(end_station_name) AS station_name,
        COUNT(*) AS trips_ended
    FROM clean_rides
    WHERE EXTRACT(HOUR FROM ended_at) BETWEEN 16 AND 18
    GROUP BY end_station_id
)
SELECT
    COALESCE(s.station_id, e.station_id) AS station_id,
    COALESCE(s.station_name, e.station_name) AS station_name,
    COALESCE(s.trips_started, 0) AS trips_started,
    COALESCE(e.trips_ended, 0) AS trips_ended,
    COALESCE(e.trips_ended, 0) - COALESCE(s.trips_started, 0) AS net_flow
FROM starts s
FULL OUTER JOIN ends e ON s.station_id = e.station_id
ORDER BY net_flow DESC
LIMIT 5;


-- =========================================================================
-- SECTION 7: Core Metric 3 - Fleet Load
-- Ride count and share (%) by bike type (classic vs electric).
-- =========================================================================
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
        BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
)
SELECT
    rideable_type,
    COUNT(*) AS total_rides,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM clean_rides
GROUP BY rideable_type
ORDER BY total_rides DESC;


-- =========================================================================
-- SECTION 8: Core Metric 4 - User Behavior
-- Total rides and average trip duration split by member vs casual.
-- =========================================================================
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
        BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
)
SELECT
    member_casual,
    COUNT(*) AS total_rides,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
    ROUND(AVG(EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0), 2)   AS avg_ride_duration
FROM clean_rides
GROUP BY member_casual
ORDER BY total_rides DESC;


-- =========================================================================
-- SECTION 9: Deeper EDA - Top 5 Start Stations by Bike Type
-- Ranked separately for classic and electric bikes.
-- =========================================================================
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
        BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
),
station_bike_stats AS (
    SELECT
        rideable_type,
        start_station_name AS station_name,
        COUNT(*) AS total_trips,
        ROUND(AVG(EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0), 2) AS avg_duration_min,
        RANK() OVER (
            PARTITION BY rideable_type
            ORDER BY COUNT(*) DESC
        ) AS rank
    FROM clean_rides
    GROUP BY rideable_type, start_station_name
)
SELECT rank, station_name, total_trips, avg_duration_min
FROM station_bike_stats
WHERE rideable_type = 'classic_bike'
  AND rank <= 5
ORDER BY rank;

WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
        BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
),
station_bike_stats AS (
    SELECT
        rideable_type,
        start_station_name AS station_name,
        COUNT(*) AS total_trips,
        ROUND(AVG(EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0), 2) AS avg_duration_min,
        RANK() OVER (
            PARTITION BY rideable_type
            ORDER BY COUNT(*) DESC
        ) AS rank
    FROM clean_rides
    GROUP BY rideable_type, start_station_name
)
SELECT rank, station_name, total_trips, avg_duration_min
FROM station_bike_stats
WHERE rideable_type = 'electric_bike'
  AND rank <= 5
ORDER BY rank;


-- =========================================================================
-- SECTION 10: Deeper EDA - Daily Trip Trends
-- Ride count per day, previous-day comparison, and day-over-day % change.
-- =========================================================================
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
        BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
),
daily_counts AS (
    SELECT
        started_at::date AS day,
        COUNT(*) AS ride_count
    FROM clean_rides
    GROUP BY started_at::date
)
SELECT
    day,
    ride_count,
    LAG(ride_count) OVER (ORDER BY day) AS previous_day_trips,
    ride_count - LAG(ride_count) OVER (ORDER BY day) AS daily_change,
    ROUND(
        100.0 * (ride_count - LAG(ride_count) OVER (ORDER BY day))
        / NULLIF(LAG(ride_count) OVER (ORDER BY day), 0), 2
    ) AS pct_change
FROM daily_counts
ORDER BY day;


-- =========================================================================
-- SECTION 11: Bonus - 7-Day Moving Average
-- Smooths daily trip trends using a trailing 7-day window.
-- =========================================================================
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
        BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
),
daily_counts AS (
    SELECT
        started_at::date AS day,
        COUNT(*) AS ride_count
    FROM clean_rides
    GROUP BY started_at::date
)
SELECT
    day,
    ride_count,
    LAG(ride_count) OVER (ORDER BY day) AS previous_day_trips,
    ride_count - LAG(ride_count) OVER (ORDER BY day) AS daily_change,
    ROUND(
        AVG(ride_count) OVER (
            ORDER BY day
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) AS moving_avg_7d
FROM daily_counts
ORDER BY day;


-- =========================================================================
-- SECTION 12: Deeper EDA - User Type Breakdown by Rush Hour
-- Splits trips into Morning Rush (7-10 AM), Evening Rush (4-7 PM), and
-- Others, by member vs casual.
-- =========================================================================
WITH clean_rides AS (
    SELECT *
    FROM citibike_trips
    WHERE (ended_at - started_at)
        BETWEEN INTERVAL '2 minutes' AND INTERVAL '120 minutes'
),
tagged_rides AS (
    SELECT
        member_casual,
        CASE
            WHEN EXTRACT(HOUR FROM started_at) BETWEEN 7 AND 9 THEN 'Morning Rush'
            WHEN EXTRACT(HOUR FROM started_at) BETWEEN 16 AND 18 THEN 'Evening Rush'
            ELSE 'Others'
        END AS rush_group
    FROM clean_rides
)
SELECT
    member_casual,
    rush_group,
    COUNT(*) AS trips_count
FROM tagged_rides
GROUP BY member_casual, rush_group
ORDER BY member_casual, rush_group;
