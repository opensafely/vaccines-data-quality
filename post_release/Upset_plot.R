# _________________________________________________
# purpose:
# read aggregated rounded counts of flu vaccine source combinations
# and generate UpSet plots by campaign
#________________________________________________

# Preliminaries ----

# Import libraries
library("tidyverse")
library("here")
library("UpSetR")

# Import aggregated UpSet counts ----
upset_counts_campaign <- read_csv(
  here("output", "outputs_flu", "flu_data_quality", "upset_counts_campaign.csv")
)

# Reconstruct row-level input for UpSetR ----
upset_plot_data <- upset_counts_campaign |>
  uncount(n) |>
  mutate(
    across(c(table, drug, snomed), as.integer)
  ) |>
  as.data.frame()

# Identify campaigns to plot ----
campaigns <- unique(upset_plot_data$campaign)

# Generate one UpSet plot per campaign ----

for (camp in campaigns) {

  plot_data <- upset_plot_data %>%
    filter(campaign == camp) %>%
    select(table, drug, snomed) %>%
    as.data.frame()

  p <- upset(
    plot_data,
    sets = c("table", "drug", "snomed"),
    sets.bar.color = "grey40",
    order.by = "freq",
    main.bar.color = "grey20",
    text.scale = 1.2,
    mainbar.y.label = paste("intersection count -", camp),
    sets.x.label = "people in each source"
  )
  dev.off()
  print(p)
}