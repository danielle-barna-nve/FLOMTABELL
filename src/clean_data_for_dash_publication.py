# I want to load in and clean the findata_tabell and save it as a pkl file under first_week_september_published. I will then use this pkl file in the dash app.

# read in the findata_tabell tsv file: C:\Users\daba\OneDrive - Norges vassdrags- og energidirektorat\Dokumenter\Projects\flomtabell\tables\findata_tabell.tsv

import pandas as pd

df_fresh = pd.read_csv(
    r"C:\FLOMTABELL\output_data\findata_tabell.tsv",
    sep="\t"
)

# load in station-IDs.csv
df_station_ids = pd.read_csv(
    r"C:\FLOMTABELL\input_to_hydra_ii\station-IDs.csv",
    sep=","
)

# merge df_fresh with df_station_ids on station_id (df_fresh) and ID (df_station_ids). only take columns ID and version from df_station_ids
df_fresh = df_fresh.merge(
    df_station_ids[['ID', 'version']],
    left_on='station_id',
    right_on='ID',
    how='left'
)

# want to exclude all rows where year == 2026
df_fresh = df_fresh[df_fresh['year'] != 2026]

# i want to exclude the six stations where the hykval_vannfring is not NA, but the hykval_vannstand is NA
df_fresh = df_fresh[~(df_fresh['hykval_vannfring'].notna() & df_fresh['hykval_vannstand'].isna())]

print(f"df_fresh shape: {df_fresh.shape}")

# replace "-" in the station_id column with "."
df_fresh['station_id'] = df_fresh['station_id'].str.replace("-", ".")


# add a column that shows the percent difference between hyfinc_vannfring and hykval_vannfring and round it to two decimal places
df_fresh['percent_diff_hyfinc_hykval'] = ((df_fresh['hyfinc_vannfring'] - df_fresh['hykval_vannfring']) / df_fresh['hyfinc_vannfring'] * 100).round(2)

# if the rounded value is == 0, take the absoltute value
df_fresh.loc[df_fresh['percent_diff_hyfinc_hykval'] == 0, 'percent_diff_hyfinc_hykval'] = df_fresh['percent_diff_hyfinc_hykval'].abs()


############### now: check and see which rows have been updated

# Findata tabell ----------------------------------------------------------

# Mon 31 Aug
df_jan = pd.read_csv(
    r"C:\FLOMTABELL\tables\summer_days_published_df_reduced.tsv",
    sep="\t"
)

# replace "-" in the station_id column with "."
df_jan['station_id'] = df_jan['station_id'].str.replace("-", ".")

# Convert the character column to datetime and exclude the current year.
df_fresh["hyfinc_datetime"] = pd.to_datetime(
    df_fresh["hyfinc_datetime"],
    format="mixed",
    errors="coerce"
)
df_fresh = df_fresh[df_fresh["hyfinc_datetime"].dt.year != 2026]

# Align the January dataset's names with the current dataset before merging.
df_jan = df_jan.rename(columns={
    "datetime": "hyfinc_datetime",
    "value": "hyfinc_vannfring",
    "gamfelt_ts2_value": "hykval_vannfring",
    "waterlevel_ts39_value": "hyfinc_vannstand",
    "waterlevel_ts2_value": "hykval_vannstand",
})

keys = ["station_id", "year"]
compare = df_jan.merge(
    df_fresh,
    on=keys,
    how="outer",
    suffixes=("_jan", "_new")
)

# Find differences in discharge and water-level values.
value_columns = [
    "hykval_vannstand",
]
changes = []

for column in value_columns:
    old_column = f"{column}_jan"
    new_column = f"{column}_new"
    values_differ = (
        compare[old_column].ne(compare[new_column])
        & ~(compare[old_column].isna() & compare[new_column].isna())
    )
    changed_values = compare.loc[
        values_differ,
        ["station_id", "year", "hyfinc_datetime_jan", "hyfinc_datetime_new", old_column, new_column]
    ].copy()
    changed_values["variable"] = column
    changed_values = changed_values.rename(
        columns={old_column: "old_value", new_column: "new_value"}
    )
    changes.append(changed_values)

changed = pd.concat(changes, ignore_index=True)

print(changed)

# merge df_fresh and changed. merge on station_id and year, and only add the column 'old_Value' from changed
df_fresh = df_fresh.merge(
    changed[['station_id', 'year', 'old_value']],
    on=['station_id', 'year'],
    how='left'
)


# in df_fresh, add an indicator column'changed' if old_Value is not NaN and not == hykval_vannstand 
df_fresh['changed'] = df_fresh.apply(
    lambda row: pd.notna(row['old_value']) and row['old_value'] != row['hykval_vannstand'],
    axis=1
)

# print the rows for df_fresh where 'changed' is True
print(df_fresh[df_fresh['changed']])

# save teh pkl file to first_week_sept_published folder
df_fresh.to_pickle(r"C:\FLOMTABELL\first_week_sept_published\findata_tabell_cleaned.pkl")


# load in tables\day_streamflow_table.tsv
df_day_streamflow = pd.read_csv(
    r"C:\FLOMTABELL\tables\day_streamflow_table.tsv",
    sep="\t"
)

# exclude 2026 from the df_day_streamflow
df_day_streamflow = df_day_streamflow[df_day_streamflow['year'] != 2026]

# only use the stations that are in the findata_tabell_cleaned
df_day_streamflow['station_id'] = df_day_streamflow['station_id'].str.replace("-", ".")

df_day_streamflow = df_day_streamflow[df_day_streamflow['station_id'].isin(df_fresh['station_id'])]


# save teh pkl file to first_week_sept_published folder
df_day_streamflow.to_pickle(r"C:\FLOMTABELL\first_week_sept_published\day_streamflow_table_cleaned.pkl") 


# do the same thing for the day_waterlevel_table.tsv
df_day_waterlevel = pd.read_csv(
    r"C:\FLOMTABELL\tables\day_waterlevel_table.tsv",
    sep="\t"
)

# exclude 2026 from the df_day_waterlevel
df_day_waterlevel = df_day_waterlevel[df_day_waterlevel['year'] != 2026]

# only use the stations that are in the findata_tabell_cleaned
df_day_waterlevel['station_id'] = df_day_waterlevel['station_id'].str.replace("-", ".")
df_day_waterlevel = df_day_waterlevel[df_day_waterlevel['station_id'].isin(df_fresh['station_id'])]






# save the pkl file to first_week_sept_published folder
df_day_waterlevel.to_pickle(r"C:\FLOMTABELL\first_week_sept_published\day_waterlevel_table_cleaned.pkl")




