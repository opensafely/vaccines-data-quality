# _________________________________________________
# Purpose:
#   Import event‑level COVID‑19 vaccination data
#   Construct data‑quality flags
#   Output 8 descriptive summary tables
# _________________________________________________


# Preliminaries ----

# Import libraries
library(tidyverse)
library(dtplyr)
library(lubridate)
library(arrow)
library(here)
library(glue)
library(fs)

# Import custom functions
source(here("analysis", "covid", "fn_covid_data_quality.R"))
source(here("analysis", "covid", "0_covid_design.R"))

# Create output directories
output_dir <- here("output", "covid", "covid_data_quality")

output_dir_consistency <- fs::path(output_dir, "consistency")
output_dir_interval <- fs::path(output_dir, "interval")
output_dir_interval_campaign <- fs::path(output_dir, "interval_campaign")
output_dir_same_day <- fs::path(output_dir, "same_day")

fs::dir_create(output_dir_consistency)
fs::dir_create(output_dir_interval)
fs::dir_create(output_dir_interval_campaign)
fs::dir_create(output_dir_same_day)
options(width = 200) # set output width for capture.output


# 1. extract event level data for vaccines ----
localrun <- Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")

data_vax_ELD0 <- read_feather(here("output", "covid", "extract_covid", "vaccinations.arrow"))

if (localrun) {
  data_vax_ELD0 <- 
    data_vax_ELD0 |>
      make_vax_baseline_clean(seed = 123) |>
      inject_vax_errors(seed = 123) 
}


# 2. Prepare dataset ----

# ---- Missing vaccination date flag ----

data_vax_ELD0 <-
  data_vax_ELD0 |>
  mutate(
    event_id = row_number(),
    flag_missing_vax_date = is.na(vax_date)
  )

# Initial denominators before excluding missing vaccination dates
denom_records_initial <- nrow(data_vax_ELD0)
denom_patients_initial <- n_distinct(data_vax_ELD0$patient_id)


# Continue with records that have vaccination dates
data_vax_ELD <-
  data_vax_ELD0 |>
  lazy_dt() |>
  arrange(patient_id, vax_date) |>
  filter(!flag_missing_vax_date) |>
  as_tibble() |>
  mutate(
    # Harmonise product variable
    vax_product_raw = vax_product,
    vax_product = fct_recode(factor(vax_product, vax_product_lookup), !!!vax_product_lookup) |> fct_na_value_to_level("UNMAPPED"),

    # Assign campaign label
    campaign = cut(
      vax_date,
      breaks = c(campaign_info$campaign_start_date, as.Date(Inf)),
      labels = campaign_info$campaign_label,
      right = FALSE
    )
  ) |>
  lazy_dt()


# report any unmapped product names
unmapped_products <- data_vax_ELD |> filter(vax_product == "UNMAPPED") |> pull(vax_product_raw) |> unique()
if (length(unmapped_products) > 0) {
  message("Unmapped product names found:")
  message(paste(unmapped_products, collapse = "\n"))
  stop("There are unmapped product names — see log for details.")
}

# drop unused variable
data_vax_ELD <- data_vax_ELD |>
  select(-vax_product_raw)

# 3. Construct data‑quality flags

# --- 3.1 Impossible dates ---
data_vax_ELD <-
  data_vax_ELD |>
  mutate(
    flag_implausible_early_date = vax_date < study_dates$firstpossiblevax_date,
    flag_pre_rollout_date =
      vax_date >= study_dates$firstpossiblevax_date &
      vax_date <  study_dates$start_date
  ) |>
  as_tibble()



# ---- 3.2 Non-routine product flags ----

routine_lookup_df <-
  enframe(campaign_product_lookup, name = "campaign", value = "routine_products") |>
  unnest_longer(routine_products, values_to = "routine_product")

data_vax_ELD <-
  data_vax_ELD |>
  mutate(
    product_chr = as.character(vax_product)
  ) |>
  left_join(
    routine_lookup_df |>
      mutate(flag_routine_product = TRUE),
    by = c("campaign", "product_chr" = "routine_product")
  ) |>
  mutate(
    flag_routine_product = coalesce(flag_routine_product, FALSE),
    flag_non_routine_product = !flag_routine_product
  ) |>
  as_tibble()


# ---- 3.3 Multiple Vaccinations on the Same Day ----

products_cooccurrence_flat <- 
  data_vax_ELD |>
  group_by(patient_id, vax_date, vax_product) |>
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
        patient_id, vax_date,
        total_records_day, n_products_day, product_pattern,
        flag_same_day_same_product,
        flag_same_day_mixed_product
      ),
    by = c("patient_id", "vax_date")
  ) |>
  as_tibble()


# ---- 3.4 Implausible Intervals Between Consecutive Dates ----
# - Exclude "Pre-2020-04-23" and "Pre-roll-out"
# - Combine same-day records into one date-level event
# - Retain mixed-product dates with product marked as unknown
# - "Primary series" classified as "primary"
# - All Spring and Autumn campaigns classified as "booster"
#
# Interval analysis:
# - Interval bins and contexts
# - Campaign and product transitions
#
# Patient-level indicators:
# - PR: Number of distinct vaccination dates in the primary series
# - PS: Number of within-primary intervals <14 days
# - BM: Number of booster campaigns with >1 distinct vaccination date
# - CS: Number of cross-campaign intervals <90 days
# - CSI: At least two consecutive short intervals
#        using context-specific thresholds (14 or 90 days)

short_interval_threshold <- 14   #for primary campaign

# ---- 3.4.1 Date-level vaccination history ----

data_vax_date_level <-
  data_vax_ELD |>
  filter(!campaign %in% c("Pre-2020-04-23", "Pre-roll-out")) |>
  arrange(patient_id, vax_date, vax_product) |>
  mutate(
    campaign = as.character(campaign),
    vax_product = as.character(vax_product)
  ) |>
  group_by(patient_id, vax_date) |>
  summarise(
    campaign = first(campaign),
    vax_product = if (first(flag_same_day_mixed_product))
      "MIXED_PRODUCT_UNKNOWN" else first(vax_product),
    product_pattern = first(product_pattern),
    .groups = "drop"
  )


# ---- 3.4.2 Interval-level analysis ----

data_vax_interval <-
  data_vax_date_level |>
  arrange(patient_id, vax_date) |>
  group_by(patient_id) |>
  mutate(
    prev_date = lag(vax_date),
    prev_product = lag(vax_product),
    prev_campaign = lag(campaign),
    prev_product_pattern = lag(product_pattern),
    interval_days = as.numeric(vax_date - prev_date)
  ) |>
  ungroup() |>
  filter(!is.na(interval_days)) |> # keep only records with a previous vaccination date
  mutate(
    interval_bin = case_when(
      interval_days >= 1   & interval_days <= 6   ~ "1-6",
      interval_days >= 7   & interval_days <= 13  ~ "7-13",
      interval_days >= 14  & interval_days <= 20  ~ "14-20",  
      interval_days >= 21  & interval_days <= 29  ~ "21-29",
      interval_days >= 30  & interval_days <= 89  ~ "30-89",
      interval_days >= 90  & interval_days <= 112 ~ "90-112",
      interval_days >= 113 & interval_days <= 179 ~ "113-179",
      interval_days >= 180                         ~ "180+",
      TRUE ~ NA_character_
    ),
    interval_bin = factor(
      interval_bin,
      levels = c("1-6", "7-13","14-20", "21-29","30-89", "90-112", "113-179", "180+")
    ),


    campaign_stage = case_when(
      campaign == "Primary series" ~ "primary",
      grepl("Spring|Autumn", campaign) ~ "booster",
      TRUE ~ NA_character_
    ),

    prev_campaign_stage = case_when(
      prev_campaign == "Primary series" ~ "primary",
      grepl("Spring|Autumn", prev_campaign) ~ "booster",
      TRUE ~ NA_character_
    ),

    interval_context = case_when(
      prev_campaign_stage == "primary" &
        campaign_stage == "primary" ~ "within_primary",

      prev_campaign_stage == "primary" &
        campaign_stage == "booster" ~ "primary_to_booster",

      prev_campaign_stage == "booster" &
        campaign_stage == "booster" &
        prev_campaign == campaign ~ "within_booster_campaign",

      prev_campaign_stage == "booster" &
        campaign_stage == "booster" &
        prev_campaign != campaign ~ "between_booster_campaigns",

      TRUE ~ NA_character_
    ),

    campaign_transition_type =
      paste0(prev_campaign, " -> ", campaign),

    product_transition_type =
      paste0(prev_product, " -> ", vax_product),


    # Short-interval indicators
    flag_PS_interval =
      interval_context == "within_primary" &
      interval_days < short_interval_threshold,

    flag_CS_interval =
      prev_campaign != campaign &
      interval_days < 90,

    flag_short_interval = case_when(
      interval_context == "within_primary" ~ interval_days < short_interval_threshold,
      interval_context %in% c(
        "primary_to_booster",
        "within_booster_campaign",
        "between_booster_campaigns"
      ) ~ interval_days < 90,
      TRUE ~ FALSE
    )
   ) |>
  arrange(patient_id, vax_date) |>
  group_by(patient_id) |>
  mutate(
    flag_CSI_interval =
      flag_short_interval &
      lag(flag_short_interval, default = FALSE)
  ) |>
  ungroup() |>
  select(
    patient_id,
    prev_date,
    vax_date,
    prev_product,
    vax_product,
    prev_product_pattern,
    product_pattern,
    prev_campaign,
    campaign,
    prev_campaign_stage,
    campaign_stage,
    interval_days,
    interval_bin,
    interval_context,
    campaign_transition_type,
    product_transition_type,
    flag_PS_interval,
    flag_CS_interval,
    flag_short_interval,
    flag_CSI_interval
  )


# ---- 3.4.3 Patient-level indicators ----
# PR: Number of primary vaccination dates
# PS: Number of within-primary intervals <14 days
# BM: Number of booster campaigns with >1 vaccination date
# CS: Number of cross-campaign intervals <90 days
# CSI: Presence of two consecutive short intervals,
#      using context-specific thresholds (14 or 90 days)
patient_BM <-
  data_vax_date_level |>
  filter(campaign != "Primary series") |>
  count(patient_id, campaign, name = "n_dates") |>
  filter(n_dates > 1) |>
  count(patient_id, name = "BM")

patient_intervals <-
  data_vax_interval |>
  group_by(patient_id) |>
  summarise(
    PS = sum(flag_PS_interval),
    CS = sum(flag_CS_interval),
    CSI = any(flag_CSI_interval),
    .groups = "drop"
  )

data_vax_patient <-
  data_vax_date_level |>
  group_by(patient_id) |>
  summarise(
    PR = sum(campaign == "Primary series"),
    .groups = "drop"
  ) |>
  left_join(patient_BM, by = "patient_id") |>
  left_join(patient_intervals, by = "patient_id") |>
  mutate(
    across(c(PR, PS, BM, CS), ~ replace_na(.x, 0L)),
    CSI = replace_na(CSI, FALSE),
    history_pattern = paste0(
      PR, "PR_", PS, "PS_", BM, "BM_",
      CS, "CS_", as.integer(CSI), "CSI"
    )
  )


# 4. Convert consistency flags to long format ----

flag_long_consistency <-
  data_vax_ELD |>
  select(
    event_id, patient_id, vax_date, campaign, vax_product,
    flag_implausible_early_date,
    flag_pre_rollout_date,
    flag_non_routine_product,
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
    flag_type = as.character(flag_type),
    campaign = as.character(campaign),
    vax_product = as.character(vax_product)
  ) |>
  select(event_id, patient_id, vax_date, campaign, vax_product, flag_type)

# Missing vaccination dates
flag_long_missing_date <-
  data_vax_ELD0 |>
  filter(flag_missing_vax_date) |>
  transmute(
    event_id,
    patient_id,
    vax_date,
    campaign = NA_character_,
    vax_product = as.character(vax_product),
    flag_type = "flag_missing_vax_date"
  )

# Combine all six flags
flag_long_consistency_all <-
  bind_rows(flag_long_consistency, flag_long_missing_date)


# 5. Output: descriptive summary tables
# 2 version: unrounded + rounded
# we can look on L4 to see if rounding has introduced any issues


# ---- Table 1: Overall consistency issues ----

table_overall_consistency_flags_unrounded <-
  flag_long_consistency_all |>
  make_summary_table_total(
    group_vars = "flag_type",
    denom_records_initial = denom_records_initial,
    denom_patients_initial = denom_patients_initial
  ) |>
  arrange(flag_type)

table_overall_consistency_flags_rounded <-
  table_overall_consistency_flags_unrounded |>
  mutate(
    across(
      c(n_records, n_patients,
        denom_records_total, denom_patients_total),
      ~ roundmid_any(.x, sdc_threshold)
    )
  )

write_csv(
  table_overall_consistency_flags_unrounded,
  fs::path(
    output_dir_consistency,
    "count_overall_consistency_flags_unrounded.csv"
  )
)

write_csv(
  table_overall_consistency_flags_rounded,
  fs::path(
    output_dir_consistency,
    "count_overall_consistency_flags.csv"
  )
)

# ---- Table 2: Non-routine products by campaign and product ----

analysis_campaigns <-
  setdiff(
    as.character(campaign_info$campaign_label),
    c("Pre-2020-04-23", "Pre-roll-out")
  )

flag_data_campaign <-
  flag_long_consistency_all |>
  filter(campaign %in% analysis_campaigns)

table_nonroutine_campaign_product_unrounded <-
  make_summary_table_consistency_product(
    data = flag_data_campaign,
    flag_name = "flag_non_routine_product"
  )

table_nonroutine_campaign_product_rounded <-
  table_nonroutine_campaign_product_unrounded |>
  mutate(
    across(
      c(n_records, n_patients, denom_records_flag, denom_patients_flag),
      ~ roundmid_any(.x, sdc_threshold)
    )
  )

write_csv(
  table_nonroutine_campaign_product_unrounded,
  fs::path(output_dir_consistency, "count_nonroutine_campaign_product_unrounded.csv")
)

write_csv(
  table_nonroutine_campaign_product_rounded,
  fs::path(output_dir_consistency, "count_nonroutine_campaign_product.csv")
)


# ---- Table 3: Same-day same-product records by campaign and product ----

table_same_day_same_product_unrounded <-
  make_summary_table_consistency_product(
    data = flag_data_campaign,
    flag_name = "flag_same_day_same_product"
  )

table_same_day_same_product_rounded <-
  table_same_day_same_product_unrounded |>
  mutate(
    across(
      c(n_records, n_patients, denom_records_flag, denom_patients_flag),
      ~ roundmid_any(.x, sdc_threshold)
    )
  )

write_csv(
  table_same_day_same_product_unrounded,
  fs::path(output_dir_same_day, "count_same_day_same_product_unrounded.csv")
)

write_csv(
  table_same_day_same_product_rounded,
  fs::path(output_dir_same_day, "count_same_day_same_product.csv")
)

# ---- Table 4: count same-day mixed-product co-occurrence ----

mixed_products_cooccurrence_flat <-
  data_vax_ELD |>
  filter(flag_same_day_mixed_product) |>
  count(patient_id, campaign, vax_date, vax_product, name = "n") |>
  arrange(patient_id, campaign, vax_date, vax_product) |>
  group_by(patient_id, campaign, vax_date) |>
  summarise(
    vax_product =
      paste0(n, "x ", as.character(vax_product),
             collapse = "  --AND-- "),
    .groups = "drop"
  )

count_mixed_products_cooccurrence_unrounded <-
  mixed_products_cooccurrence_flat |>
  count(
    campaign,
    vax_date,
    vax_product,
    name = "count_total"
    ) |>
  arrange(campaign, desc(count_total)) |>
  as_tibble()

count_mixed_products_cooccurrence <-
  count_mixed_products_cooccurrence_unrounded |>
  mutate(
    count_total = roundmid_any(count_total, sdc_threshold)
  )

write_csv_split_by(
  count_mixed_products_cooccurrence_unrounded,
  "campaign",
  output_dir_same_day,
  "count_same_day_mixed_product_cooccurrence_unrounded"
)

write_csv_split_by(
  count_mixed_products_cooccurrence,
  "campaign",
  output_dir_same_day,
  "count_same_day_mixed_product_cooccurrence"
)

# ---- Table 5: Interval context x interval bin ----

table_interval_context_unrounded <-
  make_interval_table(
    data = data_vax_interval,
    group_vars = "interval_context"
  ) |>
  dplyr::arrange(interval_context, interval_bin)

table_interval_context_rounded <-
  table_interval_context_unrounded |>
  dplyr::mutate(
    dplyr::across(
      c(
        n_intervals,
        n_patients,
        denom_intervals_group,
        denom_patients_group,
        denom_intervals_total,
        denom_patients_total
      ),
      ~ roundmid_any(.x, sdc_threshold)
    )
  )

write_csv(
  table_interval_context_unrounded,
  fs::path(
    output_dir_interval,
    "count_interval_context_unrounded.csv"
  )
)

write_csv(
  table_interval_context_rounded,
  fs::path(
    output_dir_interval,
    "count_interval_context.csv"
  )
)

# ---- Table 6: Intervals <90 days by campaign and product transitions ----

table_interval_transitions_unrounded <-
  make_interval_table(
    data = data_vax_interval |>
      filter(interval_days < 90),
    group_vars = c(
      "prev_campaign",
      "campaign",
      "prev_product",
      "vax_product"
    )
  ) |>
  arrange(
    prev_campaign,
    campaign,
    prev_product,
    vax_product,
    interval_bin
  )

table_interval_transitions_rounded <-
  table_interval_transitions_unrounded |>
  mutate(
    across(
      c(
        n_intervals,
        n_patients,
        denom_intervals_group,
        denom_patients_group,
        denom_intervals_total,
        denom_patients_total
      ),
      ~ roundmid_any(.x, sdc_threshold)
    )
  )

write_csv_split_by(
  table_interval_transitions_unrounded,
  "campaign",
  output_dir_interval_campaign,
  "count_interval_transitions_under90_unrounded"
)

write_csv_split_by(
  table_interval_transitions_rounded,
  "campaign",
  output_dir_interval_campaign,
  "count_interval_transitions_under90"
)


# ---- Table 7: Patient-level vaccination patterns ----

table_patient_patterns_unrounded <-
  data_vax_patient |>
  count(history_pattern, name = "n_patients") |>
  mutate(
    denom_patients_total = nrow(data_vax_patient)
  ) |>
  arrange(desc(n_patients))

table_patient_patterns_rounded <-
  table_patient_patterns_unrounded |>
  mutate(
    across(
      c(n_patients, denom_patients_total),
      ~ roundmid_any(.x, sdc_threshold)
    )
  )

write_csv(
  table_patient_patterns_unrounded,
  fs::path(output_dir_interval, "count_patient_patterns_unrounded.csv")
)

write_csv(
  table_patient_patterns_rounded,
  fs::path(output_dir_interval, "count_patient_patterns.csv")
)


# ---- Table 8: Number and overlap of consistency flags ----

record_flag_patterns <-
  flag_long_consistency_all |>
  distinct(event_id, patient_id, flag_type) |>
  arrange(event_id, flag_type) |>
  group_by(event_id, patient_id) |>
  summarise(
    flag_count = n(),
    flag_pattern = paste(flag_type, collapse = " --AND-- "),
    .groups = "drop"
  )

table_consistency_flags_unrounded <-
  record_flag_patterns |>
  group_by(flag_count, flag_pattern) |>
  summarise(
    n_records = n_distinct(event_id),
    n_patients = n_distinct(patient_id),
    .groups = "drop"
  ) |>
  bind_rows(
    tibble(
      flag_count = 0L,
      flag_pattern = "No flags",
      n_records = denom_records_initial - n_distinct(record_flag_patterns$event_id),
      n_patients = denom_patients_initial - n_distinct(record_flag_patterns$patient_id)
    )
  ) |>
  mutate(
    denom_records_initial = .env$denom_records_initial,
    denom_patients_initial = .env$denom_patients_initial
  ) |>
  arrange(flag_count, desc(n_records))

table_consistency_flags_rounded <-
  table_consistency_flags_unrounded |>
  mutate(
    across(
      c(n_records, n_patients,
        denom_records_initial, denom_patients_initial),
      ~ roundmid_any(.x, sdc_threshold)
    )
  )

write_csv(
  table_consistency_flags_unrounded,
  fs::path(output_dir_consistency, "count_consistency_flags_unrounded.csv")
)

write_csv(
  table_consistency_flags_rounded,
  fs::path(output_dir_consistency, "count_consistency_flags.csv")
)