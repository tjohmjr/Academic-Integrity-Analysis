SELECT d.tool,
       ROUND(100 * AVG(d.detected_as_ai), 2) AS computed_fpr_pct,
       ROUND(100 * CAST(f.detected_as_ai AS REAL), 2) AS published_fpr_pct
FROM detector_results d
JOIN c_false_positive_rates f ON f.tool = d.tool
WHERE d.actual_type = 'human_written'
GROUP BY d.tool, f.detected_as_ai
ORDER BY computed_fpr_pct;

DROP VIEW IF EXISTS v_detector_confusion;
CREATE VIEW v_detector_confusion AS
SELECT tool,
       SUM(actual_type = 'ai_generated'  AND detected_as_ai = 1) AS tp,
       SUM(actual_type = 'human_written' AND detected_as_ai = 1) AS fp,
       SUM(actual_type = 'human_written' AND detected_as_ai = 0) AS tn,
       SUM(actual_type = 'ai_generated'  AND detected_as_ai = 0) AS fn
FROM detector_results
WHERE actual_type IN ('ai_generated', 'human_written')
GROUP BY tool;

SELECT tool, tp, fp, tn, fn,
       ROUND(1.0 * tp / (tp + fp), 3)                       AS precision_,
       ROUND(1.0 * tp / (tp + fn), 3)                       AS recall_tpr,
       ROUND(1.0 * fp / (fp + tn), 3)                       AS false_positive_rate,
       ROUND(2.0 * tp / (2 * tp + fp + fn), 3)              AS f1,
       ROUND(1.0 * (tp + tn) / (tp + fp + tn + fn), 3)      AS accuracy,
       ROUND((1.0 * tp / (tp + fn) + 1.0 * tn / (tn + fp)) / 2, 3) AS balanced_accuracy,
       ROUND(1.0 * (tp * tn - fp * fn) /
             SQRT(1.0 * (tp + fp) * (tp + fn) * (tn + fp) * (tn + fn)), 3) AS mcc,
       RANK() OVER (ORDER BY 1.0 * (tp * tn - fp * fn) /
             SQRT(1.0 * (tp + fp) * (tp + fn) * (tn + fp) * (tn + fn)) DESC) AS mcc_rank
FROM v_detector_confusion
ORDER BY mcc_rank;

SELECT tool,
       ROUND(1000.0 * fp / (fp + tn)) AS honest_students_flagged_per_1000,
       ROUND(1000.0 * fn / (fn + tp)) AS ai_essays_missed_per_1000
FROM v_detector_confusion ORDER BY honest_students_flagged_per_1000;

SELECT tool,
       ROUND(100 * AVG(CASE WHEN actual_type = 'human_written' THEN detected_as_ai END), 1) AS pct_flagged_human,
       ROUND(100 * AVG(CASE WHEN actual_type = 'mixed'         THEN detected_as_ai END), 1) AS pct_flagged_mixed,
       ROUND(100 * AVG(CASE WHEN actual_type = 'ai_generated'  THEN detected_as_ai END), 1) AS pct_flagged_ai,
       ROUND(AVG(CASE WHEN actual_type = 'mixed' THEN detection_probability END), 3) AS avg_prob_mixed
FROM detector_results GROUP BY tool ORDER BY pct_flagged_mixed DESC;

SELECT grade_level,
       COUNT(*) AS human_texts,
       ROUND(100 * AVG(detected_as_ai), 2) AS fpr_pct,
       ROUND(100 * (AVG(detected_as_ai) -
             (SELECT AVG(detected_as_ai) FROM detector_results WHERE actual_type = 'human_written')), 2)
             AS pp_vs_overall
FROM detector_results WHERE actual_type = 'human_written'
GROUP BY grade_level ORDER BY fpr_pct DESC;

WITH s AS (
  SELECT subject, COUNT(*) AS n, 1.0 * SUM(detected_as_ai) AS fp
  FROM detector_results WHERE actual_type = 'human_written' GROUP BY subject
), t AS (SELECT 1.0 * SUM(n) AS n_all, SUM(fp) AS fp_all FROM s)
SELECT s.subject, s.n AS human_texts,
       ROUND(100 * s.fp / s.n, 2) AS fpr_pct,
       ROUND(100 * (t.fp_all - s.fp) / (t.n_all - s.n), 2) AS fpr_rest_pct,
       ROUND((s.fp / s.n - (t.fp_all - s.fp) / (t.n_all - s.n)) /
             SQRT((t.fp_all / t.n_all) * (1 - t.fp_all / t.n_all) * (1.0 / s.n + 1.0 / (t.n_all - s.n))), 2)
             AS z_score,
       CASE WHEN ABS((s.fp / s.n - (t.fp_all - s.fp) / (t.n_all - s.n)) /
             SQRT((t.fp_all / t.n_all) * (1 - t.fp_all / t.n_all) * (1.0 / s.n + 1.0 / (t.n_all - s.n)))) >= 1.96
            THEN 'Significant (p<0.05)' ELSE 'Not significant' END AS verdict
FROM s CROSS JOIN t ORDER BY fpr_pct DESC;

SELECT CASE WHEN text_length < 1000 THEN '1 <1,000 chars'
            WHEN text_length < 2500 THEN '2 1,000-2,499'
            WHEN text_length < 4000 THEN '3 2,500-3,999'
            ELSE '4 4,000+' END AS length_band,
       COUNT(*) AS human_texts,
       ROUND(100 * AVG(detected_as_ai), 2) AS fpr_pct
FROM detector_results WHERE actual_type = 'human_written'
GROUP BY length_band ORDER BY length_band;

SELECT tool,
       ROUND(100 * AVG(CASE WHEN grade_level = 'Freshman'  THEN detected_as_ai END), 1) AS freshman,
       ROUND(100 * AVG(CASE WHEN grade_level = 'Sophomore' THEN detected_as_ai END), 1) AS sophomore,
       ROUND(100 * AVG(CASE WHEN grade_level = 'Junior'    THEN detected_as_ai END), 1) AS junior,
       ROUND(100 * AVG(CASE WHEN grade_level = 'Senior'    THEN detected_as_ai END), 1) AS senior,
       ROUND(100 * AVG(CASE WHEN grade_level = 'Graduate'  THEN detected_as_ai END), 1) AS graduate
FROM detector_results WHERE actual_type = 'human_written'
GROUP BY tool ORDER BY tool;

SELECT actual_type,
       ROUND(MIN(detection_probability), 3) AS min_prob,
       ROUND(MAX(detection_probability), 3) AS max_prob,
       ROUND(AVG(detection_probability), 3) AS avg_prob
FROM detector_results GROUP BY actual_type ORDER BY avg_prob;

DROP TABLE IF EXISTS detector_roc;
CREATE TABLE detector_roc AS
WITH RECURSIVE steps (i) AS (
  SELECT 0
  UNION ALL SELECT i + 1 FROM steps WHERE i < 100
)
SELECT d.tool, st.i / 100.0 AS threshold,
       1.0 * SUM(d.actual_type = 'ai_generated'  AND d.detection_probability >= st.i / 100.0)
         / SUM(d.actual_type = 'ai_generated')  AS tpr,
       1.0 * SUM(d.actual_type = 'human_written' AND d.detection_probability >= st.i / 100.0)
         / SUM(d.actual_type = 'human_written') AS fpr
FROM detector_results d CROSS JOIN steps st
WHERE d.actual_type IN ('ai_generated', 'human_written')
GROUP BY d.tool, st.i;

SELECT tool,
       ROUND(SUM((prev_fpr - fpr) * (tpr + prev_tpr) / 2), 4) AS roc_auc
FROM (SELECT tool, tpr, fpr,
             LAG(fpr, 1, 1) OVER (PARTITION BY tool ORDER BY threshold) AS prev_fpr,
             LAG(tpr, 1, 1) OVER (PARTITION BY tool ORDER BY threshold) AS prev_tpr
      FROM detector_roc) r
GROUP BY tool ORDER BY roc_auc DESC;

WITH best AS (
  SELECT tool, threshold, tpr, fpr, tpr - fpr AS youden_j,
         ROW_NUMBER() OVER (PARTITION BY tool ORDER BY tpr - fpr DESC, threshold) AS rn
  FROM detector_roc
)
SELECT b.tool, b.threshold AS best_threshold,
       ROUND(b.tpr, 3) AS tpr_at_best, ROUND(b.fpr, 3) AS fpr_at_best,
       ROUND(1.0 * c.tp / (c.tp + c.fn), 3) AS tool_default_tpr,
       ROUND(1.0 * c.fp / (c.fp + c.tn), 3) AS tool_default_fpr,
       ROUND(b.youden_j - (1.0 * c.tp / (c.tp + c.fn) - 1.0 * c.fp / (c.fp + c.tn)), 3) AS j_improvement
FROM best b JOIN v_detector_confusion c USING (tool)
WHERE b.rn = 1 ORDER BY j_improvement DESC;

SELECT tool, MIN(threshold) AS lowest_threshold_with_fpr_le_1pct,
       ROUND(MAX(tpr), 3) AS recall_at_that_threshold
FROM detector_roc
WHERE fpr <= 0.01
GROUP BY tool ORDER BY recall_at_that_threshold DESC;

SELECT CAST(detection_probability * 10 AS INTEGER) / 10.0 AS prob_bucket,
       COUNT(*) AS texts,
       ROUND(AVG(detection_probability), 3) AS avg_predicted,
       ROUND(AVG(actual_type = 'ai_generated'), 3) AS actual_ai_share,
       ROUND(AVG(actual_type = 'ai_generated') - AVG(detection_probability), 3) AS calibration_gap
FROM detector_results
WHERE actual_type IN ('ai_generated', 'human_written')
GROUP BY prob_bucket ORDER BY prob_bucket;

SELECT CASE detected_as_ai WHEN 1 THEN 'False positive' ELSE 'True negative' END AS result,
       COUNT(*) AS texts,
       ROUND(AVG(text_length)) AS avg_length,
       ROUND(AVG(perplexity_score), 3) AS avg_perplexity,
       ROUND(AVG(writing_style_score), 3) AS avg_style_score,
       ROUND(AVG(confidence_score), 3) AS avg_tool_confidence,
       ROUND(AVG(detection_probability), 3) AS avg_detection_prob
FROM detector_results WHERE actual_type = 'human_written'
GROUP BY detected_as_ai;

SELECT tool,
       ROUND(AVG(CASE WHEN correct = 1 THEN confidence_score END), 3) AS avg_conf_when_right,
       ROUND(AVG(CASE WHEN correct = 0 THEN confidence_score END), 3) AS avg_conf_when_wrong
FROM (SELECT tool, confidence_score,
             (detected_as_ai = (actual_type = 'ai_generated')) AS correct
      FROM detector_results WHERE actual_type <> 'mixed') x
GROUP BY tool ORDER BY tool;
