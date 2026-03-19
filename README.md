# vaccines-data-quality

[View on OpenSAFELY](https://jobs.opensafely.org/repo/https%253A%252F%252Fgithub.com%252Fopensafely%252Fvaccines-data-quality)

Details of the purpose and any published outputs from this project can be found at the link above.

The contents of this repository MUST NOT be considered an accurate or valid representation of the study or its purpose. 
This repository may reflect an incomplete or incorrect analysis with no further ongoing work.
The content has ONLY been made public to support the OpenSAFELY [open science and transparency principles](https://www.opensafely.org/about/#contributing-to-best-practice-around-open-science) and to support the sharing of re-usable code for other subsequent users.
No clinical, policy or safety conclusions must be drawn from the contents of this repository.

# About the OpenSAFELY framework

The OpenSAFELY framework is a Trusted Research Environment (TRE) for electronic
health records research in the NHS, with a focus on public accountability and
research quality.

Read more at [OpenSAFELY.org](https://opensafely.org).

# Licences
As standard, research projects have a MIT license. 

## Instructions for adding new vaccines

Please use the following pattern to add a new vaccine or set of variables:
1. Choose a meaningful identifying `{NAME}` for your vaccine, and use this name consistently.
2. Create a new working branch from `main`.
3. Create a dataset definition `./analysis/{NAME}/{NAME}_dataset_definition.py` in the [`./analysis/`](./analysis/) directory. This dataset definition will contain the new vaccine. You may wish to add further scripts to the `./analysis/{NAME}/` directory that define additional functions or other code snippets.
4. Any new codelists will need to be added directly to the [`./codelists/codelist.txt`](./codelists/codelist.txt) - specifying codelists in the variable-specific directories does not work neatly with the `opensafely codelists update` operation. You can also add the codelists to [`./analysis/codelists.py`](./analysis/codelists.py). Use a large separator, as below, to clearly distinguish the groups of codelists that belong to each vaccine.
     ````
     #######################################################
     # {NAME}
     #######################################################
     ````
5. Add the new actions to [`./project.yaml`](./project.yaml) file, using names such as `extract_{NAME}`, for the dataset definition and any additional reporting actions (e.g.`report_data_quality_{NAME}`). Use a clear, large separator like the one below to visually distinguish the groups of actions for each vaccine.
     ````
     #######################################################
     # {NAME}
     #######################################################
     ````
7. Check everything works as intended, then submit a PR for review.
