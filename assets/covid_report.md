# Descriptive Data Quality Assessment of COVID‑19 Vaccination Records

## 1. Aim

This descriptive data quality assessment examines COVID‑19 vaccination records on OpenSAFELY at the event level. The aim is to evaluate whether the underlying data contain structural or recording issues by applying predefined flags and visual summaries to identify and quantify anomalies in dates, product, and dose intervals.
The purpose of this work is to assess the quality of the data themselves, rather than to interpret population characteristics, conduct stratified analyses.
Insights from this assessment will support the wider OVERTURE project in determining how best to process vaccination data, minimise errors, and understand limitations before any downstream analytic or inferential work.

---

## 2. Overview of Data Quality Framework

Four main domains are assessed:

1. Impossible dates  
2. Product–approval mismatches  
3. Multiple vaccinations recorded on the same day  
4. Implausible intervals between consecutive doses

All issues are flagged and quantified, rather than used for exclusion at this stage.

---

## 3. Definitions of Flags
The analysis uses event-level COVID-19 vaccination records.
Before constructing any data-quality flags, the following preprocessing steps are applied:

- **Records with missing vaccination dates (`vax_date`) are excluded.**
- **Raw vaccine product names are harmonised using `vax_product_lookup`.**
- **Campaign labels are assigned based on vaccination dates using `campaign_info`.**

### 3.1 Impossible Dates

#### A. Implausible early date
- **Definition:** `vax_date < 2020‑04‑23`  
- **Interpretation:** Likely erroneous.  
- **Action:** Flag + typically exclude.

#### B. Pre‑rollout date
- **Definition:** `2020‑04‑23 ≤ vax_date < 2020‑12‑08`  
- **Interpretation:** May reflect trial participation or exceptional early use; not automatically invalid.  
- **Action:** Flag + retain.

Eligibility assessment is not applied due to incomplete capture and complex early rollout practices.
Because rollout dates vary by product, product‑approval mismatches are assessed separately below.

---

### 3.2 Product–Approval Mismatches

#### A. Unapproved products
- **Definition:** Product not found in (`approval_lookup`).
- **Interpretation:** May indicate overseas vaccination or non‑standard entry.  
- **Action:** Flag + retain.

#### B. Products used before approval
- **Definition:** Product appears in (`approval_lookup`), but (`vax_date`) < (`approval_date`)
- **Interpretation:** Could be early use or recording error.  
- **Action:** Flag; inclusion/exclusion is study‑dependent.

#### Approval reference data:
- The approval lookup table is based on the ECHO protocol and supplemented with publicly available regulatory sources to improve completeness.
- Products not included in this list are not assumed to be erroneous and are retained for descriptive quantification.
- **The current workflow is aligned with the ECHO protocol**.

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
### 3.3 Multiple Vaccinations on the Same Day


Same-day patterns are assessed by grouping vaccination records by:

- `patient_id`
- `vax_date`
- `campaign`
- `vax_product` (or not)

For each **patient–date–campaign** combination, the script derives the following summary variables:

- `total_records_day`
- `n_products_day`
- `product_pattern`


#### A. Same-day multiple record
- **Definition:** `total_records_day > 1`  
- **Interpretation:** More than one vaccination record exists for the same patient on the same date.  
- **Action:** Flag.

#### B. Same‑day same‑product
`total_records_day > 1` *and* `n_products_day == 1` 
- **Definition:** Same patient + same date + same product, multiple entries.  
- **Interpretation:** Highly likely duplicate.  
- **Action:** Retain one; remove duplicates.

#### C. Same‑day mixed‑product
`total_records_day > 1` *and* `n_products_day > 1`
- **Definition:** Same patient + same date + different products.  
- **Interpretation:** Could represent conflicting entries or corrected-but-not-deleted records.  
- **Action:** Quantify; study‑specific treatment.

Mixed‑product days take precedence: if any mixed‑product combination occurs on a given patient‑date, all records for that day are flagged as mixed‑product.

---
### 3.4 Implausible Intervals Between Consecutive Doses

#### Exclusions
- records in campaign **"Pre-2020-04-23"**
- records flagged as **`flag_same_day_multiple`**
- records without a previous vaccination date

#### Campaign stage classification

Campaigns are grouped into broader stages for interval interpretation:

- **"Pre-roll-out"** and **"Primary series"** → *primary*
- campaigns matching **"Spring"** or **"Autumn"** → *booster*


#### Derived variables
- `prev_date`
- `prev_product`
- `prev_campaign`
- `interval_days`
- `interval_bin`
- `campaign_stage`
- `prev_campaign_stage`
- `interval_context`
- `campaign_transition_type`
- `product_transition_type`


#### Interval bins (days)
- **1–6**
- **7–13**
- **14–20**
- **21–29**
- **30–89**
- **90–112**
- **113–179**
- **180+**


#### Expected ranges
- Primary within‑campaign: **14–112 days**  
- Booster within‑campaign: **≥90 days**  
- Across‑campaign: **≥90 days**

Although expected ranges are defined, shorter intervals can still be clinically appropriate in specific circumstances, such as for high‑risk individuals, people with reduced immune function, or certain occupational groups where accelerated scheduling may be justified.

For extremely short intervals, records are removed as they are unlikely to represent valid dosing events. For the remaining non‑standard intervals, interpretation should be contextual and assessed case by case.

---

## 4. Overview of All Flag Types
Non-interval flags are converted into long format using the following variables:
- `flag_implausible_early_date`
- `flag_pre_rollout_date`
- `flag_unapproved_product`
- `flag_product_before_approval`
- `flag_same_day_multiple`
- `flag_same_day_same_product`
- `flag_same_day_mixed_product`

Only records with `flag_value == TRUE` are retained in the long-format non‑interval flag table.


Interval flags are derived using `Interval bins (1–6 → 180+ days)` to classify intervals into predefined day‑range categories. 

---

## 5. Summary Tables

**Note:** The summary tables produced here represent the initial, high‑level version of the data‑quality summaries. Further refinements will be implemented in the R visualisation stage, including grouping vaccine products into broader categories and collapsing certain interval bins into “plausible” vs “implausible” ranges for more interpretable reporting.

### 5.1 Non-interval summaries
Three summary tables are produced from the long-format non‑interval flag table.

---

#### Table 1. overall_noninterval_flags  `count_overall_noninterval_flags.csv`

**Purpose:**  
Summarises each non‑interval flag type across the full event‑level dataset.

**Contents:**  
For each `flag_type`:

- `n_records`
- `n_patients`
- `denom_records_total`
- `denom_patients_total`
- `pct_records_total`
- `pct_patients_total`


---

#### Table 2. campaign_noninterval_flags  `count_campaign_noninterval_flags.csv`

**Purpose:**  
Summarises non‑interval flags by campaign.

**Contents:**  
For each `campaign × flag_type`:

- `n_records`
- `n_patients`
- `denom_records_total`
- `denom_patients_total`
- `pct_records_total`
- `pct_patients_total`

---

#### Table 3. product_noninterval_flags  `count_product_noninterval_flags.csv`

**Purpose:**  
Summarises non‑interval flags by vaccine product.

**Contents:**  
For each `vax_product × flag_type`:

- `n_records`
- `n_patients`
- `denom_records_total`
- `denom_patients_total`
- `pct_records_total`
- `pct_patients_total`

---
### 5.2 Interval summaries

Three interval summary tables are produced from `data_vax_interval`

---
#### Table 4. interval_context x interval bin  `count_interval_context.csv`

**Purpose:**  
Summarises interval bins within each interval context.

**Contents:**  
For each `interval_context × interval_bin`:

- `n_records`
- `n_patients`
- `denom_records_group`
- `denom_patients_group`
- `denom_records_total`
- `denom_patients_total`
- `pct_records_within_group`
- `pct_patients_within_group`
- `pct_records_total`
- `pct_patients_total`

---

#### Table 5. campaign transition type x interval bin `count_interval_campaign_transition.csv`

**Purpose:**  
Summarises interval bins by campaign transition type.

**Contents:**  
For each `campaign_transition_type × interval_bin`:

- `n_records`
- `n_patients`
- `denom_records_group`
- `denom_patients_group`
- `denom_records_total`
- `denom_patients_total`
- `pct_records_within_group`
- `pct_patients_within_group`
- `pct_records_total`
- `pct_patients_total`

--

#### Table 6. product transition type x interval bin `count_interval_product_transition.csv`

**Purpose:**  
Summarises interval bins by product transition type.

**Contents:**  
For each `product_transition_type × interval_bin`:

- `n_records`
- `n_patients`
- `denom_records_group`
- `denom_patients_group`
- `denom_records_total`
- `denom_patients_total`
- `pct_records_within_group`
- `pct_patients_within_group`
- `pct_records_total`
- `pct_patients_total`

---

## 6. Main Descriptive Results

Summaries should be provided for each domain:
1. Impossible dates  
2. Product–approval mismatches  
3. Same‑day duplicates  
4. Interval anomalies  


---

## 7. Flow of Flagged Records and Patients

Although the concept of a flow diagram draws on previous data‑processing work, the current analysis focuses primarily on identifying and quantifying issues rather than applying strict exclusion rules. Only a small proportion of records are expected to be removed at this stage, with most anomalies flagged for further study‑specific evaluation.
For this reason, a full flow diagram is not presented here.

---

## 8. Potential Extensions

- age–product consistency checks  
- product‑specific expected‑use windows  


---


## 9. Conclusion

---