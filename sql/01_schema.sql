-- ============================================================
--  FIFA WORLD CUP 2026 — Schema Definition
--  PostgreSQL 15
--  Run against the "worldcup" database.
--
--  WARNING: this script drops all tables. Do not run it on a
--  loaded database unless you intend to reload from scratch.
-- ============================================================

-- Required for accent-insensitive name matching (see 02_transform.sql)
CREATE EXTENSION IF NOT EXISTS unaccent;

DROP TABLE IF EXISTS attack_stats, defencestats, goals, match_stats,
                     matches, players, playersstats, teams, teamstats, venues CASCADE;

-- ------------------------------------------------------------
-- DIMENSIONS
-- ------------------------------------------------------------

CREATE TABLE teams (
    team_id     INT PRIMARY KEY,
    team_name   TEXT NOT NULL,
    manager     TEXT
);

CREATE TABLE venues (
    stadium_id    INT PRIMARY KEY,
    stadium_name  TEXT NOT NULL,
    city          TEXT,
    country       TEXT
);

CREATE TABLE players (
    player_id     INT PRIMARY KEY,
    player_name   TEXT NOT NULL,
    player_age    INT,
    playing_role  TEXT,
    team_name     TEXT
);

-- ------------------------------------------------------------
-- FACTS
-- ------------------------------------------------------------

-- Grain: one row per match
CREATE TABLE matches (
    match_no    INT PRIMARY KEY,
    match_type  TEXT,          -- 'Group Stage' | 'Knockouts'
    group_name  TEXT,          -- 'A'..'L' | 'RO32' | 'RO16' | 'QF' | 'SF'
    home_team   TEXT,
    htg         INT,           -- home team goals
    atg         INT,           -- away team goals
    away_team   TEXT,
    winner      TEXT,          -- team name, or 'Draw'
    potm        TEXT,          -- player of the match
    stadium     TEXT,
    city        TEXT,
    referee     TEXT,
    result_in   TEXT           -- 'FT' | 'AET' | 'Pen'
);

-- Grain: one row per team per match (204 rows = 102 x 2)
CREATE TABLE match_stats (
    match_no    INT,
    team        TEXT,
    possession  INT,
    xg          NUMERIC(5,2),
    shots       INT,
    on_target   INT,
    bcm         INT,           -- big chances missed
    yellow_c    INT,
    red_c       INT,
    fouls       INT
);

-- Grain: one row per goal
-- Note: penalty shootout goals are NOT included here (correct behaviour).
CREATE TABLE goals (
    goal_no     INT PRIMARY KEY,
    scored_for  TEXT,          -- benefiting team (for own goals too)
    scored_by   TEXT,
    minute      INT,           -- actual minute, reaches 125 in extra time
    half        TEXT,          -- '1', '2', 'ET-1', 'ET-2'  <- NOT an integer
    assist_by   TEXT,          -- NULL = unassisted goal (82 cases)
    goal_type   TEXT,          -- 'Regular' | 'Header' | 'Penalty' | 'Free Kick' | 'Own Goal'
    scored_ag   TEXT,          -- conceding team
    match_no    INT
);

-- Grain: one row per player per match (attacking stats)
CREATE TABLE attack_stats (
    player_name      TEXT,
    team_name        TEXT,
    match_no         INT,
    goals            INT,
    assists          INT,
    xg               NUMERIC(5,2),
    bcm              INT,
    dribbles         INT,
    chances_created  INT
);

-- Grain: one row per player per match (defensive stats)
CREATE TABLE defencestats (
    player_name  TEXT,
    team_name    TEXT,
    match_no     INT,
    tackles      INT,
    recoveries   INT,
    gk_saves     INT
);

-- ------------------------------------------------------------
-- PRE-AGGREGATED SOURCES
-- Redundant with the fact tables above. Loaded only to validate
-- that our own aggregations match the source. Do not publish to
-- Power BI.
-- ------------------------------------------------------------

CREATE TABLE teamstats (
    team       TEXT,
    matches    INT,
    goals      INT,
    avg_pos    NUMERIC(5,2),
    xg         NUMERIC(6,2),
    shots      NUMERIC(6,1),
    on_target  NUMERIC(6,1),
    bcm        NUMERIC(6,1),
    yellow_c   NUMERIC(6,1),
    red_c      NUMERIC(6,1),
    fouls      NUMERIC(6,1)
);

CREATE TABLE playersstats (
    player           TEXT,
    player_position  TEXT,     -- renamed: "position" is a reserved word
    team             TEXT,
    goals            NUMERIC(6,1),
    assists          NUMERIC(6,1),
    xg               NUMERIC(6,2),
    bcm              NUMERIC(6,1),
    dribbles         NUMERIC(6,1),
    chances_created  NUMERIC(6,1),
    tackles          NUMERIC(6,1),
    recoveries       NUMERIC(6,1),
    saves            NUMERIC(6,1)
);
