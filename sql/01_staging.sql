-- 01_staging.sql  Land the raw files as all-text staging tables (no cleaning yet).
-- DuckDB: read_csv(..., all_varchar = true) with snake_case names (the raw header has spaces and '#'). On Databricks use
--   SELECT `Inspection ID` AS inspection_id, `DBA Name` AS dba_name, ... , `Location` AS location
--   FROM read_files('/Volumes/workspace/da_learn_26/raw/food_inspections.csv', format => 'csv', header => true, inferSchema => false)
-- which gives the same 17 columns, all typed STRING.

-- City of Chicago Food Inspections (data.cityofchicago.org 4ijn-s7e5): one row per inspection, 17 columns, 2010-01-04 .. snapshot date
CREATE OR REPLACE TABLE stg_inspections AS
SELECT * FROM read_csv('{{RAW_DIR}}/food_inspections.csv', header = true, all_varchar = true,
  names = ['inspection_id', 'dba_name', 'aka_name', 'license_no', 'facility_type', 'risk', 'address', 'city', 'state', 'zip',
           'inspection_date', 'inspection_type', 'results', 'violations', 'latitude', 'longitude', 'location']);

-- references (data/reference/):
--   geo_point_community_area.csv  every distinct raw Latitude/Longitude text pair -> community area number (scripts/build_geo_reference.py)
--   community_areas.csv           the 77 official community areas (City of Chicago boundaries igwz-8jzy)
--   violation_codes.csv           both inspection-form code lists: 2010 form (codes 1-45, 70) and the 1 Jul 2018 Food Code form (1-64)
CREATE OR REPLACE TABLE ref_geo_point AS
SELECT * FROM read_csv('{{REF_DIR}}/geo_point_community_area.csv', header = true, all_varchar = true);
CREATE OR REPLACE TABLE ref_community_area AS
SELECT * FROM read_csv('{{REF_DIR}}/community_areas.csv', header = true, all_varchar = true);
CREATE OR REPLACE TABLE ref_violation_codes AS
SELECT * FROM read_csv('{{REF_DIR}}/violation_codes.csv', header = true, all_varchar = true);
