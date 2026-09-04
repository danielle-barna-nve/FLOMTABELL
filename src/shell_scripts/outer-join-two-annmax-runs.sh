#!/usr/bin/env bash
set -euo pipefail

# Full outer join two TSV outputs from join-annmax-with-lookups.sh
# using key pair (station_id, year).
#
# Notes:
# - Input files must be tab-separated with a header row.
# - By default, key columns are station_id and year.
# - Non-key columns from each file are prefixed to avoid name collisions.
#
# Example:
#   ./outer-join-two-annmax-runs.sh \
#     --left annual_max_join_exact_run1.tsv \
#     --right annual_max_join_exact_run2.tsv \
#     --output annual_max_join_combined.tsv

LEFT_FILE=""
RIGHT_FILE=""
OUTPUT_FILE=""
KEY1="station_id"
KEY2="year"
LEFT_PREFIX=""
RIGHT_PREFIX=""
SORT_OUTPUT="1"

print_help() {
  cat <<'EOF'
Full outer join two TSV files on a 2-column key.

Required:
  --left <path>         Left TSV file
  --right <path>        Right TSV file
  --output <path>       Combined output TSV

Optional:
  --key1 <name>         First key column name (default: station_id)
  --key2 <name>         Second key column name (default: year)
  --left-prefix <text>  Prefix for non-key left columns (default: "")
  --right-prefix <text> Prefix for non-key right columns (default: "")
  --no-sort             Keep unsorted row order from awk map traversal
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --left)
      LEFT_FILE="$2"
      shift 2
      ;;
    --right)
      RIGHT_FILE="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --key1)
      KEY1="$2"
      shift 2
      ;;
    --key2)
      KEY2="$2"
      shift 2
      ;;
    --left-prefix)
      LEFT_PREFIX="$2"
      shift 2
      ;;
    --right-prefix)
      RIGHT_PREFIX="$2"
      shift 2
      ;;
    --no-sort)
      SORT_OUTPUT="0"
      shift
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

if [[ -z "$LEFT_FILE" || -z "$RIGHT_FILE" || -z "$OUTPUT_FILE" ]]; then
  echo "--left, --right, and --output are required." >&2
  print_help >&2
  exit 1
fi

if [[ ! -f "$LEFT_FILE" ]]; then
  echo "Left file not found: $LEFT_FILE" >&2
  exit 1
fi

if [[ ! -f "$RIGHT_FILE" ]]; then
  echo "Right file not found: $RIGHT_FILE" >&2
  exit 1
fi

TMP_OUT="${OUTPUT_FILE}.tmp"

awk -F '\t' -v OFS='\t' \
  -v key1="$KEY1" -v key2="$KEY2" \
  -v lprefix="$LEFT_PREFIX" -v rprefix="$RIGHT_PREFIX" '
function key_from_row(arr, i1, i2) {
  return arr[i1] SUBSEP arr[i2]
}

function nonkey_values(arr, n, k1i, k2i,   i, out, first) {
  out = ""
  first = 1
  for (i = 1; i <= n; i++) {
    if (i == k1i || i == k2i) continue
    if (!first) out = out OFS
    out = out arr[i]
    first = 0
  }
  return out
}

function blanks(n,   i, out) {
  out = ""
  for (i = 1; i <= n; i++) {
    if (i > 1) out = out OFS
    out = out ""
  }
  return out
}

FNR == 1 {
  if (NR == 1) {
    lk1 = lk2 = 0
    lnf = NF
    for (i = 1; i <= NF; i++) {
      lhdr[i] = $i
      if ($i == key1) lk1 = i
      if ($i == key2) lk2 = i
    }
    if (!lk1 || !lk2) {
      print "ERROR: left file missing key columns" > "/dev/stderr"
      exit 1
    }

    lnonk = 0
    for (i = 1; i <= NF; i++) {
      if (i == lk1 || i == lk2) continue
      lnonk++
      lnonk_hdr[lnonk] = lprefix $i
    }
    next
  }

  rk1 = rk2 = 0
  rnf = NF
  for (i = 1; i <= NF; i++) {
    rhdr[i] = $i
    if ($i == key1) rk1 = i
    if ($i == key2) rk2 = i
  }
  if (!rk1 || !rk2) {
    print "ERROR: right file missing key columns" > "/dev/stderr"
    exit 1
  }

  rnonk = 0
  for (i = 1; i <= NF; i++) {
    if (i == rk1 || i == rk2) continue
    rnonk++
    rnonk_hdr[rnonk] = rprefix $i
  }

  header = key1 OFS key2
  for (i = 1; i <= lnonk; i++) header = header OFS lnonk_hdr[i]
  for (i = 1; i <= rnonk; i++) header = header OFS rnonk_hdr[i]
  print header
  next
}

NR == FNR {
  split($0, row, FS)
  k = key_from_row(row, lk1, lk2)
  lseen[k] = 1
  lkey1[k] = row[lk1]
  lkey2[k] = row[lk2]
  lvals[k] = nonkey_values(row, lnf, lk1, lk2)
  next
}

{
  split($0, row, FS)
  k = key_from_row(row, rk1, rk2)
  rseen[k] = 1
  rkey1[k] = row[rk1]
  rkey2[k] = row[rk2]
  rvals[k] = nonkey_values(row, rnf, rk1, rk2)
}

END {
  lblank = blanks(lnonk)
  rblank = blanks(rnonk)

  for (k in lseen) {
    if (k in rseen) {
      print lkey1[k], lkey2[k], lvals[k], rvals[k]
    } else {
      print lkey1[k], lkey2[k], lvals[k], rblank
    }
    emitted[k] = 1
  }

  for (k in rseen) {
    if (k in emitted) continue
    print rkey1[k], rkey2[k], lblank, rvals[k]
  }
}
' "$LEFT_FILE" "$RIGHT_FILE" > "$TMP_OUT"

if [[ "$SORT_OUTPUT" == "1" ]]; then
  {
    head -n 1 "$TMP_OUT"
    tail -n +2 "$TMP_OUT" | sort -t $'\t' -k1,1 -k2,2n
  } > "$OUTPUT_FILE"
  rm -f "$TMP_OUT"
else
  mv "$TMP_OUT" "$OUTPUT_FILE"
fi

echo "Done. Combined file: $OUTPUT_FILE"
