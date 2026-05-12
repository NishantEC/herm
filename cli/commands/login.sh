# shellcheck shell=bash
# herm login — initiate auth flows for the CLIs running on the VM.
# Each provider has its own interactive prompt; this just wires up the SSH
# transport and drops the owner into the auth flow.

herm::__login_run() {
  # Run a command on the VM via IAP SSH, with allocated tty for interactive flows.
  local cmd="$1"
  local project_id zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  herm::require_cmd gcloud
  herm::log "running on $hostname: $cmd"
  gcloud compute ssh "$hostname" \
    --project "$project_id" \
    --zone "$zone" \
    --tunnel-through-iap \
    -- -t "sudo -u herm -H bash -lc '$cmd'"
}

herm::cmd::login() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH — run 'herm init' first"
  fi

  local provider="${1:-}"
  if [[ -z $provider ]]; then
    cat <<EOF >&2
usage: herm login <provider>

providers:
  claude     Claude Code OAuth (Pro/Max subscription)
  gh         GitHub device-code auth
  gemini     Gemini CLI Google account auth
  codex      OpenAI Codex CLI
  opencode   OpenCode CLI
  goose      Goose CLI
  all        Run claude, gh, gemini in sequence

each provider opens a browser-based flow you complete on your laptop.
EOF
    return 2
  fi

  case "$provider" in
    claude)
      herm::__login_run 'command -v claude >/dev/null || npm install -g @anthropic-ai/claude-code; claude setup-token'
      ;;
    gh)
      herm::__login_run 'command -v gh >/dev/null || { apt-get update && apt-get install -y gh; }; gh auth login --web -h github.com'
      ;;
    gemini)
      herm::__login_run 'command -v gemini >/dev/null || npm install -g @google/gemini-cli; gemini auth login'
      ;;
    codex)
      herm::__login_run 'command -v codex >/dev/null || npm install -g @openai/codex; codex login'
      ;;
    opencode)
      herm::__login_run 'command -v opencode >/dev/null || npm install -g opencode-ai; opencode auth login'
      ;;
    goose)
      herm::__login_run 'command -v goose >/dev/null || curl -fsSL https://github.com/block/goose/releases/latest/download/download_cli.sh | bash; goose configure'
      ;;
    all)
      herm::cmd::login claude || herm::warn "claude login failed; continuing"
      herm::cmd::login gh     || herm::warn "gh login failed; continuing"
      herm::cmd::login gemini || herm::warn "gemini login failed; continuing"
      ;;
    *)
      herm::die "unknown provider: $provider"
      ;;
  esac
}
