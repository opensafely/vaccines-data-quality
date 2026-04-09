# Purpose:
# define codelist objects from codelist files imported by codelist.txt spec

# Import code building blocks from cohort extractor package
from ehrql import codelist_from_csv


## --VARIABLES--
# if the variable uses a codelist then it should be added below
# after updating the codelist.txt configuration and importing the codelist

# Flu vaccine
flu_vac_SNOMED = codelist_from_csv(
    "codelists/nhsd-primary-care-domain-refsets-flu_cod.csv", 
    column="code",
)
flu_vac_drug = codelist_from_csv(
    "codelists/nhs-drug-refsets-fludrug_cod.csv", 
    column="code",
)