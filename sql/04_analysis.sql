-- 04_analysis.sql  KPIs and business questions (Spark SQL dialect). Rates use COMPLETED inspections (Pass / Pass w/ Conditions / Fail)
-- as the denominator; Out of Business / No Entry / Not Ready / Business Not Located reports are not inspection outcomes.

-- working table (w_ = not exported): completed inspections with their dimensions
CREATE OR REPLACE TABLE w_base AS
SELECT f.*, d.year, d.month, d.month_name, d.year_month, d.weekday_num, d.day_name, r.result, r.result_group,
       t.inspection_type, t.type_group, fa.facility_group, fa.facility_type, k.risk
FROM fact_inspection f
JOIN dim_date d ON f.date_key = d.date_key JOIN dim_result r ON f.result_key = r.result_key
JOIN dim_inspection_type t ON f.inspection_type_key = t.inspection_type_key
JOIN dim_facility fa ON f.facility_key = fa.facility_key JOIN dim_risk k ON f.risk_key = k.risk_key
WHERE f.is_completed = 1;

-- Q1 result mix and its trend
CREATE OR REPLACE TABLE a_result_mix AS
SELECT r.result_key, r.result, r.result_group, COUNT(f.inspection_id) AS reports,
       ROUND(100.0 * COUNT(f.inspection_id) / (SELECT COUNT(*) FROM fact_inspection), 2) AS pct_of_reports,
       ROUND(CASE WHEN r.is_completed = 1 THEN 100.0 * COUNT(f.inspection_id) / (SELECT COUNT(*) FROM w_base) END, 2) AS pct_of_completed
FROM dim_result r LEFT JOIN fact_inspection f ON f.result_key = r.result_key
GROUP BY r.result_key, r.result, r.result_group, r.is_completed HAVING COUNT(f.inspection_id) > 0;

CREATE OR REPLACE TABLE a_yearly AS
WITH allr AS (SELECT d.year, COUNT(*) AS reports, SUM(CASE WHEN f.result_key = 4 THEN 1 ELSE 0 END) AS out_of_business,
                     SUM(CASE WHEN f.result_key IN (5, 6, 7) THEN 1 ELSE 0 END) AS no_entry_not_ready
              FROM fact_inspection f JOIN dim_date d ON f.date_key = d.date_key GROUP BY d.year)
SELECT b.year, CASE WHEN b.year = (SELECT MAX(year) FROM w_base) THEN 1 ELSE 0 END AS is_partial_year,
       a.reports, COUNT(*) AS completed, SUM(CASE WHEN result_key = 1 THEN 1 ELSE 0 END) AS passes,
       SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) AS pass_conditions, SUM(is_fail) AS fails,
       ROUND(100.0 * SUM(CASE WHEN result_key = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct,
       ROUND(AVG(n_citations), 2) AS avg_citations, a.out_of_business, a.no_entry_not_ready,
       COUNT(DISTINCT facility_key) AS facilities_inspected
FROM w_base b JOIN allr a ON b.year = a.year GROUP BY b.year, a.reports, a.out_of_business, a.no_entry_not_ready;

CREATE OR REPLACE TABLE a_era AS
SELECT code_scheme, CASE WHEN code_scheme = '2018' THEN '2018 Food Code form (from 1 Jul 2018)' ELSE '2010 form (to 30 Jun 2018)' END AS era,
       MIN(inspection_date) AS first_date, MAX(inspection_date) AS last_date, COUNT(*) AS completed,
       ROUND(100.0 * SUM(CASE WHEN result_key = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct, ROUND(AVG(n_citations), 2) AS avg_citations,
       ROUND(100.0 * SUM(CASE WHEN n_citations = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS no_citation_pct
FROM w_base GROUP BY code_scheme;

CREATE OR REPLACE TABLE a_monthly AS
SELECT year_month, COUNT(*) AS completed, SUM(is_fail) AS fails, ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct
FROM w_base GROUP BY year_month;

-- seasonality: full calendar years only (2010 .. last complete year)
CREATE OR REPLACE TABLE a_seasonal AS
SELECT month, month_name, COUNT(*) AS completed, ROUND(COUNT(*) / COUNT(DISTINCT year), 1) AS completed_per_year,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct,
       ROUND(100.0 * SUM(CASE WHEN type_group = 'Complaint' THEN 1 ELSE 0 END) / COUNT(*), 2) AS complaint_share_pct,
       ROUND(100.0 * SUM(CASE WHEN n_codes > 0 AND inspection_id IN (SELECT inspection_id FROM fact_violation v JOIN dim_violation dv
             ON v.violation_key = dv.violation_key WHERE dv.theme = 'Pests & rodents') THEN 1 ELSE 0 END) / COUNT(*), 2) AS pest_citation_pct
FROM w_base WHERE year < (SELECT MAX(year) FROM w_base) GROUP BY month, month_name;

CREATE OR REPLACE TABLE a_weekday AS
SELECT weekday_num, day_name, COUNT(*) AS completed, ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM w_base), 2) AS share_pct,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct
FROM w_base GROUP BY weekday_num, day_name;

-- Q2 facility types and risk
CREATE OR REPLACE TABLE a_facility_group AS
SELECT facility_group, COUNT(*) AS completed, COUNT(DISTINCT facility_key) AS facilities,
       ROUND(100.0 * SUM(CASE WHEN result_key = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct, ROUND(AVG(n_citations), 2) AS avg_citations
FROM w_base GROUP BY facility_group;

CREATE OR REPLACE TABLE a_facility_type_top AS
SELECT ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rnk, COALESCE(facility_type, '(blank)') AS facility_type, facility_group,
       COUNT(*) AS completed, ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct
FROM w_base GROUP BY facility_type, facility_group HAVING COUNT(*) >= 500;

CREATE OR REPLACE TABLE a_risk AS
SELECT risk_key, risk, COUNT(*) AS completed, COUNT(DISTINCT facility_key) AS facilities,
       ROUND(100.0 * SUM(CASE WHEN result_key = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct, ROUND(AVG(n_citations), 2) AS avg_citations,
       ROUND(COUNT(*) / COUNT(DISTINCT facility_key), 2) AS inspections_per_facility
FROM w_base GROUP BY risk_key, risk;

CREATE OR REPLACE TABLE a_risk_group AS
SELECT facility_group, risk_key, risk, COUNT(*) AS completed, ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct
FROM w_base WHERE risk_key > 0 GROUP BY facility_group, risk_key, risk;

-- Q3 geography: ZIP codes (>= 1,000 completed inspections) and the 77 community areas
CREATE OR REPLACE TABLE a_zip AS
SELECT ROW_NUMBER() OVER (ORDER BY SUM(is_fail) / COUNT(*) DESC) AS rnk, zip5, COUNT(*) AS completed, SUM(is_fail) AS fails,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct,
       COUNT(DISTINCT facility_key) AS facilities, ROUND(AVG(n_citations), 2) AS avg_citations,
       ROUND(100.0 * SUM(CASE WHEN type_group = 'Complaint' THEN 1 ELSE 0 END) / COUNT(*), 1) AS complaint_share_pct,
       ROUND(100.0 * SUM(CASE WHEN type_group = 'Canvass' AND is_reinspection = 0 THEN is_fail ELSE 0 END)
             / NULLIF(SUM(CASE WHEN type_group = 'Canvass' AND is_reinspection = 0 THEN 1 ELSE 0 END), 0), 2) AS canvass_fail_pct
FROM w_base WHERE zip5 IS NOT NULL GROUP BY zip5 HAVING COUNT(*) >= 1000;

-- community areas are ranked only with >= 500 completed inspections (74 of 77); rnk is NULL for the 3 smallest
CREATE OR REPLACE TABLE a_community_area AS
SELECT CASE WHEN completed >= 500 THEN ROW_NUMBER() OVER (ORDER BY CASE WHEN completed >= 500 THEN 0 ELSE 1 END, fail_pct DESC, area_num) END AS rnk, x.*
FROM (
SELECT b.area_num, c.community_area, COUNT(*) AS completed,
       SUM(b.is_fail) AS fails, ROUND(100.0 * SUM(b.is_fail) / COUNT(*), 2) AS fail_pct,
       ROUND(100.0 * SUM(CASE WHEN b.result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct,
       COUNT(DISTINCT b.facility_key) AS facilities, ROUND(AVG(b.n_citations), 2) AS avg_citations,
       ROUND(100.0 * SUM(CASE WHEN b.facility_group = 'Restaurant' THEN 1 ELSE 0 END) / COUNT(*), 1) AS restaurant_share_pct,
       ROUND(100.0 * SUM(CASE WHEN b.type_group = 'Complaint' THEN 1 ELSE 0 END) / COUNT(*), 1) AS complaint_share_pct,
       ROUND(100.0 * SUM(CASE WHEN b.type_group = 'Canvass' AND b.is_reinspection = 0 THEN b.is_fail ELSE 0 END)
             / NULLIF(SUM(CASE WHEN b.type_group = 'Canvass' AND b.is_reinspection = 0 THEN 1 ELSE 0 END), 0), 2) AS canvass_fail_pct,
       c.centroid_lat, c.centroid_lng
FROM w_base b JOIN dim_community_area c ON b.area_num = c.area_num WHERE b.area_num > 0
GROUP BY b.area_num, c.community_area, c.centroid_lat, c.centroid_lng) x;

-- is the neighbourhood gap just the inspection mix? correlate area fail rate with the routine-canvass fail rate and the complaint share
CREATE OR REPLACE TABLE a_geo_fit AS
SELECT COUNT(*) AS areas, ROUND(corr(fail_pct, canvass_fail_pct), 3) AS corr_fail_vs_canvass_fail,
       ROUND(corr(fail_pct, complaint_share_pct), 3) AS corr_fail_vs_complaint_share,
       MAX(canvass_fail_pct) AS canvass_fail_pct_max, MIN(canvass_fail_pct) AS canvass_fail_pct_min
FROM a_community_area WHERE rnk IS NOT NULL;

-- fail density map: 0.01 degree grid cells (about 1.1 km N-S x 0.8 km E-W) with >= 30 completed inspections
CREATE OR REPLACE TABLE a_map_grid AS
SELECT ROUND(FLOOR(fa.lat / 0.01) * 0.01 + 0.005, 3) AS cell_lat, ROUND(FLOOR(fa.lng / 0.01) * 0.01 + 0.005, 3) AS cell_lng,
       COUNT(*) AS completed, SUM(b.is_fail) AS fails, ROUND(100.0 * SUM(b.is_fail) / COUNT(*), 2) AS fail_pct,
       COUNT(DISTINCT b.facility_key) AS facilities
FROM w_base b JOIN dim_facility fa ON b.facility_key = fa.facility_key WHERE fa.lat IS NOT NULL
GROUP BY ROUND(FLOOR(fa.lat / 0.01) * 0.01 + 0.005, 3), ROUND(FLOOR(fa.lng / 0.01) * 0.01 + 0.005, 3) HAVING COUNT(*) >= 30;

-- Q4 re-inspections and repeat failure
CREATE OR REPLACE TABLE a_after_fail AS
WITH f AS (SELECT b.*, nt.is_reinspection AS next_is_reinspection FROM w_base b LEFT JOIN dim_inspection_type nt ON b.next_type_key = nt.inspection_type_key
           WHERE b.is_fail = 1),
g AS (SELECT 'All fails' AS failed_inspection_type, f.* FROM f
      UNION ALL SELECT concat(type_group, CASE WHEN is_reinspection = 1 THEN ' re-inspection' ELSE '' END), f.* FROM f
      WHERE type_group IN ('Canvass', 'Complaint', 'License'))
SELECT failed_inspection_type, COUNT(*) AS fails, SUM(CASE WHEN next_result_key IS NOT NULL THEN 1 ELSE 0 END) AS with_next_inspection,
       ROUND(100.0 * SUM(CASE WHEN next_result_key = 1 THEN 1 ELSE 0 END) / SUM(CASE WHEN next_result_key IS NOT NULL THEN 1 ELSE 0 END), 2) AS next_pass_pct,
       ROUND(100.0 * SUM(CASE WHEN next_result_key = 2 THEN 1 ELSE 0 END) / SUM(CASE WHEN next_result_key IS NOT NULL THEN 1 ELSE 0 END), 2) AS next_pass_conditions_pct,
       ROUND(100.0 * SUM(CASE WHEN next_result_key = 3 THEN 1 ELSE 0 END) / SUM(CASE WHEN next_result_key IS NOT NULL THEN 1 ELSE 0 END), 2) AS next_fail_pct,
       percentile_approx(days_to_next_completed, 0.5) AS median_days_to_next,
       ROUND(100.0 * SUM(CASE WHEN days_to_next_completed <= 30 THEN 1 ELSE 0 END) / COUNT(*), 2) AS next_within_30d_pct,
       ROUND(100.0 * SUM(CASE WHEN next_is_reinspection = 1 THEN 1 ELSE 0 END) / SUM(CASE WHEN next_result_key IS NOT NULL THEN 1 ELSE 0 END), 2) AS next_is_reinspection_pct
FROM g GROUP BY failed_inspection_type;

CREATE OR REPLACE TABLE a_reinspection_lag AS
SELECT CASE WHEN days_to_next_completed IS NULL THEN '9 none yet / closed' WHEN days_to_next_completed <= 7 THEN '1 0-7 days'
            WHEN days_to_next_completed <= 14 THEN '2 8-14 days' WHEN days_to_next_completed <= 30 THEN '3 15-30 days'
            WHEN days_to_next_completed <= 90 THEN '4 31-90 days' WHEN days_to_next_completed <= 365 THEN '5 91-365 days'
            ELSE '6 over 1 year' END AS lag_band,
       COUNT(*) AS fails, ROUND(100.0 * COUNT(*) / (SELECT SUM(is_fail) FROM w_base), 2) AS pct_of_fails,
       ROUND(100.0 * SUM(CASE WHEN next_result_key IN (1, 2) THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN next_result_key IS NOT NULL THEN 1 ELSE 0 END), 0), 2) AS next_passed_pct
FROM w_base WHERE is_fail = 1 GROUP BY 1;

CREATE OR REPLACE TABLE a_repeat_fail AS
SELECT CASE WHEN fails >= 5 THEN '5+' ELSE CAST(fails AS STRING) END AS fails_band, COUNT(*) AS facilities,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dim_facility WHERE completed_inspections > 0), 2) AS pct_of_facilities,
       SUM(fails) AS total_fails, ROUND(AVG(completed_inspections), 1) AS avg_completed_inspections
FROM dim_facility WHERE completed_inspections > 0 GROUP BY 1;

CREATE OR REPLACE TABLE a_top_fail_facilities AS
SELECT ROW_NUMBER() OVER (ORDER BY fails DESC, completed_inspections, facility_key) AS rnk, facility_key, license_no, dba_name, address,
       facility_group, completed_inspections, fails, ROUND(100.0 * fails / completed_inspections, 1) AS fail_pct, first_inspection, last_inspection
FROM dim_facility WHERE completed_inspections > 0
QUALIFY ROW_NUMBER() OVER (ORDER BY fails DESC, completed_inspections, facility_key) <= 15;

-- Q6 inspection programmes
CREATE OR REPLACE TABLE a_inspection_type AS
SELECT concat(type_group, CASE WHEN is_reinspection = 1 THEN ' re-inspection' ELSE '' END) AS inspection_kind, type_group, is_reinspection,
       COUNT(*) AS completed, ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM w_base), 2) AS share_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct, ROUND(AVG(n_citations), 2) AS avg_citations
FROM w_base GROUP BY type_group, is_reinspection HAVING COUNT(*) >= 100;

CREATE OR REPLACE TABLE a_type_year AS
SELECT year, type_group, COUNT(*) AS completed, ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct
FROM w_base WHERE is_reinspection = 0 AND type_group IN ('Canvass', 'Complaint', 'License') GROUP BY year, type_group;

-- Q5 violations: themes, codes and citation levels behind failures
CREATE OR REPLACE TABLE w_insp_theme AS
SELECT DISTINCT v.inspection_id, dv.code_scheme, dv.theme FROM fact_violation v JOIN dim_violation dv ON v.violation_key = dv.violation_key;

CREATE OR REPLACE TABLE a_violation_theme AS
WITH den AS (SELECT code_scheme, SUM(is_fail) AS n_fail, SUM(CASE WHEN result_key = 1 THEN 1 ELSE 0 END) AS n_pass,
                    SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) AS n_pwc FROM w_base GROUP BY code_scheme)
SELECT b.code_scheme, t.theme, COUNT(*) AS inspections_cited,
       ROUND(100.0 * SUM(b.is_fail) / MAX(den.n_fail), 2) AS pct_of_failed,
       ROUND(100.0 * SUM(CASE WHEN b.result_key = 2 THEN 1 ELSE 0 END) / MAX(den.n_pwc), 2) AS pct_of_pass_conditions,
       ROUND(100.0 * SUM(CASE WHEN b.result_key = 1 THEN 1 ELSE 0 END) / MAX(den.n_pass), 2) AS pct_of_passed,
       ROUND((1.0 * SUM(b.is_fail) / MAX(den.n_fail)) / NULLIF(1.0 * SUM(CASE WHEN b.result_key = 1 THEN 1 ELSE 0 END) / MAX(den.n_pass), 0), 2) AS fail_vs_pass_ratio
FROM w_base b JOIN w_insp_theme t ON b.inspection_id = t.inspection_id JOIN den ON b.code_scheme = den.code_scheme
GROUP BY b.code_scheme, t.theme;

CREATE OR REPLACE TABLE a_violation_top AS
WITH den AS (SELECT code_scheme, SUM(is_fail) AS n_fail, SUM(CASE WHEN result_key = 1 THEN 1 ELSE 0 END) AS n_pass FROM w_base GROUP BY code_scheme),
x AS (SELECT DISTINCT v.inspection_id, v.violation_key FROM fact_violation v),
s AS (SELECT dv.code_scheme, dv.code, dv.violation_id, dv.title, dv.official_class, dv.theme, COUNT(*) AS inspections_cited,
             SUM(b.is_fail) AS failed_cited, SUM(CASE WHEN b.result_key = 1 THEN 1 ELSE 0 END) AS passed_cited
      FROM x JOIN w_base b ON x.inspection_id = b.inspection_id JOIN dim_violation dv ON x.violation_key = dv.violation_key
      GROUP BY dv.code_scheme, dv.code, dv.violation_id, dv.title, dv.official_class, dv.theme)
SELECT ROW_NUMBER() OVER (PARTITION BY s.code_scheme ORDER BY s.failed_cited DESC) AS rnk, s.*,
       ROUND(100.0 * s.failed_cited / den.n_fail, 2) AS pct_of_failed, ROUND(100.0 * s.passed_cited / den.n_pass, 2) AS pct_of_passed,
       ROUND(100.0 * s.failed_cited / s.inspections_cited, 2) AS fail_pct_when_cited
FROM s JOIN den ON s.code_scheme = den.code_scheme
QUALIFY ROW_NUMBER() OVER (PARTITION BY s.code_scheme ORDER BY s.failed_cited DESC) <= 15;

-- most severe citation on the inspection -> outcome (2010 form: Critical / Serious / Minor; 2018 form: Priority / Priority foundation / Core)
CREATE OR REPLACE TABLE a_fail_driver AS
SELECT code_scheme,
       CASE WHEN code_scheme = '2018' THEN CASE WHEN n_priority > 0 THEN '1 Priority' WHEN n_priority_foundation > 0 THEN '2 Priority foundation'
                                                WHEN n_citations > 0 THEN '3 Core / untagged only' ELSE '4 No citations' END
            ELSE CASE WHEN n_critical_2010 > 0 THEN '1 Critical' WHEN n_serious_2010 > 0 THEN '2 Serious'
                      WHEN n_citations > 0 THEN '3 Minor / other only' ELSE '4 No citations' END END AS worst_citation,
       COUNT(*) AS completed, ROUND(100.0 * SUM(CASE WHEN result_key = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_pct,
       ROUND(100.0 * SUM(CASE WHEN result_key = 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_conditions_pct,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct,
       ROUND(100.0 * SUM(is_fail) / (SELECT SUM(is_fail) FROM w_base a WHERE a.code_scheme = b.code_scheme), 2) AS share_of_fails
FROM w_base b GROUP BY 1, 2;

CREATE OR REPLACE TABLE a_citation_count AS
SELECT code_scheme, CASE WHEN n_citations >= 12 THEN 12 ELSE n_citations END AS citations, COUNT(*) AS completed,
       ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) AS fail_pct
FROM w_base GROUP BY 1, 2;

-- headline KPIs (one row)
CREATE OR REPLACE TABLE a_kpi_headline AS
SELECT
  (SELECT COUNT(*) FROM stg_inspections) AS raw_rows,
  (SELECT COUNT(*) FROM fact_inspection) AS inspection_reports,
  (SELECT COUNT(*) FROM stg_inspections) - (SELECT COUNT(*) FROM fact_inspection) AS exact_duplicates_removed,
  (SELECT COUNT(*) FROM w_base) AS completed_inspections,
  (SELECT COUNT(*) FROM fact_inspection WHERE is_completed = 0) AS not_inspected_reports,
  (SELECT COUNT(*) FROM dim_facility) AS facilities,
  (SELECT CAST(MIN(inspection_date) AS STRING) FROM fact_inspection) AS first_date,
  (SELECT CAST(MAX(inspection_date) AS STRING) FROM fact_inspection) AS last_date,
  (SELECT pct_of_completed FROM a_result_mix WHERE result_key = 1) AS pass_pct,
  (SELECT pct_of_completed FROM a_result_mix WHERE result_key = 2) AS pass_conditions_pct,
  (SELECT pct_of_completed FROM a_result_mix WHERE result_key = 3) AS fail_pct,
  (SELECT fail_pct FROM a_era WHERE code_scheme = '2010') AS fail_pct_2010_form,
  (SELECT fail_pct FROM a_era WHERE code_scheme = '2018') AS fail_pct_2018_form,
  (SELECT pass_conditions_pct FROM a_era WHERE code_scheme = '2010') AS pass_conditions_pct_2010_form,
  (SELECT pass_conditions_pct FROM a_era WHERE code_scheme = '2018') AS pass_conditions_pct_2018_form,
  (SELECT COUNT(*) FROM fact_violation) AS violation_citations,
  (SELECT ROUND(AVG(n_citations), 2) FROM w_base) AS avg_citations_per_inspection,
  (SELECT fail_pct FROM a_inspection_type WHERE inspection_kind = 'Canvass') AS canvass_fail_pct,
  (SELECT fail_pct FROM a_inspection_type WHERE inspection_kind = 'Complaint') AS complaint_fail_pct,
  (SELECT fail_pct FROM a_inspection_type WHERE inspection_kind = 'License') AS license_fail_pct,
  (SELECT ROUND(100.0 * SUM(is_fail) / COUNT(*), 2) FROM w_base WHERE is_reinspection = 1) AS reinspection_fail_pct,
  (SELECT next_pass_pct FROM a_after_fail WHERE failed_inspection_type = 'All fails') AS after_fail_next_pass_pct,
  (SELECT next_pass_conditions_pct FROM a_after_fail WHERE failed_inspection_type = 'All fails') AS after_fail_next_pass_conditions_pct,
  (SELECT next_fail_pct FROM a_after_fail WHERE failed_inspection_type = 'All fails') AS after_fail_next_fail_pct,
  (SELECT median_days_to_next FROM a_after_fail WHERE failed_inspection_type = 'All fails') AS after_fail_median_days_to_next,
  (SELECT ROUND(100.0 * SUM(CASE WHEN fails > 0 THEN 1 ELSE 0 END) / COUNT(*), 2) FROM dim_facility WHERE completed_inspections > 0) AS facilities_ever_failed_pct,
  (SELECT ROUND(100.0 * SUM(CASE WHEN fails >= 2 THEN 1 ELSE 0 END) / SUM(CASE WHEN fails >= 1 THEN 1 ELSE 0 END), 2) FROM dim_facility) AS repeat_fail_pct_of_failed_facilities,
  (SELECT fail_pct FROM a_risk WHERE risk_key = 1) AS high_risk_fail_pct,
  (SELECT fail_pct FROM a_risk WHERE risk_key = 3) AS low_risk_fail_pct,
  (SELECT fail_pct FROM a_fail_driver WHERE code_scheme = '2018' AND worst_citation = '1 Priority') AS priority_citation_fail_pct,
  (SELECT fail_pct FROM a_fail_driver WHERE code_scheme = '2018' AND worst_citation = '3 Core / untagged only') AS core_only_fail_pct,
  (SELECT COUNT(*) FROM a_zip) AS zips_ranked,
  (SELECT MAX(fail_pct) FROM a_zip) AS zip_fail_pct_max, (SELECT MIN(fail_pct) FROM a_zip) AS zip_fail_pct_min,
  (SELECT COUNT(*) FROM a_community_area WHERE rnk IS NOT NULL) AS areas_ranked,
  (SELECT MAX(fail_pct) FROM a_community_area WHERE rnk IS NOT NULL) AS area_fail_pct_max,
  (SELECT MIN(fail_pct) FROM a_community_area WHERE rnk IS NOT NULL) AS area_fail_pct_min;
