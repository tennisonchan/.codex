#!/usr/bin/env bash
# Description: Load Codex environment variables from .env.local and render config.toml from the template.
# Usage: source ~/.codex/scripts/setup-codex.sh [--quiet]
# Inputs: CODEX_ROOT (default: $HOME/.codex), ENV_FILE, CONFIG_TEMPLATE, CONFIG_OUTPUT, QUIET.
# Deps: envsubst (gettext)

codex_setup() {
  local quiet_flag="${1:-}"
  local root="${CODEX_ROOT:-$HOME/.codex}"
  local env_file="${ENV_FILE:-$root/.env.local}"
  local template="${CONFIG_TEMPLATE:-$root/config.toml.tmpl}"
  local output="${CONFIG_OUTPUT:-$root/config.toml}"

  if ! command -v envsubst >/dev/null 2>&1; then
    echo "codex_setup: envsubst not found (install gettext)" >&2
    return 1
  fi

  if [[ ! -f "$env_file" ]]; then
    echo "codex_setup: missing env file at $env_file" >&2
    return 1
  fi

  if [[ ! -f "$template" ]]; then
    echo "codex_setup: missing template at $template" >&2
    return 1
  fi

  # Export env vars from .env.local for substitution and current shell.
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  envsubst < "$template" > "$output"

  if [[ "$quiet_flag" != "--quiet" && "${QUIET:-false}" != "true" ]]; then
    echo "codex_setup: rendered $output"
  fi
}

codev() {
  codex_setup --quiet
  codex "$@"
}

alias yolo="codev --dangerously-bypass-approvals-and-sandbox"

# When executed directly, run immediately. When sourced (e.g., from ~/.zshrc),
# the caller can invoke codex_setup as needed.
if [[ "${0##*/}" == "setup-codex.sh" ]]; then
  codex_setup "$@"
fi
