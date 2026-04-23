# _________________________________________________
# Purpose:
# define key design features for the study
# define some look up tables to use in the codebase
# this script should be sourced using:
# source(here("analysis", "covid", "0_covid_design.R"))
# _________________________________________________

library("tidyverse")

# Design elements ----

# key study dates
# - firstpossiblevax_date is the date from which we want to identify covid vaccines. the mass vax programme was 8 Dec 2020 but other people were vaccinated earlier in trials, so want to pick these people up too (and possibly exclude them)
# - start_date is when we start the observational period proper, at the start of the mass vax programme
# - end_date is when we stop the observation period. This may be extended as the study progresses

study_dates <-
  list(
    firstpossiblevax_date = "2020-04-23",
    start_date = "2020-12-08",
    end_date = "2026-12-31"
  ) |>
  lapply(as.Date)

# make these available in the global environment
# so we don't have to use `study_dates$start_date` or `start_date <- study_dates$start_date` in each script
# list2env(study_dates, globalenv())

# statistical disclosure control rounding precision
sdc_threshold <- 10

# covid-19 vaccine campaign dates
campaign_info <-
  tribble(
    ~campaign_label,        ~campaign_start_date,      ~primary_milestone_date, ~age_date, ~age_threshold, ~clinical_priority,
    "Pre-2020-04-23", "1900-01-01", "1900-01-01", "1900-01-01", 16, "primis_atrisk",
    "Pre-roll-out",   as.character(study_dates$firstpossiblevax_date), as.character(study_dates$firstpossiblevax_date), as.character(study_dates$firstpossiblevax_date), 16, "primis_atrisk",
    "Primary series", "2020-12-08", "2021-06-30", "2021-03-31", 16, "primis_atrisk",
    "Autumn 2021",    "2021-09-06", "2022-02-28", "2021-08-31", 16, "primis_atrisk",
    "Spring 2022",    "2022-03-21", "2022-06-30", "2022-06-30", 75, "immunosuppressed",
    "Autumn 2022",    "2022-08-29", "2023-02-28", "2023-03-31", 50, "primis_atrisk",
    "Spring 2023",    "2023-04-03", "2023-06-30", "2023-06-30", 75, "immunosuppressed",
    "Autumn 2023",    "2023-08-28", "2024-02-28", "2024-03-31", 65, "primis_atrisk",
    "Spring 2024",    "2024-04-15", "2024-06-30", "2024-06-30", 75, "immunosuppressed",
    "Autumn 2024",    "2024-09-30", "2025-02-28", "2025-03-31", 65, "primis_atrisk",
    "Spring 2025",    "2025-03-31", "2025-06-30", "2025-06-30", 75, "immunosuppressed",
    "Autumn 2025",    "2025-09-29", "2026-02-28", "2026-03-31", 75, "primis_atrisk",
  ) |>
  mutate(
    across(c(campaign_start_date, primary_milestone_date, age_date), as.Date),
    early_milestone_date = campaign_start_date + (7 * 8) - 1, # end of eighth week after campaign_start_date
    final_milestone_date = lead(campaign_start_date, 1, as.Date("2030-01-01")) - 1 # day before next campaign date (or some arbitrary future date if last campaign)
  )  |>
  mutate(
    early_milestone_days = as.integer(early_milestone_date - campaign_start_date) + 1L,
    primary_milestone_days = as.integer(primary_milestone_date - campaign_start_date) + 1L,
    final_milestone_days = as.integer(final_milestone_date - campaign_start_date) + 1L
  )

# output from https://jobs.opensafely.org/opensafely-internal/tpp-vaccination-names/ workspace
# shows all possible covid vaccination names in TPP

# lookup to rename TPP product names to coding-friendly product names
# taking format: manufacturer/brand _ era/variant _ (dose/target) _ (modality)
vax_product_lookup <- c(

  # Pfizer adult
  "pfizer_original" = "COVID-19 mRNA Vaccine Comirnaty 30micrograms/0.3ml dose conc for susp for inj MDV (Pfizer)",
  "pfizer_BA1" = "Comirnaty Original/Omicron BA.1 COVID-19 Vacc md vials",
  "pfizer_BA45" = "Comirnaty Original/Omicron BA.4-5 COVID-19 Vacc md vials",
  "pfizer_XBB15" = "Comirnaty Omicron XBB.1.5 COVID-19 Vacc md vials",
  "pfizer_JN1" = "Comirnaty JN.1 COVID-19 mRNA Vaccine 0.3ml inj md vials (Pfizer Ltd)",
  "pfizer_LP81" = "Comirnaty LP.8.1 COVID-19 Vacc 30microg/0.3ml dose inj pfs (Pfizer Ltd)",
  "pfizer_KP2" = "Comirnaty KP.2 COVID-19 Vacc 30microg/0.3ml dose inj md vial (Pfizer Ltd)",
  "pfizer_KP2_pfs" = "Comirnaty KP.2 COVID-19 Vacc 30microg/0.3ml dose inj pfs (Pfizer Ltd)",

  "pfizer_unspecified" = "Comirnaty COVID-19 mRNA Vacc ready to use 0.3ml inj md vials",

  # Pfizer children

  "pfizer_original_children" = "COVID-19 mRNA Vaccine Comirnaty Children 5-11yrs 10mcg/0.2ml dose conc for disp for inj MDV (Pfizer)",
  "pfizer_JN1_children" = "Comirnaty JN.1 Children 5-11yrs COVID-19 Vacc 0.3ml sd vials (Pfizer Ltd)",
  "pfizer_XBB15_children" = "Comirnaty Omicron XBB.1.5 Child 5-11y COVID-19 Vacc md vials",
  "pfizer_LP81_children" = "Comirnaty LP.8.1 Children 5-11y COVID-19 Vacc 0.3ml sd vials  (Pfizer Ltd)", # note double space before "(Pfizer Ltd)"

  "pfizer_original_under5" = "Comirnaty Children 6m-4yrs COVID-19 mRNA Vacc 0.2ml md vials",
  "pfizer_JN1_under5" = "Comirnaty JN.1 Children 6m-4yrs COVID-19 Vacc 0.3ml md vials (Pfizer Ltd)",
  "pfizer_XBB15_under5" = "Comirnaty Omicron XBB.1.5 Child 6m-4y COVID-19 Vacc md vials",
  "pfizer_LP81_under5" = "Comirnaty LP.8.1 Children 6m-4y COVID-19 Vacc 0.3m md vials  (Pfizer Ltd)", # note, double space before "(Pfizer Ltd)"

  # Astrazeneca

  "az_original" = "COVID-19 Vaccine Vaxzevria 0.5ml inj multidose vials (AstraZeneca)",
  "az_original_half" = "COVID-19 Vac AZD2816 (ChAdOx1 nCOV-19) 3.5x10*9 viral part/0.5ml dose sol for inj MDV (AstraZeneca)",

  # Moderna

  "moderna_original" = "COVID-19 mRNA Vaccine Spikevax (nucleoside modified) 0.1mg/0.5mL dose disp for inj MDV (Moderna)",
  "moderna_omicron" = "COVID-19 Vac Spikevax (Zero)/(Omicron) inj md vials",
  "moderna_BA45" = "COVID-19 Vacc Spikevax Orig/Omicron BA.4/BA.5 inj md vials",
  "moderna_XBB15" = "COVID-19 Vacc Spikevax (XBB.1.5) 0.1mg/1ml inj md vials",
  "moderna_JN1" = "Spikevax JN.1 COVID-19 Vacc 0.1mg/ml inj md vials (Moderna, Inc)",
  "moderna_omicron2" = "COVID-19 Vaccine Moderna (mRNA-1273.529) 50micrograms/0.25ml dose sol for inj MDV",
  "moderna_unspecified" = "COVID-19 Vaccine Moderna 0.5ml dispersion for inj vials",
  "moderna_LP81" = "Spikevax LP.8.1 COVID-19 Vacc 0.1mg/ml inj md vials",


  # Sanofi-GSK
  "sanofigsk_B1" = "COVID-19 Vacc VidPrevtyn (B.1.351) 0.5ml inj multidose vials",
  "sanofigsk_D614" = "COVID-19 Vac Sanofi (CoV2 preS dTM monovalent D614 (recombinant)) 5mcg/0.5ml dose susp for inj MDV",
  "sanofigsk_D614B1" = "COVID-19 Vacc Sanofi (D614+B.1.351) 0.5ml inj md vials",


  # Novavax
  "novavax" = "COVID-19 Vac Nuvaxovid (recombinant, adj) 5micrograms/0.5ml dose susp for inj MDV (Novavax CZ a.s.)",
  "novavax_JN1" = "Nuvaxovid JN.1 COVID-19 Vaccine 0.5ml dose inj pfs",

  # Sputnik
  "sputnik_i_multi" = "COVID-19 Vacc Sputnik V Component I 0.5ml multidose vials",
  "sputnik_ii_multi" = "COVID-19 Vacc Sputnik V Component II 0.5ml multidose vials",
  "sputnik_i_inj" = "COVID-19 Vaccine Sputnik V Component I 0.5ml inj vials",
  "sputnik_ii_inj" = "COVID-19 Vaccine Sputnik V Component II 0.5ml inj vials",

  # Janssen
  "jansenn" = "COVID-19 Vaccine Janssen (Ad26.COV2-S (recomb)) 0.5ml dose solution for injection multidose vials",

  # Sinopharm
  "sinopharm" = "COVID-19 Vac Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose susp for inj vials",

  # Valneva
  "valneva" = "COVID-19 Vaccine Valneva (inactivated adj whole virus) 40antigen units/0.5ml dose susp for inj MDV",

  # Medicago
  "medicago" = "COVID-19 Vaccine Medicago (CoVLP) 3.75micrograms/0.5ml dose emulsion for injection multidose vials",

  # Convidecia
  "convidecia" = "COVID-19 Vaccine Convidecia 0.5ml inj vials",

  # Covaxin
  "covaxin" = "COVID-19 Vac Covaxin (NIV-2020-770 inactivated) 6micrograms/0.5ml dose susp for inj MDV",

  # Coronavac
  "coronavac" = "COVID-19 Vac CoronaVac (adjuvanted) 600U/0.5ml dose susp for inj vials",

  # Covishield
  "covishield" = "COVID-19 Vac Covishield (ChAdOx1 S recombinant) 5x10*9 viral particles/0.5ml dose sol for inj MDV",

  # Covovax
  "covovax" = "COVID-19 Vac Covovax (adjuvanted) 5micrograms/0.5ml dose susp for inj MDV (Serum Institute of India)",

  # Not specified
  "unspecified" = "SARS-2 Coronavirus vaccine"

)


# lookup to rename coding-friendly product names to publication-friendly product names
vax_product_core_levels <- c(
  "pfizer_original",
  "pfizer_BA1",
  "pfizer_BA45",
  "pfizer_XBB15",
  "pfizer_JN1",
  "pfizer_LP81",
  "pfizer_KP2",

  "pfizer_original_children",

  "az_original",
  "az_original_half",

  "moderna_original",
  "moderna_omicron",
  "moderna_BA45",
  "moderna_XBB15",
  "moderna_JN1",
  "moderna_omicron2",
  "moderna_LP81",
  
  "sanofigsk_B1",

  "novavax",
  "novavax_JN1",

  "jansenn",
  "coronavac",
  "covishield"
)

# Approval dates come mainly from Table 2 of the ECHO protocol.
# Additional products found in vax_product_lookup were checked against
# official regulatory sources; these supplementary entries are provisional
# and pending confirmation.
approval_lookup <- c(
  pfizer_original = "2020-12-02",
  pfizer_BA1 = "2022-09-03", #"2022-09-01"?
  pfizer_BA45 = "2022-09-11", #"2022-09-12"?
  pfizer_XBB15 = "2023-09-05",
  pfizer_JN1 = "2024-07-24",
  #pfizer_KP2 = "2024-10-10",
  #pfizer_KP2_pfs = "2024-10-10",
  #pfizer_unspecified = "2020-12-02",

  #pfizer_original_children = "2021-12-22",
  #pfizer_JN1_children = "2024-07-24",
  #pfizer_XBB15_children = "2023-09-05",
  #pfizer_LP81_children = "2025-08-01",

  #pfizer_original_under5 = "2022-12-06",
  #pfizer_JN1_under5 = "2024-07-24",
  #pfizer_XBB15_under5 = "2023-09-05",
  #pfizer_LP81_under5 = "2025-08-01",

  az_original = "2020-12-30",

  moderna_original = "2021-01-08",
  moderna_omicron = "2022-08-15", #"2022-08-12"?
  moderna_BA45 = "2023-02-21",
  moderna_XBB15 = "2023-09-15",
  moderna_JN1 = "2024-09-02",
  #moderna_unspecified = "2021-01-08",

  sanofigsk_B1 = "2022-12-21",
  #novavax = "2022-02-03",
  novavax_JN1 = "2024-11-13"
  #jansenn = "2021-05-28",
  #valneva = "2022-04-14"
)


# relabel_from_lookup <- function(x, from, to, source){
#   left_join(tibble(x=x), source, by = {{from}})[[{{to}}]]
# }