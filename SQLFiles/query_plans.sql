-- =====================================================================
-- query_plans.sql  (SQLite version, run step 8 of 8)
-- MySQL used EXPLAIN ANALYZE. SQLite has EXPLAIN QUERY PLAN, which shows
-- whether a query SCANs the whole table or SEARCHes using an index.
-- Compare the plan for the same query with and without an index.
-- =====================================================================

-- With the index ix_acc_accuser: look for SEARCH ... USING INDEX
EXPLAIN QUERY PLAN
SELECT COUNT(*) FROM accusations WHERE accused_by = 'S020';

DROP INDEX IF EXISTS ix_acc_accuser;

-- Without the index: look for SCAN accusations (reads every row)
EXPLAIN QUERY PLAN
SELECT COUNT(*) FROM accusations WHERE accused_by = 'S020';

CREATE INDEX ix_acc_accuser ON accusations (accused_by);

-- Same idea for violations by course: index ix_hcv_course
EXPLAIN QUERY PLAN
SELECT COUNT(*) FROM honor_code_violations WHERE course = 'CS101';

DROP INDEX IF EXISTS ix_hcv_course;

EXPLAIN QUERY PLAN
SELECT COUNT(*) FROM honor_code_violations WHERE course = 'CS101';

CREATE INDEX ix_hcv_course ON honor_code_violations (course);

-- Row counts of every table and derived table in the project
SELECT 'students' AS tbl, COUNT(*) AS row_count FROM students
UNION ALL SELECT 'cheating_edges', COUNT(*) FROM cheating_edges
UNION ALL SELECT 'accusations', COUNT(*) FROM accusations
UNION ALL SELECT 'detector_results', COUNT(*) FROM detector_results
UNION ALL SELECT 'essay_submissions', COUNT(*) FROM essay_submissions
UNION ALL SELECT 'honor_code_violations', COUNT(*) FROM honor_code_violations
UNION ALL SELECT 'assignment_design', COUNT(*) FROM assignment_design
UNION ALL SELECT 'undirected_edges', COUNT(*) FROM undirected_edges
UNION ALL SELECT 'directed_reach', COUNT(*) FROM directed_reach
UNION ALL SELECT 'network_distance', COUNT(*) FROM network_distance
UNION ALL SELECT 'detector_roc', COUNT(*) FROM detector_roc;
