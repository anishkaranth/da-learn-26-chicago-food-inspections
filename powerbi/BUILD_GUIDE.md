# Build guide · Power BI Desktop (Windows)

There is no `.pbix` in this repo: Power BI Desktop only runs on Windows and this project was built on Linux. Everything needed to build the
report in about 20 minutes is here.

1. **Get the data.** Use the committed CSVs in `powerbi/data/`, or regenerate them: `python scripts/download_full_data.py` then
   `python run_pipeline.py --source full`.
2. **Load.** Home > Get data > Text/CSV, load the 11 files from `powerbi/data/`. In Power Query set types: every `*_key`, `inspection_id`,
   `license_no`, `area_num`, counts (`reports`, `completed`, `fails`, `passes`, `pass_conditions`, `citations`, `n_*`), `year`, `month`,
   `quarter`, `weekday_num`, `code`, `completed_seq`, `days_*` and the 0/1 flags as Whole number; `lat`, `lng`, `centroid_*`, `area_km2` as
   Decimal; `date`, `inspection_date`, `first_inspection`, `last_inspection` as Date; `zip5`, `code_scheme`, `year_month` and all names as
   Text (keep `zip5` as text so leading digits are not reformatted). Empty cells are nulls. Close & Apply.
3. **Model.** Create the relationships in `model.md` (many-to-one, single direction). Mark `dim_date` as the date table (column `date`) and
   sort `dim_date[day_name]` by `weekday_num`, `dim_date[month_name]` by `month`.
4. **Measures.** Create a blank table `_Measures` and paste each measure from `measures.dax`. Format rates as percentages.
5. **Visuals.** Build the page in `dashboard_spec.md`.
6. **Check against the repo** (no slicers): [Completed (full)] = 272,061, [Fails (full)] = 61,031, [Fail Rate % (full)] = 22.43%,
   [Pass w Conditions % (full)] = 17.27%; `dim_facility` has 49,547 rows. On the sample: [Reports] = 16,481, [Completed Inspections] =
   14,294, [Fails] = 3,269, [Fail Rate %] = 22.87% (full data: 22.43%).
