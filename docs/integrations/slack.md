# Slack

Hermes Agent talks to Slack via **Socket Mode** — Slack opens a WebSocket *to* your VM, so the VM doesn't need a public HTTPS endpoint. This matches the `herm` deny-all-ingress firewall posture: no port has to open for Slack to work.

## What you need

| Thing | Where it comes from |
|---|---|
| Slack app | https://api.slack.com/apps — create from manifest (next section) |
| `SLACK_BOT_TOKEN` (`xoxb-…`) | App's OAuth & Permissions → Install to Workspace |
| `SLACK_APP_TOKEN` (`xapp-…`) | App's Basic Information → App-Level Tokens, scope `connections:write` |
| `SLACK_ALLOWED_USERS` (**required**) | Comma-separated Slack member IDs (`U…`). Hermes defaults to **deny-all**: if this is unset, every DM gets logged as `Unauthorized user: U… on slack` and the bot silently drops the message (the typing indicator flashes then nothing). Set `GATEWAY_ALLOW_ALL_USERS=true` instead if you want open access (riskier — anyone in the workspace can talk to the bot). |

## One-time setup

1. **On the VM**, generate the Slack app manifest:
   ```bash
   tailscale ssh herm@herm-vm 'hermes slack manifest --write && cat ~/.hermes/slack-manifest.json' | pbcopy
   ```
   The manifest is now on your Mac clipboard.

2. **In your browser**, open https://api.slack.com/apps → **Create New App** → **From an app manifest** → choose your workspace → paste → **Create**.

3. **In the new Slack app's admin UI**:
   - **OAuth & Permissions** → **Install to Workspace** → approve → copy the `xoxb-…` token.
   - **Basic Information** → **App-Level Tokens** → **Generate Token and Scopes** → name `hermes-socket`, add scope `connections:write` → **Generate** → copy the `xapp-…` token.
   - Find your member ID: click your avatar in Slack → **Profile** → **More** (⋯) → **Copy member ID** (`U…`).

4. **On the VM**, append the tokens to `~/.hermes/.env`:
   ```bash
   tailscale ssh herm@herm-vm
   nano ~/.hermes/.env
   ```
   Add three lines (replace placeholders with your real tokens):
   ```
   SLACK_BOT_TOKEN=xoxb-...
   SLACK_APP_TOKEN=xapp-...
   SLACK_ALLOWED_USERS=U...
   ```

5. **Restart Hermes**:
   ```bash
   pkill -9 -f 'hermes gateway'
   ```
   systemd respawns it within ~5s. The slack adapter loads on startup if both tokens are present.

6. **Verify** via the log:
   ```bash
   tail -5 ~/.hermes/logs/agent.log | grep -i slack
   ```
   Look for `[Slack] Authenticated as @<botname> in workspace <name>` and `✓ slack connected`.

## Talking to the bot

- Invite the bot into a channel: `/invite @<botname>`
- DM the bot directly
- Use slash commands the manifest registers: `/hermes`, `/new`, `/retry`, `/model`, `/sessions`, `/usage`, `/help`, etc. (the manifest declares all of them with Socket Mode, so they work without a public webhook URL)

## If it's not working

| Symptom | Cause | Fix |
|---|---|---|
| Log says `slack-bolt not installed` | The Python extras weren't installed | `~/.local/bin/uv pip install --python ~/.hermes/hermes-agent/venv/bin/python slack-bolt slack-sdk` then restart. (v0.2's `04-install-hermes.sh` installs these on a fresh VM.) |
| Log says `No adapter available for slack` | `slack` is in `agent.disabled_toolsets` | Edit `~/.hermes/config.yaml`, remove `- slack` from the list under `agent.disabled_toolsets`, restart. |
| Log says `slack: missing SLACK_BOT_TOKEN/SLACK_APP_TOKEN` | One or both env vars missing | Re-check `~/.hermes/.env`; both tokens must be present and the file must be readable by `herm`. |
| Bot's typing indicator appears for a moment then nothing | `SLACK_ALLOWED_USERS` not set, or your member ID not in the list | `grep 'Unauthorized user' ~/.hermes/logs/agent.log` will show your member ID. Append `SLACK_ALLOWED_USERS=U06...` (comma-separated for multiple) to `~/.hermes/.env`, `pkill -9 -f 'hermes gateway'`. |
| Bot connects but doesn't respond to channel mentions | `require_mention: true` set or bot not in channel | `/invite @<botname>` into the channel, and `@<botname>` it explicitly. |
| `Channel directory: failed to list Slack channels` warning | OAuth scopes `channels:read` / `groups:read` not yet propagated | Wait 30s and re-check, or re-install the app from manifest. |

## Reusing OpenClaw's tokens

If you ran OpenClaw locally with Slack configured, Hermes' migration script copies `SLACK_BOT_TOKEN` and `SLACK_APP_TOKEN` into the local `~/.hermes/.env`. To move those to the remote VM:

```bash
grep -E '^SLACK_(BOT|APP)_TOKEN=' ~/.hermes/.env \
  | tailscale ssh herm@herm-vm '
      sed -i "/^SLACK_/d" ~/.hermes/.env
      cat >> ~/.hermes/.env
      chmod 0600 ~/.hermes/.env
    '
tailscale ssh herm@herm-vm 'pkill -9 -f "hermes gateway"'
```

This pipes the values via stdin so the tokens never appear in argv or shell history.
