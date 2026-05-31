# Troubleshooting

## `herm up` fails with `credentials: could not find default credentials`

Terraform's Google provider and GCS backend use Application Default Credentials (ADC), which are separate from `gcloud auth login`. Run this once:

```bash
gcloud auth application-default login
```

It opens a browser, you grant scopes, it writes `~/.config/gcloud/application_default_credentials.json`. Then re-run `herm up`. `herm init` does this for you on fresh setups; this error only appears if the ADC file is missing or was deleted.

## `herm up` hangs after "Provisioning VM..."

Cloud-init can take 6–10 minutes on a cold boot. Check progress:

```bash
gcloud compute instances get-serial-port-output herm-vm --zone <zone>
```

Look for `cloud-init: finished` near the end. If you see a script error, the line number points at `cloud-init/scripts/*.sh`.

## VM is up but `tailscale ssh herm@herm-vm` says "no such host"

The VM may not have completed the tailnet join. Tail the Tailscale daemon log:

```bash
gcloud compute ssh herm-vm --zone <zone> --tunnel-through-iap -- sudo journalctl -u tailscaled -f
```

Common causes:

- Tailscale auth key expired or was already used (they're single-use). Generate a fresh one and rerun `herm up`.
- The Secret Manager secret was created by a different service account. Run `herm nuke && herm up` to reset.

## `herm down` says "disk still attached"

That's expected — the persistent disk is configured with `deletion_policy = "RETAIN"`. To force destroy, use `herm nuke`.

## I see GCP billing charges after `herm down`

`herm down` does NOT delete the persistent disk or the GCS backup bucket (by design). Those should idle at ~$2/mo combined. If you see more:

```bash
gcloud compute disks list --filter="name~herm"
gsutil ls -L gs://<your-project>-herm-backups
```

If something unexpected is there, `herm nuke` will clean up everything herm-managed; you may also have orphaned resources from a failed `terraform apply` — see `terraform/` and use `terraform state list`.
