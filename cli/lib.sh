# herm — shared shell helpers. Sourced by bin/herm and each cli/commands/*.sh.
# Do not run directly.

# shellcheck shell=bash

set -euo pipefail

# Locate the repo root from this file's location.
HERM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERM_REPO_ROOT="$(cd "$HERM_LIB_DIR/.." && pwd)"
export HERM_LIB_DIR HERM_REPO_ROOT

# Default config path.
HERM_CONFIG_PATH="${HERM_CONFIG_PATH:-$HOME/.config/herm/config.toml}"

# ---- Output ----------------------------------------------------------------

herm::log()  { printf '\033[36m[herm]\033[0m %s\n' "$*"; }
herm::warn() { printf '\033[33m[herm]\033[0m %s\n' "$*" >&2; }
herm::err()  { printf '\033[31m[herm]\033[0m %s\n' "$*" >&2; }
herm::die()  { herm::err "$@"; exit 1; }

# ---- Command availability --------------------------------------------------

herm::require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    herm::err "missing required command: $cmd"
    return 1
  fi
}

# ---- TOML reading ----------------------------------------------------------
# Minimal TOML reader. Supports [section] headers and key = value (string/number),
# with optional whitespace and quoted-string values. Good enough for herm's
# small config; we deliberately do NOT pull in a TOML parser dependency.

herm::read_config() {
  local file="$1" section="$2" key="$3"
  if [[ ! -f $file ]]; then
    herm::err "config file not found: $file"
    return 1
  fi

  local current_section=""
  local found=""
  while IFS= read -r raw; do
    # Strip comments and trim.
    local line="${raw%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z $line ]] && continue

    if [[ $line =~ ^\[([a-zA-Z0-9_.-]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi

    if [[ $current_section == "$section" && $line =~ ^([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      local k="${BASH_REMATCH[1]}"
      local v="${BASH_REMATCH[2]}"
      if [[ $k == "$key" ]]; then
        # Strip surrounding quotes if any.
        v="${v#\"}"; v="${v%\"}"
        printf '%s\n' "$v"
        found=1
        break
      fi
    fi
  done < "$file"

  if [[ -z $found ]]; then
    herm::err "key not found: [$section] $key in $file"
    return 1
  fi
}

# ---- Confirmation ---------------------------------------------------------

herm::confirm() {
  local prompt="${1:-Proceed?}"
  local answer
  read -r -p "$prompt [y/N] " answer
  [[ $answer =~ ^[Yy]$ ]]
}

# ---- Terraform wrapper ----------------------------------------------------

herm::tf() {
  ( cd "$HERM_REPO_ROOT/terraform" && terraform "$@" )
}
