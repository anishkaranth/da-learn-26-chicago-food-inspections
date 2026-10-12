#!/usr/bin/env python3
"""Write results/RESULTS.md from results/metrics.json + results/tables/*.csv (every number comes from the full-data run)."""
import csv, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
RES = ROOT / "results"
T = RES / "tables"


def rd(name):
    with open(T / f"{name}.csv", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def i(x):
    return int(f(x))


def num(v):
    if v in ("", None):
        return ""
    try:
        x = float(v)
    except ValueError:
        return str(v).replace("|", "/")
    return f"{int(x):,}" if x.is_integer() and abs(x) >= 1000 else (str(int(x)) if x.is_integer() else f"{x:,.2f}".rstrip("0").rstrip("."))


KEEP = {"year", "rnk", "zip5", "month", "code", "citations", "area_num", "license_no", "weekday_num", "facility_key"}


def table(rows, cols, heads=None):
    out = ["| " + " | ".join(heads or cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        out.append("| " + " | ".join(str(r[c]).replace("|", "/") if c in KEEP else num(r[c]) for c in cols) + " |")
    return "\n".join(out)


m = json.loads((RES / "metrics.json").read_text())
k = m["kpis"]
era = {r["code_scheme"]: r for r in rd("a_era")}
yr = sorted(rd("a_yearly"), key=lambda r: i(r["year"]))
Y = {i(r["year"]): r for r in yr}
it = {r["inspection_kind"]: r for r in rd("a_inspection_type")}
fg = sorted(rd("a_facility_group"), key=lambda r: -f(r["fail_pct"]))
FG = {r["facility_group"]: r for r in fg}
rk = {i(r["risk_key"]): r for r in rd("a_risk")}
zp = sorted(rd("a_zip"), key=lambda r: i(r["rnk"]))
ca = sorted([r for r in rd("a_community_area") if r["rnk"]], key=lambda r: i(r["rnk"]))
gf = rd("a_geo_fit")[0]
af = {r["failed_inspection_type"]: r for r in rd("a_after_fail")}
lag = sorted(rd("a_reinspection_lag"), key=lambda r: r["lag_band"])
rf = sorted(rd("a_repeat_fail"), key=lambda r: r["fails_band"])
RF = {r["fails_band"]: r for r in rf}
fd = {(r["code_scheme"], r["worst_citation"][0]): r for r in rd("a_fail_driver")}
vt = {(r["code_scheme"], r["theme"]): r for r in rd("a_violation_theme")}
vtop = sorted(rd("a_violation_top"), key=lambda r: (r["code_scheme"], i(r["rnk"])))
V18 = [r for r in vtop if r["code_scheme"] == "2018"]
cc = {(r["code_scheme"], i(r["citations"])): r for r in rd("a_citation_count")}
se = sorted(rd("a_seasonal"), key=lambda r: i(r["month"]))
tf = sorted(rd("a_top_fail_facilities"), key=lambda r: i(r["rnk"]))
dq_i = rd("dq_issues"); dq_n = rd("dq_null_rates"); dq_r = rd("dq_row_counts"); asr = rd("dq_assertions")
npass = sum(1 for r in asr if r["status"] == "PASS")
DQ = {r["check_name"]: i(r["affected_rows"]) for r in dq_i}
dqv = lambda key: next(v for n, v in DQ.items() if n.startswith(key))
smax = max(se, key=lambda r: f(r["fail_pct"])); smin = min(se, key=lambda r: f(r["fail_pct"]))
pmax = max(se, key=lambda r: f(r["pest_citation_pct"])); pmin = min(se, key=lambda r: f(r["pest_citation_pct"]))
y19 = Y[2019]; y10 = Y[2010]; y25 = Y[2025]
pests18 = vt[("2018", "Pests & rodents")]
v18_38 = next(r for r in V18 if r["code"] == "38")
v10_18 = next(r for r in vtop if r["code_scheme"] == "2010" and r["code"] == "18")
fail_lo = min((r for r in fg if r["facility_group"] != "Unknown"), key=lambda r: f(r["fail_pct"]))

ins = [
    f"**About one completed inspection in five fails, and that rate has barely moved in 16 years.** Of {i(k['completed_inspections']):,} completed "
    f"inspections ({k['first_date']} to {k['last_date']}), {f(k['pass_pct']):.2f}% passed, {f(k['pass_conditions_pct']):.2f}% passed with conditions and "
    f"{f(k['fail_pct']):.2f}% failed. Yearly fail rates stay between {min(f(r['fail_pct']) for r in yr):.2f}% and {max(f(r['fail_pct']) for r in yr):.2f}% "
    f"({y10['fail_pct']}% in 2010, {y25['fail_pct']}% in 2025). What changed is the middle category: the new Food Code form of 1 July 2018 moved "
    f"inspections from Pass to Pass w/ Conditions (2019: {y19['pass_pct']}% pass, {y19['pass_conditions_pct']}% with conditions), and the conditions "
    f"share has since eased back to {y25['pass_conditions_pct']}% (2025). Before vs after the switch: fail {era['2010']['fail_pct']}% vs "
    f"{era['2018']['fail_pct']}%, conditions {era['2010']['pass_conditions_pct']}% vs {era['2018']['pass_conditions_pct']}%.",
    f"**The first visit is the risky one.** License inspections of new businesses fail {it['License']['fail_pct']}%, complaint inspections "
    f"{it['Complaint']['fail_pct']}%, routine canvass visits {it['Canvass']['fail_pct']}%, while re-inspections fail only "
    f"{f(k['reinspection_fail_pct']):.2f}%. Liquor task-force sweeps fail {it['Task force / liquor']['fail_pct']}% (n = {i(it['Task force / liquor']['completed']):,}).",
    f"**Facility type matters more than the official risk category.** Bars, taverns and liquor stores fail {FG['Bar, tavern & liquor']['fail_pct']}%, "
    f"wholesale / shared kitchens {FG['Wholesale & shared kitchen']['fail_pct']}%, grocery and convenience stores {FG['Grocery & convenience']['fail_pct']}%, "
    f"restaurants {FG['Restaurant']['fail_pct']}%, and {fail_lo['facility_group'].lower()} the least ({fail_lo['fail_pct']}%). By risk category the order is "
    f"reversed: Risk 1 (High) fails {rk[1]['fail_pct']}%, Risk 3 (Low) {rk[3]['fail_pct']}%. High-risk places are inspected far more often "
    f"({rk[1]['inspections_per_facility']} completed inspections per facility vs {rk[3]['inspections_per_facility']}); a likely reason for the reversal is "
    f"that frequent routine visits keep high-risk kitchens prepared, while low-risk places are seen rarely.",
    f"**A clear South and West Side gap.** Among the {len(ca)} community areas with 500+ completed inspections, the fail rate runs from "
    f"{ca[0]['fail_pct']}% in {ca[0]['community_area']} and {ca[1]['fail_pct']}% in {ca[1]['community_area']} to {ca[-2]['fail_pct']}% in "
    f"{ca[-2]['community_area']} and {ca[-1]['fail_pct']}% at {ca[-1]['community_area'].replace('Ohare', 'O’Hare')}. Of {len(zp)} ZIP codes with 1,000+ inspections, "
    f"{zp[0]['zip5']} is highest ({zp[0]['fail_pct']}%) and {zp[-1]['zip5']} (O'Hare airport) lowest ({zp[-1]['fail_pct']}%). It is not just more complaint "
    f"visits: the area fail rate tracks the fail rate of routine canvass visits (correlation {gf['corr_fail_vs_canvass_fail']}; canvass fail rates range "
    f"{gf['canvass_fail_pct_min']}%-{gf['canvass_fail_pct_max']}%) more closely than the complaint share ({gf['corr_fail_vs_complaint_share']}).",
    f"**Fails are usually fixed fast, but failure repeats.** {f(lag[0]['pct_of_fails']) + f(lag[1]['pct_of_fails']):.2f}% "
    f"of fails get a follow-up within 14 days (median {f(k['after_fail_median_days_to_next']):.0f} days), and the next completed inspection passes "
    f"{f(k['after_fail_next_pass_pct']):.2f}% of the time (plus {f(k['after_fail_next_pass_conditions_pct']):.2f}% with conditions); "
    f"{f(k['after_fail_next_fail_pct']):.2f}% fail again. Over the whole period {f(k['facilities_ever_failed_pct']):.2f}% of inspected facilities failed at "
    f"least once, {f(k['repeat_fail_pct_of_failed_facilities']):.2f}% of those failed again, and {i(RF['5+']['facilities']):,} facilities "
    f"({RF['5+']['pct_of_facilities']}%) failed five or more times, together {i(RF['5+']['total_fails']):,} fails "
    f"({100 * i(RF['5+']['total_fails']) / sum(i(r['total_fails']) for r in rf):.1f}% of all fails).",
    f"**Pests, hand-wash sinks and serious-risk citations decide the outcome.** On the 2018 form an inspection with a Priority violation fails "
    f"{fd[('2018', '1')]['fail_pct']}% of the time (the rest pass with conditions) and one with a Priority-foundation violation {fd[('2018', '2')]['fail_pct']}%, "
    f"while core-only inspections fail {fd[('2018', '3')]['fail_pct']}%. Code 38 (insects, rodents and animals) appears in {v18_38['pct_of_failed']}% of failed "
    f"inspections vs {v18_38['pct_of_passed']}% of passes, and {v18_38['fail_pct_when_cited']}% of inspections citing it fail; on the 2010 form code 18 "
    f"(rodent proofing / pest log) was in {v10_18['pct_of_failed']}% of fails and {v10_18['fail_pct_when_cited']}% of inspections citing it failed. "
    f"Fail rates rise steadily with the number of violations (2018 form: {cc[('2018', 0)]['fail_pct']}% with none, {cc[('2018', 5)]['fail_pct']}% with five, "
    f"{cc[('2018', 12)]['fail_pct']}% with 12 or more).",
    f"**Late summer is worst.** In full years 2010-2025 the fail rate peaks in {smax['month_name']} ({smax['fail_pct']}%) and is lowest in "
    f"{smin['month_name']} ({smin['fail_pct']}%); the share of inspections citing pests rises from {pmin['pest_citation_pct']}% ({pmin['month_name']}) to "
    f"{pmax['pest_citation_pct']}% ({pmax['month_name']}) and complaint-driven visits peak in July-August.",
    f"**Cleaning mattered.** {i(k['raw_rows']):,} raw rows -> {i(k['inspection_reports']):,} distinct reports ({i(k['exact_duplicates_removed']):,} exact "
    f"duplicates with a different Inspection ID). {i(k['not_inspected_reports']):,} reports (Out of Business, No Entry, Not Ready, Business Not Located) are "
    f"not inspection outcomes and are kept out of every rate. {dqv('Fail with'):,} fails carry no violation text, {dqv('not geocoded'):,} reports have no "
    f"coordinates, {dqv('city misspellings'):,} city spellings of CHICAGO were fixed, and the Violations free text was split into {i(k['violation_citations']):,} "
    f"coded items joined to the right code list (2010 or 2018 form). {npass}/{len(asr)} assertions pass.",
]

lines = [f"# Results · {m['project']}", "",
         f"Full-data run on DuckDB {m['engine']['duckdb']} (Databricks skipped: workspace quota). Dataset: {m['dataset']}.", "",
         "![Dashboard](images/dashboard.png)", "", "## Headline insights", ""]
lines += [f"{n}. {s}" for n, s in enumerate(ins, 1)]
lines += ["", "## Q1 · Outcomes and trend", "", table(rd("a_result_mix"), ["result", "reports", "pct_of_reports", "pct_of_completed"],
          ["Result", "Reports", "% of reports", "% of completed"]), "",
          table(yr, ["year", "completed", "pass_pct", "pass_conditions_pct", "fail_pct", "avg_citations", "out_of_business", "facilities_inspected"],
                ["Year", "Completed", "Pass %", "Pass w/ cond. %", "Fail %", "Violations / insp.", "Out of business", "Facilities"]),
          "", "2026 runs to 9 October (partial year).", "",
          table(list(era.values()), ["era", "completed", "pass_pct", "pass_conditions_pct", "fail_pct", "avg_citations", "no_citation_pct"],
                ["Inspection form", "Completed", "Pass %", "Pass w/ cond. %", "Fail %", "Violations / insp.", "No violation %"]),
          "", "![Outcome mix](images/result_mix_yearly.png)", "![Monthly fail rate](images/fail_rate_monthly.png)",
          "", "## Q2 · Facility types and risk", "",
          table(fg, ["facility_group", "completed", "facilities", "pass_pct", "pass_conditions_pct", "fail_pct", "avg_citations"],
                ["Facility group", "Completed", "Facilities", "Pass %", "Pass w/ cond. %", "Fail %", "Violations / insp."]), "",
          table([rk[n] for n in (1, 2, 3, 0)], ["risk", "completed", "facilities", "inspections_per_facility", "pass_pct", "pass_conditions_pct", "fail_pct"],
                ["Risk", "Completed", "Facilities", "Inspections / facility", "Pass %", "Pass w/ cond. %", "Fail %"]), "",
          table(sorted(rd("a_facility_type_top"), key=lambda r: -f(r["fail_pct"])), ["facility_type", "facility_group", "completed", "fail_pct", "pass_conditions_pct"],
                ["Facility type (raw, 500+)", "Group", "Completed", "Fail %", "Pass w/ cond. %"]),
          "", "![Facility groups](images/facility_group_fail.png)", "![Risk](images/risk_outcomes.png)", "![Heatmap](images/risk_group_heatmap.png)",
          "", "## Q3 · Geography", "",
          f"ZIP codes with at least 1,000 completed inspections ({len(zp)}), highest and lowest fail rates:", "",
          table(zp[:10] + zp[-5:], ["rnk", "zip5", "completed", "fails", "fail_pct", "canvass_fail_pct", "complaint_share_pct", "facilities"],
                ["Rank", "ZIP", "Completed", "Fails", "Fail %", "Canvass fail %", "Complaint share %", "Facilities"]), "",
          f"Community areas with at least 500 completed inspections ({len(ca)} of 77):", "",
          table(ca[:10] + ca[-5:], ["rnk", "community_area", "completed", "fail_pct", "canvass_fail_pct", "complaint_share_pct", "restaurant_share_pct", "facilities"],
                ["Rank", "Community area", "Completed", "Fail %", "Canvass fail %", "Complaint share %", "Restaurant share %", "Facilities"]), "",
          f"Correlation across the {gf['areas']} areas: fail % vs routine-canvass fail % = {gf['corr_fail_vs_canvass_fail']}, fail % vs complaint share = "
          f"{gf['corr_fail_vs_complaint_share']}.", "",
          "![Community areas](images/community_area_map.png)", "![Grid](images/fail_density_map.png)", "![ZIPs](images/zip_fail_vs_city.png)",
          "", "## Q4 · After a fail", "",
          table([af[o] for o in ["All fails", "Canvass", "Complaint", "License", "Canvass re-inspection", "Complaint re-inspection", "License re-inspection"]],
                ["failed_inspection_type", "fails", "with_next_inspection", "next_pass_pct", "next_pass_conditions_pct", "next_fail_pct", "median_days_to_next",
                 "next_within_30d_pct", "next_is_reinspection_pct"],
                ["Failed inspection", "Fails", "With a next inspection", "Next Pass %", "Next PwC %", "Next Fail %", "Median days", "Next within 30 d %",
                 "Next is a re-inspection %"]), "",
          table(lag, ["lag_band", "fails", "pct_of_fails", "next_passed_pct"], ["Days to next completed inspection", "Fails", "% of fails", "Next passed (incl. PwC) %"]), "",
          table(rf, ["fails_band", "facilities", "pct_of_facilities", "total_fails", "avg_completed_inspections"],
                ["Fails per facility", "Facilities", "% of inspected facilities", "Fails", "Avg completed inspections"]), "",
          table(tf, ["rnk", "dba_name", "address", "facility_group", "completed_inspections", "fails", "fail_pct"],
                ["Rank", "Facility", "Address", "Group", "Completed", "Fails", "Fail %"]), "",
          "Rank 1 is one license covering the concession stands at the White Sox ballpark (333 W 35th St), so it is inspected far more often than a single kitchen.", "",
          "![After fail](images/after_fail.png)", "![Lag](images/reinspection_lag.png)", "![Repeat](images/repeat_fail.png)", "![Top](images/top_fail_facilities.png)",
          "", "## Q5 · Violations behind failures", "",
          table(sorted(rd("a_fail_driver"), key=lambda r: (r["code_scheme"], r["worst_citation"])),
                ["code_scheme", "worst_citation", "completed", "pass_pct", "pass_conditions_pct", "fail_pct", "share_of_fails"],
                ["Form", "Most severe violation", "Completed", "Pass %", "PwC %", "Fail %", "% of the form's fails"]), "",
          table(sorted(rd("a_violation_theme"), key=lambda r: (r["code_scheme"], -f(r["pct_of_failed"]))),
                ["code_scheme", "theme", "inspections_cited", "pct_of_failed", "pct_of_pass_conditions", "pct_of_passed", "fail_vs_pass_ratio"],
                ["Form", "Theme", "Inspections citing", "% of fails", "% of PwC", "% of passes", "Fail / pass ratio"]), "",
          table(vtop, ["code_scheme", "rnk", "code", "title", "official_class", "pct_of_failed", "pct_of_passed", "fail_pct_when_cited"],
                ["Form", "Rank", "Code", "Title", "Class", "% of fails", "% of passes", "Fail % when cited"]), "",
          "![Themes](images/violation_themes.png)", "![Top codes](images/violation_top_2018.png)", "![Driver](images/fail_driver.png)",
          "![Count](images/citation_count.png)",
          "", "## Q6 · Inspection programmes", "",
          table(sorted(rd("a_inspection_type"), key=lambda r: -i(r["completed"])),
                ["inspection_kind", "completed", "share_pct", "pass_pct", "pass_conditions_pct", "fail_pct", "avg_citations"],
                ["Inspection type", "Completed", "Share %", "Pass %", "PwC %", "Fail %", "Violations / insp."]), "",
          "![Inspection types](images/inspection_type.png)", "![Inspections per year](images/inspections_yearly.png)",
          "", "## Seasonality", "", table(se, ["month_name", "completed_per_year", "fail_pct", "pest_citation_pct", "complaint_share_pct"],
                                         ["Month", "Completed per year", "Fail %", "Citing pests %", "Complaint share %"]), "",
          "![Seasonal](images/seasonal.png)",
          "", "## Q7 · Data quality", "", table(dq_r, ["entity", "raw_rows", "distinct_rows", "clean_rows", "grain"],
                                                ["Entity", "Raw rows", "Distinct", "Clean", "Grain"]), "",
          table(dq_n, ["column_name", "null_pct", "treatment"], ["Raw column", "Blank %", "Treatment"]), "",
          table(dq_i, ["check_name", "affected_rows"], ["Issue", "Rows"]), "",
          f"### Assertions: {npass}/{len(asr)} pass", "", table(asr, ["check_name", "failed_rows", "status"], ["Check", "Failed rows", "Status"]), "",
          "![Data quality](images/data_quality.png)", "",
          "## How the images were made", "",
          "`scripts/make_charts.py` reads the DuckDB result tables in `results/tables/*.csv` and writes every chart as a plain-vector SVG with the small "
          "custom writer `scripts/svgcharts.py` (rect / line / polyline / polygon / circle / text only, no plotting library, no embedded raster). The "
          "community-area map draws the 77 official boundaries (simplified in `data/reference/community_area_shapes.json`) as SVG polygons. "
          "`scripts/render_png.py` then rasterises each SVG to PNG at 2x with headless Google Chrome.", ""]
(RES / "RESULTS.md").write_text("\n".join(lines))
print("wrote results/RESULTS.md,", len(lines), "lines")
