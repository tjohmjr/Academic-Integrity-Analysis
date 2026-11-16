-- =====================================================================
-- transform.sql  (SQLite version, run step 2 of 8)
-- Staging -> core. Cleans blanks, converts True/False text to 0/1,
-- rounds float word counts, and logs every data-quality issue it finds
-- to data_quality_log.
--
-- Cleaning layer: one c_* view per staging table. Each view trims
-- whitespace and turns empty strings into NULL (replaces the MySQL
-- clean() function, since SQLite has no user-defined SQL functions).
-- =====================================================================

DROP VIEW IF EXISTS c_student_nodes;
CREATE VIEW c_student_nodes AS
SELECT NULLIF(TRIM(student_id), '') AS student_id, NULLIF(TRIM(year), '') AS year,
       NULLIF(TRIM(major), '') AS major, NULLIF(TRIM(gpa), '') AS gpa
FROM stg_student_nodes;

DROP VIEW IF EXISTS c_edges;
CREATE VIEW c_edges AS
SELECT NULLIF(TRIM(source), '') AS source, NULLIF(TRIM(target), '') AS target,
       NULLIF(TRIM(edge_type), '') AS edge_type, NULLIF(TRIM(confidence), '') AS confidence,
       NULLIF(TRIM(ts), '') AS ts, NULLIF(TRIM(source_year), '') AS source_year,
       NULLIF(TRIM(target_year), '') AS target_year, NULLIF(TRIM(source_major), '') AS source_major,
       NULLIF(TRIM(target_major), '') AS target_major
FROM stg_cheating_network_edges;

DROP VIEW IF EXISTS c_cascades;
CREATE VIEW c_cascades AS
SELECT NULLIF(TRIM(cascade_id), '') AS cascade_id, NULLIF(TRIM(student_id), '') AS student_id,
       NULLIF(TRIM(accused_by), '') AS accused_by, NULLIF(TRIM(accusation_date), '') AS accusation_date,
       NULLIF(TRIM(evidence_strength), '') AS evidence_strength, NULLIF(TRIM(outcome), '') AS outcome,
       NULLIF(TRIM(cascade_level), '') AS cascade_level, NULLIF(TRIM(subject), '') AS subject,
       NULLIF(TRIM(sanction_level), '') AS sanction_level
FROM stg_plagiarism_cascades;

DROP VIEW IF EXISTS c_detection;
CREATE VIEW c_detection AS
SELECT NULLIF(TRIM(submission_id), '') AS submission_id, NULLIF(TRIM(tool), '') AS tool,
       NULLIF(TRIM(actual_type), '') AS actual_type, NULLIF(TRIM(detected_as_ai), '') AS detected_as_ai,
       NULLIF(TRIM(confidence_score), '') AS confidence_score, NULLIF(TRIM(text_length), '') AS text_length,
       NULLIF(TRIM(subject), '') AS subject, NULLIF(TRIM(grade_level), '') AS grade_level,
       NULLIF(TRIM(writing_style_score), '') AS writing_style_score,
       NULLIF(TRIM(perplexity_score), '') AS perplexity_score,
       NULLIF(TRIM(detection_probability), '') AS detection_probability
FROM stg_chatgpt_detection_results;

DROP VIEW IF EXISTS c_essays;
CREATE VIEW c_essays AS
SELECT NULLIF(TRIM(submission_id), '') AS submission_id, NULLIF(TRIM(semester), '') AS semester,
       NULLIF(TRIM(assignment_type), '') AS assignment_type, NULLIF(TRIM(is_ai_generated), '') AS is_ai_generated,
       NULLIF(TRIM(ai_probability), '') AS ai_probability, NULLIF(TRIM(word_count), '') AS word_count,
       NULLIF(TRIM(cited_references), '') AS cited_references,
       NULLIF(TRIM(similarity_score), '') AS similarity_score,
       NULLIF(TRIM(submission_date), '') AS submission_date, NULLIF(TRIM(grade), '') AS grade
FROM stg_ai_essay_submissions;

DROP VIEW IF EXISTS c_violations;
CREATE VIEW c_violations AS
SELECT NULLIF(TRIM(violation_date), '') AS violation_date, NULLIF(TRIM(violation_type), '') AS violation_type,
       NULLIF(TRIM(severity), '') AS severity, NULLIF(TRIM(course), '') AS course,
       NULLIF(TRIM(reported_by), '') AS reported_by,
       NULLIF(TRIM(investigation_duration), '') AS investigation_duration,
       NULLIF(TRIM(appealed), '') AS appealed
FROM stg_honor_code_violations;

DROP VIEW IF EXISTS c_design;
CREATE VIEW c_design AS
SELECT NULLIF(TRIM(design_type), '') AS design_type, NULLIF(TRIM(efficacy_score), '') AS efficacy_score,
       NULLIF(TRIM(student_engagement), '') AS student_engagement,
       NULLIF(TRIM(learning_outcome), '') AS learning_outcome,
       NULLIF(TRIM(ai_detection_rate), '') AS ai_detection_rate,
       NULLIF(TRIM(student_satisfaction), '') AS student_satisfaction,
       NULLIF(TRIM(implementation_cost), '') AS implementation_cost,
       NULLIF(TRIM(faculty_workload), '') AS faculty_workload,
       NULLIF(TRIM(class_size), '') AS class_size, NULLIF(TRIM(subject), '') AS subject
FROM stg_assignment_design_efficacy;

DROP VIEW IF EXISTS c_network_metrics;
CREATE VIEW c_network_metrics AS
SELECT NULLIF(TRIM(num_nodes), '') AS num_nodes, NULLIF(TRIM(num_edges), '') AS num_edges,
       NULLIF(TRIM(density), '') AS density, NULLIF(TRIM(avg_clustering), '') AS avg_clustering,
       NULLIF(TRIM(num_strongly_connected), '') AS num_strongly_connected,
       NULLIF(TRIM(max_in_degree), '') AS max_in_degree, NULLIF(TRIM(max_out_degree), '') AS max_out_degree
FROM stg_network_metrics;

DROP VIEW IF EXISTS c_false_positive_rates;
CREATE VIEW c_false_positive_rates AS
SELECT NULLIF(TRIM(tool), '') AS tool, NULLIF(TRIM(detected_as_ai), '') AS detected_as_ai
FROM stg_false_positive_rates;

-- Clear the core tables (children first) so this script can be re-run
DELETE FROM data_quality_log;
DELETE FROM accusations;
DELETE FROM cheating_edges;
DELETE FROM students;
DELETE FROM detector_results;
DELETE FROM essay_submissions;
DELETE FROM honor_code_violations;
DELETE FROM assignment_design;
DELETE FROM sanction_scale;

-- ---------------------------------------------------------------------
-- Data-quality checks on staging (logged before loading)
-- ---------------------------------------------------------------------
INSERT INTO data_quality_log (table_name, check_name, rows_found, severity)
SELECT 'stg_cheating_network_edges', 'self-loop edges (source = target)', COUNT(*), 'ERROR'
FROM c_edges WHERE source = target
UNION ALL
SELECT 'stg_cheating_network_edges', 'edges referencing unknown students', COUNT(*), 'ERROR'
FROM c_edges e
WHERE e.source NOT IN (SELECT student_id FROM c_student_nodes)
   OR e.target NOT IN (SELECT student_id FROM c_student_nodes)
UNION ALL
SELECT 'stg_cheating_network_edges', 'denormalized year/major disagrees with student_nodes', COUNT(*), 'WARN'
FROM c_edges e
JOIN c_student_nodes s ON s.student_id = e.source
WHERE e.source_year <> s.year OR e.source_major <> s.major
UNION ALL
SELECT 'stg_cheating_network_edges', 'duplicate (source, target, edge_type)',
       COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT source, target, edge_type FROM c_edges)), 'WARN'
FROM c_edges
UNION ALL
SELECT 'stg_plagiarism_cascades', 'accusations referencing unknown students', COUNT(*), 'ERROR'
FROM c_cascades c
WHERE c.student_id NOT IN (SELECT student_id FROM c_student_nodes)
   OR c.accused_by NOT IN (SELECT student_id FROM c_student_nodes)
UNION ALL
SELECT 'stg_plagiarism_cascades', 'student accused more than once in same cascade',
       COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT cascade_id, student_id FROM c_cascades)), 'WARN'
FROM c_cascades
UNION ALL
SELECT 'stg_plagiarism_cascades', 'self-accusations (student_id = accused_by)', COUNT(*), 'WARN'
FROM c_cascades WHERE student_id = accused_by
UNION ALL
SELECT 'stg_chatgpt_detection_results', 'boolean stored as text (True/False)', COUNT(*), 'INFO'
FROM c_detection WHERE detected_as_ai IN ('True', 'False')
UNION ALL
SELECT 'stg_chatgpt_detection_results', 'duplicate submission_id',
       COUNT(*) - COUNT(DISTINCT submission_id), 'ERROR'
FROM c_detection
UNION ALL
SELECT 'stg_ai_essay_submissions', 'non-integer word_count (rounded)', COUNT(*), 'WARN'
FROM c_essays WHERE word_count LIKE '%.%'
UNION ALL
SELECT 'stg_ai_essay_submissions', 'grade outside 0-100', COUNT(*), 'WARN'
FROM c_essays WHERE CAST(grade AS REAL) NOT BETWEEN 0 AND 100
UNION ALL
SELECT 'stg_ai_essay_submissions', 'similarity_score outside 0-100', COUNT(*), 'WARN'
FROM c_essays WHERE CAST(similarity_score AS REAL) NOT BETWEEN 0 AND 100
UNION ALL
SELECT 'stg_student_nodes', 'GPA outside 0-4', COUNT(*), 'ERROR'
FROM c_student_nodes WHERE CAST(gpa AS REAL) NOT BETWEEN 0 AND 4
UNION ALL
SELECT 'stg_honor_code_violations', 'negative or missing investigation duration', COUNT(*), 'WARN'
FROM c_violations
WHERE investigation_duration IS NULL OR CAST(investigation_duration AS INTEGER) < 0;

-- ---------------------------------------------------------------------
-- Load core tables
-- ---------------------------------------------------------------------
INSERT INTO students (student_id, class_year, major, gpa)
SELECT student_id, CAST(year AS INTEGER), major, ROUND(CAST(gpa AS REAL), 2)
FROM c_student_nodes;

-- INSERT OR IGNORE drops any duplicates already counted in the log
INSERT OR IGNORE INTO cheating_edges (source_id, target_id, edge_type, confidence, observed_at)
SELECT source, target, edge_type, CAST(confidence AS REAL), ts
FROM c_edges
WHERE source <> target;

INSERT INTO accusations (cascade_id, cascade_level, student_id, accused_by, accused_at,
                         evidence_strength, outcome, subject, sanction_level)
SELECT cascade_id, CAST(cascade_level AS INTEGER), student_id, accused_by, accusation_date,
       CAST(evidence_strength AS REAL), outcome, subject, sanction_level
FROM c_cascades;

INSERT INTO sanction_scale VALUES
  ('None', 0), ('Warning', 1), ('Probation', 2), ('Suspension', 3), ('Expulsion', 4);

INSERT INTO detector_results
SELECT submission_id, tool, actual_type,
       CASE LOWER(detected_as_ai) WHEN 'true' THEN 1 WHEN '1' THEN 1
                                  WHEN 'false' THEN 0 WHEN '0' THEN 0 END,
       CAST(confidence_score AS REAL), CAST(text_length AS INTEGER), subject, grade_level,
       CAST(writing_style_score AS REAL), CAST(perplexity_score AS REAL),
       CAST(detection_probability AS REAL)
FROM c_detection;

INSERT INTO essay_submissions
SELECT submission_id, semester, assignment_type,
       CASE LOWER(is_ai_generated) WHEN 'true' THEN 1 WHEN '1' THEN 1
                                   WHEN 'false' THEN 0 WHEN '0' THEN 0 END,
       CAST(ai_probability AS REAL),
       CAST(ROUND(CAST(word_count AS REAL)) AS INTEGER),
       CAST(cited_references AS INTEGER), CAST(similarity_score AS REAL),
       submission_date, CAST(grade AS REAL)
FROM c_essays;

INSERT INTO honor_code_violations (violation_date, violation_type, severity, course,
                                   reported_by, investigation_days, appealed)
SELECT violation_date, violation_type, severity, course, reported_by,
       CAST(investigation_duration AS INTEGER),
       CASE LOWER(appealed) WHEN 'true' THEN 1 WHEN '1' THEN 1
                            WHEN 'false' THEN 0 WHEN '0' THEN 0 END
FROM c_violations;

INSERT INTO assignment_design (design_type, efficacy_score, student_engagement,
       learning_outcome, ai_detection_rate, student_satisfaction,
       implementation_cost, faculty_workload, class_size, subject)
SELECT design_type, CAST(efficacy_score AS REAL), CAST(student_engagement AS REAL),
       CAST(learning_outcome AS REAL), CAST(ai_detection_rate AS REAL),
       CAST(student_satisfaction AS REAL), implementation_cost, faculty_workload,
       CAST(class_size AS INTEGER), subject
FROM c_design;

-- Reconciliation: staging rows vs core rows
SELECT 'students' AS tbl, (SELECT COUNT(*) FROM stg_student_nodes) AS staged, (SELECT COUNT(*) FROM students) AS loaded
UNION ALL SELECT 'cheating_edges', (SELECT COUNT(*) FROM stg_cheating_network_edges), (SELECT COUNT(*) FROM cheating_edges)
UNION ALL SELECT 'accusations', (SELECT COUNT(*) FROM stg_plagiarism_cascades), (SELECT COUNT(*) FROM accusations)
UNION ALL SELECT 'detector_results', (SELECT COUNT(*) FROM stg_chatgpt_detection_results), (SELECT COUNT(*) FROM detector_results)
UNION ALL SELECT 'essay_submissions', (SELECT COUNT(*) FROM stg_ai_essay_submissions), (SELECT COUNT(*) FROM essay_submissions)
UNION ALL SELECT 'honor_code_violations', (SELECT COUNT(*) FROM stg_honor_code_violations), (SELECT COUNT(*) FROM honor_code_violations)
UNION ALL SELECT 'assignment_design', (SELECT COUNT(*) FROM stg_assignment_design_efficacy), (SELECT COUNT(*) FROM assignment_design);

SELECT * FROM data_quality_log
ORDER BY CASE severity WHEN 'ERROR' THEN 1 WHEN 'WARN' THEN 2 ELSE 3 END, check_id;
