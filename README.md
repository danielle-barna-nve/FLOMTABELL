# FLOMTABELL

This repository contains the datasets and table-generation scripts used by a Dash application.

## Project Overview

The Dash app itself is located in:

```text
frist_week_sept_published/
```

The main purpose of this repository is to store the source data and scripts that generate the tables consumed by that app.

## Important Files and Directories

### `src/shell_scripts/`

The shell scripts under `src/shell_scripts/` are the most important part of the repository. They call lescon_var, perform SQL-style joins, and generate the tables used by the Dash app.

Run these scripts when the source datasets change or when the app tables need to be rebuilt.

### `clean_data_for_dash_publication.py`

This Python script cleans the tables output by the shell scripts so they are ready for publication in the Dash app.

Use this script after generating the raw output tables.

### `first_week_sept_published/`

This directory contains the published Dash app.

## Typical Workflow

1. Update or add source datasets `input_to_hydra_ii/lescon_var_commands/`.
2. Run the shell scripts in `src/shell_scripts/` to generate the app tables.
3. Run `clean_data_for_dash_publication.py` to clean the generated tables.
4. Use the cleaned tables in the Dash app under `first_week_sept_published/`.

## Notes

- Dash app can be found at 
