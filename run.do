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

* ---- Top/Bottom 5 by PCI in ${Y} + plots ----
use "panel_labeled_tmp.dta", clear
keep if year==${Y}
keep hs_code hs_label pci export_value import_value
drop if missing(pci)

* Top-5 (highest PCI)
preserve
    gsort -pci
    gen rank = _n
    keep if _n<=5
    order rank hs_code hs_label pci export_value import_value
    export delimited using "outputs/tables/top5_pci_${Y}.csv", replace
    keep hs_code hs_label pci
    gen group = "Top 5 (highest PCI)"
    save "top5_pci_${Y}_tmp.dta", replace
restore

* Bottom-5 (lowest PCI)
preserve
    gsort pci
    gen rank = _n
    keep if _n<=5
    order rank hs_code hs_label pci export_value import_value
    export delimited using "outputs/tables/bottom5_pci_${Y}.csv", replace
    keep hs_code hs_label pci
    gen group = "Bottom 5 (lowest PCI)"
    save "bottom5_pci_${Y}_tmp.dta", replace
restore

* Combine the two lists (handy for a single view)
use "top5_pci_${Y}_tmp.dta", clear
append using "bottom5_pci_${Y}_tmp.dta"
order group hs_code hs_label pci
export delimited using "outputs/tables/top_and_bottom5_pci_${Y}.csv", replace

* PCI distribution visuals (PNG in outputs/figures)
histogram pci, bin(40) normal ///
    title("PCI distribution in ${Y}") ///
    xtitle("Product Complexity Index (PCI)") ///
    ytitle("Frequency")
graph export "outputs/figures/pci_hist_${Y}.png", width(2000) replace

twoway kdensity pci, ///
    title("PCI density in ${Y}") ///
    xtitle("Product Complexity Index (PCI)") ///
    ytitle("Density")
graph export "outputs/figures/pci_kdensity_${Y}.png", width(2000) replace

*------------------------------------------------------
* Done — close log so it's readable in outputs/logs
*------------------------------------------------------
log close
di as result "== One-click run finished successfully =="
