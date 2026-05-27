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
      ),
      age_date = campaign_info_flu$age_date[
        match(campaign, campaign_info_flu$campaign_label)
      ],
      age = if_else(
        campaign == "Pre-2018",
        NA_real_,
        floor(time_length(interval(birth_date, age_date), "years"))
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
    count(patient_id, vax_date, birth_date) |>
    as_tibble() |>
    add_campaign_vars() |>
    group_by(patient_id, campaign, age) |>
    # Summarise one source at person-campaign level
    summarise(
      !!paste0("n_vax") := n(),
      !!paste0("n_vax_including_exact_duplicates") := sum(n),
      !!paste0("vax_dates_list") := list(sort(unique(vax_date))),
      .groups = "drop"
    ) |>
    mutate(
      ageband4 = cut(
        age,
        breaks = c(-Inf, 12, 50, 65, 75, 105, Inf),
        labels = c("under 12", "12-49", "50-64", "65-74", "75-104", "105+"), # under 12 and 105+ should be excluded in analysis but include here to ensure nobody slipped through the net
        right = FALSE
      ) ,
      # ageband13 = cut(
      #   age,
      #   breaks = c(-Inf, 12, 18, 30, 40, 50, 55, 60, 65, 70, 75, 80, 85, 90, 105, Inf),
      #   labels = c("under 12", "12-17", "18-29", "30-39", "40-49", "50-54", "55-59", "60-64", "65-69", "70-74", "75-79", "80-84", "85-89", "90-104", "105+"), # under 12 and 105+ should be excluded in analysis but include here to ensure nobody slipped through the net
      #   right = FALSE
      # )
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