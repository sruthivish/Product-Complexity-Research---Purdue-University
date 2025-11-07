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

## 🗂 Suggested Repository Layout

