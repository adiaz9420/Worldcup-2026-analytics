-- ============================================================
--  FIFA WORLD CUP — Historical benchmarks (1930-2022)
--
--  Source: FIFA World Cup historical dataset (Kaggle), aggregated
--  from its matches.csv and world_cups.csv. Figures are pre-computed
--  here rather than loaded raw because only tournament-level
--  aggregates are needed for comparison.
--
--  Purpose: give the 2026 KPIs context. A figure like "2.96 goals
--  per match" means nothing on its own — against this table it
--  becomes "the highest since 1970".
-- ============================================================

DROP TABLE IF EXISTS wc_benchmarks;

CREATE TABLE wc_benchmarks (
    year             INT PRIMARY KEY,
    host_country     TEXT,
    champion         TEXT,
    teams            INT,
    matches          INT,
    goals            INT,
    goals_per_match  NUMERIC(5,3),
    draw_pct         NUMERIC(5,4)
);

INSERT INTO wc_benchmarks VALUES
    (1930, 'Uruguay', 'Uruguay', 13, 18, 70, 3.889, 0.0),
    (1934, 'Italy', 'Italy', 16, 17, 70, 4.118, 0.0588),
    (1938, 'France', 'Italy', 15, 18, 84, 4.667, 0.1667),
    (1950, 'Brazil', 'Uruguay', 13, 22, 88, 4.0, 0.1364),
    (1954, 'Switzerland', 'West Germany', 16, 26, 140, 5.385, 0.0769),
    (1958, 'Sweden', 'Brazil', 16, 35, 126, 3.6, 0.2857),
    (1962, 'Chile', 'Brazil', 16, 32, 89, 2.781, 0.1562),
    (1966, 'England', 'England', 16, 32, 89, 2.781, 0.1562),
    (1970, 'Mexico', 'Brazil', 16, 32, 95, 2.969, 0.1562),
    (1974, 'West Germany', 'West Germany', 16, 38, 97, 2.553, 0.2632),
    (1978, 'Argentina', 'Argentina', 16, 38, 102, 2.684, 0.2368),
    (1982, 'Spain', 'Italy', 24, 52, 146, 2.808, 0.3077),
    (1986, 'Mexico', 'Argentina', 24, 52, 132, 2.538, 0.2115),
    (1990, 'Italy', 'West Germany', 24, 52, 115, 2.212, 0.1538),
    (1994, 'United States', 'Brazil', 24, 52, 141, 2.712, 0.1538),
    (1998, 'France', 'France', 32, 64, 171, 2.672, 0.25),
    (2002, 'Korea, Japan', 'Brazil', 32, 64, 161, 2.516, 0.2188),
    (2006, 'Germany', 'Italy', 32, 64, 147, 2.297, 0.1719),
    (2010, 'South Africa', 'Spain', 32, 64, 145, 2.266, 0.2188),
    (2014, 'Brazil', 'Germany', 32, 64, 171, 2.672, 0.1406),
    (2018, 'Russia', 'France', 32, 64, 169, 2.641, 0.1406),
    (2022, 'Qatar', 'Argentina', 32, 64, 172, 2.688, 0.1562);


-- ------------------------------------------------------------
-- Key comparisons for the 2026 dashboard
-- ------------------------------------------------------------

-- 2026 recorded 2.96 goals per match. Where does that rank?
SELECT year, host_country, goals_per_match
FROM wc_benchmarks
WHERE goals_per_match >= 2.96
ORDER BY year DESC;
-- Last tournament to reach it: 1970 (2.969)

-- Modern-era baseline (32-team format, 1998-2022)
SELECT ROUND(SUM(goals)::numeric / SUM(matches), 2) AS goals_per_match,
       ROUND(SUM(matches * draw_pct) / SUM(matches), 3) AS draw_pct
FROM wc_benchmarks
WHERE teams = 32;
-- 2.54 goals per match, 18.6% draws

-- All-time baseline
SELECT ROUND(SUM(goals)::numeric / SUM(matches), 2) AS goals_per_match
FROM wc_benchmarks;
-- 2.82
