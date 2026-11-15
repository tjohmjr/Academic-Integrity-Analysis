# Academic Integrity Analytics
Kaggle Dataset: https://www.kaggle.com/datasets/aliahmadmphil/student-cheating-networks-and-ai-detection-data 

## What the project does

The project takes a synthetic dataset about cheating at a university and answers four questions using only SQL:

1. **How do students cheat together?** The dataset records 135 cheating links between 200 students. The project finds the cheating rings, the most connected students, and how tightly the groups are linked.
2. **Are accusations connected to real cheating?** The dataset has 439 plagiarism accusations grouped into 50 cascades. The project checks whether accusers and accused are linked in the cheating network, whether evidence predicts outcomes, and whether sanctions are applied consistently.
3. **How good are AI-writing detectors?** Five tools (Copyleaks, GPTZero, Originality.ai, Turnitin, Winston AI) were tested on 5,000 texts. The project measures their errors, checks fairness across subjects and grade levels, and tunes their thresholds.
4. **What are the trends, and what works?** The project tracks the share of AI-written essays over time, honor-code violations by month, and which assignment designs resist AI best.

It also shows the data-engineering side: raw data goes into staging tables, gets cleaned and typed, passes data-quality checks, and ends up in reusable tables and views.

## Files and run order

Run the SQL files in numeric order.

| Step | File
| 1 | `schema.sql`
| 2 | `transform.sql` 
| 3 | `network_analysis.sql`
| 4 | `cascade_analysis.sql`
| 5 | `detector_audit.sql` 
| 6 | `trends_and_design.sql` 
| 7 | `views_and_queries.sql` 
| 8 | `query_plans.sql` 

## The SQL files

### `schema.sql`
Creates the structure of the database.
- **Staging tables** (`stg_*`, nine of them): one per CSV, every column stored as TEXT so the raw data always loads. They use `CREATE TABLE IF NOT EXISTS`, so re-running the file never wipes the loaded data.
- **Core tables**, which are dropped and recreated each run, with proper types, primary keys, foreign keys, CHECK rules (for example GPA between 0 and 4, no self-loop edges) and indexes:
  - `students`, `cheating_edges`, `accusations`, `sanction_scale`
  - `detector_results`, `essay_submissions`, `honor_code_violations`, `assignment_design`
  - `data_quality_log`, which records every data problem found

### `transform.sql`
Moves data from staging into the core tables and checks its quality.
- Creates nine **`c_*` cleaning views** that trim whitespace and turn empty strings into NULL.
- Runs **14 data-quality checks** and writes the counts to `data_quality_log`. Findings include 13 repeat accusations in the same cascade, 2 self-accusations, and booleans stored as the text "True"/"False".
- Loads the core tables, converting text to numbers, `True`/`False` to 1/0, and rounding the fractional word counts.
- Fills the `sanction_scale` lookup (None, Warning, Probation, Suspension, Expulsion ranked 0 to 4).
- Ends with a **reconciliation** table comparing staged rows to loaded rows, and the data-quality log.

### `network_analysis.sql`
Graph analysis of the cheating network, using recursive queries and window functions.
- Builds `undirected_edges` (each link in both directions) and `student_degree` (links in, out and total per student).
- **Validates** the published numbers: 200 nodes, 135 edges, density, max degree.
- Ranks the most central students (S102 is the hub with 18 links) and labels each as a supplier, consumer or two-way trader.
- Measures **reciprocity** (32% of connected pairs cheat in both directions).
- Finds **cheating rings** (`student_ring`), the connected groups. One ring holds 39 students and 85 of the 135 links.
- Finds **strongly connected components** (`directed_reach`, `student_scc`): 161, matching the published figure.
- Counts **triangles** and the **clustering coefficient** (`student_clustering`): 47 triangles, 0.121 average.
- Tests whether students cheat within their own major (they do not: 14.1% same-major vs 16.7% expected by chance).
- Finds **brokers** who connect many majors, checks GPA against network activity, and tracks network growth by month.

### `cascade_analysis.sql`
Analysis of the accusation cascades.
- `cascade_summary`: size, depth, duration and outcomes per cascade.
- A recursive query walking each cascade level by level.
- A **witch-hunt test**: does evidence get weaker in deeper levels, and is the correlation (Pearson r) near zero? It is, at about 0.01.
- **Evidence vs outcome** by quintile: upheld rates barely change, so evidence does not predict the result.
- A **sanction audit**: 114 dismissed cases still carry a sanction (26 severe), 32 upheld cases carry none, and MATH is punished harder than other subjects.
- `network_distance`: shortest path between every pair of students, built with a recursive query. The network diameter is 12.
- `accusation_network_link`: how far each accuser is from the accused in the cheating network. 95% of accusations connect students with no path between them.
- Retaliation (A accuses B, then B accuses A), contagion, and timing checks, including 167 level changes dated out of order.

### `detector_audit.sql`
Evaluation of the five AI detectors.
- Checks the published false-positive rates against the recomputed ones.
- `v_detector_confusion` view: true and false positives and negatives per tool.
- Precision, recall, F1, accuracy and **MCC** (Copyleaks is best at 0.82), plus "honest students wrongly flagged per 1,000" (GPTZero: 151).
- How tools treat **mixed** (partly AI) texts, which the published summary ignores.
- **Fairness tests** by grade level, subject (two-proportion z-test: CS is flagged more, PHYS less), and text length.
- `detector_roc`: a **ROC curve** built by sweeping thresholds from 0 to 1, then AUC, the best threshold per tool, and a policy threshold that keeps false accusations at or under 1%.
- A **label-leakage check**: `detection_probability` separates AI from human text perfectly (AUC 1.0), which real detectors never do, so it is reported as a data-quality finding.
- **Calibration**, and whether a tool's self-reported confidence means anything (it does not).

### `trends_and_design.sql`
Trends over time and assignment-design effectiveness.
- AI-generated essay share by semester: 22.9%, 33.2%, 41.9%, 49.6%.
- A data-quality check showing semester labels do not match submission dates.
- AI vs human essay grades (AI essays score about 3 points higher), by assignment type.
- Weekly AI share with a 4-week moving average.
- Honor-code violations by type, month, year-over-year change, weekday, season, reporter and course, plus investigation-duration percentiles.
- A check for violations dated in the future (the count depends on today's date).
- **Assignment design** ranking: Oral Defense is the most effective (89%) and still ranks first after adjusting for cost and faculty workload. Traditional assignments are at 19%.

### `views_and_queries.sql`
Reusable pieces for dashboards and repeat lookups.
- `v_student_risk`: a composite 0 to 100 risk score per student built from network activity, link confidence, ring size and upheld accusations, plus risk quintile and tier (High, Medium, Low).
- BI-ready views for Tableau or Power BI: `v_edges_enriched`, `v_detector_tool_summary`, `v_violations_monthly`.
- Three ready-made queries that replace the MySQL stored procedures. Edit the value on the line marked `CHANGE ME`:
  - a one-page report on any student
  - the shortest cheating path between any two students
  - a detector's results at any probability threshold

### `query_plans.sql`
A short performance lesson. It runs `EXPLAIN QUERY PLAN` on the same query with and without an index, so you can see `SEARCH ... USING INDEX` change to `SCAN` (a full table read). It recreates each index afterwards and ends with row counts for every table.

## The Python file

### `build_db.py`
An optional helper that rebuilds the database from the raw CSVs. You only need it to start over, because `academic_integrity.db` is already built.
- `python3 build_db.py` deletes any existing `academic_integrity.db`, runs `schema.sql`, and loads each CSV in `data/` into its staging table. It uses Python's `csv` module, so quoting and line endings are handled correctly.
- `python3 build_db.py --run-all` does the same and then runs `files 2` until `files 9` in order, splitting each file into statements, and writes every result table to `results.txt`.
- It uses only Python's standard library, so nothing needs to be installed.

## Other files

| File | Purpose 
| `academic_integrity.db` | The SQLite database: schema plus raw CSVs already in the `stg_*` tables 
| `data/` | The nine source CSVs and `dataset_summary.txt` (the published statistics the project validates against) 
| `results.txt` | Saved output of every script