# _________________________________________________
# Purpose:
#   Import event‑level COVID‑19 vaccination data
#   Construct data‑quality flags
#   Output five descriptive summary tables
#
# Notes:
#   - No records are removed in this script
#   - All outputs are event-level and descriptive only
#   - Interval bins (1–6 → 180+) are included as flag types
# _________________________________________________


# Preliminaries ----

# Import libraries
library(tidyverse)
library(dtplyr)
library(lubridate)
library(arrow)
library(here)
library(glue)

# Import custom functions
source(here("analysis", "covid", "0_covid_design.R"))

# create output directory
output_dir <- here("output", "outputs_covid", "covid_data_quality")
fs::dir_create(output_dir)
options(width = 200) # set output width for capture.output


# 1. extract event level data for vaccines ----

data_vax_ELD0 <- read_feather(
  here("output", "outputs_covid", "modify_dummy_extract", "vaccinations.arrow")
)


# 2. Prepare dataset 
# - remove rows where vaccination date is missing
# - attach info about the campaign during which the vaccination was given

data_vax_ELD <-
  data_vax_ELD0 |>
  lazy_dt() |>
  arrange(patient_id, vax_date) |>
  filter(!is.na(vax_date)) |>   # only minimal removal
  as_tibble() |>
  mutate(
    # Harmonise product variable
    vax_product_raw = vax_product,
    vax_product = fct_recode(factor(vax_product, vax_product_lookup), !!!vax_product_lookup) |> fct_na_value_to_level("UNMAPPED"),

    # Assign campaign label
    campaign = cut(
      vax_date,
      breaks = c(campaign_info$campaign_start_date, as.Date(Inf)),
      labels = campaign_info$campaign_label
    )
  ) |>
  lazy_dt()

# report any unmapped product names
# and stop if there are any
unmapped_products <- data_vax_ELD |> filter(vax_product %in% "UNMAPPED") |> pull(vax_product_raw) |> unique()
cat("Unmapped product names: \n")
cat(paste0(unmapped_products, collapse = "\n"))
stopifnot("There are unmapped product names" = length(unmapped_products) == 0)


# 3. Construct data‑quality flags


# --- Impossible dates ---
data_vax_ELD <-
  data_vax_ELD |>
  mutate(
    flag_implausible_early_date = vax_date < as.Date("2020-07-01"),
    flag_pre_rollout_date =
      vax_date >= as.Date("2020-07-01") &
      vax_date <  as.Date("2020-12-08")
  ) |>
  as_tibble()



# ---- Product approval flags ----
data_vax_ELD <-
  data_vax_ELD |>
  mutate(
    product_chr   = as.character(vax_product),
    approval_date = as.Date(approval_lookup[product_chr]),

    # A: product not found in the approval lookup table
    flag_unapproved_product = !(product_chr %in% names(approval_lookup)),

    # B: product recorded before approval (only if recognised)
    flag_product_before_approval =
      (product_chr %in% names(approval_lookup)) &
      vax_date < approval_date
  ) |>
  as_tibble()



# ---- Same‑day multiple records ----

products_cooccurrence_flat <- 
  data_vax_ELD |>
  filter(age >= 12) |>
  group_by(patient_id, vax_date, campaign, vax_product) |>
  summarise(
    n_product = n(),
    .groups = "drop_last"
  ) |>
  arrange(patient_id, vax_date, vax_product) |>
  summarise(
    total_records_day = sum(n_product),
    n_products_day = n(),
    product_pattern = paste0(
      paste0(n_product, "x ", as.character(vax_product)),
      collapse = "  --AND-- "
    ),
    .groups = "drop"
  ) |>
  mutate(
    flag_same_day_multiple =
      total_records_day > 1,

    flag_same_day_same_product =
      total_records_day > 1 & n_products_day == 1,

    flag_same_day_mixed_product =
      total_records_day > 1 & n_products_day > 1
  )

data_vax_ELD <- 
  data_vax_ELD |>
  left_join(
    products_cooccurrence_flat |>
      select(
        patient_id, vax_date, campaign,
        total_records_day, n_products_day, product_pattern,
        flag_same_day_multiple,
        flag_same_day_same_product,
        flag_same_day_mixed_product
      ),
    by = c("patient_id", "vax_date", "campaign")
  ) |>
  as_tibble()


# ---- Dose interval bins ----
data_vax_interval <-
  data_vax_ELD |>
  filter(!flag_same_day_multiple) |> # exclude same-day multiple-record combinations
  arrange(patient_id, vax_date) |>
  group_by(patient_id) |>
  mutate(
    prev_date     = lag(vax_date),
    prev_product  = lag(vax_product),
    prev_campaign = lag(campaign),
    interval_days = as.numeric(vax_date - prev_date)
  ) |>
  ungroup() |>
  filter(!is.na(interval_days)) |> # keep only records with a previous vaccination date
  mutate(
    interval_bin = case_when(
      interval_days >= 1   & interval_days <= 6   ~ "1-6",
      interval_days >= 7   & interval_days <= 13  ~ "7-13",
      interval_days >= 14  & interval_days <= 29  ~ "14-29",
      interval_days >= 30  & interval_days <= 89  ~ "30-89",
      interval_days >= 90  & interval_days <= 112 ~ "90-112",
      interval_days >= 113 & interval_days <= 179 ~ "113-179",
      interval_days >= 180                         ~ "180+",
      TRUE ~ NA_character_
    )
  ) |>
  select(
    patient_id,
    prev_date,
    vax_date,
    prev_product,
    vax_product,
    prev_campaign,
    campaign,
    interval_days,
    interval_bin
  )

  data_vax_ELD <-
  data_vax_ELD |>
  left_join(
    data_vax_interval |>
      select(
        patient_id,
        vax_date,
        campaign,
        vax_product,
        prev_date,
        prev_product,
        prev_campaign,
        interval_days,
        interval_bin
      ),
    by = c("patient_id", "vax_date", "campaign", "vax_product")
  ) |>
  as_tibble()


# 4. Convert to long-format flag table

# denominators for percentages ----
n_total_records  <- nrow(data_vax_ELD)
n_total_patients <- data_vax_ELD |>
  distinct(patient_id) |>
  nrow()


# ---- Non-interval flags ----
flag_long_main <-
  data_vax_ELD |>
  select(
    patient_id, vax_date, campaign, vax_product,
    flag_implausible_early_date,
    flag_pre_rollout_date,
    flag_unapproved_product,
    flag_product_before_approval,
    flag_same_day_multiple,
    flag_same_day_same_product,
    flag_same_day_mixed_product
  ) |>
  pivot_longer(
    cols = starts_with("flag_"),
    names_to = "flag_type",
    values_to = "flag_value"
  ) |>
  filter(flag_value) |>
  mutate(
    flag_type = as.character(flag_type)
  ) |>
  select(patient_id, vax_date, campaign, vax_product, flag_type)


# ---- Interval flags ----
flag_long_interval <-
  data_vax_interval |>
  filter(!is.na(interval_bin)) |>
  mutate(
    flag_type = paste0("interval_", interval_bin)
  ) |>
  select(patient_id, vax_date, campaign, vax_product, flag_type)


# ---- Combine ----
flag_full <-
  bind_rows(flag_long_main, flag_long_interval)


# 5. Output: five descriptive summary tables

# ---- Table 1: Overall summary ----
table_overall <-
  flag_full |>
  group_by(flag_type) |>
  summarise(
    n_records  = roundmid_any(n(), sdc_threshold),
    n_patients = roundmid_any(n_distinct(patient_id), sdc_threshold),
    .groups = "drop"
  ) |>
  mutate(
    pct_records  = round(100 * n_records  / n_total_records, 1),
    pct_patients = round(100 * n_patients / n_total_patients, 1)
  ) |>
  arrange(flag_type)

write_csv(
  table_overall,
  fs::path(output_dir, "count_overall_flags.csv")
)


# ---- Table 2: Campaign summary ----
table_campaign <-
  flag_full |>
  group_by(campaign, flag_type) |>
  summarise(
    n_records  = roundmid_any(n(), sdc_threshold),
    n_patients = roundmid_any(n_distinct(patient_id), sdc_threshold),
    .groups = "drop"
  ) |>
  left_join(
    data_vax_ELD |>
      group_by(campaign) |>
      summarise(
        denom_records  = n(),
        denom_patients = n_distinct(patient_id),
        .groups = "drop"
      ),
    by = "campaign"
  ) |>
  mutate(
    pct_records  = round(100 * n_records  / denom_records, 1),
    pct_patients = round(100 * n_patients / denom_patients, 1)
  ) |>
  select(
    campaign,
    flag_type,
    n_records,
    n_patients,
    pct_records,
    pct_patients
  ) |>
  arrange(campaign, flag_type)

write_csv(
  table_campaign,
  fs::path(output_dir, "count_campaign_flags.csv")
)


# ---- Table 3: Product summary ----
table_product <-
  flag_full |>
  group_by(vax_product, flag_type) |>
  summarise(
    n_records  = roundmid_any(n(), sdc_threshold),
    n_patients = roundmid_any(n_distinct(patient_id), sdc_threshold),
    .groups = "drop"
  ) |>
  left_join(
    data_vax_ELD |>
      group_by(vax_product) |>
      summarise(
        denom_records  = n(),
        denom_patients = n_distinct(patient_id),
        .groups = "drop"
      ),
    by = "vax_product"
  ) |>
  mutate(
    pct_records  = round(100 * n_records  / denom_records, 1),
    pct_patients = round(100 * n_patients / denom_patients, 1)
  ) |>
  select(
    vax_product,
    flag_type,
    n_records,
    n_patients,
    pct_records,
    pct_patients
  ) |>
  arrange(vax_product, flag_type)

write_csv(
  table_product,
  fs::path(output_dir, "count_product_flags.csv")
)


# ---- Table 4: Flag × Campaign distribution ----
flag_campaign_plot <-
  flag_full |>
  group_by(campaign, flag_type) |>
  summarise(
    n = roundmid_any(n(), sdc_threshold),
    .groups = "drop"
    )


write_csv(
  flag_campaign_plot,
  fs::path(output_dir, "flag_distribution_campaign.csv")
)



# ---- Table 5: Flag × Product distribution ----
flag_product_plot <-
  flag_full |>
  group_by(vax_product, flag_type) |>
  summarise(
    n = roundmid_any(n(), sdc_threshold),
    .groups = "drop"
    )

write_csv(
  flag_product_plot,
  fs::path(output_dir, "flag_distribution_product.csv")
)
