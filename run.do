/********************************************************************
  Product Complexity Research — One-Click Runner (Fully Commented)

  What this file does (end-to-end):
    1) Creates local folders for data, outputs, and logs.
    2) Downloads the two required source files directly from GitHub:
         - hs92_product_year_4.csv  (trade panel at HS92 4-digit)
         - HS92 codes.json          (dictionary: HS codes -> names)
    3) Sets $DAT and $HSJ globals to those local files.
    4) Runs the full analysis:
         - basic summaries
         - per-product change diagnostics
         - HS code dictionary build + merge
         - "changed products" table
         - top-10 imports/exports by year (with names)
         - panel balance + re-entry summary
         - HS codes present in data but missing in dictionary
    5) Answers 1995-specific questions:
         - do all dictionary codes appear in 1995?
         - which appear later or never?
         - top/bottom 5 products by PCI (1995) + PCI plots

  Requirements:
    * Stata 17/18 (18 uses json load; 16/17 will use the Python fallback)
    * Internet access (just for the initial GitHub downloads)

  Output locations:
    - outputs/tables/(...).csv, (...).xlsx
    - outputs/figures/(..).png
    - outputs/logs/run.smcl
********************************************************************/
/*
*  HOW TO RUN (one click)
*
*  PREREQS
*  --------
*  • Stata 17 or 18
*  • Internet access (first run downloads CSV & JSON from GitHub)
*  • Write permission in this project folder (to save outputs)
*
*  QUICK START – STATA GUI
*  -----------------------
*  1) Open Stata.
*  2) File  >  Change Working Directory…  → select this project folder.
*  3) File  >  Do…  → select this do-file  → click "Do".
*     • First run will create data/ and outputs/ and download the inputs.
*     • All tables go to outputs/tables/, figures to outputs/figures/,
*       and a full console log to outputs/logs/run.smcl.
*
*  QUICK START – COMMAND LINE
*  --------------------------
*  # macOS / Linux:
  cd /path/to/Project-Complexity-Research
  /Applications/Stata18/StataMP -b do run_all.do

  # Windows (PowerShell, adjust Stata edition and path):
  cd C:\path\to\Product-Complexity-Research---Purdue-University
  "C:\Program Files\Stata18\StataMP-64.exe" /e do run_all.do

  NOTES
  -----
  • Change the focus year (1995 by default) by editing:
        global Y 1995
    near the "1995 Focus" section.

  • First run downloads:
        data/raw/hs92_product_year_4.csv
        data/raw/HS92 codes.json
    from the project's GitHub. If those already exist locally,
    the script just uses them.

  • Stata 18 users: JSON is parsed via `json load`.
    Stata 16/17: a built-in Python fallback parses the JSON.

  EXPECTED OUTPUTS
  ----------------
  outputs/tables/
    - products_changed_over_time.csv
    - products_changed_counts.xlsx
    - top10_exports_by_year.csv
    - top10_imports_by_year.csv
    - panel_balance_by_product.csv
    - hs_codes_missing_in_dictionary.csv
    - dict_vs_1995_presence.csv
    - codes_missing_1995_appear_later.csv
    - codes_never_in_panel.csv
    - top5_pci_1995.csv, bottom5_pci_1995.csv, top_and_bottom5_pci_1995.csv
  outputs/figures/
    - pci_hist_1995.png
    - pci_kdensity_1995.png
  outputs/logs/
    - run.smcl  (full execution log)

  TROUBLESHOOTING
  ---------------
  • "file … not found" for CSV/JSON
      - Check internet connectivity on first run.
      - Confirm you can open the raw URLs in a browser.
      - Ensure the working directory is this project folder.

  • "permission denied" when writing outputs
      - Make sure you have write permissions to the folder.

  • "json load" not found (Stata < 18)
      - That's fine—Python fallback will auto-run.
      - If Python is not configured, install a system Python 3
        and make sure Stata can detect it (Preferences > Py).

  • Need to re-run fresh
      - Delete data/raw/* and outputs*/ and re-run the do-file.

*/



version 17
clear all
set more off
set rmsg on

*------------------------------------------------------
* 0) Project folders + logging (safe to re-run)
*    - Creates clean folder structure so all outputs
*      are easy to find and commit.
*------------------------------------------------------
cap mkdir "data"
cap mkdir "data/raw"
cap mkdir "data/clean"
cap mkdir "outputs"
cap mkdir "outputs/tables"
cap mkdir "outputs/figures"
cap mkdir "outputs/logs"

capture log close _all
log using "outputs/logs/run.smcl", replace   // captures console output

*------------------------------------------------------
* 1) Auto-download from GitHub — robust and simple
*    - We keep URLs explicit to avoid surprises.
*    - If you already have the files in data/raw, this
*      block just sets $DAT/$HSJ and proceeds.
*------------------------------------------------------

*----- File #1: the CSV panel (trade by HS92 4-digit) -----
cap mkdir "data"
cap mkdir "data/raw"

local LOCAL_CSV "data/raw/hs92_product_year_4.csv"   // where we store it locally
local got 0                                          // flag: did download succeed?

* Candidate URL(s). You can add more mirrors separated by spaces.
local GH_PATHS_CSV ///
    "https://raw.githubusercontent.com/sruthivish/Product-Complexity-Research---Purdue-University/main/data/raw/hs92_product_year_4.csv"

* Try each URL until one works. `copy` supports http/https in Stata 16+.
foreach url of local GH_PATHS_CSV {
    di as txt "Attempting: `url'"
    cap copy "`url'" "`LOCAL_CSV'", replace
    if !_rc {
        di as res "✓ Downloaded CSV to `LOCAL_CSV'"
        local got 1
        continue, break
    }
}

* If none succeeded, stop early with a helpful message.
if !`got' {
    di as err "Could not fetch the product CSV from GitHub. Check the URL or connectivity."
    di as err "Expected local path: `LOCAL_CSV'"
    exit 601
}

* Make the CSV path available to the rest of the do-file.
global DAT "`LOCAL_CSV'"

*----- File #2: the JSON dictionary (HS code -> label) -----
cap mkdir "data"
cap mkdir "data/raw"

* The file name on disk contains a space; that's okay locally.
local LOCAL_JSON "data/raw/HS92 codes.json"
local gotj 0

* URL MUST encode the space as %20
local GH_PATHS_JSON ///
    "https://raw.githubusercontent.com/sruthivish/Product-Complexity-Research---Purdue-University/main/data/raw/HS92%20codes.json"

foreach url of local GH_PATHS_JSON {
    di as txt "Attempting: `url'"
    cap copy "`url'" "`LOCAL_JSON'", replace
    if !_rc {
        di as res "✓ Downloaded JSON to `LOCAL_JSON'"
        local gotj 1
        continue, break
    }
}

if !`gotj' {
    di as err "Could not fetch the HS92 JSON from GitHub. Check the URL or connectivity."
    di as err "Expected local path: `LOCAL_JSON'"
    exit 602
}

* Make the JSON path available to the rest of the do-file.
global HSJ "`LOCAL_JSON'"

* Final sanity print (useful in logs)
ls data/raw
di as res "==> Using DAT: $DAT"
di as res "==> Using HSJ: $HSJ"

*------------------------------------------------------
* 2) Full analysis (your original code) — unchanged logic
*    This section reads the panel, runs summaries, and
*    builds diagnostics for per-product changes.
*------------------------------------------------------
import delimited using "$DAT", varnames(1) stringcols(1) clear
describe
order product_hs92_code product_id year export_value import_value pci

* Convert strings to numeric safely (force = coerce bad strings to missing).
destring year export_value import_value pci, replace force
compress   // reduce memory footprint

* Quick health checks: counts, years present, distribution by year
di "== Basic counts =="
count
bysort year: gen _one = 1
tab year
drop _one

sum export_value import_value pci
bysort year: sum export_value import_value pci

* Distinct code/year counts for context
quietly levelsof product_hs92_code, local(PRODS)
quietly levelsof year,            local(YEARS)
di "Distinct HS codes: `: word count `PRODS''"
di "Distinct years:    `: word count `YEARS''"

*======================================================
* CHANGE DIAGNOSTICS BY PRODUCT
*   - pci_sd: variability of PCI per code over time
*   - x_sd, m_sd: variability of exports/imports per code
*   - flags (pci_changed, values_changed)
*======================================================
bysort product_hs92_code: egen pci_sd = sd(pci)
gen pci_changed = (pci_sd > 0 & !missing(pci_sd))

bysort product_hs92_code: egen x_sd  = sd(export_value)
bysort product_hs92_code: egen m_sd  = sd(import_value)
gen values_changed = ((x_sd>0 & !missing(x_sd)) | (m_sd>0 & !missing(m_sd)))

* Build a small product-level panel summary (years present, first/last, re-entry)
preserve
    sort product_hs92_code year
    by product_hs92_code year: keep if _n==1

    by product_hs92_code: gen years_present = _N
    by product_hs92_code: gen first_year    = year[1]
    by product_hs92_code: gen last_year     = year[_N]

    bysort product_hs92_code (year): gen gap = year - year[_n-1] if _n>1
    by product_hs92_code: egen reenter_any = max(gap>1)
    keep product_hs92_code years_present first_year last_year reenter_any
    by product_hs92_code: keep if _n==1
    save "years_info.dta", replace
restore

*======================================================
* BUILD HS92 DICTIONARY IN A SEPARATE FRAME + MERGE
*   - Puts the JSON into a small lookup table: hs_code, hs_label
*   - Works in Stata 18 (json load) and falls back to Python in 16/17.
*======================================================
capture frame drop dict
frame create dict

cap which json
if _rc==0 {
    * Stata 18+: load from JSON directly
    frame change dict
    clear
    json load results using "$HSJ", noresidual
    keep id text
    rename (id text) (hs_code hs_label)
    duplicates drop
}
else {
    * Stata 16/17 fallback via Python: parse JSON -> tmp CSV -> import
    python clear
    python:
import json, csv
from sfi import Macro
p = Macro.getGlobal("HSJ")
with open(p, "r", encoding="utf-8") as f:
    J = json.load(f)
rows = []
for r in J.get("results", []):
    code = r.get("id"); text = r.get("text")
    if code and text: rows.append((str(code), str(text)))
with open("hs92_dict_tmp.csv","w",newline="",encoding="utf-8") as g:
    w = csv.writer(g); w.writerow(["hs_code","hs_label"]); w.writerows(rows)
end
    frame change dict
    clear
    import delimited using "hs92_dict_tmp.csv", varnames(1) clear
    erase "hs92_dict_tmp.csv"
    duplicates drop
}

* Attach labels to the main data (still in default frame) using frames-linking
frame change default
gen str hs_code = product_hs92_code
frlink m:1 hs_code, frame(dict)    // link handle named "dict"
frget  hs_label, from(dict)        // bring hs_label into the main frame

*======================================================
* COMBINE EVERYTHING INTO ONE TABLE (changed products)
*   - Adds panel coverage (balanced vs not) and ranks codes
*     by the magnitude of PCI movement.
*======================================================
preserve
    keep product_hs92_code hs_label pci_sd x_sd m_sd pci_changed values_changed
    by product_hs92_code: keep if _n==1
    merge 1:1 product_hs92_code using "years_info.dta", nogen

    levelsof year, local(ALL_YEARS)
    local T = wordcount("`ALL_YEARS'")
    gen balanced = (years_present == `T')

    gsort -pci_sd
    gen rank_pci_mover = _n

    list product_hs92_code hs_label pci_sd years_present first_year last_year ///
         reenter_any balanced if _n<=20, noobs abbreviate(24)

    export delimited using "outputs/tables/products_changed_over_time.csv", replace

    * Compact count table (Stata 17+ "table" -> "collect")
    table (pci_changed values_changed), statistic(frequency) ///
        nformat(%9.0g) name(chg)
    collect export "outputs/tables/products_changed_counts.xlsx", replace
restore

*======================================================
* BIGGEST EXPORTS / IMPORTS OVER TIME (WITH DEFINITIONS)
*   - For each year, take top-10 by value and export rows
*     with HS labels.
*======================================================
* Exports
preserve
    gsort year -export_value
    by year: gen rankX = _n
    keep if rankX <= 10
    keep year rankX product_hs92_code hs_label export_value
    sort year rankX
    list year rankX product_hs92_code hs_label export_value, sepby(year) noobs
    export delimited using "outputs/tables/top10_exports_by_year.csv", replace
restore

* Imports
preserve
    gsort year -import_value
    by year: gen rankM = _n
    keep if rankM <= 10
    keep year rankM product_hs92_code hs_label import_value
    sort year rankM
    list year rankM product_hs92_code hs_label import_value, sepby(year) noobs
    export delimited using "outputs/tables/top10_imports_by_year.csv", replace
restore

*======================================================
* PANEL BALANCE & RE-ENTRY SUMMARY
*   - Balanced: code appears in every year of the sample
*   - reenter_any: code disappears and later returns
*======================================================
preserve
    sort product_hs92_code year
    by product_hs92_code year: keep if _n==1

    by product_hs92_code: gen years_present = _N
    by product_hs92_code: gen first_year    = year[1]
    by product_hs92_code: gen last_year     = year[_N]

    bysort product_hs92_code (year): gen gap = year - year[_n-1] if _n>1
    by product_hs92_code: egen reenter_any = max(gap>1)
    drop gap

    levelsof year, local(ALL_YEARS2)
    local T2 = wordcount("`ALL_YEARS2'")
    gen balanced = (years_present == `T2')

    keep product_hs92_code hs_label years_present first_year last_year balanced reenter_any
    by product_hs92_code: keep if _n==1
    gsort balanced reenter_any -years_present
    export delimited using "outputs/tables/panel_balance_by_product.csv", replace

    tab balanced
    count if reenter_any
    di as result "Products that dropped out and returned: " r(N)
restore

*======================================================
* HS CODES IN DATA BUT NOT IN DICTIONARY
*   - Useful data hygiene: any codes we see that
*     the dictionary doesn't define?
*======================================================
preserve
    gen missing_in_dict = missing(hs_label)
    keep if missing_in_dict
    keep product_hs92_code year
    duplicates drop
    sort product_hs92_code
    export delimited using "outputs/tables/hs_codes_missing_in_dictionary.csv", replace
restore


/********************************************************************
  A) 1995 Focus:
     - Do all dictionary HS codes appear in 1995?
     - Which appear only after 1995? Which never appear?
     - Top/Bottom 5 by PCI in 1995, plus PCI plots.
********************************************************************/
global Y 1995    // change this if you want to pivot to another year

* Make a persistent dictionary .dta once (faster on re-runs)
frame change dict
keep hs_code hs_label
duplicates drop
save "hs92_dict_tmp.dta", replace
frame change default

* Ensure we have a labeled panel cached (panel_labeled_tmp.dta)
capture confirm file "panel_labeled_tmp.dta"
if _rc {
    import delimited using "$DAT", varnames(1) stringcols(1) clear
    destring year export_value import_value pci, replace force
    capture confirm variable hs_code
    if _rc gen str hs_code = product_hs92_code
    frlink m:1 hs_code, frame(dict)
    frget  hs_label, from(dict)
    save "panel_labeled_tmp.dta", replace
}

* ---- A.1: which codes appear in Y? ----
use "panel_labeled_tmp.dta", clear
keep if year==${Y}
keep hs_code hs_label
duplicates drop
save "codes_1995_tmp.dta", replace

* ---- A.2: base dictionary with canonical labels ----
use "hs92_dict_tmp.dta", clear
rename hs_label hs_label_dict
save "hs92_dict_tmp.dta", replace

* ---- A.3: merge dict vs 1995 presence ----
use "hs92_dict_tmp.dta", clear
merge 1:1 hs_code using "codes_1995_tmp.dta", keep(master match) keepusing(hs_label) nogen
rename hs_label hs_label_1995
gen present_1995    = !missing(hs_label_1995)
gen missing_in_1995 = (present_1995==0)
save "dict_vs_1995_tmp.dta", replace

* ---- A.4: find first/last year each code is ever seen ----
use "panel_labeled_tmp.dta", clear
keep hs_code year
bysort hs_code year: keep if _n==1
bys hs_code: gen first_year = year[1]
bys hs_code: gen last_year  = year[_N]
keep hs_code first_year last_year
bys hs_code: keep if _n==1
save "span_tmp.dta", replace

* ---- A.5: add spans + flags for "after 1995" and "never" ----
use "dict_vs_1995_tmp.dta", clear
merge 1:1 hs_code using "span_tmp.dta", nogen
gen never_in_panel     = missing(first_year)
gen appears_after_1995 = (missing_in_1995==1 & !missing(first_year) & first_year>${Y})

* ---- A.6: export the audit tables ----
sort missing_in_1995 -appears_after_1995 never_in_panel first_year hs_code
export delimited using "outputs/tables/dict_vs_1995_presence.csv", replace

preserve
    keep if missing_in_1995==1 & appears_after_1995==1
    export delimited using "outputs/tables/codes_missing_1995_appear_later.csv", replace
restore

preserve
    keep if never_in_panel==1
    export delimited using "outputs/tables/codes_never_in_panel.csv", replace
restore

* ---- A.7: print key counts to the console/log ----
quietly count
local N_dict = r(N)
quietly count if present_1995==1
local N_in95 = r(N)
quietly count if missing_in_1995==1 & appears_after_1995==1
local N_after = r(N)
quietly count if never_in_panel==1
local N_never = r(N)
di as res "Dictionary codes total: `N_dict'"
di as res "Present in ${Y}:                    `N_in95'"
di as res "Missing in ${Y} but appear later:   `N_after'"
di as res "Never appear in panel at all:       `N_never'"

/********************************************************************
 Top/Bottom PCI in ${Y} (tables only) + PCI plots from FULL 1995 data
********************************************************************/

* Make sure output folders exist
cap mkdir "outputs"
cap mkdir "outputs/tables"
cap mkdir "outputs/figures"

* --- Top 5 (highest PCI) — tables only, does NOT alter main data ---
preserve
    use "panel_labeled_tmp.dta", clear
    keep if year==${Y}
    keep hs_code hs_label pci export_value import_value
    drop if missing(pci)

    gsort -pci
    gen rank = _n
    keep if _n<=5
    order rank hs_code hs_label pci export_value import_value
    export delimited using "outputs/tables/top5_pci_${Y}.csv", replace

    * Save a tiny helper file for the combined top/bottom table
    keep hs_code hs_label pci
    gen group = "Top 5 (highest PCI)"
    save "top5_pci_${Y}_tmp.dta", replace
restore

* --- Bottom 5 (lowest PCI) — tables only, does NOT alter main data ---
preserve
    use "panel_labeled_tmp.dta", clear
    keep if year==${Y}
    keep hs_code hs_label pci export_value import_value
    drop if missing(pci)

    gsort pci
    gen rank = _n
    keep if _n<=5
    order rank hs_code hs_label pci export_value import_value
    export delimited using "outputs/tables/bottom5_pci_${Y}.csv", replace

    * Save a tiny helper file for the combined top/bottom table
    keep hs_code hs_label pci
    gen group = "Bottom 5 (lowest PCI)"
    save "bottom5_pci_${Y}_tmp.dta", replace
restore

* --- Combined top & bottom table (optional convenience table) ---
preserve
    use "top5_pci_${Y}_tmp.dta", clear
    append using "bottom5_pci_${Y}_tmp.dta"
    order group hs_code hs_label pci
    export delimited using "outputs/tables/top_and_bottom5_pci_${Y}.csv", replace
restore

* --- PLOTS: use the FULL 1995 PCI population (not top/bottom) ---
use "panel_labeled_tmp.dta", clear
keep if year==${Y}
drop if missing(pci)

* (1) Histogram with normal overlay — all 1995 PCI values
histogram pci, bin(40) normal ///
    title("PCI distribution in ${Y} (all products)") ///
    xtitle("Product Complexity Index (PCI)") ///
    ytitle("Frequency")
graph export "outputs/figures/pci_hist_${Y}.png", width(2000) replace

* (2) Kernel density — all 1995 PCI values
twoway kdensity pci, ///
    title("PCI density in ${Y} (all products)") ///
    xtitle("Product Complexity Index (PCI)") ///
    ytitle("Density")
graph export "outputs/figures/pci_kdensity_${Y}.png", width(2000) replace

/********************************************************************
  B) Final 1995 HS4 → SIC87DD file (with weights & industry names)
      (Option 1 fix: make a unique HS4 list from 1995, then filter
       Dorn's HS6→SIC crosswalk to just those HS4s.)

  Inputs expected (local or pulled from GitHub if missing):
    - data/raw/cw_hs6_sic87dd.dta
    - data/raw/1997_NAICS_to_1987_SIC.xls

  Outputs:
    - data/clean/hs4_to_sic_allocation_1995.dta
    - outputs/tables/hs4_to_sic_allocation_1995.csv
********************************************************************/

cap mkdir "data"
cap mkdir "data/raw"
cap mkdir "data/clean"
cap mkdir "outputs"
cap mkdir "outputs/tables"

* ---------- B.0: fetch inputs if missing ----------
capture confirm file "data/raw/cw_hs6_sic87dd.dta"
if _rc {
    di as txt "Downloading Dorn crosswalk …"
    copy "https://raw.githubusercontent.com/sruthivish/Product-Complexity-Research---Purdue-University/main/data/raw/cw_hs6_sic87dd.dta" ///
        "data/raw/cw_hs6_sic87dd.dta", replace
}

capture confirm file "data/raw/1997_NAICS_to_1987_SIC.xls"
if _rc {
    di as txt "Downloading 1997 NAICS → 1987 SIC names …"
    copy "https://raw.githubusercontent.com/sruthivish/Product-Complexity-Research---Purdue-University/main/data/raw/1997_NAICS_to_1987_SIC.xls" ///
        "data/raw/1997_NAICS_to_1987_SIC.xls", replace
}

* ---------- B.1: make a clean 1995 HS4 slice from your panel ----------
capture confirm file "panel_labeled_tmp.dta"
if _rc {
    import delimited using "$DAT", varnames(1) stringcols(1) clear
    destring year export_value import_value pci, replace force
    capture confirm variable hs_code
    if _rc gen str hs_code = product_hs92_code
    frlink m:1 hs_code, frame(dict)
    frget  hs_label, from(dict)
    save "panel_labeled_tmp.dta", replace
}

use "panel_labeled_tmp.dta", clear
keep if year==${Y}
capture confirm variable hs_code
if _rc gen str hs_code = product_hs92_code
gen str4 hs4 = hs_code
keep hs4 hs_label pci export_value
bys hs4: keep if _n==1
rename pci          pci_1995
rename export_value export_value_1995
save "data/clean/slice_1995_hs4.dta", replace

* ---------- B.1a (Option 1): build a unique HS4 list from 1995 ----------
use "data/clean/slice_1995_hs4.dta", clear
keep hs4
drop if missing(hs4)
duplicates drop
sort hs4
save "data/clean/hs4_1995_list.dta", replace

* ---------- B.2: aggregate Dorn HS6→SIC to HS4→SIC shares ----------
use "data/raw/cw_hs6_sic87dd.dta", clear

* Normalize likely variable names from Dorn file
capture confirm variable hs6
if _rc { 
    capture confirm variable HS6
    if !_rc rename HS6 hs6
}
capture confirm variable sic87dd
if _rc { 
    capture confirm variable SIC4
    if !_rc rename SIC4 sic87dd 
}
* dd- david dorns adjustment, see file c2 on website - convert SIC4 into SIC87dd
capture confirm variable share
if _rc { 
    capture confirm variable weight
    if !_rc rename weight share
}
capture confirm variable share
if _rc { 
    capture confirm variable w
    if !_rc rename w share
}

tostring hs6, replace force
tostring sic87dd, replace force
destring share, replace force
replace hs6 = trim(hs6)
drop if missing(hs6) | length(hs6)!=6

* Derive HS4 parent from HS6 (once)
gen str4 hs4 = substr(hs6,1,4)

*------------------------------------------------------------------
* Convert SIC4 → SIC87dd using David Dorn's aggregation rules
* (only if the file does NOT already provide sic87dd)
*------------------------------------------------------------------
capture confirm variable sic87dd
if _rc {
    * We need a 4-digit SIC input called `sic87` to start from.
    * Try to source it from common variants.
    capture confirm variable sic87
    if _rc {
        capture confirm variable sic4
        if !_rc gen long sic87 = real(sic4)
        if _rc {
            capture confirm variable SIC4
            if !_rc gen long sic87 = real(SIC4)
        }
    }

    * If we still don't have a base SIC variable, stop with a clear error.
    capture confirm variable sic87
    if _rc {
        di as err "No 4-digit SIC field found to convert to SIC87dd. Expected one of: sic87, sic4, SIC4."
        exit 459
    }

    * Create sic87dd from sic87 and apply Dorn's merges
    gen long sic87dd = sic87

    *******************************************************************
    * SIC87dd Codes  — David Dorn's consolidation
    *******************************************************************
    replace sic87dd=2011 if sic87dd==2013
    replace sic87dd=2099 if sic87dd==2038
    replace sic87dd=2051 if sic87dd==2052
    replace sic87dd=2051 if sic87dd==2053
    replace sic87dd=2062 if sic87dd==2061
    replace sic87dd=2062 if sic87dd==2063
    replace sic87dd= 912 if sic87dd==2092
    replace sic87dd=2252 if sic87dd==2251
    replace sic87dd=2341 if sic87dd==2254
    replace sic87dd=2392 if sic87dd==2259

    replace sic87dd=2211 if sic87dd==2261
    replace sic87dd=2221 if sic87dd==2262
    replace sic87dd=2824 if sic87dd==2282
    replace sic87dd=2325 if sic87dd==2326
    replace sic87dd=2331 if sic87dd==2361
    replace sic87dd=2389 if sic87dd==2387
    replace sic87dd=2395 if sic87dd==2397
    replace sic87dd=2449 if sic87dd==2441
    replace sic87dd=2599 if sic87dd==2511
    replace sic87dd=2599 if sic87dd==2512

    replace sic87dd=2599 if sic87dd==2519
    replace sic87dd=2599 if sic87dd==2521
    replace sic87dd=2599 if sic87dd==2531
    replace sic87dd=2599 if sic87dd==2541
    replace sic87dd=2621 if sic87dd==2631
    replace sic87dd=2621 if sic87dd==2671
    replace sic87dd=2752 if sic87dd==2754
    replace sic87dd=2752 if sic87dd==2759
    replace sic87dd=2874 if sic87dd==2875
    replace sic87dd=3069 if sic87dd==3061

    replace sic87dd=3089 if sic87dd==3086
    replace sic87dd=3089 if sic87dd==3087
    replace sic87dd=3312 if sic87dd==3316
    replace sic87dd=3312 if sic87dd==3317
    replace sic87dd=3321 if sic87dd==3322
    replace sic87dd=3321 if sic87dd==3324
    replace sic87dd=3321 if sic87dd==3325
    replace sic87dd=3357 if sic87dd==3355
    replace sic87dd=3365 if sic87dd==3363
    replace sic87dd=3499 if sic87dd==3364

    replace sic87dd=3499 if sic87dd==3366
    replace sic87dd=3499 if sic87dd==3369
    replace sic87dd=3499 if sic87dd==3451
    replace sic87dd=3499 if sic87dd==3463
    replace sic87dd=3482 if sic87dd==3483
    replace sic87dd=3496 if sic87dd==3495
    replace sic87dd=3494 if sic87dd==3498
    replace sic87dd=3577 if sic87dd==3575
    replace sic87dd=3714 if sic87dd==3592
    replace sic87dd=3648 if sic87dd==3645

    replace sic87dd=3648 if sic87dd==3646
    replace sic87dd=3711 if sic87dd==3716
    replace sic87dd=3728 if sic87dd==3769

    * Step 1b: additional hand matches
    replace sic87dd=2221 if sic87dd==2269
    replace sic87dd=2731 if sic87dd==2732
    replace sic87dd=2782 if sic87dd==2789
    replace sic87dd=2796 if sic87dd==2791
    replace sic87dd=3399 if sic87dd==3398
    replace sic87dd=3944 if sic87dd==3942
    replace sic87dd=3999 if sic87dd==3995
    replace sic87dd=3499 if sic87dd==3471
    replace sic87dd=3499 if sic87dd==3479

    * (Optional) Keep only manufacturing
    * keep if sic87dd>=2011 & sic87dd<=3999
}

* Keep only HS4 that actually appear in the 1995 panel (Option 1 fix)
merge m:1 hs4 using "data/clean/hs4_1995_list.dta", keep(3) nogen

* Aggregate HS6→SIC to HS4→SIC and renormalize within HS4
collapse (sum) share, by(hs4 sic87dd)
bys hs4: egen _sumshare = total(share)
gen share4 = share/_sumshare
drop share _sumshare
rename sic87dd sic4
order hs4 sic4 share4
save "data/clean/hs4_sic_share_agg.dta", replace

* ---------- B.3: pull SIC industry names from the Excel ----------
import excel using "data/raw/1997_NAICS_to_1987_SIC.xls", firstrow clear

* Try to detect a SIC code and a title/description column
* (Add/adjust renames below if your sheet uses different headers.)
capture confirm variable SIC
if _rc { 
    capture confirm variable "1987_SIC"
    if !_rc rename "1987_SIC" SIC
}
capture confirm variable SICCode
if !_rc rename SICCode SIC

* Title/description column variants
capture confirm variable SICDescription
if _rc {
    capture confirm variable "SIC_Title"
    if !_rc rename "SIC_Title" SICDescription
}
capture confirm variable "SIC Description"
if !_rc rename "SIC Description" SICDescription
capture confirm variable "SIC Title"
if !_rc rename "SIC Title" SICDescription

* Build a unique SIC4 → title map
tostring SIC, replace force
gen str4 sic4 = substr(trim(SIC),1,4)
capture confirm variable SICDescription
if _rc gen SICDescription = ""
keep sic4 SICDescription
drop if missing(sic4)
duplicates drop
rename SICDescription sic_title
save "data/clean/sic4_titles.dta", replace

* ---------- B.4: build final 1995 file ----------
use "data/clean/slice_1995_hs4.dta", clear
joinby hs4 using "data/clean/hs4_sic_share_agg.dta", unmatched(none)
* some unmatched ones should go with dd cleanup

* Attach industry titles (simple merge, avoids frame issues)
merge m:1 sic4 using "data/clean/sic4_titles.dta"
* remove nogen to get merge variable, study where what comes from
* drop whats in dictionary but not in our data
* see if anything in our data doesnt have labels

* --- show output / quick diagnostics ---
label define _m 1 "data only (no title)" 2 "title only (no data)" 3 "matched", replace
label values _merge _m
tab _merge, missing

quietly count if _merge==1
di as txt "Rows in your data without a SIC title (need attention): " as res r(N)
quietly count if _merge==2
di as txt "Titles present in dictionary but NOT in your data (to drop): " as res r(N)
quietly count if _merge==3
di as txt "Matched rows kept: " as res r(N)

* Save diagnostics for audit
preserve
    keep if _merge==2
    duplicates drop sic4, force
    export delimited using "outputs/tables/_drop_titles_not_in_data.csv", replace
restore

preserve
    keep if _merge==1
    duplicates drop sic4, force
    export delimited using "outputs/tables/_data_missing_titles.csv", replace
restore

* --- drop any records that are present in the dictionary but not in your data ---
drop if _merge==2   // drop title-only rows

* (Optional) if you want to keep ONLY perfect matches, uncomment the next line:
* drop if _merge!=3

drop _merge

* ================================
* Audit: any records missing labels?
* ================================

* 1) Missing SIC titles in your data
quietly count if missing(sic_title) & !missing(sic4)
di as txt "Records in DATA missing SIC titles: " as res r(N)

* show a small sample in the Results window
list sic4 hs4 hs_label share4 export_value_1995 pci_1995 ///
    if missing(sic_title) & !missing(sic4) in 1/50, noobs abbreviate(24)

* save a full CSV for review
preserve
    keep if missing(sic_title) & !missing(sic4)
    export delimited using "outputs/tables/_data_missing_sic_titles.csv", replace
restore


* 2) Missing HS product labels in your data
quietly count if missing(hs_label) & !missing(hs4)
di as txt "Records in DATA missing HS labels:  " as res r(N)

* show a small sample in the Results window
list hs4 sic4 sic_title share4 export_value_1995 pci_1995 ///
    if missing(hs_label) & !missing(hs4) in 1/50, noobs abbreviate(24)

* save a full CSV for review
preserve
    keep if missing(hs_label) & !missing(hs4)
    export delimited using "outputs/tables/_data_missing_hs_labels.csv", replace
restore


* 3) (Optional) hard assertions to fail fast on missing metadata
*    Uncomment if you want the run to stop when labels are missing.
* assert !missing(sic_title) if !missing(sic4)
* assert !missing(hs_label)  if !missing(hs4)


order hs4 hs_label sic4 sic_title share4 export_value_1995 pci_1995
sort  hs4 sic4

save "data/clean/hs4_to_sic_allocation_1995.dta", replace
export delimited using "outputs/tables/hs4_to_sic_allocation_1995.csv", replace

di as res "✓ Wrote outputs/tables/hs4_to_sic_allocation_1995.csv"

* see command collapse for grouping by sic 
* weight by export value %, calculate mean pci
* each sic - one obs with average complexity of products in industry 

* ==============================================================
* Collapse to SIC-level: export-value-% weighted average PCI (1995)
* Input needed: data/clean/hs4_to_sic_allocation_1995.dta
*   with columns: hs4, sic4, sic_title, share4, export_value_1995, pci_1995
* --------------------------------------------------------------

* If you're continuing in the same session after writing the file, you can skip the 'use' line.
use "data/clean/hs4_to_sic_allocation_1995.dta", clear

* Weight each (hs4,sic4) by its allocated export value:
*   exp_alloc = export_value_1995 × share4
gen double exp_alloc = export_value_1995 * share4 
* drop for final data
* put in labels and put in desc for most and least complex industries

* Contribution to weighted PCI numerator:
gen double pci_exp = pci_1995 * exp_alloc

* --- Pick the top-contributing HS4 (by export allocation) per SIC ---
preserve
    keep sic4 hs4 hs_label exp_alloc
    drop if missing(sic4) | missing(hs4)
    gsort sic4 -exp_alloc
    by sic4: gen byte _rk = _n
    keep if _rk==1
    keep sic4 hs4 hs_label
    rename hs4     top_hs4
    rename hs_label top_hs_label
    save "data/clean/_sic_top_hs_label.dta", replace
restore

* --- Collapse to one row per SIC (weighted PCI) ---
collapse (sum) exp_alloc pci_exp (count) n_products = exp_alloc, by(sic4)

* Weighted mean PCI per SIC
gen double pci_avg_exportweighted_1995 = .
replace pci_avg_exportweighted_1995 = pci_exp/exp_alloc if exp_alloc>0

* Attach the top HS label (instead of sic_title)
merge m:1 sic4 using "data/clean/_sic_top_hs_label.dta", keep(3) nogen

order sic4 top_hs4 top_hs_label pci_avg_exportweighted_1995 exp_alloc n_products
sort  sic4

save "data/clean/sic_pci_1995_exportweighted.dta", replace
export delimited using "outputs/tables/sic_pci_1995_exportweighted.csv", replace

/********************************************************************
  === ALL-YEARS RUNNER (add AFTER the 1995 block) ===================
  Replicates the 1995 functionality for every year in the dataset.
  Outputs are suffixed with _YYYY to avoid overwriting 1995 files.
********************************************************************/

* Ensure we have the labeled panel & dict saved from the earlier block
capture confirm file "panel_labeled_tmp.dta"
if _rc {
    import delimited using "$DAT", varnames(1) stringcols(1) clear
    capture confirm variable year
    if _rc destring year, replace force
    quietly foreach v in export_value import_value pci {
        capture confirm variable `v'
        if !_rc destring `v', replace force
    }
    capture confirm variable hs_code
    if _rc {
        * create from product_hs92_code if needed
        capture confirm variable product_hs92_code
        if !_rc gen str hs_code = product_hs92_code
    }
    * (dict frame already created above)
    frlink m:1 hs_code, frame(dict)
    frget  hs_label, from(dict)
    save "panel_labeled_tmp.dta", replace
}

* ---------- Precompute HS4→SIC shares (no year filter) ----------
capture confirm file "data/clean/hs4_sic_share_agg_all.dta"
if _rc {
    use "data/raw/cw_hs6_sic87dd.dta", clear

    * Normalize likely variable names from Dorn file
    capture confirm variable hs6
    if _rc {
        capture confirm variable HS6
        if !_rc rename HS6 hs6
    }
    capture confirm variable sic87dd
    if _rc {
        capture confirm variable SIC4
        if !_rc rename SIC4 sic87dd
    }
    capture confirm variable share
    if _rc {
        capture confirm variable weight
        if !_rc rename weight share
    }
    capture confirm variable share
    if _rc {
        capture confirm variable w
        if !_rc rename w share
    }

    * ---- Make hs6 a 6-char string with leading zeros preserved ----
    capture confirm string variable hs6
    if _rc==0 {
        replace hs6 = trim(hs6)
    }
    else {
        * numeric -> string with %06.0f to preserve leading zeros
        tostring hs6, gen(hs6_s) format(%06.0f) force
        drop hs6
        rename hs6_s hs6
    }

    * sic87dd should be 4-digit string for robust merging later
    capture confirm string variable sic87dd
    if _rc==0 {
        replace sic87dd = trim(sic87dd)
    }
    else {
        tostring sic87dd, gen(sic87dd_s) force
        drop sic87dd
        rename sic87dd_s sic87dd
    }
    replace sic87dd = substr(sic87dd,1,4)

    capture confirm variable share
    if !_rc destring share, replace force
    drop if missing(hs6) | length(hs6)!=6
    drop if missing(sic87dd)

    gen str4 hs4 = substr(hs6,1,4)

    collapse (sum) share, by(hs4 sic87dd)
    bys hs4: egen _sum = total(share)
    replace share = share / _sum if _sum>0
    drop _sum
    rename share share4
    rename sic87dd sic4
    order hs4 sic4 share4
    save "data/clean/hs4_sic_share_agg_all.dta", replace
}

* ---------- SIC titles dictionary (from Excel), reused for all years ----------
capture confirm file "data/clean/sic4_titles.dta"
if _rc {
    * Try common sheet guesses; fall back to first sheet.
    capture noisily import excel using "data/raw/1997_NAICS_to_1987_SIC.xls", ///
        firstrow clear sheet("1997 NAICS to 1987 SIC")
    if _rc {
        capture noisily import excel using "data/raw/1997_NAICS_to_1987_SIC.xls", ///
            firstrow clear sheet("Sheet1")
        if _rc import excel using "data/raw/1997_NAICS_to_1987_SIC.xls", firstrow clear
    }

    * Find a SIC-like column and a title/description-like column by name pattern
    local sicvar ""
    local titlevar ""
    foreach v of varlist _all {
        local vn : lower name `v'
        if regexm("`vn'","(^|[^a-z])sic($|[^a-z0-9])") | ///
           regexm("`vn'","1987") | regexm("`vn'","siccode") | regexm("`vn'","sic4") {
            local sicvar "`v'"
        }
        if regexm("`vn'","desc|title|name|label") {
            local titlevar "`v'"
        }
    }

    if "`sicvar'"=="" {
        di as err "Could not detect a SIC column in the Excel. Columns found:"
        describe
        exit 111
    }

    tempvar _sicstr _ttlstr
    capture drop sic4 sic_title

    * make sic4
    capture confirm string variable `sicvar'
    if _rc==0 {
        gen strL `_sicstr' = trim(`sicvar')
    }
    else {
        tostring `sicvar', gen(`_sicstr') force
        replace `_sicstr' = trim(`_sicstr')
    }
    gen str4 sic4 = substr(`_sicstr',1,4)

    * title column (optional)
    gen strL sic_title = ""
    if "`titlevar'"!="" {
        capture confirm string variable `titlevar'
        if _rc==0 {
            replace sic_title = trim(`titlevar')
        }
        else {
            tostring `titlevar', gen(`_ttlstr') force
            replace sic_title = trim(`_ttlstr')
        }
    }

    keep sic4 sic_title
    drop if missing(sic4)
    duplicates drop
    save "data/clean/sic4_titles.dta", replace
}

* ---------- Get the list of all years in the data ----------
use "panel_labeled_tmp.dta", clear
quietly levelsof year, local(ALL_YEARS)

* Make sure output folders exist
cap mkdir "outputs/figures/all_years"
cap mkdir "outputs/tables/all_years"

* ---------- Loop across all years and replicate functionality ----------
foreach YY of local ALL_YEARS {

    di as res "==== Processing year `YY' ===="

    * --- Slice for year `YY' (with labels) ---
    preserve
        use "panel_labeled_tmp.dta", clear
        keep if year==`YY'
        capture confirm variable hs_code
        if _rc gen str hs_code = product_hs92_code
        * ensure hs4 is 4-char HS from the left
        gen str4 hs4 = substr(hs_code,1,4)
        keep hs4 hs_label pci export_value import_value
        bys hs4: keep if _n==1
        rename pci          pci_`YY'
        rename export_value export_value_`YY'
        save "data/clean/slice_`YY'_hs4.dta", replace
    restore

    * --- Top 5 / Bottom 5 PCI tables for `YY' ---
    preserve
        use "panel_labeled_tmp.dta", clear
        keep if year==`YY'
        keep hs_code hs_label pci export_value import_value
        drop if missing(pci)
        gsort -pci
        gen rank = _n
        keep if _n<=5
        order rank hs_code hs_label pci export_value import_value
        export delimited using "outputs/tables/all_years/top5_pci_`YY'.csv", replace
    restore

    preserve
        use "panel_labeled_tmp.dta", clear
        keep if year==`YY'
        keep hs_code hs_label pci export_value import_value
        drop if missing(pci)
        gsort pci
        gen rank = _n
        keep if _n<=5
        order rank hs_code hs_label pci export_value import_value
        export delimited using "outputs/tables/all_years/bottom5_pci_`YY'.csv", replace
    restore

    * --- PCI plots for `YY' (hist & density) ---
    preserve
        use "panel_labeled_tmp.dta", clear
        keep if year==`YY'
        drop if missing(pci)
        histogram pci, bin(40) normal ///
            title("PCI distribution in `YY' (all products)") ///
            xtitle("Product Complexity Index (PCI)") ytitle("Frequency")
        graph export "outputs/figures/all_years/pci_hist_`YY'.png", width(2000) replace

        twoway kdensity pci, ///
            title("PCI density in `YY' (all products)") ///
            xtitle("Product Complexity Index (PCI)") ytitle("Density")
        graph export "outputs/figures/all_years/pci_kdensity_`YY'.png", width(2000) replace
    restore

    * --- Build HS4→SIC allocation for `YY' (using global shares) ---
    use "data/clean/slice_`YY'_hs4.dta", clear
    keep hs4
    drop if missing(hs4)
    duplicates drop
    sort hs4
    tempfile hs4list
    save `hs4list'

    use "data/clean/hs4_sic_share_agg_all.dta", clear
    merge m:1 hs4 using `hs4list', keep(3) nogen     // keep only HS4 present in `YY'

    * Attach SIC titles
    merge m:1 sic4 using "data/clean/sic4_titles.dta", keep(1 3) nogen

    * Bring back exports & PCI for `YY'
    merge m:1 hs4 using "data/clean/slice_`YY'_hs4.dta", keep(3) nogen

    order hs4 hs_label sic4 sic_title share4 export_value_`YY' pci_`YY'
    sort  hs4 sic4

    save "data/clean/hs4_to_sic_allocation_`YY'.dta", replace
    export delimited using "outputs/tables/all_years/hs4_to_sic_allocation_`YY'.csv", replace

    * --- Collapse to SIC-level export-weighted PCI for `YY' ---
    use "data/clean/hs4_to_sic_allocation_`YY'.dta", clear
    gen double exp_alloc = export_value_`YY' * share4
    gen double pci_exp   = pci_`YY' * exp_alloc

    * Top contributing HS4 per SIC (for context column)
    preserve
        keep sic4 hs4 hs_label exp_alloc
        drop if missing(sic4) | missing(hs4)
        gsort sic4 -exp_alloc
        by sic4: gen byte _rk = _n
        keep if _rk==1
        keep sic4 hs4 hs_label
        rename hs4      top_hs4
        rename hs_label top_hs_label
        tempfile topmap
        save `topmap'
    restore

    collapse (sum) exp_alloc pci_exp (count) n_products = exp_alloc, by(sic4)
    gen double pci_avg_exportweighted_`YY' = .
    replace pci_avg_exportweighted_`YY' = pci_exp/exp_alloc if exp_alloc>0

    merge m:1 sic4 using `topmap', keep(1 3) nogen

    order sic4 top_hs4 top_hs_label pci_avg_exportweighted_`YY' exp_alloc n_products
    sort  sic4
    save "data/clean/sic_pci_`YY'_exportweighted.dta", replace
    export delimited using "outputs/tables/all_years/sic_pci_`YY'_exportweighted.csv", replace
}

di as result "== All-years replication finished successfully =="

/********************************************************************
  === AGGREGATES (robust: rebuild ALL_YEARS if missing) ============
********************************************************************/

cap mkdir "outputs/figures/aggregates"

* If ALL_YEARS is empty or out of scope, rebuild it from the panel
capture confirm local ALL_YEARS
if _rc | "`ALL_YEARS'"=="" {
    use "panel_labeled_tmp.dta", clear
    quietly levelsof year, local(ALL_YEARS)
}

*---------------------------
* 1) Build HS4 panel (all years)
*---------------------------
tempfile hs4_all
clear
set obs 0
gen int year = .
gen str4 hs4 = ""
gen strL hs_label = ""
gen double pci = .
gen double export_value = .
save `hs4_all', replace

foreach YY of local ALL_YEARS {
    capture confirm file "data/clean/slice_`YY'_hs4.dta"
    if _rc continue

    use "data/clean/slice_`YY'_hs4.dta", clear
    * slice contains: hs4 hs_label pci_`YY' export_value_`YY'
    capture confirm variable pci_`YY'
    if _rc continue
    capture confirm variable export_value_`YY'
    if _rc continue

    rename pci_`YY'          pci
    rename export_value_`YY' export_value
    capture confirm variable hs4
    if _rc gen str4 hs4 = substr(hs_code,1,4)
    capture confirm variable hs_label
    if _rc gen strL hs_label = ""

    gen int year = `YY'
    order year hs4 hs_label pci export_value
    append using `hs4_all'
    save `hs4_all', replace
}

* Bail out cleanly if nothing was accumulated
use `hs4_all', clear
count
if r(N)==0 {
    di as error "Aggregates: no HS4-year rows were assembled; skipping figures."
    exit
}

drop if missing(year) | missing(pci)

*---------------------------
* 1A) Economy-wide PCI trend: unweighted vs export-weighted
*---------------------------
preserve
    collapse (mean) mean_pci = pci ///
             (p50) med_pci  = pci ///
             (p10) p10_pci  = pci ///
             (p90) p90_pci  = pci, by(year)
    tempfile stats_unw
    save `stats_unw'
restore

preserve
    gen double w     = export_value
    gen double w_pci = pci * w
    collapse (sum) w_pci w, by(year)
    gen double mean_pci_w = .
    replace mean_pci_w = w_pci / w if w>0
    keep year mean_pci_w
    tempfile stats_w
    save `stats_w'
restore

use `stats_unw', clear
merge 1:1 year using `stats_w', nogen

twoway ///
 (rarea p10_pci p90_pci year, fintensity(20) lcolor(%0)) ///
 (line med_pci year, lpattern(dash) lwidth(medthick)) ///
 (line mean_pci year, lwidth(medthick)) ///
 (line mean_pci_w year, lwidth(thick)), ///
    legend(order(2 "Median (unw.)" 3 "Mean (unw.)" 4 "Mean (export-weighted)" 1 "P10–P90 range") ///
           pos(6) ring(0) cols(1)) ///
    title("PCI over time — all products") ///
    ytitle("PCI") xtitle("Year")
graph export "outputs/figures/aggregates/pci_trends_all_years.png", width(2400) replace

*---------------------------
* 1B) Distribution envelope only
*---------------------------
use `stats_unw', clear
twoway ///
 (rarea p10_pci p90_pci year, fintensity(25) lcolor(%0)) ///
 (line med_pci year, lpattern(dash) lwidth(medthick)), ///
    legend(order(2 "Median" 1 "P10–P90 range") pos(6) ring(0) cols(1)) ///
    title("PCI distribution envelope — all years") ///
    ytitle("PCI") xtitle("Year")
graph export "outputs/figures/aggregates/pci_envelope_all_years.png", width(2400) replace

*---------------------------
* 2) Build SIC panel from per-year export-weighted files
*---------------------------
tempfile sic_all
clear
set obs 0
gen str4  sic4 = ""
gen str4  top_hs4 = ""
gen strL  top_hs_label = ""
gen double pci_w = .
gen double exp_alloc = .
gen int    year = .
save `sic_all', replace

foreach YY of local ALL_YEARS {
    capture confirm file "data/clean/sic_pci_`YY'_exportweighted.dta"
    if _rc continue

    use "data/clean/sic_pci_`YY'_exportweighted.dta", clear
    capture confirm variable pci_avg_exportweighted_`YY'
    if _rc continue
    rename pci_avg_exportweighted_`YY' pci_w
    gen int year = `YY'
    order year sic4 top_hs4 top_hs_label pci_w exp_alloc n_products
    append using `sic_all'
    save `sic_all', replace
}

use `sic_all', clear
count
if r(N)>0 {
    preserve
        gen double w_pci = pci_w * exp_alloc
        collapse (sum) w_pci exp_alloc, by(year)
        gen double mean_pci_w_from_sic = w_pci/exp_alloc if exp_alloc>0
        twoway line mean_pci_w_from_sic year, ///
            title("Export-weighted PCI (aggregated from SIC)") ///
            ytitle("PCI") xtitle("Year")
        graph export "outputs/figures/aggregates/pci_weighted_from_sic.png", width(2000) replace
    restore

    preserve
    * average export allocation per SIC across years
		bysort sic4: egen double avg_exp = mean(exp_alloc)

    * keep the row with the maximum avg_exp within each SIC
		bysort sic4 (avg_exp): keep if _n==_N

		keep sic4 avg_exp
		gsort -avg_exp          // order by largest overall
		keep in 1/6             // top 6 SICs
		tempfile toptic
		save `toptic'
	restore


    preserve
        merge m:1 sic4 using `toptic', keep(3) nogen
        gen str60 _lbl = "SIC " + sic4 + " – " + substr(top_hs_label,1,40)

        levelsof sic4, local(SICS)
        local pl ""
        foreach s of local SICS {
            local pl `pl' (line pci_w year if sic4=="`s'", lwidth(medthick))
        }

        twoway `pl', ///
			legend(cols(1) pos(6) ring(0) order(-) size(small)) ///
			title("Export-weighted PCI by SIC (top 6 by export share)") ///
			ytitle("PCI") xtitle("Year")

        graph export "outputs/figures/aggregates/sic_top6_pci_over_time.png", width(2400) replace
    restore
}

*------------------------------------------------------
* Done — close log so it's readable in outputs/logs
*------------------------------------------------------
capture log close
di as result "== One-click run finished successfully =="





