--Creating the Churn_Modelling table with appropriate data types and constraints

CREATE TABLE citi_bike_trips (
    ride_id VARCHAR(50) PRIMARY KEY,
    rideable_type VARCHAR(20),
    started_at TIMESTAMP,
    ended_at TIMESTAMP,
    start_station_name TEXT,
    start_station_id VARCHAR(50),
    end_station_name TEXT,
    end_station_id VARCHAR(50),
    start_lat DECIMAL(10, 8),
    start_lng DECIMAL(11, 8),
    end_lat DECIMAL(10, 8),
    end_lng DECIMAL(11, 8),
    member_casual VARCHAR(10)
);