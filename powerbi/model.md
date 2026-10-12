# Power BI model · da-learn-26 Chicago food inspections

Star schema exported by `python run_pipeline.py --source full` (same files in `data/clean/star/`). Dimensions and the two aggregate
tables are complete; the two fact tables are a deterministic sample: every facility whose `facility_key` is divisible by 20 (5% of
facilities, with their complete inspection history), because the full facts have 316,851 reports and 1,026,610 violation items.

| Table | Rows | Grain | Key |
|---|---|---|---|
| `fact_inspection_sample` | 16,481 | one inspection report | `inspection_id` |
| `fact_violation_sample` | 54,077 | one cited violation item | (`inspection_id`, item) |
| `agg_zip_month` | 11,914 | ZIP x month (complete) | (`zip5`, `year_month`) |
| `agg_area_year` | 1,326 | community area x year (complete) | (`area_num`, `year`) |
| `dim_date` | 6,126 | day, 2010-01-01 .. 2026-10-09 | `date_key` (yyyymmdd) |
| `dim_facility` | 49,547 | license number (or name + address) | `facility_key` |
| `dim_result` | 8 | result | `result_key` |
| `dim_inspection_type` | 99 | standardised inspection type | `inspection_type_key` |
| `dim_risk` | 4 | risk category | `risk_key` |
| `dim_community_area` | 78 | community area (0 = unknown) | `area_num` |
| `dim_violation` | 110 | code on the 2010 or 2018 form | `violation_key` |

## Relationships (many-to-one, single direction, dimension filters fact)
| From (many) | To (one) |
|---|---|
| `fact_inspection_sample[date_key]` | `dim_date[date_key]` |
| `fact_inspection_sample[facility_key]` | `dim_facility[facility_key]` |
| `fact_inspection_sample[result_key]` | `dim_result[result_key]` |
| `fact_inspection_sample[inspection_type_key]` | `dim_inspection_type[inspection_type_key]` |
| `fact_inspection_sample[risk_key]` | `dim_risk[risk_key]` |
| `fact_inspection_sample[area_num]` | `dim_community_area[area_num]` |
| `fact_violation_sample[violation_key]` | `dim_violation[violation_key]` |
| `fact_violation_sample[inspection_id]` | `fact_inspection_sample[inspection_id]` (so violations follow inspection slicers) |
| `agg_area_year[area_num]` | `dim_community_area[area_num]` |

`agg_zip_month` stands alone (ZIP and month are text columns on it); `agg_area_year[year]` can relate to a small calculated year table if needed.

## Notes
- `risk_key` on the fact is the risk category printed on that report; `dim_facility[latest_risk_level]` is the latest one.
- `code_scheme` = `2010` before 1 Jul 2018 and `2018` from then on: the same code number means different things on the two forms,
  so always slice violations by `dim_violation[code_scheme]` or `[theme]`, never by `code` alone.
- `citation_level` (Priority / Priority foundation / Core) exists only on 2018-form items.
- Rates use completed inspections (`is_completed = 1`: Pass, Pass w/ Conditions, Fail). Out of Business / No Entry / Not Ready are reports, not outcomes.
- `prev_result_key`, `next_result_key`, `days_to_next_completed` link each completed inspection to the facility's previous / next completed one.
