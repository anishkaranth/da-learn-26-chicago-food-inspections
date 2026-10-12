#!/usr/bin/env python3
"""Build the community-area reference files in data/reference/ (committed; re-run only to refresh).

Source: City of Chicago "Boundaries - Community Areas" (dataset igwz-8jzy, the 77 official community areas, City of Chicago Data
Portal Terms of Use), https://data.cityofchicago.org/api/geospatial/igwz-8jzy?method=export&format=GeoJSON
The food-inspections CSV export carries Latitude/Longitude but not the portal's computed region columns, so every distinct
inspection coordinate is assigned to a community area here (point-in-polygon, ray casting on the full-resolution boundaries).

Writes
  data/reference/community_areas.csv            area_num, community_area, centroid_lat, centroid_lng, area_km2 (77 rows)
  data/reference/geo_point_community_area.csv   latitude, longitude (raw text, as in the CSV), area_num (blank = outside every area)
  data/reference/community_area_shapes.json     simplified outlines (Douglas-Peucker, ~12 m) used only to draw the SVG map
  python scripts/build_geo_reference.py      # uses data/raw_full/food_inspections.csv (falls back to data/raw/)
"""
import csv, json, math, pathlib, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
URL = "https://data.cityofchicago.org/api/geospatial/igwz-8jzy?method=export&format=GeoJSON"
GJ = ROOT / "data/raw_full/community_areas.geojson"
REF = ROOT / "data/reference"
if not GJ.exists():
    GJ.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(URL, GJ)
feats = json.loads(GJ.read_text())["features"]


def ring_area_centroid(r):
    a = cx = cy = 0.0
    for (x1, y1), (x2, y2) in zip(r, r[1:] + r[:1]):
        cr = x1 * y2 - x2 * y1
        a += cr; cx += (x1 + x2) * cr; cy += (y1 + y2) * cr
    return a / 2, (cx / (3 * a) if a else 0), (cy / (3 * a) if a else 0)


def inside(x, y, ring):
    c = False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def dp(pts, tol):
    if len(pts) < 4:
        return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    dx, dy = x2 - x1, y2 - y1; L = math.hypot(dx, dy) or 1e-12
    dmax, idx = 0, 0
    for i in range(1, len(pts) - 1):
        d = abs(dy * pts[i][0] - dx * pts[i][1] + x2 * y1 - y2 * x1) / L
        if d > dmax:
            dmax, idx = d, i
    if dmax <= tol:
        return [pts[0], pts[-1]]
    return dp(pts[:idx + 1], tol)[:-1] + dp(pts[idx:], tol)


def simplify_ring(r, tol=0.00012):
    """Closed ring: split at the vertex farthest from the first one and simplify both halves (~12 m tolerance)."""
    k = max(range(len(r)), key=lambda i: (r[i][0] - r[0][0]) ** 2 + (r[i][1] - r[0][1]) ** 2)
    return dp(r[:k + 1], tol)[:-1] + dp(r[k:] + [r[0]], tol)[:-1]


areas = []
for f in feats:
    p = f["properties"]; num = int(p["area_numbe"]); name = p["community"].title()
    polys = [[[(float(x), float(y)) for x, y, *_ in ring] for ring in poly] for poly in f["geometry"]["coordinates"]]
    xs = [x for poly in polys for x, _ in poly[0]]; ys = [y for poly in polys for _, y in poly[0]]
    A = CX = CY = 0.0
    for poly in polys:
        a, cx, cy = ring_area_centroid(poly[0]); A += a; CX += a * cx; CY += a * cy
    lat0 = CY / A
    km2 = abs(A) * 111.32 ** 2 * math.cos(math.radians(lat0))
    areas.append(dict(num=num, name=name, polys=polys, bbox=(min(xs), min(ys), max(xs), max(ys)), clat=CY / A, clng=CX / A, km2=km2))
areas.sort(key=lambda a: a["num"])
with open(REF / "community_areas.csv", "w", newline="") as fh:
    w = csv.writer(fh, lineterminator="\n"); w.writerow(["area_num", "community_area", "centroid_lat", "centroid_lng", "area_km2"])
    for a in areas:
        w.writerow([a["num"], a["name"], f"{a['clat']:.6f}", f"{a['clng']:.6f}", f"{a['km2']:.2f}"])

shapes = {str(a["num"]): {"name": a["name"], "rings": [[[round(x, 5), round(y, 5)] for x, y in simplify_ring(poly[0])]
                                                      for poly in a["polys"]]} for a in areas}
(REF / "community_area_shapes.json").write_text(json.dumps(shapes, separators=(",", ":")) + "\n")

src = ROOT / "data/raw_full/food_inspections.csv"
src = src if src.exists() else ROOT / "data/raw/food_inspections_sample.csv"
pts = set()
with open(src, newline="", encoding="utf-8") as fh:
    for r in csv.DictReader(fh):
        if r["Latitude"] and r["Longitude"]:
            pts.add((r["Latitude"], r["Longitude"]))
hit = 0
with open(REF / "geo_point_community_area.csv", "w", newline="") as fh:
    w = csv.writer(fh, lineterminator="\n"); w.writerow(["latitude", "longitude", "area_num"])
    for la, lo in sorted(pts):
        x, y = float(lo), float(la); found = ""
        for a in areas:
            b = a["bbox"]
            if b[0] <= x <= b[2] and b[1] <= y <= b[3] and any(inside(x, y, poly[0]) and not any(inside(x, y, h) for h in poly[1:])
                                                               for poly in a["polys"]):
                found = a["num"]; break
        hit += found != ""
        w.writerow([la, lo, found])
print(f"{len(areas)} community areas; {len(pts):,} distinct coordinates from {src.name}, {hit:,} inside an area, {len(pts) - hit:,} outside")
