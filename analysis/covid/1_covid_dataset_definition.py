# _________________________________________________
# Purpose:
# Extract event-level COVID-19 vaccination data.
# One row in the event table = one COVID-19 vaccination event.
# _________________________________________________

# import libraries and functions

from json import loads
from pathlib import Path

from ehrql import (
   # case,
    create_dataset,
    # days,
    # when,
    # minimum_of,
    # maximum_of,
    claim_permissions
)
from ehrql.tables.tpp import (
  patients,
#   practice_registrations, 
  vaccinations, 
#   clinical_events, 
#   ons_deaths,
#   addresses,
)
# import codelists
#from codelists import *

study_dates_covid = loads(
    Path("analysis/covid/study_dates_covid.json").read_text(),
)

# Change these in ./analysis/covid/0_covid_design.R if necessary
start_date = study_dates_covid["start_date"]
end_date = study_dates_covid["end_date"]


# all covid-19 vaccination events

## covid vaccination events ----
covid_vaccinations = (
  vaccinations
  .where(vaccinations.target_disease.is_in(["SARS-2 CORONAVIRUS"]))
  .sort_by(vaccinations.date)
)

## initialise dataset
dataset = create_dataset()
dataset.configure_dummy_data(population_size=1000)

## define dataset poppulation
dataset.define_population(
   covid_vaccinations.exists_for_patient()
   #& (patients.age_on(end_date) >= 12) # only include people who are aged 12 or over during at least one season
)

claim_permissions("event_level_data")

covid_vaccinations_ELD = covid_vaccinations 
dataset.add_event_table(
    "vaccinations",
    vax_date = covid_vaccinations_ELD.date,
    vax_product = covid_vaccinations_ELD.product_name,
    age = patients.age_on(covid_vaccinations_ELD.date),
)
