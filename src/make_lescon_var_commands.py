from pathlib import Path
import pandas as pd

# -----------------------------------------------------------------------------
# Read station list
# -----------------------------------------------------------------------------

flomtabell = pd.read_csv(
    r"C:\FLOMTABELL\input_to_hydra_ii\station-IDs.csv",
    dtype=str
)

# Split station ID into RN and HN
flomtabell[["RN", "HN"]] = flomtabell["ID"].str.split("-", expand=True)

# -----------------------------------------------------------------------------
# Helper function for writing command files
# -----------------------------------------------------------------------------

def write_lescon_commands(
    outfile,
    station_tab,
    command_args,
    archive_id,
    series_selector,
    suffix
):
    """
    Write a shell script containing one lescon_var command per station.

    lescon_var layout:

        lescon_var [options] <source> <regine> <main_no> <point> <param> <version>

    Parameters
    ----------
    archive_id : str
        Source archive (e.g. 39 HYFIN_COMPLETE, 37 HYDAG, 2 HYKVAL_POINT)

    series_selector : str
        1000 = water level
        1001 = streamflow
    """

    with open(outfile, "w", newline="\n") as f:
        f.write("#!/bin/bash\n")

        for _, row in station_tab.iterrows():

            cmd = (
                f"lescon_var {command_args} "
                f"{archive_id} "
                f"{row['RN']} "
                f"{row['HN']} "
                f"0 "
                f"{series_selector} "
                f"{row['version']} > "
                f"{row['RN']}-{row['HN']}_{suffix}.txt"
            )

            f.write(cmd + "\n")


# -----------------------------------------------------------------------------
# Output directory
# -----------------------------------------------------------------------------

output_dir = Path(r"C:\FLOMTABELL\input_to_hydra_ii\lescon_var_commands")
output_dir.mkdir(parents=True, exist_ok=True)

# -----------------------------------------------------------------------------
# Instantaneous streamflow
# -----------------------------------------------------------------------------

write_lescon_commands(
    output_dir / "1001_b0_39.txt",
    flomtabell,
    "-b 0 -f timevalue",
    "39",
    "1001",
    "39_1001"
)

write_lescon_commands(
    output_dir / "1001_b0_2.txt",
    flomtabell,
    "-b 0 -f timevalue",
    "2",
    "1001",
    "2_1001"
)

# -----------------------------------------------------------------------------
# Instantaneous water level
# -----------------------------------------------------------------------------

write_lescon_commands(
    output_dir / "1000_b0_39.txt",
    flomtabell,
    "-b 0 -f timevalue",
    "39",
    "1000",
    "39_1000"
)

write_lescon_commands(
    output_dir / "1000_b0_2.txt",
    flomtabell,
    "-b 0 -f timevalue",
    "2",
    "1000",
    "2_1000"
)

# -----------------------------------------------------------------------------
# Daily water level
# -----------------------------------------------------------------------------

write_lescon_commands(
    output_dir / "1000_b0_37.txt",
    flomtabell,
    "-b 0 -f timevalue",
    "37",
    "1000",
    "37_1000"
)

write_lescon_commands(
    output_dir / "1000_b1440_2.txt",
    flomtabell,
    "-b 1440 -f timevalue",
    "2",
    "1000",
    "1440_2_1000"
)

# Rolling 24-hour mean water level
write_lescon_commands(
    output_dir / "1000_b60_G1440_39.txt",
    flomtabell,
    "-b 60 -f timevalue -c -G 1440 3",
    "39",
    "1000",
    "b60_G1440_39_1000"
)

write_lescon_commands(
    output_dir / "1000_b60_G1440_2.txt",
    flomtabell,
    "-b 60 -f timevalue -c -G 1440 3",
    "2",
    "1000",
    "b60_G1440_2_1000"
)

# -----------------------------------------------------------------------------
# Daily streamflow
# --------------------------------