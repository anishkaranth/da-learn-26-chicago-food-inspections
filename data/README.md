# data/

| Folder | In git | Content |
|---|---|---|
| `raw/food_inspections.csv` | yes | deterministic sample of the raw export: 7,500 of 316,963 rows (2.37%, 8.0 MB), same 17 columns and text. Rule: the complete history of every facility whose license number is divisible by 40, plus edge cases for every cleaning rule (exact duplicates, CHICAGO misspellings, blank city, suburb addresses, blank license / facility type, Risk `All`, no coordinates, Fail without violation text, violations on Out of Business / No Entry reports). Rebuild with `python scripts/make_sample.py`. |
| `raw_full/` | no (gitignored) | `food_inspections.csv` (347,860,264 B, 316,963 rows) and `community_areas.geojson` from `python scripts/download_full_data.py --geo` |
| `reference/` | yes | `violation_codes.csv` (110 codes: 2010 form 1-45 + 70, 2018 Food Code form 1-64, with official class and a theme), `community_areas.csv` (77 areas), `geo_point_community_area.csv` (18,968 distinct raw coordinates -> community area, point-in-polygon), `community_area_shapes.json` (simplified outlines for the SVG map). Built by `scripts/build_geo_reference.py`; the theme mapping is hand-made. |
| `clean/star/` | yes | star schema from the full run: complete dimensions + aggregates, facts as a 5%-of-facilities sample (`facility_key % 20 = 0`) |
| `clean/possible_duplicates.csv` | yes | same facility + day + inspection type + result reported more than once with different content (kept, listed) |
| `clean/city_fixes.csv` | yes | raw city spellings and how they were standardised |
