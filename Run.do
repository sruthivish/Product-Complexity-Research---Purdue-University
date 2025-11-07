/****************************************************************************************
 Project:   Product Complexity & U.S. Trade — Stata analysis
 Purpose:   1) Load product-year trade data and compute descriptive + change diagnostics
            2) Build/attach an HS92 "dictionary" (code → text label)
            3) Produce "changed over time" tables and top-10 import/export rankings
            4) Audit panel balance (do codes drop out and re-enter?)
            5) Cross-check dictionary vs. data in a given focal year (default: 1995)
            6) Output top/bottom PCI lists and PCI distribution plots for that year

 Inputs:    - $DAT : CSV of product-year trade (HS92 4-digit), columns:
                        product_hs92_code, product_id, year, export_value, import_value, pci
            - $HSJ : JSON of HS92 code definitions (id/text pairs)
 Outputs:   CSV/XLSX tables in working directory and ./outputs/… (created if missing)

 Notes:     * Uses Stata "frames" to keep a separate dictionary dataset resident in memory.
           * Uses python fallback to read JSON if Stata's json command is unavailable.
           * Edit global Y below to change the focal year for the A-block audit/plots.
****************************************************************************************/

*-------------------------------------------------------------------------------
* USER PATHS (edit for your machine OR set by an earlier automation step)
*-------------------------------------------------------------------------------
global DAT "/Users/sruthivisvanathan/Downloads/hs92_product_year_4.csv"
global HSJ "/Users/sruthivisvanathan/Downloads/HS92 codes.json"

clear all
set more off   // run to completion without pausing

*===============================================================================
* 1) LOAD DATA + BASIC SUMMARIES
*    - Read the product-year panel
*    - Make sure numeric fields are numeric
*    - Basic frequency and summary statistics
*===============================================================================
import delimited using "$DAT", varnames(1) stringcols(1) clear
describe

* Keep a familiar column order to ease reading of browse/list output
order product_hs92_code product_id year export_value import_value pci

* Ensure types are numeric (if CSV read them as text); force=TRUE coerces quietly
destring year export_value import_value pci, replace force
compress   // reduce memory footprint

di "== Basic counts =="
count

* Frequency of years observed in the data
bysort year: gen _one = 1
tab year
drop _one

* Overall and by-year summaries of values and PCI
sum export_value import_value pci
bysort year: sum export_value import_value pci

* Distinct counts for quick shape sanity check
quietly levelsof product_hs92_code, local(PRODS)
quietly levelsof year,            local(YEARS)
di "Distinct HS codes: `: word count `PRODS''"
di "Distinct years:    `: word count `YEARS''"

*===============================================================================
* 2) CHANGE DIAGNOSTICS BY PRODUCT
*    - For each HS code, compute SD over time of PCI and values
*    - Mark whether PCI/values changed (SD>0)
*    - Build a small per-product "years_info.dta" with span and re-entry flag
*===============================================================================
bysort product_hs92_code: egen pci_sd = sd(pci)
gen pci_changed = (pci_sd > 0 & !missing(pci_sd))

bysort product_hs92_code: egen x_sd  = sd(export_value)
bysort product_hs92_code: egen m_sd  = sd(import_value)
gen values_changed = ((x_sd>0 & !missing(x_sd)) | (m_sd>0 & !missing(m_sd)))

preserve
    * Work at (product,year) grain; one line per year per product
    sort product_hs92_code year
    by product_hs92_code year: keep if _n==1

    * Span and re-entry diagnostics:
    by product_hs92_code: gen years_present = _N
    by product_hs92_code: gen first_year    = year[1]
    by product_hs92_code: gen last_year     = year[_N]

    * gap>1 means a missing year between consecutive appearances (dropout/return)
    bysort product_hs92_code (year): gen gap = year - year[_n-1] if _n>1
    by product_hs92_code: egen reenter_any = max(gap>1)

    keep product_hs92_code years_present first_year last_year reenter_any
    by product_hs92_code: keep if _n==1
    save "years_info.dta", replace
restore

*===============================================================================
* 3) BUILD HS92 DICTIONARY IN A SEPARATE FRAME + MERGE INTO MAIN
*    - Frame "dict" holds the HS code → label mapping
*    - Prefer Stata's json command when available; otherwise use python fallback
*    - After dict exists, bring labels into the main frame (default)
*===============================================================================
capture frame drop dict
frame create dict

cap which json
if _rc==0 {
    * -------- Stata 18+ path: read JSON directly into frame:dict --------
    frame change dict
    clear
    json load results using "$HSJ", noresidual   // expect fields id and text
    keep id text
    rename (id text) (hs_code hs_label)
    duplicates drop
}
else {
    * -------- Python fallback for Stata 16/17 (no json command) ----------
    python clear
    python:
import json, csv
from sfi import Macro
p = Macro.getGlobal("HSJ")                   # path passed from Stata global
with open(p, "r", encoding="utf-8") as f:
    J = json.load(f)
rows = []
for r in J.get("results", []):               # json structure: results:[{id,text},...]
    code = r.get("id"); text = r.get("text")
    if code and text:
        rows.append((str(code), str(text)))
with open("hs92_dict_tmp.csv","w",newline="",encoding="utf-8") as g:
    w = csv.writer(g)
    w.writerow(["hs_code","hs_label"])
    w.writerows(rows)
end
    frame change dict
    clear
    import delimited using "hs92_dict_tmp.csv", varnames(1) clear
    erase "hs92_dict_tmp.csv"
    duplicates drop
}

* Bring the labels into the data that is still in the default frame
frame change default
gen str hs_code = product_hs92_code

* frlink creates a linkage variable called 'dict' pointing to matching rows in frame dict
frlink m:1 hs_code, frame(dict)

* frget copies the label column from the linked row(s) in frame dict
frget  hs_label, from(dict)

*===============================================================================
* 4) "CHANGED OVER TIME" TABLE (per product) + EXPORTED COUNTS
*    - Merge with years_info.dta created earlier
*    - Add "balanced" flag: present in all years in the file
*    - Rank by PCI movement size (pci_sd) for a quick top list
*===============================================================================
preserve
    keep product_hs92_code hs_label pci_sd x_sd m_sd pci_changed values_changed
    by product_hs92_code: keep if _n==1

    merge 1:1 product_hs92_code using "years_info.dta", nogen

    * Balanced if present exactly in all sample years
    levelsof year, local(ALL_YEARS)
    local T = wordcount("`ALL_YEARS'")
    gen balanced = (years_present == `T')

    * Preview: biggest PCI movers at the top
    gsort -pci_sd
    gen rank_pci_mover = _n
    list product_hs92_code hs_label pci_sd years_present first_year last_year ///
         reenter_any balanced if _n<=20, noobs abbreviate(24)

    * Full CSV for downstream analysis
    export delimited using "products_changed_over_time.csv", replace

    * Small counts table of "changed/not changed"
    table (pci_changed values_changed), statistic(frequency) ///
        nformat(%9.0g) name(chg)
    collect export "products_changed_counts.xlsx", replace
restore

*===============================================================================
* 5) BIGGEST EXPORTS / IMPORTS OVER TIME (WITH DEFINITIONS)
*    - For each year, rank products by export/import value and keep Top-10
*    - hs_label is already attached from the dictionary
*===============================================================================
* ---- Exports ----
preserve
    gsort year -export_value
    by year: gen rankX = _n
    keep if rankX <= 10
    keep year rankX product_hs92_code hs_label export_value
    sort year rankX
    list year rankX product_hs92_code hs_label export_value, sepby(year) noobs
    export delimited using "top10_exports_by_year.csv", replace
restore

* ---- Imports ----
preserve
    gsort year -import_value
    by year: gen rankM = _n
    keep if rankM <= 10
    keep year rankM product_hs92_code hs_label import_value
    sort year rankM
    list year rankM product_hs92_code hs_label import_value, sepby(year) noobs
    export delimited using "top10_imports_by_year.csv", replace
restore

*===============================================================================
* 6) PANEL BALANCE & RE-ENTRY (per product)
*    - Recompute span and "reenter_any" (gap>1)
*    - Export a compact per-product panel status table
*===============================================================================
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
    export delimited using "panel_balance_by_product.csv", replace

    tab balanced
    count if reenter_any
    di as result "Products that dropped out and returned: " r(N)
restore

*===============================================================================
* 7) HS CODES SEEN IN DATA BUT MISSING FROM DICTIONARY
*    - Quick audit list: which products lack a label (join failure)
*===============================================================================
preserve
    gen missing_in_dict = missing(hs_label)
    keep if missing_in_dict
    keep product_hs92_code year
    duplicates drop
    sort product_hs92_code
    export delimited using "hs_codes_missing_in_dictionary.csv", replace
restore


/********************************************************************************
 A) YEAR-SPECIFIC DICTIONARY vs DATA AUDIT (default: 1995)
    Questions:
      • Do all dictionary HS codes appear in 1995?
      • Which appear later? Which never appear at all?
      • Also produce Top/Bottom-5 PCI lists and PCI plots for that year.
********************************************************************************/

* Choose focal year here once; used everywhere below
global Y 1995

cap mkdir "outputs"
cap mkdir "outputs/tables"

*-- Ensure dictionary frame exists and has hs_code/hs_label
capture frame dir
local frames `r(frames)'
local have_dict = 0
foreach f of local frames {
    if ("`f'"=="dict") local have_dict = 1
}
if !`have_dict' frame create dict

frame change dict

* If the columns are still named id/text (from a previous json load), normalize
capture confirm variable hs_code
if _rc {
    capture confirm variable id
    if !_rc rename id hs_code
    capture confirm variable text
    if !_rc {
        capture confirm variable hs_label
        if _rc rename text hs_label
    }
}

* If we STILL don't have hs_code, rebuild from JSON (Stata json or python fallback)
capture confirm variable hs_code
if _rc {
    clear
    cap which json
    if _rc==0 {
        json load results using "$HSJ", noresidual
        keep id text
        rename (id text) (hs_code hs_label)
    }
    else {
        python clear
        python:
import json, csv
from sfi import Macro
p = Macro.getGlobal("HSJ")
with open(p, "r", encoding="utf-8") as f:
    J = json.load(f)
rows = []
for r in J.get("results", []):
    c = r.get("id"); t = r.get("text")
    if c and t: rows.append((str(c), str(t)))
with open("hs92_dict_tmp.csv","w",newline="",encoding="utf-8") as g:
    w = csv.writer(g); w.writerow(["hs_code","hs_label"]); w.writerows(rows)
end
        import delimited using "hs92_dict_tmp.csv", varnames(1) clear
        erase "hs92_dict_tmp.csv"
    }
}

keep hs_code hs_label
duplicates drop
save "hs92_dict_tmp.dta", replace
frame change default

*-- Build or reuse a labeled panel for fast re-runs
*   (contains hs_code, hs_label, year, pci, etc.)
capture confirm file "panel_labeled_tmp.dta"
if _rc {
    di as txt "panel_labeled_tmp.dta not found → building from $DAT"
    import delimited using "$DAT", varnames(1) stringcols(1) clear
    destring year export_value import_value pci, replace force

    capture confirm variable hs_code
    if _rc gen str hs_code = product_hs92_code

    frlink m:1 hs_code, frame(dict)
    frget  hs_label, from(dict)

    save "panel_labeled_tmp.dta", replace
}
else {
    use "panel_labeled_tmp.dta", clear
    capture confirm variable year
    if _rc {
        di as txt "panel_labeled_tmp.dta missing 'year' → rebuilding from $DAT"
        import delimited using "$DAT", varnames(1) stringcols(1) clear
        destring year export_value import_value pci, replace force
        capture confirm variable hs_code
        if _rc gen str hs_code = product_hs92_code
        frlink m:1 hs_code, frame(dict)
        frget  hs_label, from(dict)
        save "panel_labeled_tmp.dta", replace
    }
}

*---------------- A.1: HS codes present in focal year ----------------
use "panel_labeled_tmp.dta", clear
keep if year==${Y}
keep hs_code hs_label
duplicates drop
save "codes_1995_tmp.dta", replace

*---------------- A.2: Clean dictionary copy for merging ----------------
use "hs92_dict_tmp.dta", clear
rename hs_label hs_label_dict
save "hs92_dict_tmp.dta", replace

*---------------- A.3: Dict vs 1995 merge; presence flags ---------------
use "hs92_dict_tmp.dta", clear
merge 1:1 hs_code using "codes_1995_tmp.dta", ///
    keep(master match) keepusing(hs_label) nogen
rename hs_label hs_label_1995
gen present_1995    = !missing(hs_label_1995)
gen missing_in_1995 = (present_1995==0)
save "dict_vs_1995_tmp.dta", replace

*---------------- A.4: First/last year observed for each code -----------
use "panel_labeled_tmp.dta", clear
keep hs_code year
bysort hs_code year: keep if _n==1
bys hs_code: gen first_year = year[1]
bys hs_code: gen last_year  = year[_N]
keep hs_code first_year last_year
bys hs_code: keep if _n==1
save "span_tmp.dta", replace

*---------------- A.5: Merge span into dict list; compute audit flags ----
use "dict_vs_1995_tmp.dta", clear
merge 1:1 hs_code using "span_tmp.dta", nogen
gen never_in_panel     = missing(first_year)
gen appears_after_1995 = (missing_in_1995==1 & !missing(first_year) & first_year > ${Y})

*---------------- A.6: Export audit tables --------------------------------
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

*---------------- A.7: Console summary counts -----------------------------
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

*---------------- Top/Bottom-5 PCI in ${Y} + PCI plots --------------------
cap mkdir "outputs"
cap mkdir "outputs/tables"
cap mkdir "outputs/figures"

use "panel_labeled_tmp.dta", clear
keep if year==${Y}
keep hs_code hs_label pci export_value import_value
drop if missing(pci)

* Top 5 (highest PCI)
preserve
    gsort -pci
    gen rank = _n
    keep if _n<=5
    order rank hs_code hs_label pci export_value import_value
    list, noobs abbrev(30)
    export delimited using "outputs/tables/top5_pci_${Y}.csv", replace
    keep hs_code hs_label pci
    gen group = "Top 5 (highest PCI)"
    save "top5_pci_${Y}_tmp.dta", replace
restore

* Bottom 5 (lowest PCI)
preserve
    gsort pci
    gen rank = _n
    keep if _n<=5
    order rank hs_code hs_label pci export_value import_value
    list, noobs abbrev(30)
    export delimited using "outputs/tables/bottom5_pci_${Y}.csv", replace
    keep hs_code hs_label pci
    gen group = "Bottom 5 (lowest PCI)"
    save "bottom5_pci_${Y}_tmp.dta", replace
restore

* Combined top & bottom table for convenience
use "top5_pci_${Y}_tmp.dta", clear
append using "bottom5_pci_${Y}_tmp.dta"
order group hs_code hs_label pci
export delimited using "outputs/tables/top_and_bottom5_pci_${Y}.csv", replace

* PCI distribution plots (PNG)
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
