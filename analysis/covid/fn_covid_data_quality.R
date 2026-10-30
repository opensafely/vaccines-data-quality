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

# ---- helper A: overall consistency summary ----

make_summary_table_total <- function(
  data, group_vars,
  denom_records_initial, denom_patients_initial
) {

  data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_vars))) |>
    dplyr::summarise(
      n_records = dplyr::n_distinct(event_id),
      n_patients = dplyr::n_distinct(patient_id),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      denom_records_total = .env$denom_records_initial,
      denom_patients_total = .env$denom_patients_initial
    ) |>
    dplyr::select(dplyr::all_of(group_vars), dplyr::everything())
}


# ---- helper B: flag distribution by campaign and product ----

make_summary_table_consistency_product <- function(data, flag_name) {

  flagged_data <-
    data |>
    dplyr::filter(flag_type == flag_name)

  # Campaign-level denominators
  denominators <-
    flagged_data |>
    dplyr::group_by(campaign) |>
    dplyr::summarise(
      denom_records_flag = dplyr::n_distinct(event_id),
      denom_patients_flag = dplyr::n_distinct(patient_id),
      .groups = "drop"
    )

  # Campaign-product numerators
  flagged_data |>
    dplyr::group_by(campaign, vax_product) |>
    dplyr::summarise(
      n_records = dplyr::n_distinct(event_id),
      n_patients = dplyr::n_distinct(patient_id),
      .groups = "drop"
    ) |>
    dplyr::left_join(denominators, by = "campaign") |>
    dplyr::arrange(campaign, dplyr::desc(n_records))
}

# ---- helper C: interval table with group and total denominators ----

make_interval_table <- function(data, group_vars) {

  denom_intervals_total <- nrow(data)
  denom_patients_total <- dplyr::n_distinct(data$patient_id)

  summary_df <-
    data |>
    dplyr::group_by(
      dplyr::across(dplyr::all_of(c(group_vars, "interval_bin")))
    ) |>
    dplyr::summarise(
      n_intervals = dplyr::n(),
      n_patients = dplyr::n_distinct(patient_id),
      .groups = "drop"
    )

  denom_df_group <-
    data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_vars))) |>
    dplyr::summarise(
      denom_intervals_group = dplyr::n(),
      denom_patients_group = dplyr::n_distinct(patient_id),
      .groups = "drop"
    )

  out <-
    summary_df |>
    dplyr::left_join(denom_df_group, by = group_vars) |>
    dplyr::mutate(
      denom_intervals_total = .env$denom_intervals_total,
      denom_patients_total = .env$denom_patients_total
    )

  out |>
    dplyr::select(
      dplyr::all_of(group_vars),
      interval_bin,
      dplyr::everything()
    )
}


# ---- helper D: Split files ----
write_csv_split_by <- function(data,
                               split_var,
                               output_dir,
                               file_prefix) {

  if (split_var == "campaign") {
    data <-
      data |>
      dplyr::mutate(
        campaign_group = dplyr::case_when(
          campaign == "Autumn 2021" ~ "campaign_group_2021",
          campaign %in% c("Spring 2022", "Autumn 2022") ~ "campaign_group_2022",
          campaign %in% c("Spring 2023", "Autumn 2023") ~ "campaign_group_2023",
          campaign %in% c("Spring 2024", "Autumn 2024") ~ "campaign_group_2024",
          campaign %in% c("Spring 2025", "Autumn 2025") ~ "campaign_group_2025",
          TRUE ~ "campaign_group_pre_primary"
        )
      )

    message("Campaign groups:")
    data |>
      dplyr::count(campaign_group, campaign, name = "n_rows") |>
      print(n = Inf)
  }

  if (split_var == "campaign") {
    split_data <- split(data, data$campaign_group)
    } else {
      split_data <- split(data, data[[split_var]])
  }


  purrr::iwalk(
    split_data,
    ~ {
      safe_name <- .y |>
        stringr::str_to_lower() |>
        stringr::str_replace_all("[^a-z0-9]+", "_") |>
        stringr::str_replace_all("^_|_$", "")

      readr::write_csv(
        .x,
        fs::path(
          output_dir,
          paste0(file_prefix, "_", safe_name, ".csv")
        )
      )
    }
  )
}

# ---- helper E: consistency flag count summary ----

make_flag_count_table <- function(flag_data, level, denominator) {

  id_var <- if (level == "record") "event_id" else "patient_id"
  count_var <- if (level == "record") "n_records" else "n_patients"
  denom_var <- if (level == "record") "denom_records_initial" else "denom_patients_initial"

  flag_counts <-
    flag_data |>
    dplyr::distinct(dplyr::across(dplyr::all_of(c(id_var, "flag_type")))) |>
    dplyr::count(dplyr::across(dplyr::all_of(id_var)), name = "flag_count")

  out <-
    flag_counts |>
    dplyr::count(flag_count, name = count_var)

  n_zero <- denominator - sum(out[[count_var]])

  dplyr::bind_rows(
    tibble::tibble(flag_count = 0L, !!count_var := n_zero),
    out
  ) |>
    dplyr::mutate(!!denom_var := denominator) |>
    dplyr::arrange(flag_count)
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
  
# Recalculate age after shifting vaccination dates
data <-
  data |>
  select(-n_records_day, -prev_n_records_day, -prev_date) |>
  arrange(patient_id, vax_date) |>
  recalculate_age_from_shift()

# NEW: Missing vaccination dates
idx_missing <- sample(
  seq_len(nrow(data)),
  size = min(10, nrow(data))
)

data$vax_date[idx_missing] <- as.Date(NA)

return(data)
}

