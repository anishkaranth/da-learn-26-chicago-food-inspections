"""Project-specific settings used by run_pipeline.py (raw files, exports, JSON.shot content)."""
NAME = "da-learn-26-chicago-food-inspections"
DATASET = ("City of Chicago Food Inspections (CDPH Food Protection Program, data.cityofchicago.org dataset 4ijn-s7e5; Kaggle 'Chicago Food "
           "Inspections'), City of Chicago Data Portal Terms of Use. Snapshot downloaded 2026-10-12: 316,963 rows x 17 columns, "
           "347,860,264 B, inspections 2010-01-04 .. 2026-10-09 + Chicago community-area boundaries (igwz-8jzy) for the area lookup")
RAW_FILES = ["food_inspections.csv"]
STAR = ["dim_date", "dim_facility", "dim_result", "dim_inspection_type", "dim_risk", "dim_community_area", "dim_violation",
        "agg_zip_month", "agg_area_year"]
METRIC_TABLES = ["a_kpi_headline", "a_result_mix", "a_yearly", "a_era", "a_monthly", "a_seasonal", "a_weekday", "a_facility_group",
                 "a_facility_type_top", "a_risk", "a_risk_group", "a_zip", "a_community_area", "a_geo_fit", "a_map_grid", "a_after_fail",
                 "a_reinspection_lag", "a_repeat_fail", "a_top_fail_facilities", "a_inspection_type", "a_type_year", "a_violation_theme",
                 "a_violation_top", "a_fail_driver", "a_citation_count"]
# fact_inspection has ~317k rows and fact_violation ~1.03M: only a deterministic sample is exported
# (every facility whose facility_key is divisible by 20 = 5% of facilities, with complete histories)
FACT_SAMPLE = "(SELECT * FROM fact_inspection WHERE facility_key % 20 = 0) fs"
VIOL_SAMPLE = "(SELECT * FROM fact_violation WHERE facility_key % 20 = 0) vs"


def export_full(con, export, root):
    """Full run: dimensions + aggregates exported complete; facts as a 1/20-of-facilities sample. Same files in data/clean/star/ and powerbi/data/."""
    for t in STAR:
        export(con, t, root / "data/clean/star" / f"{t}.csv")
        export(con, t, root / "powerbi/data" / f"{t}.csv")
    for q, nm in ((FACT_SAMPLE, "fact_inspection_sample"), (VIOL_SAMPLE, "fact_violation_sample")):
        export(con, q, root / "data/clean/star" / f"{nm}.csv")
        export(con, q, root / "powerbi/data" / f"{nm}.csv")
    export(con, "cln_same_day_repeat", root / "data/clean/possible_duplicates.csv")
    export(con, "(SELECT COALESCE(city_raw, '(blank)') AS city_raw, city, COUNT(*) AS reports FROM cln_inspections "
                "WHERE dq_city_variant_fixed = 1 OR dq_non_chicago_city = 1 OR dq_city_imputed_from_zip = 1 GROUP BY city_raw, city) x",
           root / "data/clean/city_fixes.csv")


def build_shot(q, kpi):
    """Headline snapshot written to results/JSON.shot."""
    return {
        "config": {"sql_dialect": "Spark SQL style (+ DuckDB shims in sql/00), run on DuckDB; Databricks skipped (workspace quota)",
                   "snapshot": "portal export downloaded 2026-10-12 IST; inspections 2010-01-04 .. 2026-10-09 (2026 = partial year)",
                   "grain": "fact_inspection = one inspection report; fact_violation = one cited violation item; dim_facility = license number",
                   "dedupe_rule": "reports identical in every column except Inspection ID collapsed (lowest ID kept); same-day near-duplicates flagged",
                   "rate_rule": "rates use completed inspections (Pass, Pass w/ Conditions, Fail); Out of Business / No Entry / Not Ready excluded",
                   "code_rule": "violation codes joined on (form, code): 2010 form before 2018-07-01 (Critical 1-14, Serious 15-29, Minor 30-45), "
                                "2018 Food Code form after (risk factors 1-29, good retail 30-58, admin 59-64; Priority/PF/Core from comments)",
                   "geo_rule": "community area = point-in-polygon of the report coordinates in the 77 official boundaries; ranked with >= 500 "
                               "completed inspections; ZIPs ranked with >= 1,000",
                   "sample_rule": "data/raw: full history of facilities with license % 40 = 0 + edge cases; scripts/make_sample.py"},
        "headline": kpi,
        "era": q("SELECT code_scheme, completed, pass_pct, pass_conditions_pct, fail_pct, avg_citations FROM a_era ORDER BY code_scheme"),
        "yearly_fail_pct": q("SELECT year, completed, fail_pct, pass_conditions_pct FROM a_yearly ORDER BY year"),
        "inspection_type": q("SELECT inspection_kind, completed, fail_pct FROM a_inspection_type ORDER BY completed DESC"),
        "risk": q("SELECT risk, completed, fail_pct FROM a_risk WHERE risk_key > 0 ORDER BY risk_key"),
        "after_fail": q("SELECT failed_inspection_type, fails, next_pass_pct, next_pass_conditions_pct, next_fail_pct, median_days_to_next "
                        "FROM a_after_fail ORDER BY fails DESC"),
        "fail_driver": q("SELECT code_scheme, worst_citation, completed, fail_pct, share_of_fails FROM a_fail_driver ORDER BY 1, 2"),
        "top_zip_fail_top5": q("SELECT rnk, zip5, completed, fail_pct FROM a_zip WHERE rnk <= 5 ORDER BY rnk"),
        "top_area_fail_top5": q("SELECT rnk, community_area, completed, fail_pct FROM a_community_area WHERE rnk <= 5 ORDER BY rnk"),
    }
