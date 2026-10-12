#!/usr/bin/env python3
"""Rebuild the committed raw sample data/raw/food_inspections.csv from data/raw_full/food_inspections.csv.

Rule (deterministic): the COMPLETE inspection history of every facility whose license number is divisible by 40 (about 2.5% of
facilities, so re-inspection chains stay intact), plus edge cases so every cleaning rule is exercised on the sample: both copies of
exact duplicate reports, CHICAGO misspellings, blank city, suburb addresses, blank / 0 license, blank facility type, Risk 'All',
missing coordinates, a Fail with no violation text and violations on reports without an outcome. Rows are copied unchanged
(same header, same text; csv module re-quoting only)."""
import csv, pathlib, sys
import duckdb

csv.field_size_limit(sys.maxsize)
ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "data/raw_full/food_inspections.csv"; OUT = ROOT / "data/raw/food_inspections.csv"
OUT.parent.mkdir(parents=True, exist_ok=True)
con = duckdb.connect()
con.execute(f"CREATE TABLE t AS SELECT * FROM read_csv('{SRC.as_posix()}', header = true, all_varchar = true)")
q = lambda w, n: f'(SELECT "Inspection ID" FROM t WHERE {w} ORDER BY CAST("Inspection ID" AS BIGINT) LIMIT {n})'
ids = {r[0] for r in con.execute(f"""
  SELECT "Inspection ID" FROM t WHERE TRY_CAST("License #" AS BIGINT) % 40 = 0 AND TRY_CAST("License #" AS BIGINT) > 0
  UNION SELECT "Inspection ID" FROM t WHERE ("DBA Name", "Address", "Inspection Date", "Inspection Type", "Results") IN
        (SELECT ("DBA Name", "Address", "Inspection Date", "Inspection Type", "Results") FROM
           (SELECT "DBA Name", "Address", "Inspection Date", "Inspection Type", "Results", "Violations", COUNT(*) n FROM t
            GROUP BY ALL HAVING COUNT(*) > 1 ORDER BY ALL LIMIT 25))
  UNION SELECT * FROM {q("upper(trim(City)) IN ('CCHICAGO', 'CHICAGOO', '312CHICAGO', 'CHICAGO.', 'CHCHICAGO')", 25)}
  UNION SELECT * FROM {q("City IS NULL", 15)}
  UNION SELECT * FROM {q("upper(City) IN ('SCHAUMBURG', 'EVANSTON', 'OAK PARK')", 10)}
  UNION SELECT * FROM {q('COALESCE(TRY_CAST("License #" AS BIGINT), 0) = 0', 20)}
  UNION SELECT * FROM {q('"Facility Type" IS NULL', 20)}
  UNION SELECT * FROM {q("Risk = 'All' OR Risk IS NULL", 10)}
  UNION SELECT * FROM {q("Latitude IS NULL", 20)}
  UNION SELECT * FROM {q("Results = 'Fail' AND Violations IS NULL", 15)}
  UNION SELECT * FROM {q("Results IN ('Out of Business', 'No Entry') AND Violations IS NOT NULL", 15)}
""").fetchall()}
n = tot = 0
with open(SRC, newline="", encoding="utf-8") as fi, open(OUT, "w", newline="", encoding="utf-8") as fo:
    r = csv.reader(fi); w = csv.writer(fo, lineterminator="\n")
    w.writerow(next(r))
    for row in r:
        tot += 1
        if row[0] in ids:
            w.writerow(row); n += 1
print(f"sample: {n:,} of {tot:,} rows ({100 * n / tot:.2f}%), {OUT.stat().st_size:,} B -> {OUT.relative_to(ROOT)}")
