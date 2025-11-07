/********************************************************************
  Product Complexity Research — One-Click Runner
  - Auto-fetch data from GitHub (raw) -> local ./data/raw/
  - Set globals $DAT and $HSJ
  - Run full analysis (unchanged), 1995 audits, and PCI plots

  Requirements:
    * Stata 17/18 (18 uses json load; 16/17 use Python fallback)
    * Internet access (for GitHub downloads)
********************************************************************/

version 17
clear all
set more off
set rmsg on

*---------------------------
* 0) Project folders + logging
*---------------------------
cap mkdir "data"
cap mkdir "data/raw"
cap mkdir "data/clean"
cap mkdir "outputs"
cap mkdir "outputs/tables"
cap mkdir "outputs/figures"
cap mkdir "outputs/logs"

capture log close _all
log using "outputs/logs/run.smcl", replace

*---------------------------
* 1) Auto-download from GitHub (raw) — ultra-robust
*---------------------------
global GH_OWNER  "sruthivish"
global GH_REPO   "Product-Complexity-Research---Purdue-University"
global GH_BRANCH "main"
global GH_COMMIT ""              // optional: pin to commit SHA; "" uses branch

local GH_PATHS_CSV  ///
    "data/raw/hs92_product_year_4.csv" ///
    "data/hs92_product_year_4.csv" ///
    "hs92_product_year_4.csv"

local GH_PATHS_JSON ///
    "data/raw/HS92%20codes.json" ///
    "data/HS92%20codes.json"     ///
    "HS92%20codes.json"

cap mkdir "data"
cap mkdir "data/raw"
di as txt "PWD: `c(pwd)'"
ls data/raw

* Build both raw URL formats
program define __mkurls, rclass
    args relpath
    local owner  "$GH_OWNER"
    local repo   "$GH_REPO"
    local branch "$GH_BRANCH"
    local commit "$GH_COMMIT"
    if "`commit'"=="" local ref "`branch'"
    else               local ref "`commit'"

    local u1 "https://raw.githubusercontent.com/`owner'/`repo'/`ref'/`relpath'"
    local u2 "https://github.com/`owner'/`repo'/raw/`ref'/`relpath'"
    return local url1 "`u1'"
    return local url2 "`u2'"
end

* Try to place URL content at outpath using:
*   1) copy raw.githubusercontent.com   2) copy github.com/raw
*   3) import from URL then export      4) shell curl/wget (if installed)
program define __fetch_one, rclass
    args relpath outpath filetype
    local ok = 0

    * 1/2. copy
    __mkurls "`relpath'"
    local u1 `r(url1)'
    local u2 `r(url2)'
    foreach u in "`u1'" "`u2'" {
        quietly cap copy "`u'" "`outpath'", replace
        if _rc==0 {
            quietly cap confirm file "`outpath'"
            if _rc==0 {
                di as txt "Downloaded via copy(): `u'"
                return scalar ok = 1
                return local used "`u'"
                exit
            }
        }
    }

    * 3. import-from-URL then export (CSV only)
    if "`filetype'"=="csv" {
        foreach u in "`u1'" "`u2'" {
            quietly cap import delimited using "`u'", varnames(1) stringcols(1) clear
            if _rc==0 {
                quietly export delimited using "`outpath'", replace
                quietly cap confirm file "`outpath'"
                if _rc==0 {
                    di as txt "Imported from URL and cached: `u'"
                    return scalar ok = 1
                    return local used "`u'"
                    exit
                }
            }
        }
    }

    * 4. shell curl/wget (if present)
    foreach u in "`u1'" "`u2'" {
        quietly which curl
        if _rc==0 {
            shell curl -L -o "`outpath'" "`u'"
        }
        else {
            quietly which wget
            if _rc==0 {
                shell wget -O "`outpath'" "`u'"
            }
        }
        quietly cap confirm file "`outpath'"
        if _rc==0 {
            di as txt "Fetched via shell downloader: `u'"
            return scalar ok = 1
            return local used "`u'"
            exit
        }
    }

    return scalar ok = 0
end

* ----- CSV: pull from GitHub if missing locally -----
cap mkdir "data"
cap mkdir "data/raw"

local LOCAL_CSV "data/raw/hs92_product_year_4.csv"
local got 0

* Candidates (space-separated). Add as many fallbacks as you want:
local GH_PATHS_CSV ///
    "https://raw.githubusercontent.com/sruthivish/Product-Complexity-Research---Purdue-University/main/data/raw/hs92_product_year_4.csv"

* Try each URL until one succeeds
foreach url of local GH_PATHS_CSV {
    di as txt "Attempting: `url'"
    cap copy "`url'" "`LOCAL_CSV'", replace
    if !_rc {
        di as res "✓ Downloaded CSV to `LOCAL_CSV'"
        local got 1
        continue, break
    }
}

if !`got' {
    di as err "Could not fetch the product CSV from GitHub. Check the URL or connectivity."
    di as err "Expected local path: `LOCAL_CSV'"
    exit 601
}

* Point $DAT at the freshly downloaded file
global DAT "`LOCAL_CSV'"


* ----- JSON: pull from GitHub if missing locally -----
cap mkdir "data"
cap mkdir "data/raw"

* Local destination (with the space in the filename)
local LOCAL_JSON "data/raw/HS92 codes.json"
local gotj 0

* One or more candidate URLs (space-separated). Use %20 for the space.
local GH_PATHS_JSON ///
    "https://raw.githubusercontent.com/sruthivish/Product-Complexity-Research---Purdue-University/main/data/raw/HS92%20codes.json"

* Try each URL until one succeeds
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

* Point $HSJ at the downloaded JSON
global HSJ "`LOCAL_JSON'"


* Final listing + globals
ls data/raw
global DAT "`LOCAL_CSV'"
global HSJ "`LOCAL_JSON'"
di as res "==> Using DAT: $DAT"
di as res "==> Using HSJ: $HSJ"

*---------------------------
* 2) Full analysis (your original code)
*---------------------------
import delimited using "$DAT", varnames(1) stringcols(1) clear
describe
order product_hs92_code product_id year export_value import_value pci

destring year export_value import_value pci, replace force
compress

di "== Basic counts =="
count
bysort year: gen _one = 1
tab year
drop _one

sum export_value import_value pci
bysort year: sum export_value import_value pci

quietly levelsof product_hs92_code, local(PRODS)
quietly levelsof year,            local(YEARS)
di "Distinct HS codes: `: word count `PRODS''"
di "Distinct years:    `: word count `YEARS''"

*======================================================
* CHANGE DIAGNOSTICS BY PRODUCT
*======================================================
bysort product_hs92_code: egen pci_sd = sd(pci)
gen pci_changed = (pci_sd > 0 & !missing(pci_sd))

bysort product_hs92_code: egen x_sd  = sd(export_value)
bysort product_hs92_code: egen m_sd  = sd(import_value)
gen values_changed = ((x_sd>0 & !missing(x_sd)) | (m_sd>0 & !missing(m_sd)))

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
*======================================================
capture frame drop dict
frame create dict

cap which json
if _rc==0 {
    * ---- Stata 18+ json path ----
    frame change dict
    clear
    json load results using "$HSJ", noresidual
    keep id text
    rename (id text) (hs_code hs_label)
    duplicates drop
}
else {
    * ---- Python fallback (Stata 16/17) ----
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

* Link dictionary to the main data (still in default frame)
frame change default
gen str hs_code = product_hs92_code
frlink m:1 hs_code, frame(dict)
frget  hs_label, from(dict)

*======================================================
* COMBINE EVERYTHING INTO ONE TABLE (changed products)
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

    * compact counts (Stata 17+ table syntax)
    table (pci_changed values_changed), statistic(frequency) ///
        nformat(%9.0g) name(chg)
    collect export "outputs/tables/products_changed_counts.xlsx", replace
restore

*======================================================
* BIGGEST EXPORTS / IMPORTS OVER TIME (WITH DEFINITIONS)
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
* PANEL BALANCE & RE-ENTRY (export summary table)
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
  A) Do all HS codes in the JSON appear in 1995?
     Which only show up later? Which never show up?
********************************************************************/
global Y 1995

* Build persistent dict dataset (in case this run is first)
frame change dict
keep hs_code hs_label
duplicates drop
save "hs92_dict_tmp.dta", replace
frame change default

* Build/rebuild labeled panel if needed
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

* A.1 Codes in 1995
use "panel_labeled_tmp.dta", clear
keep if year==${Y}
keep hs_code hs_label
duplicates drop
save "codes_1995_tmp.dta", replace

* A.2 Dictionary base
use "hs92_dict_tmp.dta", clear
rename hs_label hs_label_dict
save "hs92_dict_tmp.dta", replace

* A.3 Merge dict vs 1995 presence
use "hs92_dict_tmp.dta", clear
merge 1:1 hs_code using "codes_1995_tmp.dta", keep(master match) keepusing(hs_label) nogen
rename hs_label hs_label_1995
gen present_1995    = !missing(hs_label_1995)
gen missing_in_1995 = (present_1995==0)
save "dict_vs_1995_tmp.dta", replace

* A.4 First/last year seen anywhere
use "panel_labeled_tmp.dta", clear
keep hs_code year
bysort hs_code year: keep if _n==1
bys hs_code: gen first_year = year[1]
bys hs_code: gen last_year  = year[_N]
keep hs_code first_year last_year
bys hs_code: keep if _n==1
save "span_tmp.dta", replace

* A.5 Bring spans back + flags
use "dict_vs_1995_tmp.dta", clear
merge 1:1 hs_code using "span_tmp.dta", nogen
gen never_in_panel     = missing(first_year)
gen appears_after_1995 = (missing_in_1995==1 & !missing(first_year) & first_year>${Y})

* A.6 Exports
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

* A.7 Console counts
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

* Top/Bottom PCI in ${Y} + PCI graphs
use "panel_labeled_tmp.dta", clear
keep if year==${Y}
keep hs_code hs_label pci export_value import_value
drop if missing(pci)

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

use "top5_pci_${Y}_tmp.dta", clear
append using "bottom5_pci_${Y}_tmp.dta"
order group hs_code hs_label pci
export delimited using "outputs/tables/top_and_bottom5_pci_${Y}.csv", replace

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

* Done
log close
di as result "== One-click run finished successfully =="
