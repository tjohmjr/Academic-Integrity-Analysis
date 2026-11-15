DROP VIEW IF EXISTS v_student_risk;
CREATE VIEW v_student_risk AS
WITH ring_size AS (
  SELECT ring_id, COUNT(*) AS ring_members FROM student_ring GROUP BY ring_id
),
acc AS (
  SELECT student_id, COUNT(*) AS times_accused, SUM(outcome = 'Upheld') AS upheld
  FROM accusations GROUP BY student_id
),
base AS (
  SELECT d.student_id, d.major, d.class_year, d.gpa,
         d.out_degree, d.in_degree, d.total_degree, d.weighted_degree,
         r.ring_id, rs.ring_members,
         c.local_clustering,
         COALESCE(a.times_accused, 0) AS times_accused,
         COALESCE(a.upheld, 0) AS upheld_accusations
  FROM student_degree d
  JOIN student_ring r       ON r.student_id = d.student_id
  JOIN ring_size rs         ON rs.ring_id = r.ring_id
  JOIN student_clustering c ON c.student_id = d.student_id
  LEFT JOIN acc a           ON a.student_id = d.student_id
),
scored AS (
  SELECT b.*,
         ROUND(100 * (0.40 * PERCENT_RANK() OVER (ORDER BY total_degree)
                    + 0.25 * PERCENT_RANK() OVER (ORDER BY weighted_degree / MAX(total_degree, 1))
                    + 0.20 * PERCENT_RANK() OVER (ORDER BY ring_members)
                    + 0.15 * PERCENT_RANK() OVER (ORDER BY upheld_accusations)), 1) AS risk_score
  FROM base b
)
SELECT s.*,
       NTILE(5) OVER (ORDER BY risk_score DESC) AS risk_quintile,
       CASE WHEN risk_score >= 70 THEN 'High'
            WHEN risk_score >= 40 THEN 'Medium'
            ELSE 'Low' END AS risk_tier
FROM scored s;

SELECT student_id, major, class_year, gpa, total_degree, ring_members,
       times_accused, upheld_accusations, risk_score, risk_tier
FROM v_student_risk ORDER BY risk_score DESC LIMIT 15;

SELECT risk_tier, COUNT(*) AS students, ROUND(AVG(gpa), 2) AS avg_gpa,
       ROUND(AVG(total_degree), 2) AS avg_links
FROM v_student_risk GROUP BY risk_tier
ORDER BY CASE risk_tier WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;

DROP VIEW IF EXISTS v_edges_enriched;
CREATE VIEW v_edges_enriched AS
SELECT e.edge_id, e.source_id, e.target_id, e.edge_type, e.confidence, e.observed_at,
       s1.major AS source_major, s1.class_year AS source_year,
       s2.major AS target_major, s2.class_year AS target_year,
       r.ring_id,
       EXISTS (SELECT 1 FROM cheating_edges x
               WHERE x.source_id = e.target_id AND x.target_id = e.source_id) AS is_mutual
FROM cheating_edges e
JOIN students s1 ON s1.student_id = e.source_id
JOIN students s2 ON s2.student_id = e.target_id
JOIN student_ring r ON r.student_id = e.source_id;

DROP VIEW IF EXISTS v_detector_tool_summary;
CREATE VIEW v_detector_tool_summary AS
SELECT tool, tp, fp, tn, fn,
       1.0 * tp / (tp + fp) AS precision_,
       1.0 * tp / (tp + fn) AS recall,
       1.0 * fp / (fp + tn) AS false_positive_rate,
       2.0 * tp / (2 * tp + fp + fn) AS f1
FROM v_detector_confusion;

DROP VIEW IF EXISTS v_violations_monthly;
CREATE VIEW v_violations_monthly AS
SELECT strftime('%Y-%m-01', violation_date) AS month_start, violation_type, severity,
       COUNT(*) AS violations, AVG(investigation_days) AS avg_investigation_days,
       AVG(appealed) AS appeal_rate
FROM honor_code_violations
GROUP BY month_start, violation_type, severity;

SELECT * FROM v_student_risk
WHERE student_id = 'S102';  

SELECT 'outgoing' AS direction, target_id AS other_student, edge_type,
       ROUND(confidence, 3) AS confidence, observed_at
FROM cheating_edges WHERE source_id = 'S102'
UNION ALL
SELECT 'incoming', source_id, edge_type, ROUND(confidence, 3), observed_at
FROM cheating_edges WHERE target_id = 'S102' 
ORDER BY observed_at;

SELECT 'accused' AS role, cascade_id, cascade_level, accused_by AS other_student,
       ROUND(evidence_strength, 3) AS evidence, outcome, sanction_level, accused_at
FROM accusations WHERE student_id = 'S102'  
UNION ALL
SELECT 'accuser', cascade_id, cascade_level, student_id,
       ROUND(evidence_strength, 3), outcome, sanction_level, accused_at
FROM accusations WHERE accused_by = 'S102'  
ORDER BY accused_at;

WITH RECURSIVE p (a, b) AS (
  SELECT 'S167', 'S194'
),
walk (node, hops, path) AS (
  SELECT p.a, 0, p.a FROM p
  UNION ALL
  SELECT u.b, w.hops + 1, w.path || ' - ' || u.b
  FROM walk w
  CROSS JOIN p
  JOIN undirected_edges u ON u.a = w.node
  JOIN network_distance d_next ON d_next.origin = u.b AND d_next.member = p.b
  JOIN network_distance d_here ON d_here.origin = w.node AND d_here.member = p.b
  WHERE d_next.hops = d_here.hops - 1
),
found AS (
  SELECT w.hops, w.path FROM walk w JOIN p ON w.node = p.b ORDER BY w.path LIMIT 1
)
SELECT p.a AS from_student, p.b AS to_student, f.hops, f.path
FROM p JOIN found f
UNION ALL
SELECT p.a, p.b, NULL, 'No path: these students are in different rings'
FROM p WHERE NOT EXISTS (SELECT 1 FROM found);

WITH p (tool, th) AS (
  SELECT 'GPTZero', 0.30
)
SELECT p.tool AS tool, p.th AS threshold,
       SUM(d.actual_type = 'ai_generated'  AND d.detection_probability >= p.th) AS tp,
       SUM(d.actual_type = 'human_written' AND d.detection_probability >= p.th) AS fp,
       SUM(d.actual_type = 'human_written' AND d.detection_probability <  p.th) AS tn,
       SUM(d.actual_type = 'ai_generated'  AND d.detection_probability <  p.th) AS fn,
       ROUND(100 * AVG(CASE WHEN d.actual_type = 'mixed'
                            THEN d.detection_probability >= p.th END), 1) AS pct_mixed_flagged
FROM detector_results d JOIN p ON d.tool = p.tool;
