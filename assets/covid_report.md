# Descriptive Data Quality Assessment of COVID‑19 Vaccination Records

## 1. Aim

This descriptive data quality assessment examines COVID‑19 vaccination records on OpenSAFELY at the event level. The aim is to evaluate whether the underlying data contain structural or recording issues by applying predefined flags and visual summaries to identify and quantify anomalies in dates, product, and dose intervals.
The purpose of this work is to assess the quality of the data themselves, rather than to interpret population characteristics, conduct stratified analyses, or evaluate policy effects.
Insights from this assessment will support the wider OVERTURE project in determining how best to process vaccination data, minimise errors, and understand limitations before any downstream analytic or inferential work.

---

## 2. Overview of Data Quality Framework

Four main domains are assessed:

1. Impossible dates  
2. Product–approval mismatches  
3. Multiple vaccinations recorded on the same day  
4. Implausible intervals between consecutive doses

---

## 3. Definitions of Flags

### 3.1 Impossible Dates

#### A. Implausible early date
- **Definition:** `vax_date < 2020‑07‑01`  
- **Interpretation:** Likely erroneous.  
- **Action:** Flag + typically exclude.

#### B. Pre‑rollout date
- **Definition:** `2020‑07‑01 ≤ vax_date < 2020‑12‑08`  
- **Interpretation:** May reflect trial participation or exceptional early use; not automatically invalid.  
- **Action:** Flag + retain.

Eligibility assessment is not applied due to incomplete capture and complex early rollout practices.
Because rollout dates vary by product, product‑approval mismatches are assessed separately.

---

### 3.2 Product–Approval Mismatches

#### A. Unapproved products
- **Definition:** Product name/code not found in approval lookup.  
- **Interpretation:** May indicate overseas vaccination or non‑standard entry.  
- **Action:** Flag + retain.

#### B. Products used before approval
- **Definition:** Vaccination date earlier than product approval date.  
- **Interpretation:** Could be early use or recording error.  
- **Action:** Flag; inclusion/exclusion is study‑dependent.

---

### 3.3 Multiple Vaccinations on the Same Day

#### A. Same‑day same‑product duplicate
- **Definition:** Same patient + same date + same product, multiple entries.  
- **Interpretation:** Highly likely duplicate.  
- **Action:** Retain one; remove duplicates.

#### B. Same‑day mixed‑product records
- **Definition:** Same patient + same date + different products.  
- **Interpretation:** Could represent conflicting entries or corrected-but-not-deleted records.  
- **Action:** Quantify; study‑specific treatment.

Mixed‑product days take precedence: if any mixed‑product combination occurs on a given patient‑date, all records for that day are flagged as mixed‑product.

| code                         | approval date  | Consistent_with_ECHO_Table2   | website |
|--------------------------|---------------|-------------|------------------------------|
| pfizer_original             | 2020‑12‑02  | Yes    | https://www.gov.uk/government/publications/regulatory-approval-of-pfizer-biontech-vaccine-for-covid-19|
| pfizer_BA1                  | 2022‑09‑01| (2022-09-03 in protocol)      | https://mhraproducts4853.blob.core.windows.net/docs/fbb5be47fda87bdd820b91b8725654e272daadf7 |
| pfizer_BA45                 | 2022‑09‑12|(2022-09-01 in protocol)   | <https://assets.publishing.service.gov.uk/media/63a17483e90e075872db815f/Public_Assessment_Report_-_Pfizer_BioNTech_bivalent_vaccine_-_Comirnaty_Original_Omicron_BA_4-5.pdf>|
| pfizer_XBB15                | 2023‑09‑05 | Yes     | https://www.gov.uk/government/news/mhra-approves-pfizerbiontechs-adapted-covid-19-vaccine-comirnaty-that-targets-omicron-xbb15 |
| pfizer_JN1                  | 2024‑07‑24   | Yes   | https://www.gov.uk/government/news/mhra-approves-comirnaty-jn1-covid-19-vaccine-for-adults-and-children-from-infancy |
| pfizer_KP2                  | 2024‑10‑10|(not in protocol)     | https://www.gov.uk/government/news/mhra-approves-comirnaty-kp2-covid-19-vaccine-for-adults |
| pfizer_KP2_pfs              | 2024‑10‑10|(not in protocol)     | https://www.gov.uk/government/news/mhra-approves-comirnaty-kp2-covid-19-vaccine-for-adults |
| pfizer_unspecified          | (*) |(not in protocol) | https://www.ema.europa.eu/en/documents/product-information/comirnaty-epar-product-information_en.pdf |
| pfizer_original_children    | 2021‑12‑22|(not in protocol)     | https://www.news-medical.net/news/20211222/MHRA-approves-new-formulation-of-Pfizer-BioNTech-COVID-19-vaccine-for-5-11-year-olds.aspx |
| pfizer_JN1_children         | 2024‑07‑24|(not in protocol)     | https://www.gov.uk/government/news/mhra-approves-comirnaty-jn1-covid-19-vaccine-for-adults-and-children-from-infancy |
| pfizer_XBB15_children       | 2023‑09‑05|(not in protocol)     | https://www.gov.uk/government/news/mhra-approves-pfizerbiontechs-adapted-covid-19-vaccine-comirnaty-that-targets-omicron-xbb15 |
| pfizer_LP81_children        | (*)|(not in protocol)  | <https://www.medicines.org.uk/emc/files/pil.101151.pdf> This leaflet was last revised in 08/2025.  |
| pfizer_original_under5      | 2022‑12‑06|(not in protocol)     | https://www.gov.uk/government/news/pfizerbiontech-covid-19-vaccine-authorised-for-use-in-infants-and-children-aged-6-months-to-4-years |
| pfizer_JN1_under5           | 2024‑07‑24|(not in protocol)     | https://www.gov.uk/government/news/mhra-approves-comirnaty-jn1-covid-19-vaccine-for-adults-and-children-from-infancy |
| pfizer_XBB15_under5         | 2023‑09‑05|(not in protocol)     | https://www.gov.uk/government/news/mhra-approves-pfizerbiontechs-adapted-covid-19-vaccine-comirnaty-that-targets-omicron-xbb15 |
| pfizer_LP81_under5          | (*)|(not in protocol)  | <https://www.medicines.org.uk/emc/files/pil.101151.pdf> This leaflet was last revised in 08/2025. |
| az_original                 | 2020‑12‑30 | Yes      | https://www.gov.uk/government/publications/regulatory-approval-of-covid-19-vaccine-astrazeneca |
| moderna_original            | 2021‑01‑08  | Yes     | https://www.gov.uk/government/publications/regulatory-approval-of-covid-19-vaccine-moderna |
| moderna_omicron             | 2022‑08‑12|(2022-08-15 in protocol)     | https://assets.publishing.service.gov.uk/media/637e7c638fa8f56eb5b66420/Spikevax_bivalent_PAR.pdf |
| moderna_BA45                | (*)|(2023-02-21in protocol)       | <https://www.nasdaq.com/articles/ema-recommends-authorization-of-modernas-omicron-ba.4-ba.5-targeting-bivalent-covid-19>≈2022‑10 |
| moderna_XBB15               | 2023‑09‑15 | Yes      | https://www.gov.uk/government/news/mhra-approves-modernas-adapted-covid-19-vaccine-spikevax-that-targets-omicron-xbb15 |
| moderna_JN1                 | 2024‑09‑02 | Yes      | https://www.gov.uk/government/news/mhra-approves-spikevax-jn1-covid-19-vaccines-for-adults-and-children-from-infancy |
| moderna_unspecified         | 2021‑01‑08|(not in protocol)      | <https://modernacovid19global.com/assets/n2j6zptc9y3o/4q9CXCUd9RG2Q7IzUUeE6t/34cd8bc1260dab1b6be767fb411d78be/Spikevax__previously_COVID-19_Vaccine_-_SmPC-_Qatar_-_English.pdf> |
| sanofigsk_B1                | 2022‑12‑21  | Yes   | https://www.gov.uk/government/news/sanofi-pasteur-covid-19-vaccine-authorised-by-mhra |
| novavax                     | 2022‑02‑03|(not in protocol)      | https://www.gov.uk/government/news/novavax-covid-19-vaccine-nuvaxovid-approved-by-mhra |
| jansenn                     | 2021‑05‑28|(not in protocol)     | https://www.gov.uk/government/publications/regulatory-approval-of-covid-19-vaccine-janssen |
| valneva                     | 2022‑04‑14|(not in protocol)     | https://www.covidvaccineresearch.org/news/valneva-vaccine-approved-use-uk |
---

### 3.4 Implausible Intervals Between Consecutive Doses

#### Included population
- Records with a previous vaccination date.

#### Exclusions
- Patients with only one vaccination record  
- Same‑day multiple‑record combinations

#### Derived variables
- Previous/current product  
- Previous/current campaign  
- Previous/current vaccination date  
- `interval_days`  
- `interval_bin`

#### Interval bins (days)
- 1–6  
- 7–13  
- 14–29  
- 30–89  
- 90–112  
- 113–179  
- 180+

#### Expected ranges
- Primary within‑campaign: **14–112 days**  
- Booster within‑campaign: **≥90 days**  
- Across‑campaign: **≥90 days**

Although expected ranges are defined, shorter intervals can still be clinically appropriate in specific circumstances, such as for high‑risk individuals, people with reduced immune function, or certain occupational groups where accelerated scheduling may be justified.

For extremely short intervals, records are removed as they are unlikely to represent valid dosing events. For the remaining non‑standard intervals, interpretation should be contextual and assessed case by case.

---

## 4. Overview of All Flag Types

- Implausible early date  
- Pre‑rollout date  
- Unapproved products  
- Products used before approval  
- Same‑day same‑product duplicates  
- Same‑day mixed‑product records  
- Interval bins (1–6 → 180+ days)

---

## 5. Summary Tables

**Note:** The summary tables produced here represent the initial, high‑level version of the data‑quality summaries. Further refinements will be implemented in the R visualisation stage, including grouping vaccine products into broader categories and collapsing certain interval bins into “plausible” vs “implausible” ranges for more interpretable reporting.


### Table 1. Overall Summary of Flagged Issues
| Flag type | n_records | % records | n_patients | % patients |
|-----------|-----------|-----------|------------|------------|
| … | … | … | … | … |

**Purpose:** Shows how common each issue is across the dataset.

---

### Table 2. Campaign‑Specific Summary
| Campaign | Flag type | n_records | % records | n_patients | % patients |
|----------|-----------|-----------|-----------|------------|------------|
| … | … | … | … | … | … |

**Purpose:** Identifies campaigns with concentrated issues.

---

### Table 3. Product‑Specific Summary
| Product | Flag type | n_records | % records | n_patients | % patients |
|---------|-----------|-----------|-----------|------------|------------|
| … | … | … | … | … | … |

**Purpose:** Highlights products associated with higher data anomalies.

---

**Note:** Table 4 and Table 5 output tidy summary tables only. Visualisations are not generated within this OpenSAFELY job and should be created separately in R.

---
### Table 4. Distribution of Flags Across Campaigns
Stacked bar 

---

### Table 5. Distribution of Flags Across Products
Horizontal grouped bar 

---

## 6. Main Descriptive Results

Summaries should be provided for each domain:
1. Impossible dates  
2. Product–approval mismatches  
3. Same‑day duplicates  
4. Interval anomalies  

Include tables and plots in each subsection.

---

## 7. Flow of Flagged Records and Patients

Although the concept of a flow diagram draws on previous data‑processing work, the current analysis focuses primarily on identifying and quantifying issues rather than applying strict exclusion rules. Only a small proportion of records are expected to be removed at this stage, with most anomalies flagged for further study‑specific evaluation.
For this reason, a full flow diagram is not presented here.

---

## 8. Future Improvements

Future work could extend the data quality assessment to additional dimensions that were outside the scope of this initial descriptive review:

### 8.1 Age–dose mismatches
Products restricted to specific age groups

---


## 9. Conclusion

---