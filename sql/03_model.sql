-- 03_model.sql  Star schema (Spark SQL dialect)
--   fact_inspection (one row per distinct inspection report)  ->  dim_date, dim_facility, dim_result, dim_inspection_type, dim_risk,
--                                                                 dim_community_area
--   fact_violation  (one row per cited violation item)         ->  fact_inspection, dim_violation
--   agg_zip_month, agg_area_year, agg_facility_year (pre-aggregated for Power BI / the charts)

CREATE OR REPLACE TABLE dim_date AS
SELECT CAST(date_format(d, 'yyyyMMdd') AS INT) AS date_key, d AS date, year(d) AS year, month(d) AS month,
       date_format(d, 'MMM') AS month_name, date_format(d, 'yyyy-MM') AS year_month, quarter(d) AS quarter,
       weekday(d) + 1 AS weekday_num, CASE weekday(d) WHEN 0 THEN 'Mon' WHEN 1 THEN 'Tue' WHEN 2 THEN 'Wed' WHEN 3 THEN 'Thu'
       WHEN 4 THEN 'Fri' WHEN 5 THEN 'Sat' ELSE 'Sun' END AS day_name,
       CASE WHEN weekday(d) >= 5 THEN 1 ELSE 0 END AS is_weekend,
       CASE WHEN d >= DATE'2018-07-01' THEN '2018 Food Code form' ELSE '2010 form' END AS code_era
FROM (SELECT CAST(explode(sequence((SELECT make_date(year(MIN(inspection_date)), 1, 1) FROM cln_inspections),
                                   (SELECT MAX(inspection_date) FROM cln_inspections))) AS DATE) AS d) x;

CREATE OR REPLACE TABLE dim_result AS
SELECT * FROM (VALUES (1, 'Pass', 'Pass', 1), (2, 'Pass w/ Conditions', 'Pass w/ Conditions', 1), (3, 'Fail', 'Fail', 1),
                      (4, 'Out of Business', 'Not inspected', 0), (5, 'No Entry', 'Not inspected', 0), (6, 'Not Ready', 'Not inspected', 0),
                      (7, 'Business Not Located', 'Not inspected', 0), (0, 'Unknown', 'Not inspected', 0))
  AS r(result_key, result, result_group, is_completed);

CREATE OR REPLACE TABLE dim_risk AS
SELECT * FROM (VALUES (1, 'Risk 1 (High)', 'High'), (2, 'Risk 2 (Medium)', 'Medium'), (3, 'Risk 3 (Low)', 'Low'),
                      (0, 'Unknown / All', 'Unknown')) AS r(risk_key, risk, risk_short);

CREATE OR REPLACE TABLE dim_inspection_type AS
SELECT ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, COALESCE(inspection_type, '')) AS inspection_type_key,
       COALESCE(inspection_type, 'UNKNOWN') AS inspection_type, type_group, is_reinspection, COUNT(*) AS reports
FROM cln_inspections GROUP BY inspection_type, type_group, is_reinspection;

CREATE OR REPLACE TABLE dim_community_area AS
SELECT CAST(area_num AS INT) AS area_num, community_area, CAST(centroid_lat AS DOUBLE) AS centroid_lat,
       CAST(centroid_lng AS DOUBLE) AS centroid_lng, CAST(area_km2 AS DOUBLE) AS area_km2
FROM ref_community_area
UNION ALL SELECT 0, 'Unknown / outside', NULL, NULL, NULL;

-- one row per facility (license number; reports without a license are keyed by name + address). Attributes = latest report.
CREATE OR REPLACE TABLE dim_facility AS
WITH r AS (
  SELECT c.*, ROW_NUMBER() OVER (PARTITION BY facility_id ORDER BY inspection_date DESC, inspection_id DESC) AS rn FROM cln_inspections c),
s AS (
  SELECT facility_id, COUNT(*) AS reports, SUM(is_completed) AS completed_inspections, SUM(is_fail) AS fails,
         MIN(inspection_date) AS first_inspection, MAX(inspection_date) AS last_inspection,
         COUNT(DISTINCT dba_name) AS n_names, COUNT(DISTINCT address) AS n_addresses,
         MAX(CASE WHEN result = 'Out of Business' THEN 1 ELSE 0 END) AS ever_out_of_business
  FROM cln_inspections GROUP BY facility_id)
SELECT DENSE_RANK() OVER (ORDER BY r.facility_id) AS facility_key, r.facility_id, r.license_no, r.dba_name, r.aka_name, r.address,
       r.zip5, r.city, r.facility_type, r.facility_group, r.risk_level AS latest_risk_level, r.lat, r.lng, COALESCE(r.area_num, 0) AS area_num,
       s.reports, s.completed_inspections, s.fails, s.first_inspection, s.last_inspection, s.n_names, s.n_addresses, s.ever_out_of_business
FROM r JOIN s ON r.facility_id = s.facility_id WHERE r.rn = 1;

-- per-inspection violation counts
CREATE OR REPLACE TABLE cln_violation_counts AS
SELECT c.inspection_id, COUNT(*) AS n_citations, COUNT(DISTINCT c.code) AS n_codes,
       SUM(CASE WHEN citation_level = 'Priority' THEN 1 ELSE 0 END) AS n_priority,
       SUM(CASE WHEN citation_level = 'Priority foundation' THEN 1 ELSE 0 END) AS n_priority_foundation,
       SUM(CASE WHEN citation_level = 'Core' THEN 1 ELSE 0 END) AS n_core,
       SUM(CASE WHEN v.official_class = 'Critical' THEN 1 ELSE 0 END) AS n_critical_2010,
       SUM(CASE WHEN v.official_class = 'Serious' THEN 1 ELSE 0 END) AS n_serious_2010,
       SUM(CASE WHEN v.official_class = 'Minor' THEN 1 ELSE 0 END) AS n_minor_2010
FROM cln_violations c LEFT JOIN ref_violation_codes v ON c.code_scheme = v.code_scheme AND c.code = CAST(v.code AS INT)
GROUP BY c.inspection_id;

CREATE OR REPLACE TABLE fact_inspection AS
WITH f AS (
  SELECT c.inspection_id, CAST(date_format(c.inspection_date, 'yyyyMMdd') AS INT) AS date_key, c.inspection_date,
         d.facility_key, COALESCE(r.result_key, 0) AS result_key, t.inspection_type_key, c.risk_level AS risk_key,
         COALESCE(c.area_num, 0) AS area_num, c.zip5, c.code_scheme, c.is_completed, c.is_fail, c.is_reinspection,
         COALESCE(v.n_citations, 0) AS n_citations, COALESCE(v.n_codes, 0) AS n_codes, COALESCE(v.n_priority, 0) AS n_priority,
         COALESCE(v.n_priority_foundation, 0) AS n_priority_foundation, COALESCE(v.n_core, 0) AS n_core,
         COALESCE(v.n_critical_2010, 0) AS n_critical_2010, COALESCE(v.n_serious_2010, 0) AS n_serious_2010,
         COALESCE(v.n_minor_2010, 0) AS n_minor_2010
  FROM cln_inspections c
  JOIN dim_facility d ON c.facility_id = d.facility_id
  LEFT JOIN dim_result r ON c.result = r.result
  JOIN dim_inspection_type t ON COALESCE(c.inspection_type, 'UNKNOWN') = t.inspection_type AND c.type_group = t.type_group
       AND c.is_reinspection = t.is_reinspection
  LEFT JOIN cln_violation_counts v ON c.inspection_id = v.inspection_id),
-- previous / next COMPLETED inspection of the same facility (re-inspection analysis)
cmp AS (
  SELECT inspection_id, facility_key, inspection_date, result_key,
         LAG(result_key) OVER (PARTITION BY facility_key ORDER BY inspection_date, inspection_id) AS prev_result_key,
         LAG(inspection_date) OVER (PARTITION BY facility_key ORDER BY inspection_date, inspection_id) AS prev_date,
         LEAD(result_key) OVER (PARTITION BY facility_key ORDER BY inspection_date, inspection_id) AS next_result_key,
         LEAD(inspection_date) OVER (PARTITION BY facility_key ORDER BY inspection_date, inspection_id) AS next_date,
         LEAD(inspection_type_key) OVER (PARTITION BY facility_key ORDER BY inspection_date, inspection_id) AS next_type_key,
         ROW_NUMBER() OVER (PARTITION BY facility_key ORDER BY inspection_date, inspection_id) AS completed_seq
  FROM f WHERE is_completed = 1)
SELECT f.*, cmp.completed_seq, cmp.prev_result_key, days_between(cmp.prev_date, f.inspection_date) AS days_since_prev_completed,
       cmp.next_result_key, days_between(f.inspection_date, cmp.next_date) AS days_to_next_completed, cmp.next_type_key
FROM f LEFT JOIN cmp ON f.inspection_id = cmp.inspection_id;

CREATE OR REPLACE TABLE dim_violation AS
SELECT ROW_NUMBER() OVER (ORDER BY code_scheme, CAST(code AS INT)) AS violation_key, code_scheme, CAST(code AS INT) AS code,
       concat(code_scheme, '-', lpad(code, 2, '0')) AS violation_id, title, official_class, theme
FROM ref_violation_codes;

CREATE OR REPLACE TABLE fact_violation AS
SELECT c.inspection_id, f.date_key, f.facility_key, f.result_key, f.inspection_type_key, v.violation_key, c.code_scheme, c.code,
       c.citation_level, c.has_comments
FROM cln_violations c JOIN fact_inspection f ON c.inspection_id = f.inspection_id
LEFT JOIN dim_violation v ON c.code_scheme = v.code_scheme AND c.code = v.code;

CREATE OR REPLACE TABLE agg_zip_month AS
SELECT COALESCE(f.zip5, 'unknown') AS zip5, d.year_month, COUNT(*) AS reports, SUM(f.is_completed) AS completed,
       SUM(CASE WHEN f.result_key = 1 THEN 1 ELSE 0 END) AS passes, SUM(CASE WHEN f.result_key = 2 THEN 1 ELSE 0 END) AS pass_conditions,
       SUM(f.is_fail) AS fails, SUM(CASE WHEN f.is_completed = 1 THEN f.n_citations ELSE 0 END) AS citations
FROM fact_inspection f JOIN dim_date d ON f.date_key = d.date_key GROUP BY COALESCE(f.zip5, 'unknown'), d.year_month;

CREATE OR REPLACE TABLE agg_area_year AS
SELECT f.area_num, d.year, COUNT(*) AS reports, SUM(f.is_completed) AS completed,
       SUM(CASE WHEN f.result_key = 1 THEN 1 ELSE 0 END) AS passes, SUM(CASE WHEN f.result_key = 2 THEN 1 ELSE 0 END) AS pass_conditions,
       SUM(f.is_fail) AS fails, COUNT(DISTINCT f.facility_key) AS facilities
FROM fact_inspection f JOIN dim_date d ON f.date_key = d.date_key GROUP BY f.area_num, d.year;

CREATE OR REPLACE TABLE agg_facility_year AS
SELECT f.facility_key, d.year, COUNT(*) AS reports, SUM(f.is_completed) AS completed, SUM(f.is_fail) AS fails,
       SUM(CASE WHEN f.result_key = 2 THEN 1 ELSE 0 END) AS pass_conditions, SUM(f.n_citations) AS citations
FROM fact_inspection f JOIN dim_date d ON f.date_key = d.date_key GROUP BY f.facility_key, d.year;
