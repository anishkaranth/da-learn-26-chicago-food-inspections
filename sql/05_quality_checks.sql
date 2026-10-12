-- 05_quality_checks.sql  Data-quality evidence: before/after counts, issue counts, null rates, assertions (Spark SQL dialect)

CREATE OR REPLACE TABLE dq_row_counts AS
SELECT 'raw inspection rows (food_inspections.csv)' AS entity, (SELECT COUNT(*) FROM stg_inspections) AS raw_rows,
       (SELECT COUNT(*) FROM cln_distinct) AS distinct_rows, (SELECT COUNT(*) FROM fact_inspection) AS clean_rows,
       'inspection report (clean = fact_inspection)' AS grain
UNION ALL SELECT 'completed inspections (Pass / Pass w/ Conditions / Fail)', NULL, NULL, (SELECT SUM(is_completed) FROM fact_inspection), 'inspection'
UNION ALL SELECT 'reports without an outcome (Out of Business, No Entry, Not Ready, Not Located)', NULL, NULL,
       (SELECT COUNT(*) FROM fact_inspection WHERE is_completed = 0), 'report'
UNION ALL SELECT 'violation items parsed from the Violations text (fact_violation)', NULL, NULL, (SELECT COUNT(*) FROM fact_violation), 'cited violation'
UNION ALL SELECT 'dim_facility', NULL, NULL, (SELECT COUNT(*) FROM dim_facility), 'license number (or name + address when no license)'
UNION ALL SELECT 'dim_date', NULL, NULL, (SELECT COUNT(*) FROM dim_date), 'day, 2010-01-01 .. last inspection'
UNION ALL SELECT 'dim_inspection_type', NULL, NULL, (SELECT COUNT(*) FROM dim_inspection_type), 'standardised inspection type'
UNION ALL SELECT 'dim_violation', NULL, NULL, (SELECT COUNT(*) FROM dim_violation), 'code on the 2010 form or the 2018 form'
UNION ALL SELECT 'dim_community_area (77 + unknown)', NULL, NULL, (SELECT COUNT(*) FROM dim_community_area), 'community area'
UNION ALL SELECT 'dim_result / dim_risk', NULL, NULL, (SELECT COUNT(*) FROM dim_result) + (SELECT COUNT(*) FROM dim_risk), '8 + 4'
UNION ALL SELECT 'agg_zip_month', NULL, NULL, (SELECT COUNT(*) FROM agg_zip_month), 'ZIP x month'
UNION ALL SELECT 'agg_area_year', NULL, NULL, (SELECT COUNT(*) FROM agg_area_year), 'community area x year'
UNION ALL SELECT 'agg_facility_year', NULL, NULL, (SELECT COUNT(*) FROM agg_facility_year), 'facility x year';

CREATE OR REPLACE TABLE dq_null_rates AS
SELECT 'raw' AS entity, 'License #' AS column_name,
       ROUND(100.0 * SUM(CASE WHEN COALESCE(CAST(license_no AS BIGINT), 0) = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_pct,
       'blank or 0: facility keyed by name + address instead' AS treatment FROM stg_inspections
UNION ALL SELECT 'raw', 'Facility Type', ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(facility_type), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'kept, facility_group = Unknown' FROM stg_inspections
UNION ALL SELECT 'raw', 'Risk (blank or All)', ROUND(100.0 * SUM(CASE WHEN risk IS NULL OR risk = 'All' THEN 1 ELSE 0 END) / COUNT(*), 2),
       'kept, risk_key = 0 (Unknown / All)' FROM stg_inspections
UNION ALL SELECT 'raw', 'City', ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(city), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'imputed CHICAGO when the ZIP is a Chicago ZIP' FROM stg_inspections
UNION ALL SELECT 'raw', 'Zip', ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(zip), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'kept, left out of the ZIP ranking' FROM stg_inspections
UNION ALL SELECT 'raw', 'Latitude / Longitude', ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(latitude), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'not geocoded: kept, community area 0 (unknown)' FROM stg_inspections
UNION ALL SELECT 'raw', 'Violations', ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(violations), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'no violation cited (normal for clean passes and non-inspections)' FROM stg_inspections
UNION ALL SELECT 'raw', 'AKA Name', ROUND(100.0 * SUM(CASE WHEN NULLIF(trim(aka_name), '') IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'optional trading name' FROM stg_inspections
UNION ALL SELECT 'raw', 'Inspection ID / DBA Name / Inspection Date / Results',
       ROUND(100.0 * SUM(CASE WHEN inspection_id IS NULL OR dba_name IS NULL OR inspection_date IS NULL OR results IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2),
       'required: never empty' FROM stg_inspections;

CREATE OR REPLACE TABLE dq_issues AS
SELECT 'exact duplicate reports (identical except Inspection ID), dropped' AS check_name,
       (SELECT COUNT(*) FROM stg_inspections) - (SELECT COUNT(*) FROM cln_distinct) AS affected_rows
UNION ALL SELECT 'same facility + day + type + result but different content (possible duplicates), kept + listed',
       (SELECT SUM(reports) - COUNT(*) FROM cln_same_day_repeat)
UNION ALL SELECT 'missing license number (blank or 0), keyed by name + address', (SELECT SUM(dq_missing_license) FROM cln_inspections)
UNION ALL SELECT 'missing facility type', (SELECT SUM(dq_missing_facility_type) FROM cln_inspections)
UNION ALL SELECT 'risk blank or All, risk_key 0', (SELECT SUM(dq_missing_risk) FROM cln_inspections)
UNION ALL SELECT 'not geocoded (no latitude / longitude)', (SELECT SUM(dq_missing_geo) FROM cln_inspections)
UNION ALL SELECT 'geocoded but outside all 77 community areas', (SELECT SUM(dq_outside_community_areas) FROM cln_inspections)
UNION ALL SELECT 'city misspellings of CHICAGO fixed (CCHICAGO, CHICAGOO, 312CHICAGO, ...)', (SELECT SUM(dq_city_variant_fixed) FROM cln_inspections)
UNION ALL SELECT 'blank city imputed CHICAGO from a Chicago ZIP', (SELECT SUM(dq_city_imputed_from_zip) FROM cln_inspections)
UNION ALL SELECT 'city still blank', (SELECT SUM(dq_missing_city) FROM cln_inspections)
UNION ALL SELECT 'address outside Chicago (suburb city name), kept + flagged', (SELECT SUM(dq_non_chicago_city) FROM cln_inspections)
UNION ALL SELECT 'ZIP outside Chicago, kept + flagged', (SELECT SUM(dq_non_chicago_zip) FROM cln_inspections)
UNION ALL SELECT 'ZIP blank', (SELECT SUM(dq_missing_zip) FROM cln_inspections)
UNION ALL SELECT 'Fail with no violation text', (SELECT SUM(dq_fail_without_violations) FROM cln_inspections)
UNION ALL SELECT 'violations recorded on a report without an outcome (Out of Business, No Entry ...)', (SELECT SUM(dq_violations_without_outcome) FROM cln_inspections)
UNION ALL SELECT 'same violation code cited more than once in one inspection (extra items)', (SELECT SUM(n_citations - n_codes) FROM cln_violation_counts)
UNION ALL SELECT 'facility-type spellings merged by upper-casing / trimming', (SELECT COUNT(DISTINCT facility_type) FROM stg_inspections)
       - (SELECT COUNT(DISTINCT facility_type) FROM cln_inspections)
UNION ALL SELECT 'inspection-type spellings merged by upper-casing / trimming', (SELECT COUNT(DISTINCT inspection_type) FROM stg_inspections)
       - (SELECT COUNT(DISTINCT inspection_type) FROM cln_inspections)
UNION ALL SELECT 'licenses seen with more than one business name (ownership / name changes)', (SELECT COUNT(*) FROM dim_facility WHERE n_names > 1)
UNION ALL SELECT 'licenses seen at more than one address', (SELECT COUNT(*) FROM dim_facility WHERE n_addresses > 1)
UNION ALL SELECT 'code list switch: inspections on the 2018 Food Code form (from 1 Jul 2018)', (SELECT COUNT(*) FROM cln_inspections WHERE code_scheme = '2018');

-- Checks marked [full data only] need the whole history and report SKIP on the committed sample.
CREATE OR REPLACE TABLE dq_assertions AS
WITH fd AS (SELECT CASE WHEN COUNT(*) >= 100000 THEN 1 ELSE 0 END AS full_data FROM stg_inspections),
c AS (
  SELECT 'distinct reports = raw rows - exact duplicates' AS check_name,
         ABS((SELECT COUNT(*) FROM cln_distinct) - (SELECT COUNT(*) FROM (SELECT DISTINCT dba_name, aka_name, license_no, facility_type, risk, address,
             city, state, zip, inspection_date, inspection_type, results, violations, latitude, longitude FROM stg_inspections) d)) AS failed_rows
  UNION ALL SELECT 'Inspection ID unique in raw and in fact_inspection', (SELECT COUNT(*) - COUNT(DISTINCT inspection_id) FROM stg_inspections)
         + (SELECT COUNT(*) - COUNT(DISTINCT inspection_id) FROM fact_inspection)
  UNION ALL SELECT 'fact_inspection = cln_inspections (no report lost in joins)', ABS((SELECT COUNT(*) FROM fact_inspection) - (SELECT COUNT(*) FROM cln_inspections))
  UNION ALL SELECT 'every inspection date parsed and not after the snapshot', (SELECT SUM(dq_bad_date) FROM cln_inspections)
         + (SELECT COUNT(*) FROM cln_inspections WHERE inspection_date > current_date() OR inspection_date < DATE'2010-01-01')
  UNION ALL SELECT 'every result is one of the 7 published values', (SELECT COUNT(*) FROM fact_inspection WHERE result_key = 0)
  UNION ALL SELECT 'risk_key in 0..3, facility_group and type_group never null', (SELECT COUNT(*) FROM cln_inspections
         WHERE risk_level NOT IN (0, 1, 2, 3) OR facility_group IS NULL OR type_group IS NULL)
  UNION ALL SELECT 'fact keys exist in every dimension (RI)', (SELECT COUNT(*) FROM fact_inspection f
         LEFT JOIN dim_date d ON f.date_key = d.date_key LEFT JOIN dim_facility fa ON f.facility_key = fa.facility_key
         LEFT JOIN dim_result r ON f.result_key = r.result_key LEFT JOIN dim_inspection_type t ON f.inspection_type_key = t.inspection_type_key
         LEFT JOIN dim_risk k ON f.risk_key = k.risk_key LEFT JOIN dim_community_area a ON f.area_num = a.area_num
         WHERE d.date_key IS NULL OR fa.facility_key IS NULL OR r.result_key IS NULL OR t.inspection_type_key IS NULL OR k.risk_key IS NULL OR a.area_num IS NULL)
  UNION ALL SELECT 'facility_key and facility_id unique in dim_facility', (SELECT COUNT(*) - COUNT(DISTINCT facility_key) FROM dim_facility)
         + (SELECT COUNT(*) - COUNT(DISTINCT facility_id) FROM dim_facility)
  UNION ALL SELECT 'every violation item parsed to a code known on its form (2010: 1-45, 70; 2018: 1-64)', (SELECT COUNT(*) FROM fact_violation WHERE violation_key IS NULL)
  UNION ALL SELECT 'violation items = items in the raw text (split on |)', ABS((SELECT COUNT(*) FROM fact_violation)
         - (SELECT SUM(size(split(violations, ' [|] '))) FROM cln_inspections WHERE violations IS NOT NULL))
  UNION ALL SELECT 'citation levels (Priority / PF / Core) only on 2018-form items', (SELECT COUNT(*) FROM fact_violation
         WHERE (code_scheme = '2010' AND citation_level <> 'n/a (2010 form)') OR (code_scheme = '2018' AND citation_level = 'n/a (2010 form)'))
  UNION ALL SELECT 'per-inspection citation counts sum to fact_violation', ABS((SELECT SUM(n_citations) FROM fact_inspection) - (SELECT COUNT(*) FROM fact_violation))
  UNION ALL SELECT 'completed + not inspected = all reports and completed shares sum to 100%', ABS((SELECT COUNT(*) FROM fact_inspection)
         - (SELECT SUM(is_completed) + SUM(1 - is_completed) FROM fact_inspection))
         + CASE WHEN ABS((SELECT SUM(pct_of_completed) FROM a_result_mix) - 100) > 0.02 THEN 1 ELSE 0 END
  UNION ALL SELECT 'a_yearly: pass + conditions + fail = completed, totals = w_base', (SELECT COUNT(*) FROM a_yearly WHERE passes + pass_conditions + fails <> completed)
         + ABS((SELECT SUM(completed) FROM a_yearly) - (SELECT COUNT(*) FROM w_base))
  UNION ALL SELECT 'a_after_fail All fails = every completed Fail', ABS((SELECT fails FROM a_after_fail WHERE failed_inspection_type = 'All fails')
         - (SELECT SUM(is_fail) FROM fact_inspection))
  UNION ALL SELECT 'next / previous completed inspection is never earlier (days >= 0)', (SELECT COUNT(*) FROM fact_inspection
         WHERE days_since_prev_completed < 0 OR days_to_next_completed < 0)
  UNION ALL SELECT 'agg_zip_month sums back to fact_inspection (reports, completed, fails)', ABS((SELECT SUM(reports) FROM agg_zip_month) - (SELECT COUNT(*) FROM fact_inspection))
         + ABS((SELECT SUM(completed) FROM agg_zip_month) - (SELECT SUM(is_completed) FROM fact_inspection))
         + ABS((SELECT SUM(fails) FROM agg_zip_month) - (SELECT SUM(is_fail) FROM fact_inspection))
  UNION ALL SELECT 'agg_area_year and agg_facility_year sum back to fact_inspection', ABS((SELECT SUM(reports) FROM agg_area_year) - (SELECT COUNT(*) FROM fact_inspection))
         + ABS((SELECT SUM(fails) FROM agg_area_year) - (SELECT SUM(is_fail) FROM fact_inspection))
         + ABS((SELECT SUM(reports) FROM agg_facility_year) - (SELECT COUNT(*) FROM fact_inspection))
         + ABS((SELECT SUM(citations) FROM agg_facility_year) - (SELECT COUNT(*) FROM fact_violation))
  UNION ALL SELECT 'dim_facility totals = fact_inspection (reports, completed, fails)', ABS((SELECT SUM(reports) FROM dim_facility) - (SELECT COUNT(*) FROM fact_inspection))
         + ABS((SELECT SUM(completed_inspections) FROM dim_facility) - (SELECT SUM(is_completed) FROM fact_inspection))
         + ABS((SELECT SUM(fails) FROM dim_facility) - (SELECT SUM(is_fail) FROM fact_inspection))
  UNION ALL SELECT 'a_repeat_fail covers every inspected facility', ABS((SELECT SUM(facilities) FROM a_repeat_fail)
         - (SELECT COUNT(*) FROM dim_facility WHERE completed_inspections > 0))
  UNION ALL SELECT 'dim_date is gap-free from 1 Jan of the first year to the last inspection', ABS((SELECT COUNT(*) FROM dim_date)
         - (SELECT days_between(MIN(date), MAX(date)) + 1 FROM dim_date)) + (SELECT COUNT(*) - COUNT(DISTINCT date_key) FROM dim_date)
  UNION ALL SELECT 'names and addresses standardised (upper case, trimmed, single spaces)', (SELECT COUNT(*) FROM dim_facility
         WHERE dba_name <> upper(dba_name) OR dba_name <> trim(dba_name) OR dba_name LIKE '%  %' OR address LIKE '%  %' OR address <> trim(address))
  UNION ALL SELECT 'no CHICAGO misspelling left in city', (SELECT COUNT(*) FROM cln_inspections WHERE city IN ('CCHICAGO', 'CHICAGOCHICAGO', 'CHICAGOO',
         'CHICAGO.', '312CHICAGO', 'CHCHICAGO', 'CHICAGOI', 'CHCICAGO', 'CHICAGOC', 'CH'))
  UNION ALL SELECT 'geocoded points inside the Chicago box (lat 41.6-42.1, lng -87.95..-87.5)', (SELECT COUNT(*) FROM cln_inspections
         WHERE lat IS NOT NULL AND (lat NOT BETWEEN 41.6 AND 42.1 OR lng NOT BETWEEN -87.95 AND -87.5))
  UNION ALL SELECT 'every full year 2010-2025 has >= 10,000 completed inspections [full data only]', ABS(16 - (SELECT COUNT(*) FROM a_yearly
         WHERE year BETWEEN 2010 AND 2025 AND completed >= 10000))
  UNION ALL SELECT 'all 77 community areas have completed inspections, >= 70 ranked (>= 500) [full data only]', ABS(77 - (SELECT COUNT(*) FROM a_community_area))
         + CASE WHEN (SELECT COUNT(*) FROM a_community_area WHERE rnk IS NOT NULL) < 70 THEN 1 ELSE 0 END
  UNION ALL SELECT '>= 99% of geocoded reports fall inside a community area [full data only]', CASE WHEN (SELECT 1.0 * SUM(dq_outside_community_areas)
         / SUM(1 - dq_missing_geo) FROM cln_inspections) > 0.01 THEN 1 ELSE 0 END
)
SELECT check_name, COALESCE(failed_rows, 0) AS failed_rows,
       CASE WHEN check_name LIKE '%[full data only]' AND (SELECT full_data FROM fd) = 0 THEN 'SKIP'
            WHEN COALESCE(failed_rows, 0) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM c;
