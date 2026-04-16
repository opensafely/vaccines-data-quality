# _________________________________________________
# Purpose:
#   Import event‑level COVID‑19 vaccination data
#   Construct data‑quality flags
#   Output 6 descriptive summary tables
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
library(fs)

# Import custom functions
source(here("analysis", "covid", "fn_covid_data_quality.R"))
source(here("analysis", "covid", "0_covid_design.R"))

# create output directory
output_dir <- here("output", "covid", "covid_data_quality")
fs::dir_create(output_dir)
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
# 2. Prepare dataset 

data_vax_ELD <-
  data_vax_ELD0 |>
  lazy_dt() |>
  arrange(patient_id, vax_date) |>
  # Remove rows where vaccination date is missing
  filter(!is.na(vax_date)) |>   
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
      
    # distinct(.keep_all = TRUE) |> # remove exact duplicates # or use
    # count(patient_id, vax_date, vax_product, age) |> 
    # or alternatively, capture how many duplicate vaccines there are. This creates a new variable `n` counting the duplicates
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



# ---- 3.2 Product approval flags ----
data_vax_ELD <-
  data_vax_ELD |>
  mutate(
    product_chr   = as.character(vax_product),
    approval_date = as.Date(approval_lookup[product_chr]),

    # A: product not found in the approval lookup table
    flag_unapproved_product = !(product_chr %in% names(approval_lookup)),

    # B: product recorded before approval (only if recognised)
    flag_product_before_approval = case_when(
      flag_unapproved_product ~ NA,
      TRUE ~ vax_date < approval_date
    )) |>
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
        patient_id, vax_date,
        total_records_day, n_products_day, product_pattern,
        flag_same_day_multiple,
        flag_same_day_same_product,
        flag_same_day_mixed_product
      ),
    by = c("patient_id", "vax_date")
  ) |>
  as_tibble()


# ---- 3.4 Implausible Intervals Between Consecutive Doses ----
# Campaign stage classification:
# - "Pre-2020-04-23" excluded from interval analysis (not meaningful)
# - "Pre-roll-out" and "Primary series" grouped as "primary"
# - All "Spring XXXX" and "Autumn XXXX" campaigns grouped as "booster"
#
# This allows interval analysis to focus on:
# - within primary series intervals
# - transitions from primary to booster
# - intervals within and between booster campaigns
data_vax_interval <-
  data_vax_ELD |>
  filter(campaign != "Pre-2020-04-23") |>
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
      campaign %in% c("Pre-roll-out", "Primary series") ~ "primary",
      grepl("Spring|Autumn", campaign) ~ "booster",
      TRUE ~ NA_character_
    ),

    prev_campaign_stage = case_when(
      prev_campaign %in% c("Pre-roll-out", "Primary series") ~ "primary",
      grepl("Spring|Autumn", prev_campaign) ~ "booster",
      TRUE ~ NA_character_
    ),

     interval_context = case_when(
      prev_campaign_stage == "primary" & campaign_stage == "primary" ~ "within_primary",
      prev_campaign_stage == "primary" & campaign_stage == "booster" ~ "primary_to_booster",
      prev_campaign_stage == "booster" & campaign_stage == "booster" & prev_campaign == campaign ~ "within_booster_campaign",
      prev_campaign_stage == "booster" & campaign_stage == "booster" & prev_campaign != campaign ~ "between_booster_campaigns",
      TRUE ~ NA_character_
    ),

    campaign_transition_type = paste0(prev_campaign, " -> ", campaign),
    product_transition_type  = paste0(prev_product, " -> ", vax_product)
  ) |>
  select(
    patient_id,
    prev_date,
    vax_date,
    prev_product,
    vax_product,
    prev_campaign,
    campaign,
    prev_campaign_stage,
    campaign_stage,
    interval_days,
    interval_bin,
    interval_context,
    campaign_transition_type,
    product_transition_type
  )

# 4. Convert to long-format flag table (non-interval)

# ---- Non-interval flags ----
flag_long_noninterval <-
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


# 5. Output: descriptive summary tables
# 2 version: unrounded + rounded
# we can look on L4 to see if rounding has introduced any issues

# ---- Table 1: Overall summary of non-interval flags ----
table_overall_noninterval_flags_unrounded <-
  make_summary_table_total_unrounded(
    data = flag_long_noninterval,
    group_vars = c("flag_type")
  ) |>
  arrange(flag_type)

table_overall_noninterval_flags_rounded <-
  make_summary_table_total_rounded(
    data = flag_long_noninterval,
    group_vars = c("flag_type")
  ) |>
  arrange(flag_type)

write_csv(
  table_overall_noninterval_flags_unrounded,
  fs::path(output_dir, "count_overall_noninterval_flags_unrounded.csv")
)

write_csv(
  table_overall_noninterval_flags_rounded,
  fs::path(output_dir, "count_overall_noninterval_flags.csv")
)


# ---- Table 2: Campaign summary of non-interval flags with campaign-specific alive denominators ----
table_campaign_noninterval_flags_unrounded <-
  make_summary_table_campaign_alive_unrounded(
    flag_data = flag_long_noninterval,
    event_data = data_vax_ELD
  ) |>
  arrange(campaign, flag_type)

table_campaign_noninterval_flags_rounded <-
  make_summary_table_campaign_alive_rounded(
    flag_data = flag_long_noninterval,
    event_data = data_vax_ELD
  ) |>
  arrange(campaign, flag_type)

write_csv(
  table_campaign_noninterval_flags_unrounded,
  fs::path(output_dir, "count_campaign_noninterval_flags_unrounded.csv")
)

write_csv(
  table_campaign_noninterval_flags_rounded,
  fs::path(output_dir, "count_campaign_noninterval_flags.csv")
)


# ---- Table 3: Product summary of non-interval flags ----
table_product_noninterval_flags_unrounded <-
  make_summary_table_total_unrounded(
    data = flag_long_noninterval,
    group_vars = c("vax_product", "flag_type")
  ) |>
  arrange(vax_product, flag_type)

table_product_noninterval_flags_rounded <-
  make_summary_table_total_rounded(
    data = flag_long_noninterval,
    group_vars = c("vax_product", "flag_type")
  ) |>
  arrange(vax_product, flag_type)

write_csv(
  table_product_noninterval_flags_unrounded,
  fs::path(output_dir, "count_product_noninterval_flags_unrounded.csv")
)

write_csv(
  table_product_noninterval_flags_rounded,
  fs::path(output_dir, "count_product_noninterval_flags.csv")
)


# ---- Table 4: interval context x interval bin ----
table_interval_context_unrounded <-
  make_interval_table_unrounded(
    data = data_vax_interval,
    group_var = "interval_context"
  ) |>
  arrange(interval_context, interval_bin)

table_interval_context_rounded <-
  make_interval_table_rounded(
    data = data_vax_interval,
    group_var = "interval_context"
  ) |>
  arrange(interval_context, interval_bin)

write_csv(
  table_interval_context_unrounded,
  fs::path(output_dir, "count_interval_context_unrounded.csv")
)

write_csv(
  table_interval_context_rounded,
  fs::path(output_dir, "count_interval_context.csv")
)


# ---- Table 5: campaign transition type x interval bin ----
table_interval_campaign_transition_unrounded <-
  make_interval_table_unrounded(
    data = data_vax_interval,
    group_var = "campaign_transition_type"
  ) |>
  arrange(campaign_transition_type, interval_bin)

table_interval_campaign_transition_rounded <-
  make_interval_table_rounded(
    data = data_vax_interval,
    group_var = "campaign_transition_type"
  ) |>
  arrange(campaign_transition_type, interval_bin)

write_csv(
  table_interval_campaign_transition_unrounded,
  fs::path(output_dir, "count_interval_campaign_transition_unrounded.csv")
)

write_csv(
  table_interval_campaign_transition_rounded,
  fs::path(output_dir, "count_interval_campaign_transition.csv")
)


# ---- Table 6: product transition type x interval bin ----
table_interval_product_transition_unrounded <-
  make_interval_table_unrounded(
    data = data_vax_interval,
    group_var = "product_transition_type"
  ) |>
  arrange(product_transition_type, interval_bin)

table_interval_product_transition_rounded <-
  make_interval_table_rounded(
    data = data_vax_interval,
    group_var = "product_transition_type"
  ) |>
  arrange(product_transition_type, interval_bin)

write_csv(
  table_interval_product_transition_unrounded,
  fs::path(output_dir, "count_interval_product_transition_unrounded.csv")
)

write_csv(
  table_interval_product_transition_rounded,
  fs::path(output_dir, "count_interval_product_transition.csv")
)