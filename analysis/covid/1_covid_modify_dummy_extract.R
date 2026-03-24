library(arrow)
library(dplyr)
library(here)
library(fs)

source(here("analysis", "covid", "0_covid_design.R"))

# this script should only be run locally / on dummy data
localrun <- Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")

# input / output paths
in_path  <- here("output", "outputs_covid", "extract_covid", "vaccinations.arrow")
out_dir  <- here("output", "outputs_covid", "modify_dummy_extract")
out_path <- fs::path(out_dir, "vaccinations.arrow")

fs::dir_create(out_dir)


inject_vax_errors <- function(data, seed = 123) {
  set.seed(seed)

  # use harmonised product names
  data <- data |>
    mutate(
      vax_product_raw = vax_product,
      vax_product = dplyr::recode(vax_product, !!!vax_product_lookup)
    )

  # pick a few common products to use when injecting errors
  pfizer_vals  <- grep("Pfizer|pfizer", vax_product_lookup, value = TRUE)
  az_vals      <- grep("AstraZeneca|AZ|az", vax_product_lookup, value = TRUE)
  moderna_vals <- grep("Moderna|moderna", vax_product_lookup, value = TRUE)

  any_pfizer  <- pfizer_vals[1]
  any_az      <- az_vals[1]
  any_moderna <- moderna_vals[1]

  n_all <- nrow(data)

  # --------------------------------------------------
  # 1) clearly implausible early dates (< 2020-07-01)
  # --------------------------------------------------
  idx_early <- sample(seq_len(n_all), min(n_all, max(10, floor(0.015 * n_all))))
  data$vax_date[idx_early] <- as.Date("2019-06-01")
  data$vax_product[idx_early] <- any_pfizer

  # --------------------------------------------------
  # 2) pre-rollout dates (2020-07-01 to 2020-12-07)
  # --------------------------------------------------
  remaining <- setdiff(seq_len(n_all), idx_early)
  idx_prerollout <- sample(
    remaining,
    min(length(remaining), max(10, floor(0.015 * n_all)))
  )

  if (length(idx_prerollout) > 0) {
    data$vax_date[idx_prerollout] <- as.Date("2020-10-01")
    data$vax_product[idx_prerollout] <- any_pfizer
  }

  # --------------------------------------------------
  # 3) product before approval
  # --------------------------------------------------
  remaining <- setdiff(remaining, idx_prerollout)

  idx_pfizer_pre <- sample(
    remaining,
    min(length(remaining), max(8, floor(0.01 * n_all)))
  )
  remaining <- setdiff(remaining, idx_pfizer_pre)

  idx_az_pre <- sample(
    remaining,
    min(length(remaining), max(8, floor(0.01 * n_all)))
  )
  remaining <- setdiff(remaining, idx_az_pre)

  idx_moderna_pre <- sample(
    remaining,
    min(length(remaining), max(8, floor(0.01 * n_all)))
  )

  if (length(idx_pfizer_pre) > 0) {
    data$vax_date[idx_pfizer_pre] <- as.Date("2020-11-01")
    data$vax_product[idx_pfizer_pre] <- any_pfizer
  }

  if (length(idx_az_pre) > 0) {
    data$vax_date[idx_az_pre] <- as.Date("2020-12-01")
    data$vax_product[idx_az_pre] <- any_az
  }

  if (length(idx_moderna_pre) > 0) {
    data$vax_date[idx_moderna_pre] <- as.Date("2020-12-15")
    data$vax_product[idx_moderna_pre] <- any_moderna
  }

  # recalculate previous record after date changes
  data <- data |>
    arrange(patient_id, vax_date) |>
    group_by(patient_id) |>
    mutate(
      prev_date = lag(vax_date),
      prev_product = lag(vax_product)
    ) |>
    ungroup()

  # --------------------------------------------------
  # 4) short intervals
  # --------------------------------------------------
  eligible_short <- which(!is.na(data$prev_date))
  idx_short <- sample(
    eligible_short,
    min(length(eligible_short), max(10, floor(0.03 * length(eligible_short))))
  )

  if (length(idx_short) > 0) {
    data$vax_date[idx_short] <- data$prev_date[idx_short] +
      sample(c(1, 3, 7, 10), length(idx_short), replace = TRUE)
  }

  # recalculate previous record again
  data <- data |>
    arrange(patient_id, vax_date) |>
    group_by(patient_id) |>
    mutate(
      prev_date = lag(vax_date),
      prev_product = lag(vax_product)
    ) |>
    ungroup()

  # --------------------------------------------------
  # 5) same-day same-product duplicates
  # --------------------------------------------------
  eligible_same_day <- which(!is.na(data$prev_date) & !is.na(data$prev_product))
  idx_same_product <- sample(
    eligible_same_day,
    min(length(eligible_same_day), max(8, floor(0.015 * length(eligible_same_day))))
  )

  if (length(idx_same_product) > 0) {
    data$vax_date[idx_same_product] <- data$prev_date[idx_same_product]
    data$vax_product[idx_same_product] <- data$prev_product[idx_same_product]
  }

  # --------------------------------------------------
  # 6) same-day mixed-product records
  # --------------------------------------------------
  eligible_mixed <- setdiff(eligible_same_day, idx_same_product)
  idx_mixed <- sample(
    eligible_mixed,
    min(length(eligible_mixed), max(8, floor(0.015 * length(eligible_mixed))))
  )

  if (length(idx_mixed) > 0) {
    data$vax_date[idx_mixed] <- data$prev_date[idx_mixed]
    data$vax_product[idx_mixed] <- ifelse(
      data$prev_product[idx_mixed] == any_pfizer,
      any_moderna,
      any_pfizer
    )
  }

  # --------------------------------------------------
  # 7) add a few extra duplicated rows
  # --------------------------------------------------
  dup_same <- data[idx_same_product[seq_len(min(10, length(idx_same_product)))], , drop = FALSE]
  dup_mixed <- data[idx_mixed[seq_len(min(10, length(idx_mixed)))], , drop = FALSE]

  if (nrow(dup_same) > 0) {
    data <- bind_rows(data, dup_same)
  }

  if (nrow(dup_mixed) > 0) {
    dup_mixed_extra <- dup_mixed
    dup_mixed_extra$vax_product <- ifelse(
      dup_mixed_extra$vax_product == any_pfizer,
      any_az,
      any_pfizer
    )
    data <- bind_rows(data, dup_mixed_extra)
  }

  data |>
    select(-vax_product_raw, -prev_date, -prev_product) |>
    arrange(patient_id, vax_date)
}


data <- read_feather(in_path)

if (localrun) {
  data <- data |>
    mutate(
      vax_date = as.Date(runif(
        n(),
        as.Date("2021-01-01"),
        max(campaign_info$early_milestone_date)
      ), origin = "1970-01-01"),
      vax_product = sample(vax_product_lookup, n(), replace = TRUE)
    ) |>
    inject_vax_errors()
}

write_feather(data, out_path)