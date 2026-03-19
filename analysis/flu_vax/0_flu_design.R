# _________________________________________________
# Purpose:
# define useful functions used in the codebase
# define key design features for the study
# define some look up tables to use in the codebase
# this script should be sourced (using `source(here("analysis", "flu_vax", "0_flu_design.R"))`) at the start of each R script
# _________________________________________________

library("tidyverse")
library("lubridate")
library("here")

# utility functions ----

roundmid_any <- function(x, to = 1) {
  # like ceiling_any, but centers on (integer) midpoint of the rounding points
  if (to == 0) {
    x
  } else {
    ceiling(x / to) * to - (floor(to / 2) * (x != 0))
  }
}

round_any <- function(x, to = 1) {
  if (to == 0) {
    x
  } else {
    if_else(x != 5, plyr::round_any(x, accuracy = to), 0)
  }
}

# Design elements ----

# key study dates
# The dates are saved in json format so they can be read in by R and python scripts
# - firstpossiblevax_date is the date from which we want to identify covid vaccines. the mass vax programme was 8 Dec 2020 but other people were vaccinated earlier in trials, so want to pick these people up too (and possibly exclude them)
# - start_date is when we start the observational period proper, at the start of the mass vax programme
# - end_date is when we stop the observation period. This may be extended as the study progresses

# statistical disclosure control rounding precision
sdc_threshold <- 10

# create flu study dates json
study_dates_flu <-
  list(
    firstpossiblevax_date = "2009-10-01",
    start_date = "2020-10-01",
    end_date = "2026-03-31"
  ) |>
  lapply(as.Date)

# make these available in the global environment
# so we don't have to use `study_dates$start_date` or `start_date <- study_dates$start_date` in each script
# list2env(study_dates, globalenv())


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

  # Local run flag ----
# is this script being run locally, and if so do we need to output objects to be picked up by ehrQL scripts

localrun <- Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")

output_dir <- here("output/outputs_flu")
fs::dir_create(output_dir)

if (localrun) {

  jsonlite::write_json(
    study_dates_flu,
    path = here::here("output","outputs_flu", "study_dates_flu.json"),
    pretty = TRUE, auto_unbox = TRUE
  )

  jsonlite::write_json(
    split(campaign_info_flu, f = campaign_info_flu$campaign_start_date) |> lapply(as.list),
    path = here::here("output","outputs_flu", "campaign_info_flu.json"),
    pretty = TRUE, auto_unbox = TRUE,
  )
}