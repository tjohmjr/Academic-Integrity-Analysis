# Academic Integrity Analytics: Cheating Networks, Accusations & AI Detection

An end-to-end SQL project on a synthetic academic-integrity dataset: raw CSVs go into a staged SQLite warehouse, get cleaned and quality-checked, are analysed with pure SQL (graph analytics, statistical tests, window functions), and end up in a Power BI dashboard.

![Dashboard](images/dashboard.png)

**Dataset:** [Student Cheating Networks & AI Detection Data](https://www.kaggle.com/datasets/aliahmadmphil/student-cheating-networks-and-ai-detection-data) on Kaggle. The data is synthetic.

## Key findings

**Cheating network**
- 131 of 200 students (65.5%) have no cheating links. One ring of **39 students holds 85 of the 135 links (63%)**.
- Student **S102** is the hub: 18 links, neighbours across 5 majors, and the highest composite risk score (91.5).
- 32% of connected pairs cheat in both directions, and the network contains 47 three-person cliques.
- Cheating is not clustered by major: 14.1% of links are same-major, below the 16.7% expected at random.

**Accusation cascades**
- **95% of accusations connect students with no path between them in the cheating network.**
- Evidence strength does not predict outcomes: the upheld rate stays between 47% and 57% in every evidence quintile.
- **114 dismissed accusations still carry a sanction, 26 of them suspension or expulsion**, while 32 upheld cases got none.

**AI detectors**
- Copyleaks has the best overall quality (MCC 0.82). GPTZero catches the most AI text but **wrongly flags 151 of every 1,000 honest students**.
- Honest **CS students are flagged significantly more often** (10.3% vs 6.3%, z = 2.69), while PHYS students are flagged significantly less.
- `detection_probability` separates AI from human text perfectly (AUC = 1.0). Real detectors never do this, so it is label leakage, and the threshold results demonstrate the method rather than real-world performance.

**Trends and design**
- The AI-generated essay share rose every term: 22.9%, 33.2%, 41.9%, 49.6%.
- Oral defense is the most effective AI-resistant assignment design (89% efficacy) and stays first after adjusting for cost and faculty workload. Traditional assignments sit at 19%.

## What the project does

The project answers four questions using only SQL:

1. **How do students cheat together?** The dataset records 135 cheating links between 200 students. The project finds the cheating rings, the most connected students, and how tightly the groups are linked.
2. **Are accusations connected to real cheating?** The dataset has 439 plagiarism accusations grouped into 50 cascades. The project checks whether accusers and accused are linked in the cheating network, whether evidence predicts outcomes, and whether sanctions are applied consistently.
3. **How good are AI-writing detectors?** Five tools (Copyleaks, GPTZero, Originality.ai, Turnitin, Winston AI) were tested on 5,000 texts. The project measures their errors, checks fairness across subjects and grade levels, and tunes their thresholds.
4. **What are the trends, and what works?** The project tracks the share of AI-written essays over time, honor-code violations by month, and which assignment designs resist AI best.

It also shows the data-engineering side: raw data goes into staging tables, gets cleaned and typed, passes 14 logged data-quality checks, and ends up in reusable tables and views. Every statistic published with the dataset is recomputed in SQL and matches.

## Repository structure

```
Academic-Integrity-Analysis/
├── Data/                       the nine source CSVs and dataset_summary.txt
├── SQLFiles/                   the eight SQL scripts (run in order, see below)
├── PostSQLVisualData/          ten CSV exports of the finished tables and views, loaded into Power BI
├── images/dashboard.png        screenshot of the dashboard
├── Academic Integrity Analysis.pbix   the Power BI report
├── academic_integrity.db       the finished SQLite database (all tables and views built)
├── build_db.py                 rebuilds the database from the CSVs
├── results.txt                 saved output of every script
└── README.md
```

## How to run it

The database `academic_integrity.db` is already built, so you can open it and start querying. To rebuild from scratch, use Option B or C.

**Option A: explore the finished database in VS Code (SQLTools)**
1. Install the **SQLTools** and **SQLTools SQLite** extensions.
2. In the SQLTools sidebar, choose **Add New Connection > SQLite**, name it `academic_integrity`, and select `academic_integrity.db` as the database file.
3. Open any file in `SQLFiles/`, press Cmd+A (Ctrl+A on Windows) to select everything, then press Cmd+E twice to run it. SQLTools shows 50 rows per result by default, which you can raise in its Results Limit setting.

**Option B: rebuild everything with Python (no installs needed)**
```bash
python3 build_db.py --run-all
```
This deletes and recreates `academic_integrity.db`, loads the CSVs from `Data/`, runs every script in `SQLFiles/` in order, and rewrites `results.txt`. Without `--run-all` it only creates the schema and loads the raw data.

**Option C: rebuild step by step in SQLTools**
Run `build_db.py` without `--run-all` to get an empty-but-loaded database, then run the scripts in `SQLFiles/` one at a time in the order below. Every script can be re-run safely.

## Run order

| Step | File | Needs first |
|---|---|---|
| 1 | `schema.sql` | nothing |
| 2 | `transform.sql` | schema and the CSV load (`build_db.py`) |
| 3 | `network_analysis.sql` | transform |
| 4 | `cascade_analysis.sql` | transform, network_analysis |
| 5 | `detector_audit.sql` | transform |
| 6 | `trends_and_design.sql` | transform |
| 7 | `views_and_queries.sql` | network_analysis, cascade_analysis, detector_audit |
| 8 | `query_plans.sql` | steps 1 to 5 |

SQLite has no `LOAD DATA` command, so `build_db.py` does the CSV load between steps 1 and 2.

## The SQL files

### `schema.sql`
Creates the structure of the database.
- **Staging tables** (`stg_*`, nine of them): one per CSV, every column stored as TEXT so the raw data always loads. They use `CREATE TABLE IF NOT EXISTS`, so re-running the file never wipes the loaded data.
- **Core tables**, dropped and recreated each run, with proper types, primary keys, foreign keys, CHECK rules (for example GPA between 0 and 4, no self-loop edges) and indexes: `students`, `cheating_edges`, `accusations`, `sanction_scale`, `detector_results`, `essay_submissions`, `honor_code_violations`, `assignment_design`, and `data_quality_log`, which records every data problem found.

### `transform.sql`
Moves data from staging into the core tables and checks its quality.
- Creates nine **`c_*` cleaning views** that trim whitespace and turn empty strings into NULL.
- Runs **14 data-quality checks** and writes the counts to `data_quality_log`. Findings include 13 repeat accusations in the same cascade, 2 self-accusations, and booleans stored as the text "True"/"False".
- Loads the core tables, converting text to numbers, `True`/`False` to 1/0, and rounding fractional word counts.
- Fills the `sanction_scale` lookup (None, Warning, Probation, Suspension, Expulsion ranked 0 to 4).
- Ends with a **reconciliation** table comparing staged rows to loaded rows.

### `network_analysis.sql`
Graph analysis of the cheating network, using recursive queries and window functions.
- Builds `undirected_edges` and `student_degree` (links in, out and total per student).
- **Validates** the published numbers: 200 nodes, 135 edges, density, max degree.
- Ranks the most central students and labels each as a supplier, consumer or two-way trader.
- Measures **reciprocity** (32% of connected pairs cheat in both directions).
- Finds **cheating rings** (`student_ring`) and **strongly connected components** (`directed_reach`, `student_scc`: 161, matching the published figure).
- Counts **triangles** and the **clustering coefficient** (`student_clustering`): 47 triangles, 0.121 average.
- Tests whether students cheat within their own major, finds **brokers** who connect many majors, checks GPA against network activity, and tracks network growth by month.

### `cascade_analysis.sql`
Analysis of the accusation cascades.
- `cascade_summary`: size, depth, duration and outcomes per cascade.
- A recursive query walking each cascade level by level.
- A **witch-hunt test**: does evidence get weaker at deeper levels? Pearson r is about 0.01, so no.
- **Evidence vs outcome** by quintile: upheld rates barely change.
- A **sanction audit**: 114 dismissed cases still carry a sanction (26 severe), 32 upheld cases carry none, and MATH is punished harder than other subjects.
- `network_distance`: shortest path between every pair of students, built with a recursive query (network diameter 12).
- `accusation_network_link`: how far each accuser is from the accused in the cheating network.
- Retaliation, contagion and timing checks, including 167 level changes dated out of order.

### `detector_audit.sql`
Evaluation of the five AI detectors.
- Checks the published false-positive rates against the recomputed ones.
- `v_detector_confusion` view: true and false positives and negatives per tool.
- Precision, recall, F1, accuracy and **MCC**, plus "honest students wrongly flagged per 1,000".
- How tools treat **mixed** (partly AI) texts, which the published summary ignores.
- **Fairness tests** by grade level, subject (two-proportion z-test) and text length.
- `detector_roc`: a **ROC curve** built by sweeping 101 thresholds from 0 to 1, then AUC, the best threshold per tool, and a policy threshold that keeps false accusations at or under 1%.
- A **label-leakage check**, and **calibration**, including whether a tool's self-reported confidence means anything (it does not).

### `trends_and_design.sql`
Trends over time and assignment-design effectiveness.
- AI-generated essay share by semester, and a data-quality check showing semester labels do not match submission dates.
- AI vs human essay grades (AI essays score about 3 points higher), by assignment type.
- Weekly AI share with a 4-week moving average.
- Honor-code violations by type, month, year-over-year change, weekday, season, reporter and course, plus investigation-duration percentiles. It also flags violations dated in the future, and that count depends on today's date.
- **Assignment design** ranking, with a cost-and-workload-adjusted version.

### `views_and_queries.sql`
Reusable pieces for dashboards and repeat lookups.
- `v_student_risk`: a composite 0 to 100 risk score per student built from network activity, link confidence, ring size and upheld accusations, plus quintile and tier (High, Medium, Low).
- BI-ready views: `v_edges_enriched`, `v_detector_tool_summary`, `v_violations_monthly`.
- Three ready-made queries. SQLite has no stored procedures, so edit the value on each line marked `CHANGE ME`: a one-page report on any student, the shortest cheating path between any two students, and a detector's results at any probability threshold.

### `query_plans.sql`
A short performance lesson. It runs `EXPLAIN QUERY PLAN` on the same query with and without an index, so you can see `SEARCH ... USING INDEX` change to `SCAN`, then recreates each index and ends with row counts for every table.

## The Python file

### `build_db.py`
Rebuilds the database from the raw CSVs. It uses only the Python standard library.
- `python3 build_db.py` deletes any existing `academic_integrity.db`, runs `SQLFiles/schema.sql`, and loads each CSV in `Data/` into its staging table. It reads with Python's `csv` module, so quoting and line endings are handled correctly.
- `python3 build_db.py --run-all` does the same, then runs the other seven scripts in order, splitting each into statements, and writes every result table to `results.txt`.

## The Power BI dashboard

`Academic Integrity Analysis.pbix` is a one-page report built from the ten CSVs in `PostSQLVisualData/`. To refresh those CSVs after changing the database:

```bash
mkdir -p PostSQLVisualData
for t in v_student_risk v_edges_enriched v_detector_tool_summary v_violations_monthly students accusation_network_link detector_results essay_submissions assignment_design detector_roc; do
  sqlite3 -header -csv academic_integrity.db "SELECT * FROM $t;" > PostSQLVisualData/$t.csv
done
```

**Visuals:** three cards (students, cheating links, high-risk students), a major slicer, and seven charts: GPTZero false-positive rate by tool, the share of accusations with no cheating link, top 10 highest-risk students, honor-code violations by month, AI essay share by semester, assignment design effectiveness, and detector ROC curves.

**Model:** `students` links 1:1 to `v_student_risk`, which links 1-to-many to `accusation_network_link`. `v_detector_tool_summary` links 1-to-many to both `detector_results` and `detector_roc` on `tool`. The other tables stand alone.

**DAX used:**
```
No Link %           = DIVIDE(CALCULATE(COUNTROWS(accusation_network_link), accusation_network_link[link_category] = "No network connection"), COUNTROWS(accusation_network_link))
High Risk Students  = CALCULATE(COUNTROWS(v_student_risk), v_student_risk[risk_tier] = "High")
Semester Sort       = VALUE(RIGHT(essay_submissions[semester],4))*10 + SWITCH(LEFT(essay_submissions[semester], FIND(" ", essay_submissions[semester])-1), "Spring",1,"Summer",2,3)
Semester Label      = essay_submissions[semester]     -- sorted by Semester Sort so semesters run in time order
```

## Data-quality issues found
- **Label leakage:** `detection_probability` perfectly separates AI from human text (human max 0.239, AI min 0.479).
- Semester labels do not match submission dates. All "Fall 2025" essays are dated March to September 2026.
- In 167 of 389 cascade-level transitions, a deeper level is dated before the level above it.
- Hundreds of honor-code violations are dated in the future, up to 2026-12-31.
- There are 2 self-accusations and 13 repeat accusations of the same student within a cascade.
- Booleans are stored as `True`/`False` text, and word counts are fractional.
