-- =====================================================================
-- schema.sql  (SQLite version, run step 1 of 8)
-- Academic Integrity Analytics: Cheating Networks and AI Detector Audit
-- Creates the raw staging tables and the typed core tables.
-- Safe to re-run: staging tables are kept (they hold the loaded CSV data),
-- core tables are dropped and recreated.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STAGING LAYER: every column is TEXT so the raw CSVs always load.
-- Types, booleans and blanks are cleaned in transform.sql.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg_student_nodes (
  student_id TEXT, year TEXT, major TEXT, gpa TEXT
);

CREATE TABLE IF NOT EXISTS stg_cheating_network_edges (
  source TEXT, target TEXT, edge_type TEXT, confidence TEXT, ts TEXT,
  source_year TEXT, target_year TEXT, source_major TEXT, target_major TEXT
);

CREATE TABLE IF NOT EXISTS stg_plagiarism_cascades (
  cascade_id TEXT, student_id TEXT, accused_by TEXT, accusation_date TEXT,
  evidence_strength TEXT, outcome TEXT, cascade_level TEXT, subject TEXT,
  sanction_level TEXT
);

CREATE TABLE IF NOT EXISTS stg_chatgpt_detection_results (
  submission_id TEXT, tool TEXT, actual_type TEXT, detected_as_ai TEXT,
  confidence_score TEXT, text_length TEXT, subject TEXT, grade_level TEXT,
  writing_style_score TEXT, perplexity_score TEXT, detection_probability TEXT
);

CREATE TABLE IF NOT EXISTS stg_ai_essay_submissions (
  submission_id TEXT, semester TEXT, assignment_type TEXT, is_ai_generated TEXT,
  ai_probability TEXT, word_count TEXT, cited_references TEXT,
  similarity_score TEXT, submission_date TEXT, grade TEXT
);

CREATE TABLE IF NOT EXISTS stg_honor_code_violations (
  violation_date TEXT, violation_type TEXT, severity TEXT, course TEXT,
  reported_by TEXT, investigation_duration TEXT, appealed TEXT
);

CREATE TABLE IF NOT EXISTS stg_assignment_design_efficacy (
  design_type TEXT, efficacy_score TEXT, student_engagement TEXT,
  learning_outcome TEXT, ai_detection_rate TEXT, student_satisfaction TEXT,
  implementation_cost TEXT, faculty_workload TEXT, class_size TEXT, subject TEXT
);

-- Published reference numbers, kept so our SQL can be validated against them
CREATE TABLE IF NOT EXISTS stg_network_metrics (
  num_nodes TEXT, num_edges TEXT, density TEXT, avg_clustering TEXT,
  num_strongly_connected TEXT, max_in_degree TEXT, max_out_degree TEXT,
  avg_shortest_path TEXT
);

CREATE TABLE IF NOT EXISTS stg_false_positive_rates (
  tool TEXT, detected_as_ai TEXT
);

-- ---------------------------------------------------------------------
-- CORE LAYER (typed, keyed, indexed)
-- Booleans are stored as 0/1, timestamps as ISO-8601 text.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS accusations;
DROP TABLE IF EXISTS cheating_edges;
DROP TABLE IF EXISTS students;
DROP TABLE IF EXISTS sanction_scale;
DROP TABLE IF EXISTS detector_results;
DROP TABLE IF EXISTS essay_submissions;
DROP TABLE IF EXISTS honor_code_violations;
DROP TABLE IF EXISTS assignment_design;
DROP TABLE IF EXISTS data_quality_log;

CREATE TABLE students (
  student_id  TEXT PRIMARY KEY,
  class_year  INTEGER NOT NULL CHECK (class_year BETWEEN 1 AND 5),
  major       TEXT    NOT NULL,
  gpa         REAL    NOT NULL CHECK (gpa BETWEEN 0 AND 4)
);
CREATE INDEX ix_students_major ON students (major);

-- Directed edge: source -> target (source shared with / was copied by target)
CREATE TABLE cheating_edges (
  edge_id     INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id   TEXT NOT NULL REFERENCES students(student_id),
  target_id   TEXT NOT NULL REFERENCES students(student_id),
  edge_type   TEXT NOT NULL,
  confidence  REAL NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  observed_at TEXT NOT NULL,
  CHECK (source_id <> target_id),
  UNIQUE (source_id, target_id, edge_type)
);
CREATE INDEX ix_edges_target ON cheating_edges (target_id, source_id);
CREATE INDEX ix_edges_time   ON cheating_edges (observed_at);

CREATE TABLE accusations (
  accusation_id     INTEGER PRIMARY KEY AUTOINCREMENT,
  cascade_id        TEXT    NOT NULL,
  cascade_level     INTEGER NOT NULL,
  student_id        TEXT    NOT NULL REFERENCES students(student_id),  -- accused
  accused_by        TEXT    NOT NULL REFERENCES students(student_id),  -- accuser
  accused_at        TEXT    NOT NULL,
  evidence_strength REAL    NOT NULL,
  outcome           TEXT    NOT NULL,
  subject           TEXT    NOT NULL,
  sanction_level    TEXT    NOT NULL
);
CREATE INDEX ix_acc_cascade ON accusations (cascade_id, cascade_level);
CREATE INDEX ix_acc_student ON accusations (student_id);
CREATE INDEX ix_acc_accuser ON accusations (accused_by);

-- Lookup giving sanctions an order so we can measure escalation
CREATE TABLE sanction_scale (
  sanction_level TEXT PRIMARY KEY,
  severity_rank  INTEGER NOT NULL
);

CREATE TABLE detector_results (
  submission_id         TEXT PRIMARY KEY,
  tool                  TEXT NOT NULL,
  actual_type           TEXT NOT NULL,   -- ai_generated, human_written or mixed
  detected_as_ai        INTEGER NOT NULL,
  confidence_score      REAL,
  text_length           INTEGER,
  subject               TEXT,
  grade_level           TEXT,
  writing_style_score   REAL,
  perplexity_score      REAL,
  detection_probability REAL
);
CREATE INDEX ix_det_tool ON detector_results (tool, actual_type);
CREATE INDEX ix_det_prob ON detector_results (tool, detection_probability);

CREATE TABLE essay_submissions (
  submission_id    TEXT PRIMARY KEY,
  semester         TEXT NOT NULL,
  assignment_type  TEXT NOT NULL,
  is_ai_generated  INTEGER NOT NULL,
  ai_probability   REAL,
  word_count       INTEGER,
  cited_references INTEGER,
  similarity_score REAL,
  submitted_at     TEXT,
  grade            REAL
);
CREATE INDEX ix_ess_sem ON essay_submissions (semester);

CREATE TABLE honor_code_violations (
  violation_id       INTEGER PRIMARY KEY AUTOINCREMENT,
  violation_date     TEXT    NOT NULL,
  violation_type     TEXT    NOT NULL,
  severity           TEXT    NOT NULL,
  course             TEXT    NOT NULL,
  reported_by        TEXT    NOT NULL,
  investigation_days INTEGER,
  appealed           INTEGER NOT NULL
);
CREATE INDEX ix_hcv_date   ON honor_code_violations (violation_date);
CREATE INDEX ix_hcv_course ON honor_code_violations (course);

CREATE TABLE assignment_design (
  design_id            INTEGER PRIMARY KEY AUTOINCREMENT,
  design_type          TEXT NOT NULL,
  efficacy_score       REAL,
  student_engagement   REAL,
  learning_outcome     REAL,
  ai_detection_rate    REAL,
  student_satisfaction REAL,
  implementation_cost  TEXT,
  faculty_workload     TEXT,
  class_size           INTEGER,
  subject              TEXT
);
CREATE INDEX ix_design_type ON assignment_design (design_type);

-- Every rule the cleaning step applies is logged here (rows affected)
CREATE TABLE data_quality_log (
  check_id    INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name  TEXT,
  check_name  TEXT,
  rows_found  INTEGER,
  severity    TEXT,
  checked_at  TEXT DEFAULT CURRENT_TIMESTAMP
);
