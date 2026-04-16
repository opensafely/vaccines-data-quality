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

## patient-level registration dates ----
first_tpp_registration = (
    practice_registrations
    .sort_by(practice_registrations.start_date)
    .first_for_patient()
)

latest_tpp_registration = (
    practice_registrations
    .sort_by(practice_registrations.start_date)
    .last_for_patient()
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
    death_date = ons_deaths.date,
    registration_start_date=first_tpp_registration.start_date,
    deregistration_date=latest_tpp_registration.end_date
)
