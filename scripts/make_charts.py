#!/usr/bin/env python3
"""Render SVG charts (pure vector shapes, no raster) from the KPI tables exported by run_pipeline.py."""
import csv, json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import svgcharts as S
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parents[1]
BLUE, ORANGE, GREEN, SAND, NAVY, BROWN, PURPLE, ROSE, TEAL, GOLD = S.PALETTE[:10]
PASS, PWC, FAIL = "#2a9d8f", "#e9c46a", "#d1495b"
OUT3 = [PASS, PWC, FAIL]
MON = {"01": "Jan", "02": "Feb", "03": "Mar", "04": "Apr", "05": "May", "06": "Jun", "07": "Jul", "08": "Aug", "09": "Sep", "10": "Oct",
       "11": "Nov", "12": "Dec"}


def rd(t, name):
    with open(pathlib.Path(t) / f"{name}.csv", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    return float(x) if x not in ("", None) else 0.0


def i(x):
    return int(f(x))


def short(s, n=28):
    s = s.title().replace("'S", "'s").replace(", Inc.", "").replace(", Inc", "").replace(" Inc.", "")
    return s if len(s) <= n else s[: n - 1] + "."


def dql(n, m=46):
    n = n.split(", ")[0].split(" (")[0]
    n = n[:1].upper() + n[1:]
    return n if len(n) <= m else n[: m - 1] + "."


def choropleth(title, values, subtitle=None, w=640, h=None, lo="#fbeee6", hi="#9b2226", vmin=None, vmax=None, labels=None, fmt="{:.0f}%"):
    """Community-area map: values {area_num: value} (None = grey). Polygons from data/reference/community_area_shapes.json."""
    shapes = json.loads((ROOT / "data/reference/community_area_shapes.json").read_text())
    xs = [x for s in shapes.values() for r in s["rings"] for x, _ in r]; ys = [y for s in shapes.values() for r in s["rings"] for _, y in r]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    kx = 0.7431   # cos(41.84 deg): equal-distance scaling of longitude
    top, pad = 52, 12
    h = h or 640
    sc = min((w - 190 - 2 * pad) / ((x1 - x0) * kx), (h - top - 30) / (y1 - y0))
    px = lambda x: pad + (x - x0) * kx * sc
    py = lambda y: top + (y1 - y) * sc
    vals = [v for v in values.values() if v is not None]
    lo_v = min(vals) if vmin is None else vmin; hi_v = max(vals) if vmax is None else vmax
    out = [S._head(title, subtitle)]
    for num, s in shapes.items():
        v = values.get(int(num))
        c = "#e5e5e5" if v is None else S._mix(lo, hi, max(0, min(1, (v - lo_v) / ((hi_v - lo_v) or 1))))
        for r in s["rings"]:
            pts = " ".join(f"{px(x):.1f},{py(y):.1f}" for x, y in r)
            out.append(f'<polygon points="{pts}" fill="{c}" stroke="#fff" stroke-width="0.7"><title>{escape(s["name"])}</title></polygon>')
    for num, txt in (labels or {}).items():
        s = shapes[str(num)]; r = max(s["rings"], key=len)
        cx = sum(x for x, _ in r) / len(r); cy = sum(y for _, y in r) / len(r)
        out.append(S._t(px(cx), py(cy) + 3, txt, 8, "middle", "#111", "bold"))
    lx = w - 170; ly = top + 20
    out.append(S._t(lx, ly - 6, "Fail rate (completed inspections)", 9, fill="#444"))
    for k in range(6):
        v = lo_v + (hi_v - lo_v) * k / 5
        out.append(f'<rect x="{lx}" y="{ly + k * 18}" width="22" height="16" fill="{S._mix(lo, hi, k / 5)}"/>' + S._t(lx + 28, ly + k * 18 + 12, fmt.format(v), 9))
    out.append(f'<rect x="{lx}" y="{ly + 6 * 18}" width="22" height="16" fill="#e5e5e5"/>' + S._t(lx + 28, ly + 6 * 18 + 12, "< 500 inspections", 9))
    return S.Panel(w, h, "".join(out))


def make_all(tables, out):
    out = pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    P = {}
    k = rd(tables, "a_kpi_headline")[0]
    yr = sorted(rd(tables, "a_yearly"), key=lambda r: i(r["year"]))
    ylab = [r["year"][2:] + ("*" if r["is_partial_year"] == "1" else "") for r in yr]
    mo = sorted(rd(tables, "a_monthly"), key=lambda r: r["year_month"])
    fg = sorted(rd(tables, "a_facility_group"), key=lambda r: -f(r["fail_pct"]))
    ft = sorted(rd(tables, "a_facility_type_top"), key=lambda r: -f(r["fail_pct"]))
    rk = sorted([r for r in rd(tables, "a_risk") if r["risk_key"] != "0"], key=lambda r: i(r["risk_key"]))
    rg = rd(tables, "a_risk_group")
    zp = sorted(rd(tables, "a_zip"), key=lambda r: i(r["rnk"]))
    ca = rd(tables, "a_community_area")
    grid = rd(tables, "a_map_grid")
    it = sorted(rd(tables, "a_inspection_type"), key=lambda r: -i(r["completed"]))
    af = rd(tables, "a_after_fail")
    lag = sorted(rd(tables, "a_reinspection_lag"), key=lambda r: r["lag_band"])
    rf = sorted(rd(tables, "a_repeat_fail"), key=lambda r: r["fails_band"])
    vt = rd(tables, "a_violation_theme")
    vtop = sorted([r for r in rd(tables, "a_violation_top") if r["code_scheme"] == "2018"], key=lambda r: i(r["rnk"]))
    fd = sorted(rd(tables, "a_fail_driver"), key=lambda r: (r["code_scheme"], r["worst_citation"]))
    cc = rd(tables, "a_citation_count")
    se = sorted(rd(tables, "a_seasonal"), key=lambda r: i(r["month"]))
    tf = sorted(rd(tables, "a_top_fail_facilities"), key=lambda r: i(r["rnk"]))
    dq = rd(tables, "dq_issues")
    city_fail = f(k["fail_pct"])
    small = dict(w=600, h=330)

    # Q1 outcomes over time
    P["result_mix_yearly"] = S.stacked_area("Outcome mix of completed inspections by year (%)", ylab,
                                            [("Pass", [f(r["pass_pct"]) for r in yr]), ("Pass w/ Conditions", [f(r["pass_conditions_pct"]) for r in yr]),
                                             ("Fail", [f(r["fail_pct"]) for r in yr])], colors=OUT3, every=1,
                                            subtitle="* 2026 = 1 Jan - 9 Oct. The 1 Jul 2018 Food Code form made 'Pass w/ Conditions' far more common")
    P["inspections_yearly"] = S.vbar("Completed inspections per year", ylab, [i(r["completed"]) for r in yr], fmt="{:,.0f}", color=BLUE,
                                     subtitle="COVID-19 dip in 2020-21; * 2026 is a partial year (to 9 Oct)",
                                     notes=[f"{f(r['fail_pct']):.0f}% fail" for r in yr])
    xs = [MON[r["year_month"][5:7]] + " " + r["year_month"][2:4] if r["year_month"][5:7] == "01" else "" for r in mo]
    xs = [r["year_month"][:4] if r["year_month"][5:7] == "01" else "" for r in mo]
    P["fail_rate_monthly"] = S.line("Monthly fail rate and pass-with-conditions rate (%)", [r["year_month"] for r in mo],
                                    [("Fail %", [f(r["fail_pct"]) for r in mo]), ("Pass w/ Conditions %", [f(r["pass_conditions_pct"]) for r in mo])],
                                    fmt="{:.0f}", every=24, colors=[FAIL, "#c9a227"], w=900, h=340, ymin=0,
                                    subtitle=f"Jan 2010 - Oct 2026, {len(mo)} months; fail rate is steady around {city_fail:.0f}% while conditions swing with the 2018 form")
    # Q2 facility type and risk
    P["facility_group_fail"] = S.hbar("Fail rate by facility group (%)", [r["facility_group"] for r in fg], [f(r["fail_pct"]) for r in fg],
                                      fmt="{:.1f}", color=[FAIL if f(r["fail_pct"]) > city_fail else BLUE for r in fg],
                                      notes=[f"n={i(r['completed']):,}" for r in fg], vmax=60,
                                      subtitle=f"completed inspections 2010-2026; red = above the city-wide {city_fail:.1f}%")
    P["facility_type_top"] = S.hbar("Fail rate by facility type (types with 500+ inspections)", [short(r["facility_type"], 30) for r in ft],
                                    [f(r["fail_pct"]) for r in ft], fmt="{:.1f}%",
                                    color=[FAIL if f(r["fail_pct"]) > city_fail else BLUE for r in ft],
                                    notes=[f"n={i(r['completed']):,}" for r in ft], vmax=40)
    P["risk_outcomes"] = S.stacked_hbar("Outcomes by risk category (% of completed inspections)", [r["risk"] for r in rk],
                                        [[f(r["pass_pct"]), f(r["pass_conditions_pct"]), f(r["fail_pct"])] for r in rk],
                                        ["Pass", "Pass w/ Conditions", "Fail"], colors=OUT3, h=210,
                                        notes=[f"{f(r['inspections_per_facility']):.1f} insp./facility" for r in rk],
                                        subtitle="High-risk places are inspected most often; low-risk places fail most when they are inspected")
    groups = [r["facility_group"] for r in fg if r["facility_group"] != "Unknown"]
    RG = {(r["facility_group"], i(r["risk_key"])): r for r in rg}
    P["risk_group_heatmap"] = S.heatmap("Fail rate: facility group x risk category (%)", groups, ["Risk 1 (High)", "Risk 2 (Medium)", "Risk 3 (Low)"],
                                        [[f(RG[(g, rr)]["fail_pct"]) if (g, rr) in RG and i(RG[(g, rr)]["completed"]) >= 100 else None for rr in (1, 2, 3)]
                                         for g in groups], fmt="{:.0f}", hi_color="#9b2226", lo_color="#fbeee6",
                                        subtitle="cells with fewer than 100 completed inspections left blank")
    # Q3 geography
    zz = zp[:10] + zp[-8:]
    P["zip_fail_vs_city"] = S.dbar("ZIP codes: fail rate vs city average (percentage points)", [f"{r['zip5']}  ({f(r['fail_pct']):.1f}%)" for r in zz],
                                   [f(r["fail_pct"]) - city_fail for r in zz], fmt="{:+.1f}", pos_color=FAIL, neg_color=PASS,
                                   subtitle=f"10 highest and 8 lowest of {len(zp)} ZIPs with 1,000+ completed inspections; city = {city_fail:.2f}%")
    ranked = {i(r["area_num"]): f(r["fail_pct"]) for r in ca if r["rnk"]}
    top5 = {i(r["area_num"]): str(i(r["rnk"])) for r in ca if r["rnk"] and i(r["rnk"]) <= 5}
    P["community_area_map"] = choropleth("Fail rate by community area", ranked, vmin=12, vmax=34,
                                         subtitle="77 official community areas; numbers = 5 highest fail rates (see table); 3 areas under 500 inspections grey",
                                         labels=top5)
    cats = [(0, 18), (18, 22), (22, 26), (26, 30), (30, 101)]
    names = ["< 18%", "18-22%", "22-26%", "26-30%", "30%+"]
    cols = ["#2a9d8f", "#8ab17d", "#e9c46a", "#f4a261", "#d1495b"]
    pts = [(f(r["cell_lng"]), f(r["cell_lat"]), next(j for j, (a, b) in enumerate(cats) if a <= f(r["fail_pct"]) < b)) for r in grid]
    P["fail_density_map"] = S.scatter("Fail rate on a 1 km grid (cells with 30+ inspections)", pts, colors=cols, groups=names, r=4.2, opacity=0.9,
                                      w=470, h=640, xlabel="longitude", ylabel="latitude", xticks=[-87.9, -87.8, -87.7, -87.6], xtick_fmt="{:.1f}",
                                      ymin=41.64, ymax=42.03, yticks=[41.65, 41.75, 41.85, 41.95], ytick_fmt="{:.2f}",
                                      subtitle=f"{len(grid)} cells of 0.01 deg; colour = share of completed inspections that failed")
    # Q6 inspection programmes
    P["inspection_type"] = S.stacked_hbar("Outcomes by inspection type (% of completed)", [r["inspection_kind"] for r in it],
                                          [[f(r["pass_pct"]), f(r["pass_conditions_pct"]), f(r["fail_pct"])] for r in it],
                                          ["Pass", "Pass w/ Conditions", "Fail"], colors=OUT3, notes=[f"n={i(r['completed']):,}" for r in it],
                                          subtitle="first visits fail far more often than the re-inspections that follow them")
    # Q4 after a fail
    order = ["All fails", "Canvass", "Complaint", "License", "Canvass re-inspection", "Complaint re-inspection", "License re-inspection"]
    AF = {r["failed_inspection_type"]: r for r in af}
    P["after_fail"] = S.stacked_hbar("Next completed inspection after a Fail (% of fails followed up)", order,
                                     [[f(AF[o]["next_pass_pct"]), f(AF[o]["next_pass_conditions_pct"]), f(AF[o]["next_fail_pct"])] for o in order],
                                     ["Pass", "Pass w/ Conditions", "Fail again"], colors=OUT3,
                                     notes=[f"median {f(AF[o]['median_days_to_next']):.0f} d" for o in order],
                                     subtitle="row = type of the failed inspection; same facility (license), next Pass / PwC / Fail on any date")
    P["reinspection_lag"] = S.vbar("Days from a Fail to the next completed inspection", [r["lag_band"][2:] for r in lag],
                                   [f(r["pct_of_fails"]) for r in lag], fmt="{:.1f}%", color=NAVY,
                                   notes=[f"{f(r['next_passed_pct']):.0f}% passed" if r["next_passed_pct"] else "" for r in lag],
                                   subtitle="share of all fails; label = share whose next inspection passed (incl. with conditions)")
    P["repeat_fail"] = S.vbar("Facilities by number of failed inspections, 2010-2026", [r["fails_band"] + " fails" for r in rf],
                              [i(r["facilities"]) for r in rf], fmt="{:,.0f}", color=[PASS] + [FAIL] * 5,
                              notes=[f"{f(r['pct_of_facilities']):.1f}%" for r in rf],
                              subtitle=f"{f(k['repeat_fail_pct_of_failed_facilities']):.1f}% of facilities that ever failed failed again")
    P["top_fail_facilities"] = S.hbar("Facilities with the most failed inspections", [short(r["dba_name"], 30) for r in tf], [i(r["fails"]) for r in tf],
                                      fmt="{:,.0f}", color=FAIL, notes=[f"of {i(r['completed_inspections'])} ({f(r['fail_pct']):.0f}%)" for r in tf],
                                      vmax=45, subtitle="one license; #1 is the concession licence at the White Sox ballpark (many stands)")
    # Q5 violations
    v18 = sorted([r for r in vt if r["code_scheme"] == "2018"], key=lambda r: -f(r["pct_of_failed"]))
    P["violation_themes"] = S.dumbbell("Violation themes: % of passed vs failed inspections citing them (2018 form)", [r["theme"] for r in v18],
                                       [f(r["pct_of_passed"]) for r in v18], [f(r["pct_of_failed"]) for r in v18], names=("passed inspections", "failed inspections"),
                                       ca=PASS, cb=FAIL, w=700, notes=[f"x{f(r['fail_vs_pass_ratio']):.1f}" for r in v18],
                                       subtitle="Jul 2018 - Oct 2026; x = how many times more common in failed inspections")
    P["violation_top_2018"] = S.hbar("Most-cited violations in failed inspections (2018 form, % of fails)", [f"{r['code']}. " + short(r["title"], 40) for r in vtop[:12]],
                                     [f(r["pct_of_failed"]) for r in vtop[:12]], fmt="{:.1f}%", color=FAIL, w=760,
                                     notes=[f"(passed: {f(r['pct_of_passed']):.1f}%)" for r in vtop[:12]], vmax=80)
    labs = [("2018: " if r["code_scheme"] == "2018" else "2010: ") + r["worst_citation"][2:] for r in fd]
    P["fail_driver"] = S.stacked_hbar("Outcome by the most severe violation cited (% of completed)", labs,
                                      [[f(r["pass_pct"]), f(r["pass_conditions_pct"]), f(r["fail_pct"])] for r in fd],
                                      ["Pass", "Pass w/ Conditions", "Fail"], colors=OUT3, notes=[f"n={i(r['completed']):,}" for r in fd],
                                      subtitle="2010 form: Critical / Serious / Minor codes; 2018 form: Priority / Priority foundation / Core in the comments")
    ccs = {(r["code_scheme"], i(r["citations"])): f(r["fail_pct"]) for r in cc}
    P["citation_count"] = S.line("Fail rate by number of violations cited (%)", [str(n) if n < 12 else "12+" for n in range(13)],
                                 [("2010 form", [ccs.get(("2010", n)) for n in range(13)]), ("2018 form", [ccs.get(("2018", n)) for n in range(13)])],
                                 fmt="{:.0f}", every=1, colors=[NAVY, FAIL], ymin=0, xlabel="violation items cited")
    P["seasonal"] = S.line("Seasonality: fail rate and pest citations by month (%)", [r["month_name"] for r in se],
                           [("Fail %", [f(r["fail_pct"]) for r in se]), ("Inspections citing pests / rodents %", [f(r["pest_citation_pct"]) for r in se]),
                            ("Complaint-driven share %", [f(r["complaint_share_pct"]) for r in se])], fmt="{:.1f}", every=1, colors=[FAIL, BROWN, NAVY],
                           ymin=0, end_labels=True, subtitle="full years 2010-2025; late summer brings more pests, complaints and fails")
    DQ = [(r["check_name"], i(r["affected_rows"])) for r in dq if i(r["affected_rows"]) > 0 and "code list switch" not in r["check_name"]
          and "extra items" not in r["check_name"]]
    DQ.sort(key=lambda x: -x[1])
    P["data_quality"] = S.hbar("Data-quality findings (rows affected)", [dql(n) for n, _ in DQ],
                               [v for _, v in DQ], fmt="{:,.0f}", color=SAND, w=760,
                               subtitle=f"{i(k['raw_rows']):,} raw rows -> {i(k['inspection_reports']):,} reports; nothing else deleted, issues flagged")

    for name, p in P.items():
        S.save(p, out / f"{name}.svg")
    cards = [("raw rows -> reports", f"{i(k['raw_rows']) / 1000:,.1f}k -> {i(k['inspection_reports']) / 1000:,.1f}k"),
             ("completed inspections", f"{i(k['completed_inspections']):,}"), ("facilities", f"{i(k['facilities']):,}"),
             ("pass / conditions / fail", f"{f(k['pass_pct']):.0f} / {f(k['pass_conditions_pct']):.0f} / {f(k['fail_pct']):.0f}%"),
             ("next visit after a fail passes", f"{f(k['after_fail_next_pass_pct']) + f(k['after_fail_next_pass_conditions_pct']):.1f}%"),
             ("fail if a Priority violation (2018+)", f"{f(k['priority_citation_fail_pct']):.1f}%")]
    S.dashboard(out / "dashboard.svg", "da-learn-26 · Chicago food inspections (2010 - Oct 2026)",
                f"City of Chicago CDPH Food Protection Program; {i(k['raw_rows']):,} raw rows, {k['first_date']} .. {k['last_date']}; "
                "DuckDB SQL pipeline on the full data; Databricks skipped (quota)", cards, [
                    S.stacked_area("Outcome mix by year (%)", ylab, [("Pass", [f(r["pass_pct"]) for r in yr]),
                                   ("Pass w/ Conditions", [f(r["pass_conditions_pct"]) for r in yr]), ("Fail", [f(r["fail_pct"]) for r in yr])],
                                   colors=OUT3, every=2, **small),
                    S.stacked_hbar("Outcomes by inspection type (%)", [r["inspection_kind"] for r in it[:6]],
                                   [[f(r["pass_pct"]), f(r["pass_conditions_pct"]), f(r["fail_pct"])] for r in it[:6]],
                                   ["Pass", "PwC", "Fail"], colors=OUT3, w=600, h=330),
                    S.hbar("Fail rate by facility group (%)", [r["facility_group"] for r in fg if r["facility_group"] != "Unknown"],
                           [f(r["fail_pct"]) for r in fg if r["facility_group"] != "Unknown"], fmt="{:.1f}",
                           color=[FAIL if f(r["fail_pct"]) > city_fail else BLUE for r in fg if r["facility_group"] != "Unknown"], vmax=40, **small),
                    S.stacked_hbar("Next inspection after a Fail (%)", order[:4],
                                   [[f(AF[o]["next_pass_pct"]), f(AF[o]["next_pass_conditions_pct"]), f(AF[o]["next_fail_pct"])] for o in order[:4]],
                                   ["Pass", "PwC", "Fail again"], colors=OUT3, w=600, h=330,
                                   notes=[f"med {f(AF[o]['median_days_to_next']):.0f} d" for o in order[:4]]),
                    S.dumbbell("Themes: % of passed vs failed (2018 form)", [r["theme"].replace("Management, certification & training", "Management & training")
                                                                             .replace("Physical facilities & maintenance", "Physical facilities")
                                                                             .replace("Hand washing, hygiene & toilets", "Hand washing & hygiene")
                                                                             .replace("Administrative & follow-up", "Admin & follow-up") for r in v18],
                               [f(r["pct_of_passed"]) for r in v18], [f(r["pct_of_failed"]) for r in v18], names=("passed", "failed"), ca=PASS, cb=FAIL,
                               w=600, h=330),
                    S.stacked_hbar("Outcome by most severe violation (%)", labs, [[f(r["pass_pct"]), f(r["pass_conditions_pct"]), f(r["fail_pct"])] for r in fd],
                                   ["Pass", "PwC", "Fail"], colors=OUT3, w=600, h=330),
                    choropleth("Fail rate by community area", ranked, vmin=12, vmax=34, w=600, h=560, labels=top5),
                    S.hbar("Most-cited violations in failed inspections (2018 form, %)", [f"{r['code']}. " + short(r["title"], 34) for r in vtop[:12]],
                           [f(r["pct_of_failed"]) for r in vtop[:12]], fmt="{:.0f}%", color=FAIL, w=600, h=560,
                           notes=[f"(pass {f(r['pct_of_passed']):.0f}%)" for r in vtop[:12]], vmax=90),
                ], cols=2)
    print(f"wrote {len(P) + 1} SVG charts to {out}")


if __name__ == "__main__":
    t = sys.argv[1] if len(sys.argv) > 1 else ROOT / "results/tables"
    make_all(t, sys.argv[2] if len(sys.argv) > 2 else ROOT / "results/images")
