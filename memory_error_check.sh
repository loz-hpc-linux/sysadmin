#!/usr/bin/env bash

#set -euo pipefail

print_help() {
  cat <<'EOF'
memory_error_check.sh

Usage:
  memory_error_check.sh [options] <XNAME|comma-separated-xnames|space-separated-xnames>

Description:
  Query ras-mc-ctl memory ECC counters on one or more compute nodes and display:
    - Memory channel label
    - Correctable errors (CE)
    - Uncorrectable errors (UE)
    - Per-node totals
    - Current NHC rule status

Supported input forms:
  memory_error_check.sh x1011c1s6b0n1
  memory_error_check.sh x1011c1s6b0n0,x1011c1s6b0n1,x1011c1s6b1n0,x1011c1s6b1n1
  memory_error_check.sh x1011c1s6b0n0 x1011c1s6b0n1 x1011c1s6b1n0 x1011c1s6b1n1
  memory_error_check.sh $XNAME
  memory_error_check.sh $NODES_XNAME

Options:
  -a, --all       Show all memory channels, including zero CE/UE rows
  -h, --help      Show this help and exit

Notes:
  - Requires SSH access to each target node
  - Requires ras-mc-ctl on the target node
  - Current NHC logic in your environment is:
      UE total > 0      -> NHC fail / offline
      CE total > 10000  -> NHC fail / offline
EOF
}

SHOW_ALL=0

die() {
  echo "Error: $*" >&2
  exit 1
}

is_valid_xname() {
  [[ "$1" =~ ^x[0-9]+c[0-9]+s[0-9]+b[0-9]+n[0-9]+$ ]]
}

run_node_check() {
  local node="$1"

  echo
  echo "============================================================"
  echo "Node: $node"
  echo "============================================================"

  ssh -o BatchMode=yes -o ConnectTimeout=8 "$node" '
    if ! command -v ras-mc-ctl >/dev/null 2>&1; then
      echo "ras-mc-ctl not found on target node"
      exit 2
    fi

    ras-mc-ctl --error-count 2>/dev/null
  ' | awk -v node="$node" -v show_all="$SHOW_ALL" '
    BEGIN {
      total_ce = 0
      total_ue = 0
      row_count = 0
    }

    NR == 1 {
      printf "%-28s %10s %10s\n", "Memory Channel", "CE", "UE"
      printf "%-28s %10s %10s\n", "----------------------------", "----------", "----------"
      next
    }

    NF >= 3 {
      label = $1
      ce    = $2 + 0
      ue    = $3 + 0

      total_ce += ce
      total_ue += ue

      if (show_all == 1 || ce > 0 || ue > 0) {
        printf "%-28s %10d %10d\n", label, ce, ue
        row_count++
      }
    }

    END {
      if (NR <= 1) {
        print "No ras-mc-ctl output returned"
        exit 1
      }

      if (row_count == 0 && show_all == 0) {
        print "No non-zero memory error counters found"
      }

      printf "\n%-28s %10d %10d\n", "TOTAL", total_ce, total_ue

      printf "\nNHC status:\n"
      if (total_ue > 0) {
        printf "  - UE rule: FAIL  (UE total %d > 0)\n", total_ue
      } else {
        printf "  - UE rule: PASS  (UE total %d)\n", total_ue
      }

      if (total_ce > 10000) {
        printf "  - CE rule: FAIL  (CE total %d > 10000)\n", total_ce
      } else {
        printf "  - CE rule: PASS  (CE total %d <= 10000)\n", total_ce
      }
    }
  '

  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    echo "SSH/command failed on $node"
    return 1
  fi

  return 0
}

# -----------------------------
# Arg parsing
# -----------------------------
if [[ $# -eq 0 ]]; then
  print_help
  exit 1
fi

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    -a|--all)
      SHOW_ALL=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

# include any remaining args after --
while [[ $# -gt 0 ]]; do
  ARGS+=("$1")
  shift
done

[[ ${#ARGS[@]} -gt 0 ]] || die "No XNAME input provided"

# Flatten comma-separated + space-separated inputs into one array
NODES=()
for arg in "${ARGS[@]}"; do
  IFS=',' read -r -a parts <<< "$arg"
  for p in "${parts[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    [[ -n "$p" ]] && NODES+=("$p")
  done
done

[[ ${#NODES[@]} -gt 0 ]] || die "No valid XNAMEs parsed"

# Validate
for node in "${NODES[@]}"; do
  is_valid_xname "$node" || die "Invalid node xname: $node"
done

echo
echo "Memory Error Check"
echo "=================="
echo "Targets: ${NODES[*]}"
echo "Show all channels: $([[ $SHOW_ALL -eq 1 ]] && echo yes || echo no)"

fail_count=0
for node in "${NODES[@]}"; do
  run_node_check "$node" || ((fail_count++))
done

echo
echo "Completed. Failed nodes: $fail_count"
exit 0
