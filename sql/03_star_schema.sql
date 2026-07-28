-- ============================================================
--  FIFA WORLD CUP 2026 — Star Schema for Power BI
--  Run AFTER 02_transform.sql
--
--  These are the ONLY objects that should be imported into Power BI.
--  Everything else is either raw input or validation-only.
-- ============================================================


-- ------------------------------------------------------------
-- dim_matches — one row per match (102)
--
-- This is the hub of the model. All three fact tables carry match_no,
-- and fact_team_match has TWO rows per match, so match_no is not unique
-- there. Without this dimension, the facts can only relate to each other
-- many-to-many.
--
-- Deliberately excludes home_team / away_team / winner: those would each
-- create a second path to dim_teams and force Power BI to deactivate
-- relationships. That information already lives in fact_team_match
-- (team / opponent / advanced).
--
-- potm is kept as plain display text with no key, so no relationship is
-- inferred from it.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS dim_matches;

CREATE VIEW dim_matches AS
SELECT
    m.match_no,
    m.match_type,                                  -- 'Group Stage' | 'Knockouts'
    m.group_name,                                  -- 'A'..'L' | 'RO32' | 'RO16' | 'QF' | 'SF'
    CASE WHEN m.match_type = 'Group Stage'
         THEN 'Group ' || m.group_name
         ELSE m.group_name
    END                        AS round_label,     -- friendly label for slicers
    CASE m.group_name
         WHEN 'RO32' THEN 2 WHEN 'RO16' THEN 3
         WHEN 'QF'   THEN 4 WHEN 'SF'   THEN 5
         ELSE 1
    END                        AS round_order,     -- for sorting rounds correctly
    m.stadium,                                     -- FK -> venues.stadium_name
    m.referee,
    m.result_in,                                   -- 'FT' | 'AET' | 'Pen'
    (m.result_in <> 'FT')      AS went_to_extra_time,
    m.htg + m.atg              AS total_goals,
    m.potm                     AS player_of_the_match
FROM matches m;

-- Must return 102 rows, 102 distinct match_no
SELECT COUNT(*) AS row_count, COUNT(DISTINCT match_no) AS distinct_matches
FROM dim_matches;


-- ------------------------------------------------------------
-- fact_goals — one row per goal (297)
--
-- Adds normalised keys so the goal can be linked to dim_players.
-- With nkey() applied, all 297 scorers, all 215 assisters and all
-- players of the match resolve against dim_players with zero orphans.
--
-- nkey() is accent-stripping only — player_key must stay unique across
-- all 1259 players or Power BI will infer many-to-many relationships.
--
-- NULLIF is required on assist_key: nkey() COALESCEs NULL to '',
-- and an empty string would be a real (wrong) key rather than a blank.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS fact_goals;

CREATE VIEW fact_goals AS
SELECT
    g.goal_no,
    g.match_no,                                    -- FK -> dim_matches
    g.scored_for            AS team,               -- FK -> teams (benefiting team)
    g.scored_ag             AS opponent,
    nkey(g.scored_by)       AS scorer_key,         -- FK -> dim_players
    g.scored_by             AS scorer_name,
    NULLIF(nkey(g.assist_by), '') AS assist_key,   -- FK -> dim_players (nullable)
    g.assist_by             AS assist_name,
    g.minute,
    g.half,
    (g.half LIKE 'ET%')     AS is_extra_time,
    g.goal_type,
    (g.goal_type = 'Own Goal') AS is_own_goal,
    -- 15-minute buckets for the goal-timing histogram.
    -- 90+ is bucketed separately: stoppage time is where the spike lives.
    CASE WHEN g.minute <= 15 THEN '1-15'
         WHEN g.minute <= 30 THEN '16-30'
         WHEN g.minute <= 45 THEN '31-45'
         WHEN g.minute <= 60 THEN '46-60'
         WHEN g.minute <= 75 THEN '61-75'
         WHEN g.minute <= 90 THEN '76-90'
         ELSE '90+'
    END                     AS minute_bucket
FROM goals g;

-- Must return 297 rows, 0 orphan scorers
SELECT COUNT(*) AS row_count,
       COUNT(*) FILTER (WHERE scorer_key NOT IN (SELECT player_key FROM dim_players)) AS orphan_scorers
FROM fact_goals;


-- ------------------------------------------------------------
-- Final integrity check — every FK resolves.
-- All four counts must be 0.
-- ------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM fact_team_match   f WHERE f.match_no   NOT IN (SELECT match_no     FROM dim_matches)) AS ftm_bad_match,
    (SELECT COUNT(*) FROM fact_player_match f WHERE f.match_no   NOT IN (SELECT match_no     FROM dim_matches)) AS fpm_bad_match,
    (SELECT COUNT(*) FROM fact_player_match f WHERE f.player_key NOT IN (SELECT player_key   FROM dim_players)) AS fpm_bad_player,
    (SELECT COUNT(*) FROM dim_matches       d WHERE d.stadium    NOT IN (SELECT stadium_name FROM venues))      AS dim_bad_venue;


-- ------------------------------------------------------------
-- dim_podium — final tournament standings (top 4)
--
-- Derived from the Final and 3rd-place matches so it regenerates
-- on reload rather than being hardcoded. The loser of each match
-- is the team that is not the winner (only two teams per match).
-- Used as a small "Final standings" table on the overview page.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS dim_podium;

CREATE VIEW dim_podium AS
SELECT 'Champion'  AS position, winner AS team, 1 AS pos_order
FROM matches WHERE group_name = 'Final'
UNION ALL
SELECT 'Runner-up',
       CASE WHEN winner = home_team THEN away_team ELSE home_team END, 2
FROM matches WHERE group_name = 'Final'
UNION ALL
SELECT 'Third', winner, 3
FROM matches WHERE group_name = '3rd Place'
UNION ALL
SELECT 'Fourth',
       CASE WHEN winner = home_team THEN away_team ELSE home_team END, 4
FROM matches WHERE group_name = '3rd Place';

-- Must return 4 rows: Spain, Argentina, England, France
SELECT * FROM dim_podium ORDER BY pos_order;
