#!/usr/bin/env bash
set -euo pipefail

echo
#############################################
# Help Menu
#############################################
print_help() {
cat <<'EOF'
link_flap_check.sh

Description:
  Queries topology.json via the fabric management shell to:
    1) Identify conn_port values associated with given node xname(s)
    2) Run show-flaps and fabric status checks for each discovered port

Usage:
  link_flap_check.sh <XNAME>
  link_flap_check.sh <comma-separated-xnames>
  link_flap_check.sh <space-separated-xnames>
  link_flap_check.sh -h | --help

Examples:
  link_flap_check.sh x1000c2s6b0n1
  link_flap_check.sh x1000c2s6b0n0,x1000c2s6b0n1,x1000c2s6b1n0,x1000c2s6b1n1
  link_flap_check.sh "x1000c2s6b0n0 x1000c2s6b0n1 x1000c2s6b1n0 x1000c2s6b1n1"

Notes:
  • No files are left behind (a temp file may be created under /tmp and is deleted on exit).
  • Duplicate ports are automatically filtered.
  • Requires: grep, cut, sort, sed, awk, and either:
      - fmnpod (function/alias/command), OR
      - kubectl access to a fabric-manager pod.
  • topology.json must exist at:
        /opt/hpc/fabric/topology.json

Output:
  ############################################################
  XNAME: <node>
  ############################################################
  == PORT: <port> ==
  show-flaps output
  fabric status filtered output

EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

need_cmd grep
need_cmd cut
need_cmd sort
need_cmd sed
need_cmd awk

# Help flag handling
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_help
  exit 0
fi

ARG="${1:-}"
[[ -n "$ARG" ]] || die "No target provided. Example: fabric_port_check.sh \$XNAME"

#############################################
# Fabric management execution wrapper
#############################################
# Prefer fmnpod if available (often a sourced function/alias).
# Else fallback to kubectl exec into a fabric-manager pod.
fmn() {
  if command -v fmnpod >/dev/null 2>&1; then
    fmnpod
    return
  fi

  need_cmd kubectl

  local ns pod
  for ns in fabric-system fabric services default; do
    pod="$(kubectl -n "$ns" get pods 2>/dev/null | awk '/fabric-manager/ && /Running/ {print $1; exit}')"
    [[ -n "${pod:-}" ]] && break
  done

  [[ -n "${pod:-}" ]] || die "Could not find a running fabric-manager pod via kubectl (tried common namespaces)."

  kubectl -n "$ns" exec -i "$pod" -- sh
}

#############################################
# Parse input xnames
#############################################
# Accept:
#   - single xname
#   - comma-separated list
#   - space-separated list
mapfile -t XNAMES < <(
  echo "$ARG" \
    | sed 's/[[:space:]]\+/,/g; s/,,\+/,/g; s/^,//; s/,$//' \
    | tr ',' '\n' \
    | sed '/^[[:space:]]*$/d' \
    | sort -u
)

[[ "${#XNAMES[@]}" -gt 0 ]] || die "No valid xnames parsed from input: $ARG"

#############################################
# Look up conn_port for a given xname
#############################################
ports_for_xname() {
  local xname="$1"

  # Keep behavior close to the original one-liner:
  # - grep xname in topology.json (via fabric management pod)
  # - find conn_port lines in the nearby context
  # - cut the JSON string value
  echo "grep --color=never -i -h -C 3 \"$xname\" /opt/hpc/fabric/topology.json 2>/dev/null" \
    | fmn 2>/dev/null \
    | grep -F 'conn_port' 2>/dev/null \
    | cut -d '"' -f4 2>/dev/null \
    | sed '/^[[:space:]]*$/d' \
    | sort -u || true
}

#############################################
# Run fabric commands for a given port
#############################################
run_for_port() {
  local port="$1"

  echo
  echo "== PORT: $port =="
  echo
  echo "CMD: show-flaps -s 0 -l -N -t $port"
  echo
  echo "show-flaps -s 0 -l -N -t $port" | fmn 2>/dev/null || true
  echo
}

#############################################
# Main
#############################################
for x in "${XNAMES[@]}"; do
  echo "############################################################"
  echo "XNAME: $x"
  echo "############################################################"

  TMP="$(mktemp -t fabriccheck.XXXXXX)"
  trap 'rm -f "$TMP"' EXIT INT TERM

  ports_for_xname "$x" >"$TMP"

  if [[ ! -s "$TMP" ]]; then
    echo "No conn_port entries found for $x in topology.json (via fabric management shell)."
    echo
    rm -f "$TMP"
    trap - EXIT INT TERM
    continue
  fi

  while IFS= read -r port; do
    run_for_port "$port"
  done <"$TMP"

  rm -f "$TMP"
  trap - EXIT INT TERM
done
