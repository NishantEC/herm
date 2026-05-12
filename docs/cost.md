# Cost — herm v0.1

All figures are list price in USD, `us-central1`, as of the time this doc was written. Your mileage will vary.

| Item | Approx. monthly |
|---|---|
| `e2-small` VM, on 24/7 (730h) | ~$11.00 |
| 10GB PD-SSD | ~$1.70 |
| GCS backup bucket (standard, 10GB stored, daily versions, 30-day retention) | <$0.20 |
| Secret Manager (1 secret in v0.1) | <$0.10 |
| Cloud Logging (30-day retention, low volume) | <$0.50 |
| Network egress (low for chat-style API) | <$0.50 |
| **GCP subtotal — idle** | **~$14/mo** |

Plus your LLM costs. v0.1 only runs Hermes Agent; you bring an LLM provider key during agent configuration. Mostly $0 if you use a subscription tier (Anthropic, Gemini) rather than per-token API.

## Stopping the meter

- `herm down` deletes the VM. Idle cost drops to ~$2/mo (disk + backup bucket).
- `herm nuke` deletes everything. Idle cost: $0.

## Budget alert

`herm init` creates a GCP Budget alert at $25/mo by default. To change:

```bash
herm init --budget 50    # set $50/mo
```

Pings are emailed to the billing account's notification address at 50%, 80%, and 100% spend.

## What can blow up cost

- Leaving the VM up while running expensive LLM calls in a loop. The 30-minute per-turn watchdog limits the blast radius.
- Generating huge volumes of Cloud Logging output. Hermes' default logging is bounded; if you turn on verbose logging, watch this line item.
- Accidentally promoting the VM to a larger machine type. Locked in `variables.tf` — change at your peril.
