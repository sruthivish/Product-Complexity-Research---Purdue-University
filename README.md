# Product-Complexity-Research---Purdue-University

This repository contains code and data assets for an undergraduate research project exploring how **U.S. trade composition** relates to **employment** through the lens of the **Product Complexity Index (PCI)** from the *Atlas of Economic Complexity*. We map **HS92 4-digit** product codes to human-readable labels and study coverage, dynamics, and outliers over time.

---

## 📦 Data Sources

1. **Product trade panel (HS92, 4-digit)**
   - **Origin:** Harvard Growth Lab, *Atlas of Economic Complexity*
   - **Filters used:**  
     - Data type: **Product trade**  
     - Classification: **HS92**  
     - Product level: **4-digit**
   - **Key fields:** `product_hs92_code`, `product_id`, `year`, `export_value`, `import_value`, `pci`
   - **Expected filename:** `hs92_product_year_4.csv`

2. **HS92 code dictionary (labels/definitions)**
   - **Origin:** United Nations Statistics Division (UNSD) classifications portal  
   - **Shape:** JSON with `results[].id` (HS code) and `results[].text` (label)
   - **Expected filename:** `HS92 codes.json`

> **Notes**
> - *HS92* refers to the 1992 revision of the Harmonized System.  
> - *PCI* is a product-level complexity metric; higher PCI ≈ more knowledge-intensive and less ubiquitous products.

---

## 🎯 Research Aim (current status)

- **Goal:** Assess whether **product complexity** in trade is associated with **economic value and employment** outcomes.
- **Completed so far:**
  - **Ingest & cleaning** of a product-year panel (HS92, 4-digit)
  - **Dictionary merge:** HS codes → human-readable labels (from JSON)
  - **Descriptives:** year counts; summary stats for exports, imports, PCI
  - **Change diagnostics:**
    - Which products’ **PCI** / **trade values** change over time
    - Which HS codes **drop out and return** (re-entry)
    - **Panel balance:** does each HS code appear in all years?
  - **Extremes:** top/bottom PCI products by year (e.g., 1995 snapshot)
  - **Coverage audits:** Do all dictionary HS codes appear in a given year? Which appear **later** or **never**?

---
## 📣 Data Background  
> **Banner:** The information in this section is **sourced from the Harvard Growth Lab (Atlas of Economic Complexity)**.

### Primary inputs used by the Atlas
- **Goods Trade (raw data):** United Nations Statistical Division (**UN Comtrade**)
- **Services Trade (raw data):** International Monetary Fund (**IMF**), Direction of Trade Statistics
- **Economic Indicators:** **IMF**
- **Price Adjustments:** Federal Reserve Economic Data (**FRED**), *Producer Price Index for Industrial Commodities*

**Currency & deflation**
- Atlas trade values are reported in **USD**.  
- “**Constant**” values are produced using the **FRED PPI for Industrial Commodities**.  
- The **base year equals the latest Atlas year**, so reported “constant” values reflect current purchasing power.  
- For historical comparisons (e.g., growth), use **constant-dollar** values.

---

## Classification Systems

### Harmonized System (**HS**)
- Modern classification covering **~5,000 products**
- Data available **from 1995 onward**
- Detail up to **6-digit** product codes
- Best for **contemporary industries/products**

### Standard International Trade Classification (**SITC**)
The Atlas provides a long-horizon, harmonized time series by stitching:
- **SITC Rev. 1:** *1962–1976*
- **SITC Rev. 2:** *1977–1994*
- **HS92 converted to SITC:** *1995 onward*

**Why this matters:** you get a **continuous ~60-year** series with a consistent product taxonomy.

**SITC highlights**
- ~**700 products**
- History back to **1962**
- Detail up to **4-digit** codes
- Ideal for **long-run trend** analysis

---

## Services Data
- Reported **unilaterally** (exports/imports)
- Partners grouped as **“Services Partners”**
- Coverage for **~50–75%** of countries
- Begins **in 1980** (gaps possible due to reporting delays)

---

## Country Coverage (Profiles & Rankings)
While **Atlas Explore** shows all available economies, the **Profiles & Rankings** subset meets:
- **Population ≥ 1M**
- **Average annual trade ≥ \$1B**
- **Verified GDP & exports** available
- **Consistent, reliable** trade reporting record

---

## Data Cleaning Methodology (Atlas pipeline)
Real-world trade reporting is noisy (duplicate/missing/misaligned exporter–importer records). The Atlas applies a three-step process to generate robust bilateral flows:

1. **Value standardization (CIF → FOB):**  
   Import values (CIF) are adjusted to be comparable with exporter values (FOB).

2. **Reliability assessment:**  
   Countries receive **reliability indices** based on the time-series consistency of their reported totals across exporter–importer pairs.

3. **Final value estimation:**  
   Exporter and importer reports are **combined using reliability weights** to produce the best estimate of true flows.

---

## Background: Product Complexity Index (**PCI**)

**Concept.** The **PCI** estimates the knowledge intensity of a product. Intuitively, **complex products** are those exported by **few countries**, and those countries also export **many other (diverse) products**. Conversely, **simple products** are exported by **many countries**—especially by countries with **narrow** export baskets.

**Network view.** Consider the binary country–product incidence matrix \(M_{cp}\) where \(M_{cp}=1\) if country \(c\) has revealed comparative advantage (RCA) in product \(p\), else \(0\).

- **Diversity (country):**  
  \[
  k_{c,0}=\sum_{p} M_{cp}
  \]
- **Ubiquity (product):**  
  \[
  k_{p,0}=\sum_{c} M_{cp}
  \]

The PCI builds on iterative relationships between a product’s **ubiquity** and the **diversity** (and sophistication) of its exporters (the “method of reflections”), then standardizes scores so that PCI has **mean 0** and is **comparable across products**.

**Interpretation.**
- **High PCI (> 0):** knowledge-intensive/complex goods, produced by few, highly diversified economies.  
- **Low PCI (< 0):** less complex goods, produced by many, less diversified economies.

> In this repository, we use **HS92 4-digit** trade data and map in HS definitions to analyze PCI distributions (e.g., top/bottom products by PCI in a given year such as 1995) and assess panel balance across years.

---


