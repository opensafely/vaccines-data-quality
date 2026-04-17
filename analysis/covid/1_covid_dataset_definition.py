# _________________________________________________
# Purpose:
# Extract event-level COVID-19 vaccination data.
# One row in the event table = one COVID-19 vaccination event.
# _________________________________________________

# import libraries and functions

from ehrql import (
    create_dataset,
    claim_permissions
)
from ehrql.tables.tpp import (
  patients,
  vaccinations,
  ons_deaths,
  practice_registrations
)

# all covid-19 vaccination events

## covid vaccination events ----
covid_vaccinations = (
  vaccinations
  .where(vaccinations.target_disease.is_in(["SARS-2 CORONAVIRUS"]))
  .sort_by(vaccinations.date)
)

## all GP registration periods
registration_periods = (
    practice_registrations
    .sort_by(practice_registrations.start_date)
)


## initialise dataset
dataset = create_dataset()
dataset.configure_dummy_data(population_size=1000)

## define dataset poppulation
dataset.define_population(
   covid_vaccinations.exists_for_patient()
 
)

claim_permissions("event_level_data")

covid_vaccinations_ELD = covid_vaccinations 
dataset.add_event_table(
    "vaccinations",
    vax_date = covid_vaccinations_ELD.date,
    vax_product = covid_vaccinations_ELD.product_name,
    age = patients.age_on(covid_vaccinations_ELD.date),
    death_date = ons_deaths.date
)

# registration event table
dataset.add_event_table(
    "registrations",
    registration_start_date = registration_periods.start_date,
    deregistration_date = registration_periods.end_date,
)