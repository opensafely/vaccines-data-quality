# _________________________________________________
# Purpose:
#   This script contains functions used in the COVID-19 vaccination
#   data quality analysis, including:
#     - general utilities
#     - summary table generation
#     - dummy data simulation
# This script should be sourced using: 
# source(here("analysis", "covid", "fn_covid_data_quality.R"))
# _________________________________________________

# 1. General utility functions ----
roundmid_any <- function(x, to = 1) {
  if (to == 0) {
    x
  } else {
    ceiling(x / to) * to - (floor(to / 2) * (x != 0))
  }
}

# 2. Summary table functions ----

# ---- helper A: summary table with total denominator only ----
make_summary_table_total <- function(data, group_vars, round = FALSE, sdc_threshold = NULL) {

  # function to optionally round values
  round_fun <- function(x) {
    if (round) roundmid_any(x, sdc_threshold) else x
  }

  # choose column suffix
  suffix <- if (round) "_midpoint6" else ""

  denom_records_total <- round_fun(nrow(data))
  denom_patients_total <- round_fun(dplyr::n_distinct(data$patient_id))

  out <-
    data |>
    dplyr::group_by(dplyr::across(all_of(group_vars))) |>
    dplyr::summarise(
      n_records = round_fun(dplyr::n()),
      n_patients = round_fun(dplyr::n_distinct(patient_id)),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      denom_records_total = denom_records_total,
      denom_patients_total = denom_patients_total
    )

  # apply suffix if rounding
  if (round) {
    names(out) <- gsub(
      "(n_records|n_patients|denom_records_total|denom_patients_total)$",
      paste0("\\1", suffix),
      names(out)
    )
  }

  out |>
    dplyr::select(all_of(group_vars), dplyr::everything())
}


# ---- helper B: campaign summary with vaccination-date-specific active denominators ----
make_summary_table_vaccination_date_specific_active <- function(
  flag_data,
  event_data,
  registration_data,
  round = FALSE,
  sdc_threshold = NULL
) {

  # function to optionally round values
  round_fun <- function(x) {
    if (round) roundmid_any(x, sdc_threshold) else x
  }

  # choose column suffix
  suffix <- if (round) "_midpoint6" else ""

  # vaccination event data: one row per vaccination event
  event_status_df <-
    event_data |>
    dplyr::mutate(
      vax_date = as.Date(vax_date),
      death_date = as.Date(death_date)
    ) |>
    dplyr::arrange(patient_id, vax_date) |>
    dplyr::mutate(
      event_id = dplyr::row_number()
    ) |>
    dplyr::select(
      event_id,
      patient_id,
      vax_date,
      campaign,
      death_date
    )

  # registration data: one row per registration period
  registration_df <-
    registration_data |>
    dplyr::select(
      patient_id,
      registration_start_date,
      deregistration_date
    ) |>
    dplyr::distinct() |>
    dplyr::mutate(
      registration_start_date = as.Date(registration_start_date),
      deregistration_date = as.Date(deregistration_date)
    )

  # for each vaccination event, check whether vax_date falls within ANY registration interval
  event_active_df <-
    event_status_df |>
    dplyr::left_join(registration_df, by = "patient_id") |>
    dplyr::mutate(
      registered_on_vax_date =
        !is.na(registration_start_date) &
        registration_start_date <= vax_date &
        (is.na(deregistration_date) | deregistration_date >= vax_date),

      active_on_vax_date =
        registered_on_vax_date &
        (is.na(death_date) | death_date >= vax_date)
    ) |>
    dplyr::group_by(event_id, patient_id, vax_date, campaign) |>
    dplyr::summarise(
      active_on_vax_date = any(active_on_vax_date, na.rm = TRUE),
      .groups = "drop"
    )

  # group denominator: patients with >=1 active vaccination record in that campaign
  denom_patients_group_df <-
    event_active_df |>
    dplyr::filter(active_on_vax_date) |>
    dplyr::group_by(campaign) |>
    dplyr::summarise(
      denom_patients_group = round_fun(dplyr::n_distinct(patient_id)),
      .groups = "drop"
    )

  # group denominator: active vaccination records in that campaign
  denom_records_group_df <-
    event_active_df |>
    dplyr::filter(active_on_vax_date) |>
    dplyr::group_by(campaign) |>
    dplyr::summarise(
      denom_records_group = round_fun(dplyr::n()),
      .groups = "drop"
    )

  # numerator
  numerator_df <-
    flag_data |>
    dplyr::group_by(campaign, flag_type) |>
    dplyr::summarise(
      n_records = round_fun(dplyr::n()),
      n_patients = round_fun(dplyr::n_distinct(patient_id)),
      .groups = "drop"
    )

  out <-
    numerator_df |>
    dplyr::left_join(denom_patients_group_df, by = "campaign") |>
    dplyr::left_join(denom_records_group_df, by = "campaign")

  # apply suffix if rounding
  if (round) {
    names(out) <- gsub(
      "(n_records|n_patients|denom_records_group|denom_patients_group)$",
      paste0("\\1", suffix),
      names(out)
    )
  }

  out |>
    dplyr::select(campaign, flag_type, dplyr::everything())
}


# ---- helper C: interval table with group and total denominators ----
make_interval_table <- function(data, group_var, round = FALSE, sdc_threshold = NULL) {

  # function to optionally round values
  round_fun <- function(x) {
    if (round) roundmid_any(x, sdc_threshold) else x
  }

  # choose column suffix
  suffix <- if (round) "_midpoint6" else ""

  denom_records_total <- round_fun(nrow(data))
  denom_patients_total <- round_fun(dplyr::n_distinct(data$patient_id))

  summary_df <-
    data |>
    dplyr::group_by(dplyr::across(all_of(c(group_var, "interval_bin")))) |>
    dplyr::summarise(
      n_records = round_fun(n()),
      n_patients = round_fun(dplyr::n_distinct(patient_id)),
      .groups = "drop"
    )

  denom_df_group <-
    data |>
    dplyr::group_by(dplyr::across(all_of(group_var))) |>
    dplyr::summarise(
      denom_records_group = round_fun(n()),
      denom_patients_group = round_fun(dplyr::n_distinct(patient_id)),
      .groups = "drop"
    )

  out <-
    summary_df |>
    dplyr::left_join(denom_df_group, by = group_var) |>
    dplyr::mutate(
      denom_records_total = denom_records_total,
      denom_patients_total = denom_patients_total
    )

  # apply suffix if rounding
  if (round) {
    names(out) <- gsub(
      "(n_records|n_patients|denom_records_group|denom_patients_group|denom_records_total|denom_patients_total)$",
      paste0("\\1", suffix),
      names(out)
    )
  }

  out |>
    dplyr::select(all_of(group_var), interval_bin, dplyr::everything())
}

# 3. Dummy data functions (for testing only) ----

recalculate_age_from_shift <- function(data) {
  data |>
    group_by(patient_id) |>
    mutate(
      ref_vax_date = min(vax_date),
      ref_age = age[which.min(vax_date)],
      age = pmax(
        0L,
        ref_age + as.integer(lubridate::time_length(lubridate::interval(ref_vax_date, vax_date),"years"))
        )
    ) |>
    ungroup() |>
    select(-ref_vax_date, -ref_age)
}

make_vax_baseline_clean <- function(data, seed = 123) {
  set.seed(seed)

  start_date <- study_dates$start_date
  end_date   <- study_dates$end_date

  valid_products <- unname(vax_product_lookup[names(approval_lookup)])
  valid_dates <- seq(start_date, end_date, by = "day")

  data |>
    mutate(
      vax_product = sample(valid_products, n(), replace = TRUE),
      vax_date = sample(valid_dates, n(), replace = TRUE)
    ) |>
    recalculate_age_from_shift()
}


inject_vax_errors <- function(data, seed = 123) {
  set.seed(seed)
  n_all <- nrow(data)

  remaining <- seq_len(n_all)

  # 0) Expand some patients to create multi-dose structure
  patients_to_expand <- data |>
    distinct(patient_id) |>
    sample_frac(0.3) |>
    pull(patient_id)

  new_rows <- data |>
    filter(patient_id %in% patients_to_expand) |>
    group_by(patient_id) |>
    slice_sample(n = 1) |>
    ungroup() |>
    mutate(
      vax_date = vax_date + sample(30:90, n(), replace = TRUE)
    )

  data <- bind_rows(data, new_rows)

  n_all <- nrow(data)
  remaining <- seq_len(n_all)

  # 1) Implausible early date: vax_date < 2020-04-23
  idx_early <- sample(remaining, max(10, floor(0.02 * n_all)))
  early_dates <- seq(as.Date("2019-01-01"), study_dates$firstpossiblevax_date - 1, by = "day")
  data$vax_date[idx_early] <- sample(early_dates, length(idx_early), replace = TRUE)

  remaining <- setdiff(remaining, idx_early)


  # 2) Pre-rollout (2020-04-23 to 2020-12-07)
  idx_prerollout <- sample(remaining, max(10, floor(0.02 * n_all)))
  prerollout_dates <- seq(study_dates$firstpossiblevax_date, study_dates$start_date - 1, by = "day")
  data$vax_date[idx_prerollout] <- sample(prerollout_dates, length(idx_prerollout), replace = TRUE)

  remaining <- setdiff(remaining, idx_prerollout)


  # 3A) Unapproved product：
  #     product exists in vax_product_lookup but not in approval_lookup
  unapproved_products <- unname(vax_product_lookup[setdiff(names(vax_product_lookup), names(approval_lookup))])
  idx_unapproved <- sample(remaining, min(length(remaining), max(10, floor(0.02 * n_all))))
  data$vax_product[idx_unapproved] <- sample(unapproved_products, length(idx_unapproved), replace = TRUE)

  remaining <- setdiff(remaining, idx_unapproved)


  # 3B) Product before approval:
  #     keep current approved product, move date before approval
  reverse_lookup <- setNames(names(vax_product_lookup), unname(vax_product_lookup))
  idx_pre_approval <- sample(remaining, min(length(remaining), max(10, floor(0.02 * n_all))))
    
  current_short_names <- unname(reverse_lookup[data$vax_product[idx_pre_approval]])
  approval_dates <- as.Date(unname(approval_lookup[current_short_names])) 
  valid_idx <- which(!is.na(approval_dates))
  
  if (length(valid_idx) > 0) {
    data$vax_date[idx_pre_approval[valid_idx]] <- approval_dates[valid_idx] -
      sample(1:30, length(valid_idx), replace = TRUE)
  }

  remaining <- setdiff(remaining, idx_pre_approval)


  # 4) Same-day same-product duplicate
  idx_dup <- sample(remaining, max(8, floor(0.015 * n_all)))

  dup_rows <- data[idx_dup, ]
  data <- bind_rows(data, dup_rows)

  remaining <- setdiff(remaining, idx_dup)


  # 5) Same-day mixed-product records
  #     duplicated row with same patient/date but different product
  # --------------------------------------------------
  idx_mixed <- sample(remaining, min(length(remaining), max(8, floor(0.015 * n_all))))
  mixed_rows <- data[idx_mixed, , drop = FALSE]

  valid_products <- unname(vax_product_lookup)

  mixed_rows$vax_product <- vapply(
    mixed_rows$vax_product,
    function(old_product) {
      sample(setdiff(valid_products, old_product), 1)
    },
    character(1)
  )

  data <- bind_rows(data, mixed_rows)
  remaining <- setdiff(remaining, idx_mixed)

  # 5B) More complex same-day mixed patterns

  idx_complex <- sample(remaining, min(length(remaining), max(5, floor(0.01 * n_all))))
  base_rows <- data[idx_complex, , drop = FALSE]

  valid_products <- unname(vax_product_lookup)


  n_repeat <- sample(2:3, length(idx_complex), replace = TRUE)

  dup_rows <- base_rows[rep(seq_len(nrow(base_rows)), n_repeat), ]

  alt_rows <- base_rows
  alt_rows$vax_product <- vapply(
    alt_rows$vax_product,
    function(old_product) {
      sample(setdiff(valid_products, old_product), 1)
    },
    character(1)
  )

  data <- bind_rows(data, dup_rows, alt_rows)

  remaining <- setdiff(remaining, idx_complex)
  
  # 6) Inject interval patterns across interval bins
  #    Exclude same-day multiple-record combinations

  data <- data |>
    arrange(patient_id, vax_date) |>
    group_by(patient_id, vax_date) |>
    mutate(n_records_day = n()) |>
    ungroup() |>
    arrange(patient_id, vax_date) |>
    group_by(patient_id) |>
    mutate(
      prev_date = lag(vax_date),
      prev_n_records_day = lag(n_records_day)
    ) |>
    ungroup()

  # eligible for interval manipulation:
  # 1) must have a previous vaccination date
  # 2) current day is not same-day multiple
  # 3) previous day is not same-day multiple
  eligible_interval <- which(
    !is.na(data$prev_date) &
      data$n_records_day == 1 &
      data$prev_n_records_day == 1
  )

  # define interval bins and candidate day values
  interval_bin_values <- list(
    `1_6`     = 1:6,
    `7_13`    = 7:13,
    `14_20`    = 14:20,
    `21_29`    = 21:29,
    `30_89`   = 30:89,
    `90_112`  = 90:112,
    `113_179` = 113:179,
    `180_plus` = 180:240
  )

  # decide how many records to inject per bin
  n_per_bin <- min(floor(length(eligible_interval) / length(interval_bin_values)), 10)

  if (n_per_bin > 0) {
    idx_interval <- sample(
      eligible_interval,
      size = n_per_bin * length(interval_bin_values),
      replace = FALSE
    )

    # assign bins equally
    assigned_bins <- rep(names(interval_bin_values), each = n_per_bin)

    # sample one day value from each assigned bin
    sampled_days <- mapply(
      function(bin_name) sample(interval_bin_values[[bin_name]], 1),
      assigned_bins
    )

    # move current vaccination date to prev_date + sampled interval
    data$vax_date[idx_interval] <- data$prev_date[idx_interval] + sampled_days
}

  #successfully tested that unmapped product names are detected and reported in the log.
  ## 7) Inject missing product
  #idx_na <- sample(remaining, min(length(remaining), max(5, floor(0.01 * n_all))))
  #data$vax_product[idx_na] <- "TEST_PRODUCT"
  
  data |>
    select(-n_records_day, -prev_n_records_day, -prev_date) |>
    arrange(patient_id, vax_date) |>
    recalculate_age_from_shift()
}