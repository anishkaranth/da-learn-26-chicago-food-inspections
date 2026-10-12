# Dashboard spec · "da-learn-26 Chicago Food Inspections" (one page, 16:9)

Mirrors `results/images/dashboard.png`. Colours: Pass `#2a9d8f`, Pass w/ Conditions `#e9c46a`, Fail `#d1495b`.

**Slicers (top):** `dim_date[year]` (between), `dim_facility[facility_group]`, `dim_risk[risk]`, `dim_inspection_type[type_group]`.

**KPI cards:** [Completed (full)] = 272,061 · [Fail Rate % (full)] = 22.43% · [Pass w Conditions % (full)] = 17.27% ·
[Next Pass After Fail %] (sample) · [Priority Inspection Fail Rate %] (sample) · [Facilities Inspected].

| # | Visual | Fields |
|---|---|---|
| 1 | 100% stacked column: outcome mix by year | axis `dim_date[year]`; values [Pass Rate %], [Pass w Conditions %], [Fail Rate %] |
| 2 | Line: monthly fail rate | axis `agg_zip_month[year_month]`; [ZIP Fail Rate % (full)]; constant line on 2018-07 (Food Code form) |
| 3 | 100% stacked bar: outcomes by inspection type | axis `dim_inspection_type[type_group]` + `[is_reinspection]`; outcome measures |
| 4 | Bar: fail rate by facility group | axis `dim_facility[facility_group]`; [Fail Rate %]; conditional colour above 22.43% |
| 5 | Filled map / shape map: fail rate by community area | `dim_community_area[community_area]` (or centroid lat/lng); [Fail Rate % (full)] |
| 6 | Table: ZIPs with 1,000+ completed inspections | `agg_zip_month[zip5]`; [ZIP Completed (full)], [ZIP Fail Rate % (full)]; visual filter completed >= 1,000 |
| 7 | 100% stacked bar: next inspection after a Fail | axis `dim_inspection_type[type_group]`; [Next Pass After Fail %], [Next Fail After Fail %] |
| 8 | Bar: violation themes in fails vs passes | axis `dim_violation[theme]`; [% of Fails Citing], [% of Passes Citing]; slicer `dim_violation[code_scheme]` = 2018 |

Tooltip on visuals 4-6: [Completed Inspections], [Facilities Inspected], [Violations per Inspection].
