DROP TABLE IF EXISTS undirected_edges;
CREATE TABLE undirected_edges (
  a TEXT, b TEXT,
  PRIMARY KEY (a, b)
);
INSERT OR IGNORE INTO undirected_edges
SELECT source_id, target_id FROM cheating_edges
UNION
SELECT target_id, source_id FROM cheating_edges;

DROP TABLE IF EXISTS student_degree;
CREATE TABLE student_degree AS
SELECT s.student_id, s.major, s.class_year, s.gpa,
       COALESCE(o.out_deg, 0)                         AS out_degree,
       COALESCE(i.in_deg, 0)                          AS in_degree,
       COALESCE(o.out_deg, 0) + COALESCE(i.in_deg, 0) AS total_degree,
       COALESCE(o.out_conf, 0) + COALESCE(i.in_conf, 0) AS weighted_degree,
       (SELECT COUNT(*) FROM undirected_edges u WHERE u.a = s.student_id) AS distinct_neighbors
FROM students s
LEFT JOIN (SELECT source_id, COUNT(*) AS out_deg, SUM(confidence) AS out_conf
           FROM cheating_edges GROUP BY source_id) o ON o.source_id = s.student_id
LEFT JOIN (SELECT target_id, COUNT(*) AS in_deg, SUM(confidence) AS in_conf
           FROM cheating_edges GROUP BY target_id) i ON i.target_id = s.student_id;
CREATE UNIQUE INDEX ux_student_degree ON student_degree (student_id);

SELECT 'num_nodes' AS metric,
       (SELECT COUNT(*) FROM students) AS computed,
       (SELECT CAST(num_nodes AS INTEGER) FROM c_network_metrics) AS published
UNION ALL
SELECT 'num_edges', (SELECT COUNT(*) FROM cheating_edges),
       (SELECT CAST(num_edges AS INTEGER) FROM c_network_metrics)
UNION ALL
SELECT 'density (directed: E / (N*(N-1)))',
       ROUND(1.0 * (SELECT COUNT(*) FROM cheating_edges)
             / ((SELECT COUNT(*) FROM students) * ((SELECT COUNT(*) FROM students) - 1)), 6),
       ROUND((SELECT CAST(density AS REAL) FROM c_network_metrics), 6)
UNION ALL
SELECT 'max_in_degree', (SELECT MAX(in_degree) FROM student_degree),
       (SELECT CAST(max_in_degree AS INTEGER) FROM c_network_metrics)
UNION ALL
SELECT 'max_out_degree', (SELECT MAX(out_degree) FROM student_degree),
       (SELECT CAST(max_out_degree AS INTEGER) FROM c_network_metrics);

SELECT student_id, major, class_year, gpa, out_degree, in_degree, total_degree,
       ROUND(weighted_degree, 3) AS weighted_degree,
       RANK() OVER (ORDER BY total_degree DESC) AS degree_rank,
       ROUND(PERCENT_RANK() OVER (ORDER BY weighted_degree), 3) AS weighted_pctile,
       CASE WHEN out_degree >= 2 * MAX(in_degree, 1) THEN 'Supplier (mostly gives)'
            WHEN in_degree  >= 2 * MAX(out_degree, 1) THEN 'Consumer (mostly receives)'
            ELSE 'Two-way trader' END AS role
FROM student_degree
WHERE total_degree > 0
ORDER BY total_degree DESC, weighted_degree DESC
LIMIT 15;

SELECT total_degree, COUNT(*) AS students,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_students,
       SUM(COUNT(*)) OVER (ORDER BY total_degree DESC) AS cumulative_students
FROM student_degree GROUP BY total_degree ORDER BY total_degree DESC;

WITH pairs AS (
  SELECT DISTINCT MIN(source_id, target_id) AS s1, MAX(source_id, target_id) AS s2,
         EXISTS (SELECT 1 FROM cheating_edges r
                 WHERE r.source_id = e.target_id AND r.target_id = e.source_id) AS mutual
  FROM cheating_edges e
)
SELECT COUNT(*)                         AS connected_pairs,
       SUM(mutual)                      AS mutual_pairs,
       SUM(1 - mutual)                  AS one_way_pairs,
       ROUND(100.0 * SUM(mutual) / COUNT(*), 1) AS pct_pairs_mutual
FROM pairs;

SELECT e.edge_type,
       COUNT(*) AS edges,
       SUM(EXISTS (SELECT 1 FROM cheating_edges r
                   WHERE r.source_id = e.target_id AND r.target_id = e.source_id)) AS reciprocated,
       ROUND(AVG(e.confidence), 3) AS avg_confidence
FROM cheating_edges e GROUP BY e.edge_type ORDER BY edges DESC;

DROP TABLE IF EXISTS student_ring;
CREATE TABLE student_ring AS
WITH RECURSIVE reach (origin, member) AS (
  SELECT student_id, student_id FROM students
  UNION                                  
  SELECT r.origin, u.b
  FROM reach r JOIN undirected_edges u ON u.a = r.member
)
SELECT origin AS student_id, MIN(member) AS ring_id
FROM reach GROUP BY origin;
CREATE UNIQUE INDEX ux_student_ring ON student_ring (student_id);
CREATE INDEX ix_student_ring ON student_ring (ring_id);

WITH ring_edges AS (
  SELECT r.ring_id, e.source_id, e.target_id, e.edge_type, e.confidence
  FROM cheating_edges e JOIN student_ring r ON r.student_id = e.source_id
),
ring_stats AS (
  SELECT r.ring_id,
         COUNT(*) AS members,
         COUNT(DISTINCT s.major) AS majors_involved,
         ROUND(AVG(s.gpa), 2) AS avg_gpa
  FROM student_ring r JOIN students s USING (student_id)
  GROUP BY r.ring_id
),
ring_type AS (
  SELECT ring_id, edge_type, COUNT(*) AS n,
         ROW_NUMBER() OVER (PARTITION BY ring_id ORDER BY COUNT(*) DESC, edge_type) AS rn
  FROM ring_edges GROUP BY ring_id, edge_type
)
SELECT rs.ring_id, rs.members,
       (SELECT COUNT(*) FROM ring_edges re WHERE re.ring_id = rs.ring_id) AS links,
       ROUND(1.0 * (SELECT COUNT(*) FROM ring_edges re WHERE re.ring_id = rs.ring_id)
             / (rs.members * (rs.members - 1)), 3) AS internal_density,
       (SELECT ROUND(AVG(confidence), 3) FROM ring_edges re WHERE re.ring_id = rs.ring_id) AS avg_confidence,
       rt.edge_type AS dominant_type,
       rs.majors_involved, rs.avg_gpa,
       DENSE_RANK() OVER (ORDER BY rs.members DESC) AS size_rank
FROM ring_stats rs
LEFT JOIN ring_type rt ON rt.ring_id = rs.ring_id AND rt.rn = 1
WHERE rs.members > 1
ORDER BY rs.members DESC, links DESC
LIMIT 15;

SELECT CASE WHEN members = 1 THEN 'Isolated (no links)'
            WHEN members = 2 THEN 'Pair'
            WHEN members <= 5 THEN 'Small ring (3-5)'
            ELSE 'Large ring (6+)' END AS ring_size_band,
       COUNT(*) AS rings, SUM(members) AS students
FROM (SELECT ring_id, COUNT(*) AS members FROM student_ring GROUP BY ring_id) x
GROUP BY ring_size_band ORDER BY MIN(members);

DROP TABLE IF EXISTS directed_reach;
CREATE TABLE directed_reach AS
WITH RECURSIVE reach (origin, member) AS (
  SELECT student_id, student_id FROM students
  UNION
  SELECT r.origin, e.target_id
  FROM reach r JOIN cheating_edges e ON e.source_id = r.member
)
SELECT origin, member FROM reach;
CREATE UNIQUE INDEX ux_directed_reach ON directed_reach (origin, member);

DROP TABLE IF EXISTS student_scc;
CREATE TABLE student_scc AS
SELECT a.origin AS student_id, MIN(a.member) AS scc_id
FROM directed_reach a
JOIN directed_reach b ON b.origin = a.member AND b.member = a.origin
GROUP BY a.origin;
CREATE UNIQUE INDEX ux_student_scc ON student_scc (student_id);

SELECT 'strongly connected components' AS metric,
       COUNT(DISTINCT scc_id) AS computed,
       (SELECT CAST(num_strongly_connected AS INTEGER) FROM c_network_metrics) AS published
FROM student_scc;

SELECT scc_id, COUNT(*) AS members,
       GROUP_CONCAT(student_id, ', ') AS students
FROM (SELECT scc_id, student_id FROM student_scc ORDER BY student_id)
GROUP BY scc_id HAVING COUNT(*) > 1
ORDER BY members DESC;

SELECT origin AS student_id, COUNT(*) - 1 AS downstream_students,
       RANK() OVER (ORDER BY COUNT(*) DESC) AS influence_rank
FROM directed_reach GROUP BY origin
ORDER BY downstream_students DESC LIMIT 10;

DROP TABLE IF EXISTS student_clustering;
CREATE TABLE student_clustering AS
SELECT d.student_id, d.distinct_neighbors AS k,
       COALESCE(t.tri, 0) AS triangles,
       CASE WHEN d.distinct_neighbors < 2 THEN 0.0
            ELSE COALESCE(t.tri, 0) / (d.distinct_neighbors * (d.distinct_neighbors - 1) / 2.0)
       END AS local_clustering
FROM student_degree d
LEFT JOIN (
  SELECT u1.a AS student_id, COUNT(*) / 2 AS tri   
  FROM undirected_edges u1
  JOIN undirected_edges u2 ON u2.a = u1.a AND u2.b <> u1.b
  JOIN undirected_edges u3 ON u3.a = u1.b AND u3.b = u2.b
  GROUP BY u1.a
) t ON t.student_id = d.student_id;
CREATE UNIQUE INDEX ux_student_clustering ON student_clustering (student_id);

SELECT 'average clustering (undirected)' AS metric,
       ROUND(AVG(local_clustering), 4) AS computed,
       ROUND((SELECT CAST(avg_clustering AS REAL) FROM c_network_metrics), 4) AS published,
       (SELECT SUM(triangles) / 3 FROM student_clustering) AS total_triangles
FROM student_clustering;

SELECT DISTINCT u1.a AS student_1, u1.b AS student_2, u2.b AS student_3
FROM undirected_edges u1
JOIN undirected_edges u2 ON u2.a = u1.a AND u2.b > u1.b
JOIN undirected_edges u3 ON u3.a = u1.b AND u3.b = u2.b
WHERE u1.a < u1.b
ORDER BY student_1;

SELECT s1.major AS source_major, s2.major AS target_major, COUNT(*) AS links,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY s1.major), 1) AS pct_of_source_major
FROM cheating_edges e
JOIN students s1 ON s1.student_id = e.source_id
JOIN students s2 ON s2.student_id = e.target_id
GROUP BY s1.major, s2.major
ORDER BY s1.major, links DESC;

SELECT SUM(s1.major = s2.major) AS same_major_links,
       SUM(s1.major <> s2.major) AS cross_major_links,
       SUM(s1.class_year < s2.class_year) AS older_to_younger,
       SUM(s1.class_year > s2.class_year) AS younger_to_older,
       SUM(s1.class_year = s2.class_year) AS same_year,
       -- Expected same-major share if links were random
       ROUND(100 * (SELECT SUM((1.0 * cnt / (SELECT COUNT(*) FROM students))
                             * (1.0 * cnt / (SELECT COUNT(*) FROM students)))
                    FROM (SELECT COUNT(*) AS cnt FROM students GROUP BY major) m), 1) AS pct_same_major_if_random,
       ROUND(100 * AVG(s1.major = s2.major), 1) AS pct_same_major_actual
FROM cheating_edges e
JOIN students s1 ON s1.student_id = e.source_id
JOIN students s2 ON s2.student_id = e.target_id;

SELECT u.a AS student_id, s.major AS own_major,
       COUNT(*) AS neighbors,
       COUNT(DISTINCT n.major) AS neighbor_majors,
       SUM(n.major <> s.major) AS cross_major_neighbors
FROM undirected_edges u
JOIN students s ON s.student_id = u.a
JOIN students n ON n.student_id = u.b
GROUP BY u.a, s.major
HAVING COUNT(DISTINCT n.major) >= 3
ORDER BY neighbor_majors DESC, neighbors DESC
LIMIT 10;

SELECT CASE WHEN total_degree = 0 THEN '0 links'
            WHEN total_degree <= 2 THEN '1-2 links'
            WHEN total_degree <= 4 THEN '3-4 links'
            ELSE '5+ links' END AS activity_band,
       COUNT(*) AS students,
       ROUND(AVG(gpa), 3) AS avg_gpa,
       ROUND(SQRT((SUM(gpa * gpa) - SUM(gpa) * SUM(gpa) / COUNT(*)) / (COUNT(*) - 1)), 3) AS sd_gpa
FROM student_degree
GROUP BY activity_band ORDER BY MIN(total_degree);

WITH monthly AS (
  SELECT strftime('%Y-%m', observed_at) AS month,
         COUNT(*) AS new_links,
         COUNT(DISTINCT source_id) AS active_sources
  FROM cheating_edges GROUP BY month
)
SELECT month, new_links, active_sources,
       SUM(new_links) OVER (ORDER BY month) AS cumulative_links,
       ROUND(AVG(new_links) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS rolling_3mo_avg,
       new_links - LAG(new_links) OVER (ORDER BY month) AS change_vs_prior_month
FROM monthly ORDER BY month;

SELECT r.ring_id,
       COUNT(*) AS links,
       MIN(e.observed_at) AS first_link,
       MAX(e.observed_at) AS last_link,
       CAST(julianday(date(MAX(e.observed_at))) - julianday(date(MIN(e.observed_at))) AS INTEGER) AS active_days
FROM cheating_edges e JOIN student_ring r ON r.student_id = e.source_id
GROUP BY r.ring_id HAVING COUNT(*) >= 4
ORDER BY links DESC;
