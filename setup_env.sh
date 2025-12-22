#!/bin/bash

# Handle --help or -h before anything else
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  echo
  echo "🔧 setup_env.sh - Node triage environment setup"
  echo
  echo "Usage:"
  echo "  source ./setup_env.sh"
  echo
  echo "This script will:"
  echo "  - Prompt for TICKET (e.g UKEMT-3555-LH) and NID(e.g nidd3493)"
  echo "  - Resolve BMC, SLOT, CHASSIS, and node lists"
  echo "  - Optionally apply a custom command prompt"
  echo "  - Optionally lock variables as readonly"
  echo "  - Export all variables for use in current session"
  echo
  echo "❗ IMPORTANT: This script must be sourced to modify your current shell."
  echo "   Running it as './setup_env.sh' will NOT work as intended."
  echo
  exit 0
fi

# Ensure the script is sourced, not executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo
  echo "❌ ERROR: This script must be sourced to work correctly."
  echo "   It sets environment variables in your current shell."
  echo
  echo "💡 Usage: source ./setup_env.sh"
  echo "   Or for help: source ./setup_env.sh --help"
  echo
  exit 1
fi

echo

# Prompt for user inputs
read -p "Enter ticket name: " TICKET
read -p "Enter NID: " NID

# === Source reusable functions ===
FUNCTIONS_FILE="/opt/cray/hpe-admin/site-team/scripts/lharding/functions.sh"
if [[ -f "$FUNCTIONS_FILE" ]]; then
  source "$FUNCTIONS_FILE"
  echo
  echo "✅ Sourced functions from: $FUNCTIONS_FILE"
else
  echo
  echo "⚠️  Warning: Could not find functions file: $FUNCTIONS_FILE"
  echo "   Some functionality may be unavailable."
fi

# Export basic environment variables
export TICKET
export NID
export n2xmapfile=/etc/cray/nidX

# Add custom paths to $PATH and display them
added_paths="/opt/cray/hpe-admin/site-team/triage:/opt/cray/hpe-admin/site-team/scripts:/opt/cray/hpe-admin/site-team/scripts/lharding"
export PATH=$PATH:$added_paths

echo
echo "📂 Added to \$PATH:"
IFS=':' read -ra ADD_PATHS <<< "$added_paths"
for p in "${ADD_PATHS[@]}"; do
  echo "  → $p"
done

vars() {
  echo "✅ Variables set:"
  echo "\$TICKET = $TICKET"
  echo "\$NID = $NID"
  echo "\$XNAME = $XNAME"
  echo "\$BMC = $BMC"
  echo "\$SLOT = $SLOT"
  echo "\$CHASSIS = $CHASSIS"
  echo "\$NODES_XNAME = $NODES_XNAME"
  echo "\$NODES_NID = $NODES_NID"
  echo "\$NODES_NID_LIST = $NODES_NID_LIST"
}

# Derived variables
export XNAME=$(n2x "$NID")

if [[ -z "$XNAME" ]]; then
  echo "❌ Failed to resolve XNAME from NID: '$NID'"
  echo "Check that '$NID' exists in $n2xmapfile"
  return 1 2>/dev/null || exit 1
fi

export BMC=${XNAME::-2}
export SLOT=${XNAME::-4}
export CHASSIS="${XNAME::-6}b0"
export NODES_XNAME=$(cluset -e -S, $(n2x "$SLOT"))
export NODES_NID=$(cluset -e -S, $(x2n "$SLOT"))
export NODES_NID_LIST=$(cluset -e $(x2n "$SLOT"))
export slot=${XNAME::-4}

# Output variables
echo
vars
echo

# Ask user if they want to apply the custom command prompt
read -p "Apply custom command prompt? [y/N]: " CUSTOM_PS1
if [[ "$CUSTOM_PS1" =~ ^[Yy]$ ]]; then
  export PS1='\[\e[38;5;201m\]\H\[\e[38;5;226m\]\s\[\e[38;5;51m\]-\[\e[38;5;51m\]\u\[\e[38;5;219m\]\w\[\e[38;5;46m\]@\[\e[38;5;46m\]\d\[\e[38;5;208m\]-\[\e[38;5;214m\]\t\[\e[38;5;196m\]\$\[\e[0m\] '
  echo "✅ Command prompt customised"
fi

echo

# Ask user if they want to lock environment variables
read -p "Lock environment variables as readonly? [y/N]: " LOCK
if [[ "$LOCK" =~ ^[Yy]$ ]]; then
  readonly TICKET
  readonly NID
  readonly XNAME
  readonly BMC
  readonly SLOT
  readonly CHASSIS
  readonly NODES_XNAME
  readonly NODES_NID
  readonly NODES_NID_LIST
  readonly slot
  echo "🔒 Variables are now readonly."
else
  echo "✅ Variables remain editable."
fi

echo
