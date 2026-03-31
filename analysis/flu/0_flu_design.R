# _________________________________________________
# Purpose:
# define key design features for the study
# this script should be sourced (using `source(here("analysis", "flu", "0_flu_design.R"))`) at the start of each R script
# _________________________________________________

#Libraries
library("tidyverse")
library("lubridate")
library("here")
library("jsonlite")
library("here")
library("fs")

# create output directory
output_dir <- here("output","outputs_flu", "design_elements")
dir_create(output_dir)

# Design elements ----

# key study dates
# The dates are saved in json format so they can be read in by R and python scripts
# - firstpossiblevax_date is the date from which we want to identify flu vaccines (2005 is the first year for which primary care data are available in OpenSAFELY).
# - start_date is when we start the observational period proper
# - end_date is when we stop the observation period. This may be extended as the study progresses

# statistical disclosure control rounding precision
sdc_threshold <- 10

# create flu study dates json
study_dates_flu <-
  list(
    firstpossiblevax_date = "2005-10-01",
    start_date = "2020-10-01",
    end_date = "2026-03-31"
  ) |>
  lapply(as.Date)

write_json(
  study_dates_flu,
  here(output_dir, "study_dates_flu.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)

# Flu vaccine campaign dates -------------

# define years we want
years <- 2020:2025

# create campaign flu table
campaign_info_flu <-
  tibble(year = years) %>%
  mutate(
    campaign_label = paste0("Autumn ", year),
    campaign_start_date = ymd(paste0(year, "-09-01")),
    early_milestone_date = ymd(paste0(year, "-11-30")),
    primary_milestone_date = ymd(paste0(year + 1, "-03-31")),
    age_date = ymd(paste0(year + 1, "-03-31"))
  ) %>%
  bind_rows(
    tibble(
      campaign_label = "Pre-2020",
      campaign_start_date = ymd("1900-01-01"),
      early_milestone_date = ymd("1900-01-01"),
      primary_milestone_date = ymd("1900-01-01"),
      age_date = ymd("1900-01-01")
    )
  ) %>%
  arrange(campaign_start_date) |>
  mutate(
    across(c(campaign_start_date, primary_milestone_date, age_date), as.Date),
  #  early_milestone_date = campaign_start_date + (7 * 8) - 1, # end of eighth week after campaign_start_date
    final_milestone_date = lead(campaign_start_date, 1, as.Date("2026-02-01")) - 1 # day before next campaign date (or some arbitrary future date if last campaign)
  )  |>
  mutate(
    early_milestone_days = as.integer(early_milestone_date - campaign_start_date) + 1L,
    primary_milestone_days = as.integer(primary_milestone_date - campaign_start_date) + 1L,
    final_milestone_days = as.integer(final_milestone_date - campaign_start_date) + 1L
  )
write_json(
  campaign_info_flu,
  here(output_dir, "campaign_info_flu.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)

#   # Local run flag ----
# # is this script being run locally, and if so do we need to output objects to be picked up by ehrQL scripts

# localrun <- Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")

# output_dir <- here("analysis/flu")
# fs::dir_create(output_dir)

# if (localrun) {

#   jsonlite::write_json(
#     study_dates_flu,
#     path = here::here("analysis", "flu", "study_dates_flu.json"),
#     pretty = TRUE, auto_unbox = TRUE
#   )

#   jsonlite::write_json(
#     split(campaign_info_flu, f = campaign_info_flu$campaign_start_date) |> lapply(as.list),
#     path = here::here("analysis", "flu", "campaign_info_flu.json"),
#     pretty = TRUE, auto_unbox = TRUE,
#   )
# }

