-- ============================================================
--  FIFA WORLD CUP 2026 — Cleaning & Modelling
--  Run AFTER loading all 10 CSV files.
--  Execute block by block, not all at once.
--
--  Row counts below reflect the FINAL (post-tournament) dataset,
--  the same one validated in 04_reload.sql.
-- ============================================================


-- ------------------------------------------------------------
-- STEP 0 — Load validation
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

-- Encoding check: must return 'Türkiye', not 'TÃ¼rkiye'
SELECT team_name FROM teams WHERE team_name LIKE 'T%rkiye';


-- ------------------------------------------------------------
-- STEP 1 — Name normalisation helper
--
-- Player names are the only join key between goals, players,
-- attack_stats and defencestats, and they are inconsistently
-- accented across files:
--   goals.csv        -> 'Julián Quiñones'
--   players.csv      -> 'Julian Quinones'
--   attack_stats.csv -> 'Ruben Vargas'
--   defencestats.csv -> 'Rubén Vargas'
--
-- Accent-stripping alone is the correct scope. Do NOT add aliases to
-- merge names that merely look similar: Brazil has TWO distinct players,
-- 'Ederson' (goalkeeper, 32) and 'Ederson Moraes' (midfielder, 26).
-- Merging them breaks player_key uniqueness and turns every dim_players
-- relationship in Power BI into many-to-many.
--
-- CAUTION: nkey() COALESCEs NULL to ''. It never returns NULL. Any
-- COALESCE() over two nkey() calls must wrap each in NULLIF(..., '')
-- or the empty string wins and produces an invalid key. See
-- fact_player_match and fact_goals.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION nkey(txt TEXT) RETURNS TEXT AS $$
    SELECT UPPER(TRIM(unaccent(COALESCE(txt, ''))));
$$ LANGUAGE sql IMMUTABLE;

-- All three must return 'JULIAN QUINONES'
SELECT nkey('Julián Quiñones'), nkey('Julian Quinones'), nkey('  julián quiñones  ');

-- Must return FALSE — these are two different players
SELECT nkey('Ederson Moraes') = nkey('Ederson') AS wrongly_merged;


-- ------------------------------------------------------------
-- STEP 2 — Data fixes
-- ------------------------------------------------------------

-- 2a. Goal #188 (Álex Baena, min 42) is tagged to match 62
--     (Senegal 5-0 Iraq) but belongs to match 64 (Uruguay 0-1 Spain),
--     which otherwise has zero goals recorded.
UPDATE goals SET match_no = 64 WHERE goal_no = 188;

-- 2b. Case-duplicated categories: 'Own goal'/'Own Goal', 'Free kick'/'Free Kick'
UPDATE goals SET goal_type = INITCAP(goal_type);

-- 2c. Inconsistent stadium and country names
UPDATE matches SET stadium   = 'MetLife Stadium' WHERE stadium   = 'Metlife Stadium';
UPDATE matches SET home_team = 'Türkiye'         WHERE home_team = 'Turkiye';
UPDATE matches SET away_team = 'Türkiye'         WHERE away_team = 'Turkiye';
UPDATE matches SET winner    = 'Türkiye'         WHERE winner    = 'Turkiye';

-- 2d. Verify the fixes — all three must return 0 rows
SELECT * FROM goals   WHERE goal_type IN ('Own goal', 'Free kick');
SELECT * FROM matches WHERE stadium NOT IN (SELECT stadium_name FROM venues);
SELECT * FROM matches WHERE home_team NOT IN (SELECT team_name FROM teams)
                         OR away_team NOT IN (SELECT team_name FROM teams);


-- ------------------------------------------------------------
-- STEP 3 — Modelled views
-- ------------------------------------------------------------

-- Players with a stable join key.
-- playing_role holds 'Goalkeeper' | 'Defender' | 'Midfielder' | 'Forward'
-- and is complete: 148 + 403 + 338 + 371 = 1260. No NULLs, no blanks.
CREATE OR REPLACE VIEW dim_players AS
SELECT
    player_id,
    player_name,
    nkey(player_name) AS player_key,   -- <<< use THIS for every join
    player_age,
    playing_role,
    team_name
FROM players;

-- Must return 1260 / 1260. A lower unique count means distinct players
-- are being collapsed and the Power BI model will break.
SELECT COUNT(*) AS row_count, COUNT(DISTINCT player_key) AS unique_keys
FROM dim_players;


-- Attack + defence merged (same grain: player x match).
-- FULL OUTER JOIN because three player-match rows exist on one side only.
--
-- NULLIF is REQUIRED on both nkey() calls below. nkey(NULL) returns ''
-- (empty string), not NULL, so a plain COALESCE(nkey(a.x), nkey(d.x))
-- always resolves to the attack side. For defence-only rows that yields
-- an empty player_key that matches no player, and Power BI groups those
-- rows under (Blank) in every player-level visual.
CREATE OR REPLACE VIEW fact_player_match AS
SELECT
    COALESCE(NULLIF(nkey(a.player_name), ''),
             NULLIF(nkey(d.player_name), ''))          AS player_key,
    COALESCE(a.team_name, d.team_name)                 AS team_name,
    COALESCE(a.match_no,  d.match_no)                  AS match_no,
    COALESCE(a.goals, 0)           AS goals,
    COALESCE(a.assists, 0)         AS assists,
    COALESCE(a.xg, 0)              AS xg,
    COALESCE(a.dribbles, 0)        AS dribbles,
    COALESCE(a.chances_created, 0) AS chances_created,
    COALESCE(d.tackles, 0)         AS tackles,
    COALESCE(d.recoveries, 0)      AS recoveries,
    COALESCE(d.gk_saves, 0)        AS gk_saves
FROM attack_stats a
FULL OUTER JOIN defencestats d
  ON nkey(a.player_name) = nkey(d.player_name)
 AND a.match_no = d.match_no;

-- Expected: 3288 rows.
--   3285 player-match pairs present in both tables
-- +    1 Tahith Chong (match 35), missing from defencestats
-- +    2 the two Edersons (match 31), each present on one side only
-- All metrics on those three rows are 0, so no KPI is affected.
SELECT COUNT(*) AS row_count FROM fact_player_match;

-- Must return 0. A non-zero result means some player_key does not
-- resolve against dim_players — the (Blank) bug described above.
SELECT COUNT(*) AS orphan_players
FROM fact_player_match f
WHERE f.player_key NOT IN (SELECT player_key FROM dim_players);


-- Team-level match facts in long format: one row per team per match (208 rows).
--
-- match_stats shares this exact grain (match_no + team), so it is merged in
-- here rather than left as a separate table. Power BI cannot build
-- relationships on composite keys, so two tables at the same grain would be
-- unusable side by side.
--
-- Two different notions of "result" are kept separate:
--   outcome    -> the match result on goals ('Win'/'Draw'/'Loss')
--   advanced   -> who progressed, which differs in the penalty shootouts
--                 (e.g. match 75: Germany 1-1 Paraguay, Paraguay advanced)
-- points is only meaningful for Group Stage rows.
CREATE OR REPLACE VIEW fact_team_match AS
WITH long_results AS (
    SELECT match_no, match_type, group_name,
           home_team AS team, away_team AS opponent,
           htg AS goals_for, atg AS goals_against,
           TRUE AS is_home, winner, stadium, city, referee, result_in
    FROM matches
    UNION ALL
    SELECT match_no, match_type, group_name,
           away_team, home_team,
           atg, htg,
           FALSE, winner, stadium, city, referee, result_in
    FROM matches
)
SELECT
    r.match_no,
    r.match_type,
    r.group_name,
    r.team,
    r.opponent,
    r.goals_for,
    r.goals_against,
    r.goals_for - r.goals_against AS goal_diff,
    CASE WHEN r.goals_for >  r.goals_against THEN 'Win'
         WHEN r.goals_for =  r.goals_against THEN 'Draw'
         ELSE 'Loss'
    END AS outcome,
    CASE WHEN r.goals_for >  r.goals_against THEN 3
         WHEN r.goals_for =  r.goals_against THEN 1
         ELSE 0
    END AS points,
    (r.winner = r.team) AS advanced,
    r.is_home,
    r.stadium,
    r.city,
    r.referee,
    r.result_in,
    ms.possession,
    ms.xg,
    ms.shots,
    ms.on_target,
    ms.bcm,
    ms.yellow_c,
    ms.red_c,
    ms.fouls
FROM long_results r
LEFT JOIN match_stats ms
       ON ms.match_no = r.match_no
      AND ms.team     = r.team;

-- Must return 208 rows with 0 nulls in possession.
-- A null here means the matches/match_stats team names disagree
-- (this is what the Türkiye fix in step 2c prevents).
SELECT COUNT(*) AS row_count,
       COUNT(*) FILTER (WHERE possession IS NULL) AS unmatched
FROM fact_team_match;


-- ------------------------------------------------------------
-- STEP 4 — Validation against pre-aggregated sources
-- Both queries must return 0 rows.
-- ------------------------------------------------------------

-- Does match_stats aggregate to teamstats?
SELECT ms.team, SUM(ms.shots) AS computed, ts.shots AS official
FROM match_stats ms
JOIN teamstats ts ON ts.team = ms.team
GROUP BY ms.team, ts.shots
HAVING SUM(ms.shots) <> ts.shots;

-- Does fact_player_match aggregate to playersstats?
SELECT ps.player, SUM(f.goals) AS computed, ps.goals AS official
FROM fact_player_match f
JOIN playersstats ps ON nkey(ps.player) = f.player_key
GROUP BY ps.player, ps.goals
HAVING SUM(f.goals) <> ps.goals;
