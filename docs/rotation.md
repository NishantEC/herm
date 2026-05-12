# Token rotation

`herm rotate` regenerates the Hermes API server bearer token and restarts the gateway. After rotation, the old token stops working within ~30 seconds (next service restart) and any Hermes Desktop / phone clients you've pointed at the old token need re-pairing.

## When to rotate

- **You pasted the token in chat.** (Including with me.) The token is now in conversation logs. Rotate.
- **Suspected device compromise.** Lost a phone with the token saved, etc.
- **Quarterly hygiene.** A standing rotation cadence shrinks the window for forgotten leaks.

## How to rotate

```bash
herm rotate
```

What this does:

1. Connects to the VM via `gcloud compute ssh --tunnel-through-iap`.
2. Generates a fresh 32-byte random base64 string.
3. Overwrites `/home/herm/.hermes/.api-token` (mode 0600, owned by `herm`).
4. `sed -i` updates `API_SERVER_KEY` in `/home/herm/.hermes/.env`.
5. `systemctl restart hermes-agent`.
6. Curls `/health` with the new token to confirm it's accepted.
7. Prints the new token **once** to your laptop terminal.

The print-once step is intentional: the token is never re-displayable. Capture it into Hermes Desktop or your password manager immediately.

## After rotation

Update wherever you had the old token:

- **Hermes Desktop** — Settings → connection → paste the new value.
- **Phone HTTP client** — re-scan the QR via `herm qr` to get the fresh token + URL bundle.
- **Anything else** — search your password manager for `ze+lLKc4...`-style strings; replace them.

## What `herm rotate` does NOT touch

- Your Anthropic OAuth token (`sk-ant-oat01-...`). Rotate that via `claude logout` + `claude setup-token`.
- GitHub PATs (`ghp_...`). Rotate at https://github.com/settings/tokens.
- Tailscale auth keys (already single-use; consumed at first node join).
- Provider API keys in `~/.hermes/.env` (`OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`). Edit `.env` directly and `pkill -9 -f 'hermes gateway'`.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `herm rotate` hangs at `gcloud compute ssh` | OS Login external-user restriction | Run from a terminal that's gcloud-auth'd to a non-restricted account, or `tailscale ssh` in manually and run the rotation steps by hand. |
| `/health` test fails with 401 | Service didn't pick up the new `.env` value | Wait 10s; if still failing, `tailscale ssh herm@herm-vm 'pkill -9 -f "hermes gateway"'` and retry. |
| You don't see the new token in the output | The rotation never reached step 6 | Re-run `herm rotate`. Idempotent — generates a fresh value each time. |
