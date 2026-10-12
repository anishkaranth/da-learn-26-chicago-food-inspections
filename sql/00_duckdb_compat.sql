-- 00_duckdb_compat.sql  (DuckDB ONLY - do NOT run on Databricks)
-- Spark / Databricks SQL function shims so that 01-05 can be written in Spark SQL dialect and still run unchanged on DuckDB.
-- On Databricks these functions are built in (only the argument patterns used in this project are supported here).
CREATE OR REPLACE MACRO regexp_like(s, p) AS regexp_matches(s, p);
CREATE OR REPLACE MACRO percentile_approx(x, p) AS quantile_cont(x, p);
-- Spark to_date(s, 'MM/dd/yyyy'): the only pattern used (Inspection Date). Unparseable text -> NULL, like Spark with ANSI mode off.
CREATE OR REPLACE MACRO to_date(s, f) AS CAST(try_strptime(s, '%m/%d/%Y') AS DATE);
-- Spark split(str, regex) returns an array; explode(array) returns one row per element
CREATE OR REPLACE MACRO split(s, p) AS string_split_regex(s, p);
CREATE OR REPLACE MACRO explode(x) AS unnest(x);
-- Spark sequence(start_date, end_date) = one element per day
CREATE OR REPLACE MACRO sequence(a, b) AS generate_series(CAST(a AS TIMESTAMP), CAST(b AS TIMESTAMP), INTERVAL 1 DAY);
-- Spark weekday(d) = 0 Monday .. 6 Sunday (DuckDB's own weekday() is 0 = Sunday, so it is overridden here)
CREATE OR REPLACE MACRO weekday(d) AS isodow(d) - 1;
-- Spark date_format(d, 'yyyy-MM') / 'yyyy-MM-dd' / 'MMM'
CREATE OR REPLACE MACRO date_format(d, f) AS strftime(d, replace(replace(replace(replace(f, 'yyyy', '%Y'), 'MMM', '%b'), 'MM', '%m'), 'dd', '%d'));
-- Project functions. On Databricks create the same SQL UDFs once:
--   CREATE OR REPLACE TEMPORARY FUNCTION collapse_spaces(s STRING) RETURNS STRING RETURN trim(regexp_replace(s, '\\s+', ' '));
--   CREATE OR REPLACE TEMPORARY FUNCTION days_between(a DATE, b DATE) RETURNS INT RETURN datediff(b, a);
CREATE OR REPLACE MACRO collapse_spaces(s) AS trim(regexp_replace(s, '\s+', ' ', 'g'));
CREATE OR REPLACE MACRO days_between(a, b) AS CAST(b AS DATE) - CAST(a AS DATE);
-- Spark size(array) = number of elements
CREATE OR REPLACE MACRO size(a) AS len(a);
