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


make_vax_baseline_clean <- function(data, seed = 123) {
  set.seed(seed)

  start_date <- as.Date("2020-12-08")
  end_date   <- as.Date("2026-03-24")

  short_names <- names(approval_lookup)
  valid_dates <- seq(start_date, end_date, by = "day")

  data |>
    mutate(
      vax_product_short = sample(short_names, n(), replace = TRUE),

      vax_product = dplyr::recode(
        vax_product_short,
        !!!vax_product_lookup,
        .default = NA_character_
      ),

      vax_date = sample(valid_dates, n(), replace = TRUE)
    )
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
  early_dates <- seq(as.Date("2019-01-01"), as.Date("2020-04-22"), by = "day")
  data$vax_date[idx_early] <- sample(early_dates, length(idx_early), replace = TRUE)

  remaining <- setdiff(remaining, idx_early)


  # 2) Pre-rollout (2020-04-23 to 2020-12-07)
  idx_prerollout <- sample(remaining, max(10, floor(0.02 * n_all)))
  prerollout_dates <- seq(as.Date("2020-04-23"), as.Date("2020-12-07"), by = "day")
  data$vax_date[idx_prerollout] <- sample(prerollout_dates, length(idx_prerollout), replace = TRUE)

  remaining <- setdiff(remaining, idx_prerollout)


  # 3A) Unapproved product：
  #     product exists in vax_product_lookup but not in approval_lookup
  unapproved_products <- setdiff(names(vax_product_lookup), names(approval_lookup))
  idx_unapproved <- sample(remaining, min(length(remaining), max(10, floor(0.02 * n_all))))
  chosen_unapproved <- sample(unapproved_products, length(idx_unapproved), replace = TRUE)
  
  data$vax_product_short[idx_unapproved] <- chosen_unapproved
  data$vax_product[idx_unapproved] <- dplyr::recode(
    chosen_unapproved,
    !!!vax_product_lookup)

  remaining <- setdiff(remaining, idx_unapproved)


  # 3B) Product before approval:
  #     keep current approved product, move date before approval
  idx_pre_approval <- sample(
    remaining,
    min(length(remaining), max(10, floor(0.02 * n_all)))
    )
    
  approval_dates <- as.Date(unname(approval_lookup[data$vax_product_short[idx_pre_approval]]))
  
  data$vax_date[idx_pre_approval] <- approval_dates -
    sample(1:30, length(idx_pre_approval), replace = TRUE)

  remaining <- setdiff(remaining, idx_pre_approval)


  # 4) Same-day same-product duplicate
  idx_dup <- sample(remaining, max(8, floor(0.015 * n_all)))

  dup_rows <- data[idx_dup, ]
  data <- bind_rows(data, dup_rows)

  remaining <- setdiff(remaining, idx_dup)


  # 5) Same-day mixed product
  idx_mixed <- sample(remaining, max(8, floor(0.015 * n_all)))

  mixed_rows <- data[idx_mixed, ]

  # 5) Same-day mixed-product records
  #     duplicated row with same patient/date but different product
  # --------------------------------------------------
  idx_mixed <- sample(remaining, min(length(remaining), max(8, floor(0.015 * n_all))))
  mixed_rows <- data[idx_mixed, , drop = FALSE]

  valid_products <- names(vax_product_lookup)

  mixed_rows$vax_product_short <- vapply(
    mixed_rows$vax_product_short,
    function(old_product) {
      sample(setdiff(valid_products, old_product), 1)
    },
    character(1)
  )

  mixed_rows$vax_product <- dplyr::recode(
    mixed_rows$vax_product_short,
    !!!vax_product_lookup,
  )

  data <- bind_rows(data, mixed_rows)


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
  `14_29`   = 14:29,
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

data |>
  select(-n_records_day, -prev_n_records_day, -prev_date) |>
  arrange(patient_id, vax_date)
}

data <- read_feather(in_path)

if (localrun) {
  data <- data |>
    make_vax_baseline_clean(seed = 123) |>
    inject_vax_errors(seed = 123)
}

write_feather(data, out_path)