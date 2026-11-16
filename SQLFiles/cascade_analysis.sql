-- =====================================================================
-- cascade_analysis.sql  (SQLite version, run step 4 of 8)
-- Plagiarism accusation cascades: how accusations spread, whether they
-- are backed by real links in the cheating network, and whether the
-- outcomes and sanctions are consistent.
--
-- Note on structure: within a cascade, accused_by almost never equals the
-- previous level accused student, so a cascade is a chain ordered by
-- cascade_level (a wave of accusations), not a parent/child tree.
-- Requires network_analysis.sql to have been run first.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1 Cascade summary
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS cascade_summary;
CREATE TABLE cascade_summary AS
SELECT cascade_id,
       COUNT(*)                         AS accusations,
       MAX(cascade_level) + 1           AS depth,
       COUNT(DISTINCT student_id)       AS distinct_accused,
       COUNT(DISTINCT subject)          AS subjects_spanned,
       MIN(accused_at)                  AS started_at,
       CAST(julianday(date(MAX(accused_at))) - julianday(date(MIN(accused_at))) AS INTEGER) AS duration_days,
       ROUND(AVG(evidence_strength), 3) AS avg_evidence,
       ROUND(AVG(outcome = 'Upheld'), 3)    AS upheld_rate,
       ROUND(AVG(outcome = 'Dismissed'), 3) AS dismissed_rate
FROM accusations GROUP BY cascade_id;
CREATE UNIQUE INDEX ux_cascade_summary ON cascade_summary (cascade_id);

SELECT COUNT(*) AS cascades,
       SUM(accusations) AS total_accusations,
       ROUND(AVG(accusations), 1) AS avg_cascade_size,
       MAX(depth) AS deepest_cascade,
       ROUND(AVG(duration_days), 1) AS avg_duration_days
FROM cascade_summary;

-- Largest cascades with rank and share of all accusations
SELECT cascade_id, accusations, depth, distinct_accused, subjects_spanned,
       duration_days, avg_evidence, upheld_rate,
       RANK() OVER (ORDER BY accusations DESC) AS size_rank,
       ROUND(100.0 * SUM(accusations) OVER (ORDER BY accusations DESC, cascade_id)
             / SUM(accusations) OVER (), 1) AS cumulative_pct_of_accusations
FROM cascade_summary
ORDER BY accusations DESC LIMIT 10;

-- VALIDATION against dataset_summary.txt (50 cascades, 439 accusations,
-- avg size 8.8, Upheld 160 / Dismissed 143)
SELECT outcome, COUNT(*) AS accusations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM accusations GROUP BY outcome ORDER BY accusations DESC;

-- ---------------------------------------------------------------------
-- 5.2 Walk each cascade level by level (recursive CTE)
-- Tracks running upheld count and the path of accused students.
-- ---------------------------------------------------------------------
WITH RECURSIVE lvl AS (
  SELECT cascade_id, cascade_level,
         MIN(student_id) AS student_id,                 -- one row per level
         AVG(evidence_strength) AS evidence,
         MAX(outcome = 'Upheld') AS upheld
  FROM accusations GROUP BY cascade_id, cascade_level
),
walk AS (
  SELECT cascade_id, cascade_level, student_id, evidence,
         upheld AS upheld_so_far,
         student_id AS chain
  FROM lvl WHERE cascade_level = 0
  UNION ALL
  SELECT l.cascade_id, l.cascade_level, l.student_id, l.evidence,
         w.upheld_so_far + l.upheld,
         w.chain || ' > ' || l.student_id
  FROM walk w
  JOIN lvl l ON l.cascade_id = w.cascade_id AND l.cascade_level = w.cascade_level + 1
)
SELECT cascade_id, cascade_level AS final_level, upheld_so_far AS total_upheld, chain
FROM walk w
WHERE cascade_level = (SELECT MAX(cascade_level) FROM accusations a WHERE a.cascade_id = w.cascade_id)
ORDER BY final_level DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- 5.3 Witch-hunt test: does evidence weaken as cascades go deeper,
-- while accusations keep being upheld?
-- ---------------------------------------------------------------------
SELECT CASE WHEN cascade_level = 0 THEN '0 (original)'
            WHEN cascade_level <= 3 THEN '1-3'
            WHEN cascade_level <= 7 THEN '4-7'
            ELSE '8+' END AS level_band,
       COUNT(*) AS accusations,
       ROUND(AVG(evidence_strength), 3) AS avg_evidence,
       ROUND(100 * AVG(outcome = 'Upheld'), 1)    AS pct_upheld,
       ROUND(100 * AVG(outcome = 'Dismissed'), 1) AS pct_dismissed,
       ROUND(AVG(ss.severity_rank), 2) AS avg_sanction_severity
FROM accusations a JOIN sanction_scale ss USING (sanction_level)
GROUP BY level_band ORDER BY MIN(cascade_level);

-- Correlation between level and evidence strength (Pearson r in SQL)
SELECT ROUND(
  (COUNT(*) * SUM(cascade_level * evidence_strength) - SUM(cascade_level) * SUM(evidence_strength))
  / SQRT((COUNT(*) * SUM(cascade_level * cascade_level) - SUM(cascade_level) * SUM(cascade_level))
       * (COUNT(*) * SUM(evidence_strength * evidence_strength) - SUM(evidence_strength) * SUM(evidence_strength))), 4)
  AS pearson_r_level_vs_evidence
FROM accusations;

-- ---------------------------------------------------------------------
-- 5.4 Does evidence strength actually predict the outcome?
-- ---------------------------------------------------------------------
WITH decided AS (
  SELECT *, NTILE(5) OVER (ORDER BY evidence_strength) AS evidence_quintile
  FROM accusations WHERE outcome IN ('Upheld', 'Dismissed')
)
SELECT evidence_quintile,
       ROUND(MIN(evidence_strength), 3) AS min_evidence,
       ROUND(MAX(evidence_strength), 3) AS max_evidence,
       COUNT(*) AS decided_cases,
       ROUND(100 * AVG(outcome = 'Upheld'), 1) AS pct_upheld
FROM decided GROUP BY evidence_quintile ORDER BY evidence_quintile;

-- ---------------------------------------------------------------------
-- 5.5 Sanction consistency audit
-- Dismissed cases should carry no sanction, so flag the ones that do.
-- ---------------------------------------------------------------------
SELECT outcome,
       SUM(sanction_level = 'None')       AS none_,
       SUM(sanction_level = 'Warning')    AS warning,
       SUM(sanction_level = 'Probation')  AS probation,
       SUM(sanction_level = 'Suspension') AS suspension,
       SUM(sanction_level = 'Expulsion')  AS expulsion,
       ROUND(AVG(ss.severity_rank), 2)    AS avg_severity
FROM accusations a JOIN sanction_scale ss USING (sanction_level)
GROUP BY outcome
ORDER BY CASE outcome WHEN 'Upheld' THEN 1 WHEN 'Appealed' THEN 2 WHEN 'Pending' THEN 3 ELSE 4 END;

SELECT 'Dismissed but sanctioned' AS issue, COUNT(*) AS cases,
       SUM(sanction_level IN ('Suspension', 'Expulsion')) AS severe_cases
FROM accusations WHERE outcome = 'Dismissed' AND sanction_level <> 'None'
UNION ALL
SELECT 'Upheld with no sanction', COUNT(*), NULL
FROM accusations WHERE outcome = 'Upheld' AND sanction_level = 'None';

-- Is the same evidence punished differently across subjects?
SELECT subject, COUNT(*) AS upheld_cases,
       ROUND(AVG(evidence_strength), 3) AS avg_evidence,
       ROUND(AVG(ss.severity_rank), 2) AS avg_severity,
       ROUND(AVG(ss.severity_rank) - AVG(AVG(ss.severity_rank)) OVER (), 2) AS severity_vs_overall
FROM accusations a JOIN sanction_scale ss USING (sanction_level)
WHERE outcome = 'Upheld'
GROUP BY subject ORDER BY avg_severity DESC;

-- ---------------------------------------------------------------------
-- 5.6 Are accusations backed by the cheating network?
-- All-pairs shortest path on the undirected network, then measure how
-- far each accuser is from the student they accused.
--
-- MySQL needed a stored-procedure BFS here. In SQLite a recursive CTE
-- works: UNION removes duplicate (origin, member, hops) rows and the
-- hops < 40 cap stops walks going round cycles forever (the largest ring
-- has 39 students, so no shortest path is longer than 38 hops).
-- MIN(hops) per pair is then the shortest distance.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS network_distance;
CREATE TABLE network_distance AS
WITH RECURSIVE walk (origin, member, hops) AS (
  SELECT student_id, student_id, 0 FROM students
  UNION
  SELECT w.origin, u.b, w.hops + 1
  FROM walk w JOIN undirected_edges u ON u.a = w.member
  WHERE w.hops < 40
)
SELECT origin, member, MIN(hops) AS hops FROM walk GROUP BY origin, member;
CREATE UNIQUE INDEX ux_network_distance ON network_distance (origin, member);

-- Network diameter / average shortest path inside connected rings
SELECT MAX(hops) AS diameter,
       ROUND(AVG(hops), 3) AS avg_shortest_path_connected_pairs
FROM network_distance WHERE origin <> member;

DROP TABLE IF EXISTS accusation_network_link;
CREATE TABLE accusation_network_link AS
SELECT a.accusation_id, a.cascade_id, a.cascade_level, a.student_id, a.accused_by,
       a.evidence_strength, a.outcome, a.sanction_level,
       nd.hops AS network_hops,
       CASE WHEN a.student_id = a.accused_by THEN 'Self-accusation (data error)'
            WHEN nd.hops = 1 THEN 'Direct cheating link'
            WHEN nd.hops BETWEEN 2 AND 3 THEN 'Same ring, 2-3 hops'
            WHEN nd.hops IS NOT NULL THEN 'Same ring, 4+ hops'
            ELSE 'No network connection' END AS link_category
FROM accusations a
LEFT JOIN network_distance nd ON nd.origin = a.accused_by AND nd.member = a.student_id
                             AND a.student_id <> a.accused_by;
CREATE UNIQUE INDEX ux_accusation_network_link ON accusation_network_link (accusation_id);

SELECT link_category,
       COUNT(*) AS accusations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_accusations,
       ROUND(AVG(evidence_strength), 3) AS avg_evidence,
       ROUND(100 * AVG(outcome = 'Upheld'), 1) AS pct_upheld
FROM accusation_network_link
GROUP BY link_category ORDER BY MIN(COALESCE(network_hops, 99));

-- Are the students who get accused actually active cheaters?
SELECT CASE WHEN d.total_degree = 0 THEN 'Not in network'
            WHEN d.total_degree <= 3 THEN '1-3 links'
            ELSE '4+ links' END AS network_activity,
       COUNT(DISTINCT d.student_id) AS students,
       COUNT(a.accusation_id) AS times_accused,
       ROUND(1.0 * COUNT(a.accusation_id) / COUNT(DISTINCT d.student_id), 2) AS accusations_per_student,
       ROUND(100 * AVG(a.outcome = 'Upheld'), 1) AS pct_upheld
FROM student_degree d
LEFT JOIN accusations a ON a.student_id = d.student_id
GROUP BY network_activity ORDER BY MIN(d.total_degree);

-- ---------------------------------------------------------------------
-- 5.7 Behaviour patterns: serial accusers, most-accused, retaliation,
-- and accused students who go on to accuse others (contagion)
-- ---------------------------------------------------------------------
SELECT accused_by AS accuser, COUNT(*) AS accusations_made,
       COUNT(DISTINCT cascade_id) AS cascades_involved,
       ROUND(100 * AVG(outcome = 'Upheld'), 1) AS pct_upheld,
       ROUND(100 * AVG(outcome = 'Dismissed'), 1) AS pct_dismissed
FROM accusations GROUP BY accused_by
HAVING COUNT(*) >= 5
ORDER BY accusations_made DESC LIMIT 10;

SELECT student_id, COUNT(*) AS times_accused,
       COUNT(DISTINCT accused_by) AS distinct_accusers,
       SUM(outcome = 'Upheld') AS upheld,
       MAX(ss.severity_rank) AS worst_sanction_rank
FROM accusations a JOIN sanction_scale ss USING (sanction_level)
GROUP BY student_id ORDER BY times_accused DESC LIMIT 10;

-- Retaliation: A accused B and B accused A (any cascade)
SELECT a.accused_by AS student_a, a.student_id AS student_b,
       a.accused_at AS a_accused_b_at, b.accused_at AS b_accused_a_at,
       CAST(julianday(b.accused_at) - julianday(a.accused_at) AS INTEGER) AS days_until_counter
FROM accusations a
JOIN accusations b ON b.accused_by = a.student_id AND b.student_id = a.accused_by
WHERE a.accused_at <= b.accused_at AND a.student_id <> a.accused_by;

-- Contagion: accused at one level, then accuses someone deeper in the same cascade
SELECT a.cascade_id, a.student_id, a.cascade_level AS accused_at_level,
       b.cascade_level AS accuses_at_level, b.student_id AS then_accuses
FROM accusations a
JOIN accusations b ON b.cascade_id = a.cascade_id AND b.accused_by = a.student_id
                  AND b.cascade_level > a.cascade_level
ORDER BY a.cascade_id, a.cascade_level;

-- ---------------------------------------------------------------------
-- 5.8 Timing: when do cascades happen and how fast does each level follow?
-- ---------------------------------------------------------------------
SELECT strftime('%Y-%m', accused_at) AS month,
       COUNT(*) AS accusations,
       COUNT(DISTINCT cascade_id) AS active_cascades,
       SUM(COUNT(*)) OVER (ORDER BY strftime('%Y-%m', accused_at)) AS running_total
FROM accusations GROUP BY month ORDER BY month;

WITH by_level AS (
  SELECT cascade_id, cascade_level, MIN(accused_at) AS level_time
  FROM accusations GROUP BY cascade_id, cascade_level
),
gaps AS (
  SELECT CAST(ROUND((julianday(level_time) -
              julianday(LAG(level_time) OVER (PARTITION BY cascade_id ORDER BY cascade_level))) * 24, 4)
              AS INTEGER) AS gap_hours
  FROM by_level
)
SELECT COUNT(*) AS level_transitions,
       ROUND(AVG(CASE WHEN gap_hours >= 0 THEN gap_hours END) / 24.0, 2) AS avg_days_between_levels,
       ROUND(MAX(gap_hours) / 24.0, 2) AS max_days_between_levels,
       SUM(gap_hours = 0) AS same_day_escalations,
       SUM(gap_hours < 0) AS out_of_order_levels   -- deeper level dated BEFORE its parent level: data issue
FROM gaps
WHERE gap_hours IS NOT NULL;
