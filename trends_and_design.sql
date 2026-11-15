WITH s AS (
  SELECT semester,
         CAST(substr(semester, -4) AS INTEGER) AS yr,
         CASE substr(semester, 1, instr(semester, ' ') - 1)
              WHEN 'Spring' THEN 1 WHEN 'Summer' THEN 2 ELSE 3 END AS season_order,
         COUNT(*) AS submissions,
         SUM(is_ai_generated) AS ai_generated,
         100.0 * AVG(is_ai_generated) AS pct_ai
  FROM essay_submissions GROUP BY semester
)
SELECT semester, submissions, ai_generated,
       ROUND(pct_ai, 2) AS pct_ai,
       ROUND(pct_ai - LAG(pct_ai) OVER (ORDER BY yr, season_order), 2) AS pp_change
FROM s ORDER BY yr, season_order;

SELECT 'Overall AI-generated rate' AS metric, ROUND(100 * AVG(is_ai_generated), 2) AS pct
FROM essay_submissions;

WITH e AS (
  SELECT semester, submitted_at,
         CAST(strftime('%Y', submitted_at) AS INTEGER) AS sub_year,
         CAST(strftime('%m', submitted_at) AS INTEGER) AS sub_month,
         CAST(substr(semester, -4) AS INTEGER) AS sem_year,
         CASE substr(semester, 1, instr(semester, ' ') - 1)
              WHEN 'Spring' THEN 1 WHEN 'Summer' THEN 5 ELSE 8 END AS first_month,
         CASE substr(semester, 1, instr(semester, ' ') - 1)
              WHEN 'Spring' THEN 5 WHEN 'Summer' THEN 8 ELSE 12 END AS last_month
  FROM essay_submissions
)
SELECT semester, COUNT(*) AS submissions,
       MIN(date(submitted_at)) AS earliest, MAX(date(submitted_at)) AS latest,
       SUM(CASE WHEN sub_year = sem_year AND sub_month BETWEEN first_month AND last_month
                THEN 0 ELSE 1 END) AS dated_outside_semester,
       ROUND(100.0 * SUM(CASE WHEN sub_year = sem_year AND sub_month BETWEEN first_month AND last_month
                              THEN 0 ELSE 1 END) / COUNT(*), 1) AS pct_mismatched
FROM e GROUP BY semester ORDER BY semester;

SELECT CASE is_ai_generated WHEN 1 THEN 'AI-generated' ELSE 'Human' END AS author,
       COUNT(*) AS essays,
       ROUND(AVG(grade), 2) AS avg_grade,
       ROUND(AVG(word_count)) AS avg_words,
       ROUND(AVG(cited_references), 2) AS avg_citations,
       ROUND(AVG(similarity_score), 2) AS avg_similarity,
       ROUND(AVG(ai_probability), 3) AS avg_ai_probability
FROM essay_submissions GROUP BY is_ai_generated;

SELECT assignment_type,
       COUNT(*) AS essays,
       ROUND(100 * AVG(is_ai_generated), 1) AS pct_ai,
       ROUND(AVG(CASE WHEN is_ai_generated = 1 THEN grade END), 2) AS avg_grade_ai,
       ROUND(AVG(CASE WHEN is_ai_generated = 0 THEN grade END), 2) AS avg_grade_human,
       ROUND(AVG(CASE WHEN is_ai_generated = 1 THEN grade END)
           - AVG(CASE WHEN is_ai_generated = 0 THEN grade END), 2) AS ai_grade_advantage,
       RANK() OVER (ORDER BY AVG(is_ai_generated) DESC) AS ai_share_rank
FROM essay_submissions GROUP BY assignment_type ORDER BY pct_ai DESC;

SELECT SUM(ai_probability >= 0.5 AND is_ai_generated = 1) AS tp,
       SUM(ai_probability >= 0.5 AND is_ai_generated = 0) AS fp,
       SUM(ai_probability <  0.5 AND is_ai_generated = 0) AS tn,
       SUM(ai_probability <  0.5 AND is_ai_generated = 1) AS fn,
       ROUND(AVG((ai_probability >= 0.5) = is_ai_generated), 3) AS accuracy
FROM essay_submissions;

WITH weekly AS (
  SELECT date(submitted_at, '-' || ((CAST(strftime('%w', submitted_at) AS INTEGER) + 6) % 7) || ' days') AS week_start,
         COUNT(*) AS essays,
         AVG(is_ai_generated) AS ai_share
  FROM essay_submissions GROUP BY week_start
)
SELECT week_start, essays, ROUND(100 * ai_share, 1) AS pct_ai,
       ROUND(100 * AVG(ai_share) OVER (ORDER BY week_start ROWS BETWEEN 3 PRECEDING AND CURRENT ROW), 1)
         AS pct_ai_4wk_avg
FROM weekly ORDER BY week_start;

SELECT violation_type, COUNT(*) AS violations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM honor_code_violations GROUP BY violation_type ORDER BY violations DESC;

WITH monthly AS (
  SELECT strftime('%Y-%m-01', violation_date) AS month_start,
         COUNT(*) AS violations,
         SUM(violation_type = 'Unauthorized AI Use') AS ai_violations
  FROM honor_code_violations GROUP BY month_start
)
SELECT month_start, violations, ai_violations,
       ROUND(100.0 * ai_violations / violations, 1) AS pct_ai_related,
       ROUND(AVG(violations) OVER (ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1)
         AS rolling_3mo_avg,
       LAG(violations, 12) OVER (ORDER BY month_start) AS same_month_last_year,
       ROUND(100.0 * (violations - LAG(violations, 12) OVER (ORDER BY month_start))
             / LAG(violations, 12) OVER (ORDER BY month_start), 1) AS yoy_pct
FROM monthly ORDER BY month_start;

SELECT violation_type,
       SUM(strftime('%Y', violation_date) = '2025') AS y2025,
       SUM(strftime('%Y', violation_date) = '2026') AS y2026,
       ROUND(100.0 * (SUM(strftime('%Y', violation_date) = '2026') - SUM(strftime('%Y', violation_date) = '2025'))
             / SUM(strftime('%Y', violation_date) = '2025'), 1) AS yoy_growth_pct
FROM honor_code_violations GROUP BY violation_type ORDER BY yoy_growth_pct DESC;

WITH d AS (
  SELECT (CAST(strftime('%w', violation_date) AS INTEGER) + 6) % 7 AS wd FROM honor_code_violations
)
SELECT CASE wd WHEN 0 THEN 'Monday' WHEN 1 THEN 'Tuesday' WHEN 2 THEN 'Wednesday'
               WHEN 3 THEN 'Thursday' WHEN 4 THEN 'Friday' WHEN 5 THEN 'Saturday'
               ELSE 'Sunday' END AS weekday,
       COUNT(*) AS violations,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM d GROUP BY wd ORDER BY wd;

WITH m AS (
  SELECT CAST(strftime('%m', violation_date) AS INTEGER) AS mo FROM honor_code_violations
)
SELECT CASE mo WHEN 1 THEN 'January' WHEN 2 THEN 'February' WHEN 3 THEN 'March'
               WHEN 4 THEN 'April' WHEN 5 THEN 'May' WHEN 6 THEN 'June'
               WHEN 7 THEN 'July' WHEN 8 THEN 'August' WHEN 9 THEN 'September'
               WHEN 10 THEN 'October' WHEN 11 THEN 'November' ELSE 'December' END AS month,
       COUNT(*) AS violations,
       ROUND(1.0 * COUNT(*) / AVG(COUNT(*)) OVER (), 2) AS seasonal_index   -- 1.00 = average month
FROM m GROUP BY mo ORDER BY mo;

SELECT reported_by,
       COUNT(*) AS reports,
       ROUND(100 * AVG(severity = 'Major'), 1) AS pct_major,
       ROUND(AVG(investigation_days), 1) AS avg_investigation_days,
       ROUND(100 * AVG(appealed), 1) AS pct_appealed
FROM honor_code_violations GROUP BY reported_by ORDER BY reports DESC;

SELECT course,
       SUM(violation_type = 'Plagiarism')          AS plagiarism,
       SUM(violation_type = 'Cheating')            AS cheating,
       SUM(violation_type = 'Unauthorized AI Use') AS unauthorized_ai,
       SUM(violation_type = 'Fabrication')         AS fabrication,
       SUM(violation_type = 'Facilitation')        AS facilitation,
       COUNT(*) AS total
FROM honor_code_violations GROUP BY course ORDER BY total DESC;

WITH ranked AS (
  SELECT severity, investigation_days,
         PERCENT_RANK() OVER (PARTITION BY severity ORDER BY investigation_days) AS pr
  FROM honor_code_violations
)
SELECT severity,
       MIN(CASE WHEN pr >= 0.25 THEN investigation_days END) AS p25_days,
       MIN(CASE WHEN pr >= 0.50 THEN investigation_days END) AS median_days,
       MIN(CASE WHEN pr >= 0.90 THEN investigation_days END) AS p90_days,
       MAX(investigation_days) AS max_days
FROM ranked GROUP BY severity
ORDER BY CASE severity WHEN 'Minor' THEN 1 WHEN 'Moderate' THEN 2 ELSE 3 END;

SELECT COUNT(*) AS future_dated_violations, MIN(violation_date) AS earliest, MAX(violation_date) AS latest
FROM honor_code_violations WHERE violation_date > date('now');

SELECT design_type, COUNT(*) AS courses,
       ROUND(100 * AVG(efficacy_score), 2) AS efficacy_pct,
       ROUND(100 * AVG(learning_outcome), 1) AS learning_outcome_pct,
       ROUND(100 * AVG(student_engagement), 1) AS engagement_pct,
       ROUND(100 * AVG(student_satisfaction), 1) AS satisfaction_pct,
       RANK() OVER (ORDER BY AVG(efficacy_score) DESC) AS efficacy_rank
FROM assignment_design GROUP BY design_type ORDER BY efficacy_pct DESC;

WITH scored AS (
  SELECT design_type,
         AVG(efficacy_score) AS efficacy,
         AVG(CASE implementation_cost WHEN 'Low' THEN 1 WHEN 'Medium' THEN 2 WHEN 'High' THEN 3 END) AS cost_score,
         AVG(CASE faculty_workload    WHEN 'Low' THEN 1 WHEN 'Medium' THEN 2 WHEN 'High' THEN 3 END) AS workload_score,
         AVG(student_satisfaction) AS satisfaction
  FROM assignment_design GROUP BY design_type
)
SELECT design_type,
       ROUND(efficacy, 3) AS efficacy,
       ROUND(cost_score, 2) AS avg_cost_1to3,
       ROUND(workload_score, 2) AS avg_workload_1to3,
       ROUND(efficacy / (cost_score + workload_score), 3) AS efficacy_per_burden,
       RANK() OVER (ORDER BY efficacy / (cost_score + workload_score) DESC) AS value_rank
FROM scored ORDER BY value_rank;

SELECT subject, design_type, ROUND(100 * AVG(efficacy_score), 1) AS efficacy_pct,
       RANK() OVER (PARTITION BY subject ORDER BY AVG(efficacy_score) DESC) AS rank_in_subject
FROM assignment_design GROUP BY subject, design_type
ORDER BY subject, rank_in_subject;

SELECT CASE WHEN class_size < 50 THEN '1 Small (<50)'
            WHEN class_size < 120 THEN '2 Medium (50-119)'
            ELSE '3 Large (120+)' END AS class_size_band,
       COUNT(*) AS courses,
       ROUND(100 * AVG(efficacy_score), 1) AS efficacy_pct,
       ROUND(100 * AVG(ai_detection_rate), 1) AS ai_detection_pct
FROM assignment_design GROUP BY class_size_band ORDER BY class_size_band;