# _________________________________________________
# Purpose:
# define useful functions used in the codebase
# this script should be sourced (using `source(here("analysis", "flu", "0_flu_utility_functions.R"))`) at the start of each R script
# _________________________________________________

# utility functions ----

roundmid_any <- function(x, to = 1) {
  # like ceiling_any, but centers on (integer) midpoint of the rounding points
  if (to == 0) {
    x
  } else {
    ceiling(x / to) * to - (floor(to / 2) * (x != 0))
  }
}


# campaign functions -----
# Add campaign label based on vaccination date
add_campaign_vars <- function(data) {
  data |>
    mutate(
      campaign = cut(
        vax_date,
        breaks = c(campaign_info_flu$campaign_start_date, as.Date(Inf)),
        labels = campaign_info_flu$campaign_label
      ),
      campaign = factor(
        as.character(campaign),
        levels = unique(campaign_info_flu$campaign_label)
      )
      )
}

# Process one flu vaccination source:
# - remove missing vaccination dates
# - collapse exact duplicates
# - attach campaign info
# - create person-campaign summary
process_flu_source <- function(data) {
  data |>
    lazy_dt() |>
    arrange(patient_id, vax_date) |>
    filter(!is.na(vax_date)) |>
    count(patient_id, vax_date, age) |>
    as_tibble() |>
    add_campaign_vars() |>
    group_by(patient_id, campaign) |>
    # Summarise one source at person-campaign level
    summarise(
      !!paste0("n_vax") := n(),
      !!paste0("n_vax_including_exact_duplicates") := sum(n),
      !!paste0("vax_dates_list") := list(sort(unique(vax_date))),
      .groups = "drop"
    ) |>
    arrange(patient_id, campaign)
}

# Check date differences between sources
check_date_match <- function(dates1, dates2, n_days = 0) {
  # comparisons where one or both sources are missing are set to NA
  if (length(dates1) == 0 || length(dates2) == 0) {
    return(NA)
  }
  if (n_days == 0) {
    any(dates1 %in% dates2)
  } else {
    any(abs(outer(dates1, dates2, "-")) <= n_days)
  }
}

# Summarise date of agreement same day and within 7 days by campaign
# - counts number of TRUE matches (n)
# - uses only comparisons where both sources are present as denominator
# - applies SDC rounding

summarise_date_agreement <- function(data, match_var, comparison_label) {
  data |>
    group_by(campaign) |>
    summarise(
      comparison = comparison_label,
      n = roundmid_any(sum({{ match_var }}, na.rm = TRUE), sdc_threshold),
      denom = roundmid_any(sum(!is.na({{ match_var }})), sdc_threshold),
      .groups = "drop"
    )
}