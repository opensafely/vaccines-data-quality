# _________________________________________________
# purpose:
# import event-level flu vaccination data extracted by ehrql from three sources
# (vaccination table, clinical records, and medicines records)
# and report data quality across sources
#
# outputs (rounded):
# - table 1. flu vaccinations by campaign and data source combination:
#   - table_flu_sources.csv
# - dataset used to produce upset plots (SDC-safe)by campaign:
#   - upset_counts_campaign.csv
# - table 2. Agreement in vaccination date across sources (same day and within 7 days):
#   - table_date_agreement.csv
#________________________________________________

# Preliminaries ----

# Import libraries
library("tidyverse")
library("dtplyr")
library("lubridate")
library("arrow")
library("here")
library("glue")
library("UpSetR")

# Import custom functions
source(here("analysis", "flu", "0_flu_utility_functions.R"))

source(here("analysis", "flu", "0_flu_design.R"))
# create output directory
output_dir <- here("output","outputs_flu", "flu_data_quality")
fs::dir_create(output_dir)

# set output width for capture.output
options(width = 200)

# import design elements

# Import event-level flu vaccination data ----

data_flu_table_raw  <- read_feather(here("output","outputs_flu", "extract_flu", "flu_vaccinations_table.arrow"))
data_flu_snomed_raw <- read_feather(here("output","outputs_flu", "extract_flu", "flu_vaccinations_SNOMED.arrow"))
data_flu_drug_raw   <- read_feather(here("output","outputs_flu", "extract_flu", "flu_vaccinations_drug.arrow"))

# For each source:
# - remove rows where vaccination date is missing
# - attach info about the campaign during which the vaccination was given
# - collapse exact duplicates (same patient_id, vax_date, age)
# - add campaign label and campaign start date based on vaccination date
# - summarise at patient-campaign level: "n_vax", "n_vax_including_exact_duplicates", "vax_dates_list"


# process table / drug /snomed source
processed_flu_table <- process_flu_source(data_flu_table_raw) |>
  mutate(source = "table")

processed_flu_drug <- process_flu_source(data_flu_drug_raw) |>
  mutate(source = "drug")

processed_flu_snomed <- process_flu_source(data_flu_snomed_raw) |>
  mutate(source = "snomed")



# Combine source summaries ----

# Join person-campaign summaries across all three sources
flu_long <- bind_rows(
  processed_flu_table,
  processed_flu_drug,
  processed_flu_snomed
)


# Source combinations by campaign ----
flu_sources <- flu_long |>
  distinct(patient_id, campaign, source) |>
  group_by(patient_id, campaign) |>
  summarise(
    table  = "table" %in% source,
    drug   = "drug" %in% source,
    snomed = "snomed" %in% source,
    source_combination = case_when(
      table & !drug & !snomed ~ "table only",
      !table & drug & !snomed ~ "drug only",
      !table & !drug & snomed ~ "snomed only",
      table & drug & !snomed ~ "table + drug",
      table & !drug & snomed ~ "table + snomed",
      !table & drug & snomed ~ "drug + snomed",
      table & drug & snomed ~ "table + drug + snomed"
    ),
    .groups = "drop"
  )

# Output 1: Table 1. Source combinations by campaign
table_flu_sources <- flu_sources |>
  group_by(campaign, source_combination) |>
  summarise(
    n_source = roundmid_any(n(), sdc_threshold),
    .groups = "drop"
  ) |>
  group_by(campaign) |>
  mutate(
    tot_camp = sum(n_source),
    perc_source = round(n_source / tot_camp * 100, 1),
    n_perc_source = glue("{n_source} ({perc_source}%)")
  ) |>
  ungroup() |>
  arrange(campaign, source_combination)

write_csv(
  table_flu_sources,
  here(output_dir, "table_flu_sources.csv")
)


# Output 2: UpSet plot data (SDC-safe) ----

upset_counts_campaign <- flu_sources |>
  group_by(campaign, table, drug, snomed) |>
  summarise(
    n = roundmid_any(n(), sdc_threshold),
    .groups = "drop"
  )

write_csv(
  upset_counts_campaign,
  here(output_dir, "upset_counts_campaign.csv")
)


# Date agreement across sources by campaign ----
# wide dates dataset
flu_dates <- flu_long |>
  select(patient_id, campaign, source, vax_dates_list) |>
  pivot_wider(
    names_from = source,
    values_from = vax_dates_list
  ) |>
  mutate(
    same_day_table_drug =
      map2_lgl(table, drug, ~ check_date_match(.x, .y, n_days = 0)),
    same_day_table_snomed =
      map2_lgl(table, snomed, ~ check_date_match(.x, .y, n_days = 0)),
    within_7d_table_drug =
      map2_lgl(table, drug, ~ check_date_match(.x, .y, n_days = 7)),
    within_7d_table_snomed =
      map2_lgl(table, snomed, ~ check_date_match(.x, .y, n_days = 7))
  )

# Output 3: Table 2. Summary table for date agreement between vaccination table and
# SNOMED or drug records
# - same-day agreement (0 days difference)
# - agreement within 7 days

table_date_agreement <-
  bind_rows(
    summarise_date_agreement(
      flu_dates,
      same_day_table_drug,
      "Same day: Table vs Drug"
    ),
    summarise_date_agreement(
      flu_dates,
      same_day_table_snomed,
      "Same day: Table vs SNOMED"
    ),
    summarise_date_agreement(
      flu_dates,
      within_7d_table_drug,
      "Within 7 days: Table vs Drug"
    ),
    summarise_date_agreement(
      flu_dates,
      within_7d_table_snomed,
      "Within 7 days: Table vs SNOMED"
    )
  ) |>
  mutate(
    pct = 100 * n / denom,
    n_pct = glue("{n} / {denom} ({round(pct, 1)}%)")
  ) |>
  arrange(campaign, comparison)

write_csv(table_date_agreement,here(output_dir, "table_date_agreement.csv"))