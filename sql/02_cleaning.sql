-- 02_cleaning.sql  Types, standardisation, dedupe, validity flags and violation parsing (Spark SQL dialect)
-- Grain after cleaning: cln_inspections = one row per distinct inspection report; cln_violations = one row per cited violation item.

-- 1. Exact duplicate reports: the portal warns that duplicate inspection reports exist. Rows identical in every column except the
--    Inspection ID are the same report entered twice: keep the lowest Inspection ID.
CREATE OR REPLACE TABLE cln_distinct AS
SELECT * FROM stg_inspections
QUALIFY ROW_NUMBER() OVER (PARTITION BY dba_name, aka_name, license_no, facility_type, risk, address, city, state, zip,
                           inspection_date, inspection_type, results, violations, latitude, longitude
                           ORDER BY CAST(inspection_id AS BIGINT)) = 1;

-- 2. Types and standardisation
CREATE OR REPLACE TABLE cln_typed AS
SELECT
  CAST(inspection_id AS BIGINT) AS inspection_id,
  collapse_spaces(upper(dba_name)) AS dba_name,
  collapse_spaces(upper(NULLIF(trim(aka_name), ''))) AS aka_name,
  CASE WHEN CAST(license_no AS BIGINT) > 0 THEN CAST(license_no AS BIGINT) END AS license_no,
  collapse_spaces(upper(NULLIF(trim(facility_type), ''))) AS facility_type,
  CASE WHEN risk LIKE 'Risk 1%' THEN 1 WHEN risk LIKE 'Risk 2%' THEN 2 WHEN risk LIKE 'Risk 3%' THEN 3 ELSE 0 END AS risk_level,
  risk AS risk_raw,
  collapse_spaces(upper(address)) AS address,
  collapse_spaces(upper(NULLIF(trim(city), ''))) AS city_raw,
  upper(NULLIF(trim(state), '')) AS state,
  CASE WHEN regexp_like(trim(zip), '^[0-9]{5}$') THEN trim(zip) END AS zip5,
  to_date(inspection_date, 'MM/dd/yyyy') AS inspection_date,
  collapse_spaces(upper(inspection_type)) AS inspection_type,
  trim(results) AS result,
  NULLIF(trim(violations), '') AS violations,
  CAST(latitude AS DOUBLE) AS lat,
  CAST(longitude AS DOUBLE) AS lng,
  latitude AS lat_txt, longitude AS lng_txt
FROM cln_distinct;

-- 3. Derived attributes and data-quality flags (kept on every row; nothing is deleted after the exact-duplicate step)
CREATE OR REPLACE TABLE cln_inspections AS
WITH t AS (
  SELECT t.*,
    CASE WHEN city_raw IN ('CHICAGO', 'CCHICAGO', 'CHICAGOCHICAGO', 'CHICAGOO', 'CHICAGO.', '312CHICAGO', 'CHCHICAGO', 'CHICAGOI',
                           'CHCICAGO', 'CHICAGOC', 'CH') THEN 'CHICAGO'
         WHEN city_raw IS NULL AND (zip5 LIKE '606%' OR zip5 IN ('60707', '60827')) THEN 'CHICAGO'
         ELSE city_raw END AS city,
    CASE
      WHEN facility_type IS NULL THEN 'Unknown'
      WHEN regexp_like(facility_type, 'DAYCARE|DAY CARE|CHILD|CHILDERN|AFTER SCHOOL|PRE ?SCHOOL') THEN 'Daycare & children'
      WHEN regexp_like(facility_type, 'SCHOOL|SHCOOL|CHARTER|UNIVERSITY|COLLEGE') THEN 'School'
      WHEN regexp_like(facility_type, 'HOSPITAL|LONG TERM|NURSING|ASSISTED|SUPPORTIVE|REHAB|SENIOR|GOLDEN DINER') THEN 'Hospital & long-term care'
      WHEN regexp_like(facility_type, 'MOBILE|SPECIAL EVENT|KIOSK|POP-UP|FESTIVAL|CART|TRUCK') THEN 'Mobile, kiosk & events'
      WHEN regexp_like(facility_type, 'CATER|BANQUET') THEN 'Catering & banquet'
      WHEN regexp_like(facility_type, 'WHOLESALE|SHARED KITCHEN|COMMISSARY|WAREHOUSE') THEN 'Wholesale & shared kitchen'
      WHEN regexp_like(facility_type, '^RESTAURANT') THEN 'Restaurant'
      WHEN regexp_like(facility_type, 'BAKERY|PASTRY') THEN 'Bakery'
      WHEN regexp_like(facility_type, 'GROCERY|CONVENIENCE|GAS STATION|MART|STORE|MARKET') THEN 'Grocery & convenience'
      WHEN regexp_like(facility_type, 'TAVERN|LIQUOR|BREWERY|LOUNGE|^BAR') THEN 'Bar, tavern & liquor'
      WHEN regexp_like(facility_type, 'RESTAURANT|CAFE|COFFEE|DELI|ICE CREAM|PALETERIA|DINER|JUICE|TEA') THEN 'Restaurant'
      ELSE 'Other' END AS facility_group,
    CASE
      WHEN regexp_like(inspection_type, 'CANVAS') THEN 'Canvass'
      WHEN regexp_like(inspection_type, 'FOOD POISON|SFP') THEN 'Suspected food poisoning'
      WHEN regexp_like(inspection_type, 'COMPLAINT|COMPLIANT') THEN 'Complaint'
      WHEN regexp_like(inspection_type, 'TASK FORCE|LIQUOR|1474|1475') THEN 'Task force / liquor'
      WHEN regexp_like(inspection_type, 'LICENSE|LICENCE|LISCENSE') THEN 'License'
      WHEN inspection_type IS NULL THEN 'Unknown'
      ELSE 'Other' END AS type_group,
    CASE WHEN regexp_like(inspection_type, 'RE-? ?INSP|REINSP') THEN 1 ELSE 0 END AS is_reinspection,
    CASE WHEN result IN ('Pass', 'Pass w/ Conditions', 'Fail') THEN result ELSE 'Not inspected' END AS result_group,
    CASE WHEN result IN ('Pass', 'Pass w/ Conditions', 'Fail') THEN 1 ELSE 0 END AS is_completed,
    CASE WHEN result = 'Fail' THEN 1 ELSE 0 END AS is_fail,
    CASE WHEN inspection_date >= DATE'2018-07-01' THEN '2018' ELSE '2010' END AS code_scheme
  FROM cln_typed t)
SELECT t.*,
  CAST(g.area_num AS INT) AS area_num,
  COALESCE(CAST(license_no AS STRING), concat('X', substr(md5(concat_ws('|', dba_name, address)), 1, 12))) AS facility_id,
  CASE WHEN license_no IS NULL THEN 1 ELSE 0 END AS dq_missing_license,
  CASE WHEN facility_type IS NULL THEN 1 ELSE 0 END AS dq_missing_facility_type,
  CASE WHEN risk_level = 0 THEN 1 ELSE 0 END AS dq_missing_risk,
  CASE WHEN risk_raw = 'All' THEN 1 ELSE 0 END AS dq_risk_all,
  CASE WHEN lat IS NULL OR lng IS NULL THEN 1 ELSE 0 END AS dq_missing_geo,
  CASE WHEN lat IS NOT NULL AND g.area_num IS NULL THEN 1 ELSE 0 END AS dq_outside_community_areas,
  CASE WHEN city = 'CHICAGO' AND city_raw IS NOT NULL AND city_raw <> 'CHICAGO' THEN 1 ELSE 0 END AS dq_city_variant_fixed,
  CASE WHEN city_raw IS NULL AND city = 'CHICAGO' THEN 1 ELSE 0 END AS dq_city_imputed_from_zip,
  CASE WHEN city IS NULL THEN 1 ELSE 0 END AS dq_missing_city,
  CASE WHEN city <> 'CHICAGO' THEN 1 ELSE 0 END AS dq_non_chicago_city,
  CASE WHEN zip5 IS NULL THEN 1 ELSE 0 END AS dq_missing_zip,
  CASE WHEN zip5 IS NOT NULL AND zip5 NOT LIKE '606%' AND zip5 NOT IN ('60707', '60827') THEN 1 ELSE 0 END AS dq_non_chicago_zip,
  CASE WHEN inspection_date IS NULL THEN 1 ELSE 0 END AS dq_bad_date,
  CASE WHEN inspection_type IS NULL THEN 1 ELSE 0 END AS dq_missing_inspection_type,
  CASE WHEN result IS NULL THEN 1 ELSE 0 END AS dq_missing_result,
  CASE WHEN result = 'Fail' AND violations IS NULL THEN 1 ELSE 0 END AS dq_fail_without_violations,
  CASE WHEN result NOT IN ('Pass', 'Pass w/ Conditions', 'Fail') AND violations IS NOT NULL THEN 1 ELSE 0 END AS dq_violations_without_outcome
FROM t LEFT JOIN ref_geo_point g ON t.lat_txt = g.latitude AND t.lng_txt = g.longitude;

-- 4. Possible duplicates that are NOT identical: same facility, same day, same inspection type, same result (kept, flagged)
CREATE OR REPLACE TABLE cln_same_day_repeat AS
SELECT facility_id, inspection_date, inspection_type, result, COUNT(*) AS reports, MIN(inspection_id) AS first_id
FROM cln_inspections GROUP BY facility_id, inspection_date, inspection_type, result HAVING COUNT(*) > 1;

-- 5. Violations: the free-text column holds 'NN. TITLE - Comments: ...' items separated by ' | '. One row per item.
--    The code list changed on 1 Jul 2018 (new Chicago Food Code), so a code means different things before / after: join on (scheme, code).
--    2018 form items carry the inspector's citation level in the comments: PRIORITY / PRIORITY FOUNDATION / CORE VIOLATION.
CREATE OR REPLACE TABLE cln_violations AS
WITH items AS (
  SELECT inspection_id, code_scheme, trim(item) AS item
  FROM (SELECT inspection_id, code_scheme, explode(split(violations, ' [|] ')) AS item FROM cln_inspections WHERE violations IS NOT NULL) x)
SELECT i.inspection_id, i.code_scheme,
  CAST(regexp_extract(i.item, '^([0-9]+)[.]', 1) AS INT) AS code,
  CASE WHEN i.code_scheme = '2018' AND regexp_like(upper(i.item), 'PRIORITY VIOLATION') THEN 'Priority'
       WHEN i.code_scheme = '2018' AND regexp_like(upper(i.item), 'PRIORITY FOUNDATION') THEN 'Priority foundation'
       WHEN i.code_scheme = '2018' AND regexp_like(upper(i.item), 'CORE VIOLATION') THEN 'Core'
       WHEN i.code_scheme = '2018' THEN 'Not tagged' ELSE 'n/a (2010 form)' END AS citation_level,
  CASE WHEN regexp_like(i.item, ' - Comments: ') THEN 1 ELSE 0 END AS has_comments,
  length(i.item) AS item_chars
FROM items i;
