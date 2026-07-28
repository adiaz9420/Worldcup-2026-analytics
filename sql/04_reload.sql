-- ============================================================
--  FIFA WORLD CUP 2026 — Data Reload (post-tournament update)
--
--  Use when the Kaggle CSVs are refreshed but the schema is unchanged.
--  The new dataset adds matches 103 (3rd place) and 104 (final) plus
--  all derived rows. It carries the SAME data-quality issues as before,
--  so every STEP 2 fix still applies unchanged.
--
--  Do NOT run 01_schema.sql — the tables already exist and the views
--  depend on them.
-- ============================================================


-- ------------------------------------------------------------
-- STEP A — Empty the tables (order does not matter: no FKs defined)
-- ------------------------------------------------------------
TRUNCATE teams, venues, players, matches, match_stats, goals,
         attack_stats, defencestats, teamstats, playersstats;

-- Views are NOT dropped by TRUNCATE — they stay and will simply
-- reflect the new rows once reload + fixes are done.


-- ------------------------------------------------------------
-- STEP B — Reimport all 10 CSVs via pgAdmin
--   Right-click each table -> Import/Export Data -> Import
--   Header: ON   Encoding: UTF8   Format: csv
--   (goals.half is already TEXT, so ET-1/ET-2 load fine)
--
--   >>> Do the imports now, then continue with STEP C below. <<<
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- STEP C — Row-count check (run after importing)
-- ------------------------------------------------------------
SELECT 'teams'        AS table_name, COUNT(*) AS actual, 48   AS expected FROM teams
UNION ALL SELECT 'venues',       COUNT(*), 16   FROM venues
UNION ALL SELECT 'players',      COUNT(*), 1260 FROM players
UNION ALL SELECT 'matches',      COUNT(*), 104  FROM matches
UNION ALL SELECT 'match_stats',  COUNT(*), 208  FROM match_stats
UNION ALL SELECT 'goals',        COUNT(*), 308  FROM goals
UNION ALL SELECT 'attack_stats', COUNT(*), 3287 FROM attack_stats
UNION ALL SELECT 'defencestats', COUNT(*), 3286 FROM defencestats
UNION ALL SELECT 'teamstats',    COUNT(*), 48   FROM teamstats
UNION ALL SELECT 'playersstats', COUNT(*), 1040 FROM playersstats;


-- ------------------------------------------------------------
-- STEP D — Re-apply the data fixes (identical to 02_transform STEP 2)
-- The fixes were verified to still apply to the refreshed data.
-- ------------------------------------------------------------

UPDATE goals   SET match_no  = 64 WHERE goal_no = 188;
UPDATE goals   SET goal_type = INITCAP(goal_type);
UPDATE matches SET stadium   = 'MetLife Stadium' WHERE stadium   = 'Metlife Stadium';
UPDATE matches SET home_team = 'Türkiye'         WHERE home_team = 'Turkiye';
UPDATE matches SET away_team = 'Türkiye'         WHERE away_team = 'Turkiye';
UPDATE matches SET winner    = 'Türkiye'         WHERE winner    = 'Turkiye';


-- ------------------------------------------------------------
-- STEP E — Verify everything (all checks must pass)
-- ------------------------------------------------------------

-- 1. Encoding intact -> must return 'Türkiye'
SELECT team_name FROM teams WHERE team_name LIKE 'T%rkiye';

-- 2. player_key unique -> must return 1260 / 1260
SELECT COUNT(*) AS row_count, COUNT(DISTINCT player_key) AS unique_keys FROM dim_players;

-- 3. fact_player_match grain -> expected 3288
--    3285 pairs in both files + Tahith Chong (m35) + both Edersons (m31)
SELECT COUNT(*) AS row_count FROM fact_player_match;

-- 4. Team-match facts -> must return 208 / 0
SELECT COUNT(*) AS row_count,
       COUNT(*) FILTER (WHERE possession IS NULL) AS unmatched
FROM fact_team_match;

-- 5. Match dimension -> must return 104 / 104
SELECT COUNT(*) AS row_count, COUNT(DISTINCT match_no) AS distinct_matches
FROM dim_matches;

-- 6. Goal facts -> must return 308 / 0
SELECT COUNT(*) AS row_count,
       COUNT(*) FILTER (WHERE scorer_key NOT IN (SELECT player_key FROM dim_players)) AS orphan_scorers
FROM fact_goals;

-- 7. All foreign keys resolve -> all four counts must be 0
SELECT
    (SELECT COUNT(*) FROM fact_team_match   f WHERE f.match_no   NOT IN (SELECT match_no     FROM dim_matches)) AS ftm_bad_match,
    (SELECT COUNT(*) FROM fact_player_match f WHERE f.match_no   NOT IN (SELECT match_no     FROM dim_matches)) AS fpm_bad_match,
    (SELECT COUNT(*) FROM fact_player_match f WHERE f.player_key NOT IN (SELECT player_key   FROM dim_players)) AS fpm_bad_player,
    (SELECT COUNT(*) FROM dim_matches       d WHERE d.stadium    NOT IN (SELECT stadium_name FROM venues))      AS dim_bad_venue;
