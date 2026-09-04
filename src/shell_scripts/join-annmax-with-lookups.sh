#!/usr/bin/env bash
set -euo pipefail

# Run lescon_var commands to compute annual maxima from one command file,
# then exact-timestamp left join to values from one to three lookup command files.
#
# Usage:
#   ./join-annmax-with-lookups.sh \
#     --commands-dir ./lescon_var-commands-test-cases \
#     --join-max-file 1001_b0_39.txt \
#     --join-lookup-file 1001_b0_2.txt \
#     --join-output ./results/my_join.tsv
#
# Notes:
# - Expects command lines like:
#     lescon_var ... > stationid_archive_param.txt
# - Uses annual maxima from --join-max-file only.
# - Left joins lookup values from one to three lookup files on exact timestamp.

COMMANDS_DIR="./lescon_var-commands-test-cases"
JOIN_MAX_COMMAND_FILE=""
JOIN_LOOKUP_COMMAND_FILE=""
JOIN_LOOKUP_COMMAND_FILE_2=""
JOIN_LOOKUP_COMMAND_FILE_3=""
JOIN_OUTPUT_FILE=""
ERROR_LOG_FILE=""
COLUMN_ANNUAL_MAX_VALUE="annual_max_value"
COLUMN_ANNUAL_MAX_TIMESTAMP="annual_max_timestamp"
COLUMN_LOOKUP1="lookup1_value_at_annual_max_timestamp"
COLUMN_LOOKUP2="lookup2_value_at_annual_max_timestamp"
COLUMN_LOOKUP3="lookup3_value_at_annual_max_timestamp"

print_help() {
  cat <<'EOF'
Compute annual maxima from one command file and exact-join to one to three lookup files.

Options:
  -c, --commands-dir   Directory containing command files (default: ./lescon_var-commands-test-cases)
  --join-max-file      Command file used to compute annual maxima (for example source 39)
  --join-lookup-file   First lookup command file used to fetch value at max timestamp
  --join-lookup-file-2 Optional second lookup command file (same format)
  --join-lookup-file-3 Optional third lookup command file (same format; requires --join-lookup-file-2)
  --join-output        Required output TSV path for exact timestamp join
  --col-annual-max-value Name of annual max value column (default: annual_max_value)
  --col-annual-max-ts    Name of annual max timestamp column (default: annual_max_timestamp)
  --col-lookup1          Name of lookup1 column (default: lookup1_value_at_annual_max_timestamp)
  --col-lookup2          Name of lookup2 column (default: lookup2_value_at_annual_max_timestamp)
  --col-lookup3          Name of lookup3 column (default: lookup3_value_at_annual_max_timestamp)
  -h, --help           Show this help

Output structure:
  <join-output>
  <join-output-without-.tsv>.errors.log

Column format for join file:
  station_id<TAB>year<TAB><annual max value column><TAB><annual max timestamp column><TAB><lookup1 column>
  + optional <lookup2 column> when --join-lookup-file-2 is provided
  + optional <lookup3 column> when --join-lookup-file-3 is provided
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--commands-dir)
      COMMANDS_DIR="$2"
      shift 2
      ;;
    -o|--output-dir)
      echo "--output-dir is no longer supported. Use --join-output with a .tsv filename." >&2
      exit 1
      ;;
    --join-max-file)
      JOIN_MAX_COMMAND_FILE="$2"
      shift 2
      ;;
    --join-lookup-file)
      JOIN_LOOKUP_COMMAND_FILE="$2"
      shift 2
      ;;
    --join-lookup-file-2)
      JOIN_LOOKUP_COMMAND_FILE_2="$2"
      shift 2
      ;;
    --join-lookup-file-3)
      JOIN_LOOKUP_COMMAND_FILE_3="$2"
      shift 2
      ;;
    --join-output)
      JOIN_OUTPUT_FILE="$2"
      shift 2
      ;;
    --col-annual-max-value)
      COLUMN_ANNUAL_MAX_VALUE="$2"
      shift 2
      ;;
    --col-annual-max-ts)
      COLUMN_ANNUAL_MAX_TIMESTAMP="$2"
      shift 2
      ;;
    --col-lookup1)
      COLUMN_LOOKUP1="$2"
      shift 2
      ;;
    --col-lookup2)
      COLUMN_LOOKUP2="$2"
      shift 2
      ;;
    --col-lookup3)
      COLUMN_LOOKUP3="$2"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_help >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$COMMANDS_DIR" ]]; then
  echo "Commands directory not found: $COMMANDS_DIR" >&2
  exit 1
fi

if ! command -v awk >/dev/null 2>&1; then
  echo "awk is required but not found in PATH" >&2
  exit 1
fi

if [[ -z "$JOIN_OUTPUT_FILE" ]]; then
  echo "--join-output is required and must be a .tsv filename." >&2
  exit 1
fi

if [[ "$JOIN_OUTPUT_FILE" != *.tsv ]]; then
  echo "--join-output must end with .tsv" >&2
  exit 1
fi

mkdir -p "$(dirname "$JOIN_OUTPUT_FILE")"
ERROR_LOG_FILE="${JOIN_OUTPUT_FILE%.tsv}.errors.log"
: > "$ERROR_LOG_FILE"

if [[ -z "$JOIN_MAX_COMMAND_FILE" || -z "$JOIN_LOOKUP_COMMAND_FILE" ]]; then
  echo "Both --join-max-file and --join-lookup-file are required." >&2
  exit 1
fi

if [[ -n "$JOIN_LOOKUP_COMMAND_FILE_3" && -z "$JOIN_LOOKUP_COMMAND_FILE_2" ]]; then
  echo "--join-lookup-file-3 requires --join-lookup-file-2." >&2
  exit 1
fi

resolve_command_file() {
  local maybe_path="$1"
  if [[ -f "$maybe_path" ]]; then
    printf '%s\n' "$maybe_path"
  elif [[ -f "$COMMANDS_DIR/$maybe_path" ]]; then
    printf '%s\n' "$COMMANDS_DIR/$maybe_path"
  else
    printf '%s\n' ""
  fi
}

run_exact_timestamp_join() {
  local max_file_raw="$1"
  local lookup1_file_raw="$2"
  local lookup2_file_raw="$3"
  local lookup3_file_raw="$4"
  local out_file="$5"
  local col_max_value="$6"
  local col_max_ts="$7"
  local col_lookup1="$8"
  local col_lookup2="$9"
  local col_lookup3="${10}"

  local max_file lookup1_file lookup2_file lookup3_file
  max_file="$(resolve_command_file "$max_file_raw")"
  lookup1_file="$(resolve_command_file "$lookup1_file_raw")"
  if [[ -n "$lookup2_file_raw" ]]; then
    lookup2_file="$(resolve_command_file "$lookup2_file_raw")"
  else
    lookup2_file=""
  fi
  if [[ -n "$lookup3_file_raw" ]]; then
    lookup3_file="$(resolve_command_file "$lookup3_file_raw")"
  else
    lookup3_file=""
  fi

  if [[ -z "$max_file" ]]; then
    echo "ERROR join max file not found: $max_file_raw" >> "$ERROR_LOG_FILE"
    return 1
  fi
  if [[ -z "$lookup1_file" ]]; then
    echo "ERROR join lookup file not found: $lookup1_file_raw" >> "$ERROR_LOG_FILE"
    return 1
  fi
  if [[ -n "$lookup2_file_raw" && -z "$lookup2_file" ]]; then
    echo "ERROR join lookup file 2 not found: $lookup2_file_raw" >> "$ERROR_LOG_FILE"
    return 1
  fi
  if [[ -n "$lookup3_file_raw" && -z "$lookup3_file" ]]; then
    echo "ERROR join lookup file 3 not found: $lookup3_file_raw" >> "$ERROR_LOG_FILE"
    return 1
  fi

  local has_lookup2 has_lookup3
  has_lookup2="0"
  has_lookup3="0"
  [[ -n "$lookup2_file" ]] && has_lookup2="1"
  [[ -n "$lookup3_file" ]] && has_lookup3="1"

  local join_awk
  join_awk="$(mktemp)"
  trap "rm -f '$join_awk'" RETURN
  cat > "$join_awk" <<'AWK'
BEGIN { OFS = "\t" }

BEGIN {
  while ((getline row < lookup_file_1) > 0) {
    n = split(row, f)
    if (n < 2) continue
    if (f[1] ~ /^#/) continue

    ts = f[1]
    v_str = f[2]
    ts_digits = ts
    gsub(/[^0-9]/, "", ts_digits)
    if (length(ts_digits) < 4) continue
    if (v_str !~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) continue

    v_num = v_str + 0
    if (v_num <= -9998) continue

    lookup1_val_str[ts] = v_str
  }
  close(lookup_file_1)

  if (has_lookup2 == "1") {
    while ((getline row < lookup_file_2) > 0) {
      n = split(row, f)
      if (n < 2) continue
      if (f[1] ~ /^#/) continue

      ts = f[1]
      v_str = f[2]
      ts_digits = ts
      gsub(/[^0-9]/, "", ts_digits)
      if (length(ts_digits) < 4) continue
      if (v_str !~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) continue

      v_num = v_str + 0
      if (v_num <= -9998) continue

      lookup2_val_str[ts] = v_str
    }
    close(lookup_file_2)
  }

  if (has_lookup3 == "1") {
    while ((getline row < lookup_file_3) > 0) {
      n = split(row, f)
      if (n < 2) continue
      if (f[1] ~ /^#/) continue

      ts = f[1]
      v_str = f[2]
      ts_digits = ts
      gsub(/[^0-9]/, "", ts_digits)
      if (length(ts_digits) < 4) continue
      if (v_str !~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) continue

      v_num = v_str + 0
      if (v_num <= -9998) continue

      lookup3_val_str[ts] = v_str
    }
    close(lookup_file_3)
  }
}

{
  n = split($0, f)
  if (n < 2) next
  if (f[1] ~ /^#/) next

  ts = f[1]
  v_str = f[2]
  ts_digits = ts
  gsub(/[^0-9]/, "", ts_digits)
  if (length(ts_digits) < 4) next
  if (v_str !~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) next

  v_num = v_str + 0
  if (v_num <= -9998) next

  y = substr(ts_digits, 1, 4)
  key = sid FS y
  if (!(key in ymax_num) || v_num > ymax_num[key]) {
    # Compare using numeric value, but store original text value for output.
    ymax_num[key] = v_num
    ymax_str[key] = v_str
    ymax_ts[key] = ts
  }
}

END {
  for (k in ymax_num) {
    split(k, a, FS)
    ts = ymax_ts[k]
    v1 = (ts in lookup1_val_str) ? lookup1_val_str[ts] : "NA"
    if (has_lookup2 == "1") {
      v2 = (ts in lookup2_val_str) ? lookup2_val_str[ts] : "NA"
      if (has_lookup3 == "1") {
        v3 = (ts in lookup3_val_str) ? lookup3_val_str[ts] : "NA"
        print a[1], a[2], ymax_str[k], ts, v1, v2, v3
      } else {
        print a[1], a[2], ymax_str[k], ts, v1, v2
      }
    } else {
      print a[1], a[2], ymax_str[k], ts, v1
    }
  }
}
AWK

  declare -A max_cmd_by_station
  declare -A lookup1_cmd_by_station
  declare -A lookup2_cmd_by_station
  declare -A lookup3_cmd_by_station

  local parse_target parse_cmd parse_series station
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#${line%%[![:space:]]*}}"
    line="${line%${line##*[![:space:]]}}"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" != *">"* ]] && continue

    parse_cmd="${line%%>*}"
    parse_target="${line##*>}"
    parse_cmd="${parse_cmd#${parse_cmd%%[![:space:]]*}}"
    parse_cmd="${parse_cmd%${parse_cmd##*[![:space:]]}}"
    parse_target="${parse_target#${parse_target%%[![:space:]]*}}"
    parse_target="${parse_target%${parse_target##*[![:space:]]}}"

    parse_series="${parse_target%.txt}"
    station="${parse_series%%_*}"
    [[ -z "$station" ]] && continue

    if [[ -z "${max_cmd_by_station[$station]+x}" ]]; then
      max_cmd_by_station["$station"]="$parse_cmd"
    else
      echo "WARN duplicate max command for station $station in $(basename "$max_file"); keeping first" >> "$ERROR_LOG_FILE"
    fi
  done < "$max_file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#${line%%[![:space:]]*}}"
    line="${line%${line##*[![:space:]]}}"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" != *">"* ]] && continue

    parse_cmd="${line%%>*}"
    parse_target="${line##*>}"
    parse_cmd="${parse_cmd#${parse_cmd%%[![:space:]]*}}"
    parse_cmd="${parse_cmd%${parse_cmd##*[![:space:]]}}"
    parse_target="${parse_target#${parse_target%%[![:space:]]*}}"
    parse_target="${parse_target%${parse_target##*[![:space:]]}}"

    parse_series="${parse_target%.txt}"
    station="${parse_series%%_*}"
    [[ -z "$station" ]] && continue

    if [[ -z "${lookup1_cmd_by_station[$station]+x}" ]]; then
      lookup1_cmd_by_station["$station"]="$parse_cmd"
    else
      echo "WARN duplicate lookup command for station $station in $(basename "$lookup1_file"); keeping first" >> "$ERROR_LOG_FILE"
    fi
  done < "$lookup1_file"

  if [[ "$has_lookup2" == "1" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line#${line%%[![:space:]]*}}"
      line="${line%${line##*[![:space:]]}}"
      [[ -z "$line" ]] && continue
      [[ "$line" == \#* ]] && continue
      [[ "$line" != *">"* ]] && continue

      parse_cmd="${line%%>*}"
      parse_target="${line##*>}"
      parse_cmd="${parse_cmd#${parse_cmd%%[![:space:]]*}}"
      parse_cmd="${parse_cmd%${parse_cmd##*[![:space:]]}}"
      parse_target="${parse_target#${parse_target%%[![:space:]]*}}"
      parse_target="${parse_target%${parse_target##*[![:space:]]}}"

      parse_series="${parse_target%.txt}"
      station="${parse_series%%_*}"
      [[ -z "$station" ]] && continue

      if [[ -z "${lookup2_cmd_by_station[$station]+x}" ]]; then
        lookup2_cmd_by_station["$station"]="$parse_cmd"
      else
        echo "WARN duplicate lookup2 command for station $station in $(basename "$lookup2_file"); keeping first" >> "$ERROR_LOG_FILE"
      fi
    done < "$lookup2_file"
  fi

  if [[ "$has_lookup3" == "1" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line#${line%%[![:space:]]*}}"
      line="${line%${line##*[![:space:]]}}"
      [[ -z "$line" ]] && continue
      [[ "$line" == \#* ]] && continue
      [[ "$line" != *">"* ]] && continue

      parse_cmd="${line%%>*}"
      parse_target="${line##*>}"
      parse_cmd="${parse_cmd#${parse_cmd%%[![:space:]]*}}"
      parse_cmd="${parse_cmd%${parse_cmd##*[![:space:]]}}"
      parse_target="${parse_target#${parse_target%%[![:space:]]*}}"
      parse_target="${parse_target%${parse_target##*[![:space:]]}}"

      parse_series="${parse_target%.txt}"
      station="${parse_series%%_*}"
      [[ -z "$station" ]] && continue

      if [[ -z "${lookup3_cmd_by_station[$station]+x}" ]]; then
        lookup3_cmd_by_station["$station"]="$parse_cmd"
      else
        echo "WARN duplicate lookup3 command for station $station in $(basename "$lookup3_file"); keeping first" >> "$ERROR_LOG_FILE"
      fi
    done < "$lookup3_file"
  fi

  local header
  header="station_id\tyear\t${col_max_value}\t${col_max_ts}\t${col_lookup1}"
  if [[ "$has_lookup2" == "1" ]]; then
    header+="\t${col_lookup2}"
  fi
  if [[ "$has_lookup3" == "1" ]]; then
    header+="\t${col_lookup3}"
  fi
  echo -e "$header" > "$out_file"

  local sid cmd_max cmd_lookup1 cmd_lookup2 cmd_lookup3 tmp_lookup1 tmp_lookup2 tmp_lookup3
  for sid in "${!max_cmd_by_station[@]}"; do
    cmd_max="${max_cmd_by_station[$sid]}"

    tmp_lookup1="$(mktemp)"
    if [[ -n "${lookup1_cmd_by_station[$sid]+x}" ]]; then
      cmd_lookup1="${lookup1_cmd_by_station[$sid]}"
      if ! eval "$cmd_lookup1" > "$tmp_lookup1" 2>>"$ERROR_LOG_FILE"; then
        echo "ERROR join lookup command failed for station $sid" >> "$ERROR_LOG_FILE"
        rm -f "$tmp_lookup1"
        continue
      fi
    else
      echo "WARN no lookup1 command found for station $sid; using NA lookup values" >> "$ERROR_LOG_FILE"
      : > "$tmp_lookup1"
    fi

    tmp_lookup2=""
    if [[ "$has_lookup2" == "1" ]]; then
      tmp_lookup2="$(mktemp)"
      if [[ -n "${lookup2_cmd_by_station[$sid]+x}" ]]; then
        cmd_lookup2="${lookup2_cmd_by_station[$sid]}"
        if ! eval "$cmd_lookup2" > "$tmp_lookup2" 2>>"$ERROR_LOG_FILE"; then
          echo "ERROR join lookup2 command failed for station $sid" >> "$ERROR_LOG_FILE"
          rm -f "$tmp_lookup1" "$tmp_lookup2"
          continue
        fi
      else
        echo "WARN no lookup2 command found for station $sid; using NA lookup values" >> "$ERROR_LOG_FILE"
        : > "$tmp_lookup2"
      fi
    fi

    tmp_lookup3=""
    if [[ "$has_lookup3" == "1" ]]; then
      tmp_lookup3="$(mktemp)"
      if [[ -n "${lookup3_cmd_by_station[$sid]+x}" ]]; then
        cmd_lookup3="${lookup3_cmd_by_station[$sid]}"
        if ! eval "$cmd_lookup3" > "$tmp_lookup3" 2>>"$ERROR_LOG_FILE"; then
          echo "ERROR join lookup3 command failed for station $sid" >> "$ERROR_LOG_FILE"
          rm -f "$tmp_lookup1" "$tmp_lookup2" "$tmp_lookup3"
          continue
        fi
      else
        echo "WARN no lookup3 command found for station $sid; using NA lookup values" >> "$ERROR_LOG_FILE"
        : > "$tmp_lookup3"
      fi
    fi

    if ! eval "$cmd_max" 2>>"$ERROR_LOG_FILE" | \
      awk -v sid="$sid" \
          -v lookup_file_1="$tmp_lookup1" \
          -v lookup_file_2="$tmp_lookup2" \
          -v lookup_file_3="$tmp_lookup3" \
          -v has_lookup2="$has_lookup2" \
          -v has_lookup3="$has_lookup3" \
          -f "$join_awk" >> "$out_file"; then
      echo "ERROR join max command failed for station $sid" >> "$ERROR_LOG_FILE"
    fi

    rm -f "$tmp_lookup1"
    [[ -n "$tmp_lookup2" ]] && rm -f "$tmp_lookup2"
    [[ -n "$tmp_lookup3" ]] && rm -f "$tmp_lookup3"
  done

  # Sort data rows by station_id then year and keep header as first row.
  local sorted_tmp
  sorted_tmp="$(mktemp)"
  {
    head -n 1 "$out_file"
    tail -n +2 "$out_file" | sort -t $'\t' -k1,1 -k2,2n
  } > "$sorted_tmp"
  mv "$sorted_tmp" "$out_file"
}

run_exact_timestamp_join \
  "$JOIN_MAX_COMMAND_FILE" \
  "$JOIN_LOOKUP_COMMAND_FILE" \
  "$JOIN_LOOKUP_COMMAND_FILE_2" \
  "$JOIN_LOOKUP_COMMAND_FILE_3" \
  "$JOIN_OUTPUT_FILE" \
  "$COLUMN_ANNUAL_MAX_VALUE" \
  "$COLUMN_ANNUAL_MAX_TIMESTAMP" \
  "$COLUMN_LOOKUP1" \
  "$COLUMN_LOOKUP2" \
  "$COLUMN_LOOKUP3"

echo "- Exact join: $JOIN_OUTPUT_FILE"
echo "- Errors/warnings: $ERROR_LOG_FILE"
