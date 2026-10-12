#!/usr/bin/env python3
"""Download the full City of Chicago Food Inspections CSV into data/raw_full/food_inspections.csv.

Dataset: "Food Inspections", City of Chicago Department of Public Health (CDPH) Food Protection Program, dataset id 4ijn-s7e5 on the
City of Chicago Data Portal: https://data.cityofchicago.org/Health-Human-Services/Food-Inspections/4ijn-s7e5
Kaggle copies: https://www.kaggle.com/datasets/chicago/chicago-food-inspections (older snapshot) and
https://www.kaggle.com/datasets/tjkyner/chicago-food-inspections. There is no Kaggle API key, so the portal export is used.
Licence: City of Chicago Data Portal Terms of Use (https://www.chicago.gov/city/en/narr/foia/data_disclaimer.html), free public use.

The portal updates the dataset daily, so a fresh download will have more rows and a different checksum than the snapshot
this project was built on. The snapshot is printed for comparison; pass --strict to fail when the file differs from it.
  python scripts/download_full_data.py            # ~348 MB CSV, 17 columns
  python scripts/download_full_data.py --strict   # exit 1 unless the bytes match the 2026-10-12 snapshot
  python scripts/download_full_data.py --geo      # also fetch the community-area boundaries (GeoJSON, 2.1 MB) for build_geo_reference.py
"""
import hashlib, pathlib, sys, urllib.request

URL = "https://data.cityofchicago.org/api/views/4ijn-s7e5/rows.csv?accessType=DOWNLOAD"
ALT_URL = "https://data.cityofchicago.org/api/v3/views/4ijn-s7e5/export.csv?accessType=DOWNLOAD"   # same export, newer API path
GEO_URL = "https://data.cityofchicago.org/api/geospatial/igwz-8jzy?method=export&format=GeoJSON"
# snapshot used for every number in this repo (downloaded 2026-10-12 IST; last inspection date 2026-10-09)
SNAPSHOT = {"bytes": 347860264, "rows": 316963, "sha256": "b3c01e4400cfcfc72dbd03025dd7b03769cb8d5fb210e40656c3757caf9f1f94"}
GEO_SNAPSHOT = {"bytes": 2072024, "sha256": "0921a90f21ee433da800194c62044dbc6fc208f3a6828e2e358b382082ecd719"}

ROOT = pathlib.Path(__file__).resolve().parents[1]
out = ROOT / "data" / "raw_full"; out.mkdir(parents=True, exist_ok=True)


def fetch(url, dest):
    tmp = dest.with_suffix(".part")
    print("downloading", url)
    with urllib.request.urlopen(url) as r, open(tmp, "wb") as fh:
        while chunk := r.read(1 << 20):
            fh.write(chunk)
    tmp.replace(dest)


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        while chunk := fh.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


csv = out / "food_inspections.csv"
if not csv.exists():
    try:
        fetch(URL, csv)
    except Exception as e:
        print("primary URL failed:", e); fetch(ALT_URL, csv)
digest = sha(csv)
match = csv.stat().st_size == SNAPSHOT["bytes"] and digest == SNAPSHOT["sha256"]
print(f"{csv.name}: {csv.stat().st_size:,} bytes, sha256 {digest}")
print("matches the 2026-10-12 snapshot (316,963 rows)" if match else
      f"differs from the snapshot ({SNAPSHOT['bytes']:,} bytes, {SNAPSHOT['rows']:,} rows): the portal adds inspections daily")
if "--geo" in sys.argv:
    gj = out / "community_areas.geojson"
    if not gj.exists():
        fetch(GEO_URL, gj)
    print(f"{gj.name}: {gj.stat().st_size:,} bytes, sha256 {sha(gj)} (snapshot {GEO_SNAPSHOT['sha256'][:12]}...)")
sys.exit(1 if "--strict" in sys.argv and not match else 0)
