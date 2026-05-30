# Fortra

Salesforce DX project for the Fortra org — source-controlled metadata, deployment scripts, and supporting assets.

## Branches

- `main` — minimal scaffolding (this README).
- `uat` — working branch tracking the FortraUAT sandbox; contains the full `force-app/` metadata tree, migration scripts, and ticket working notes.

## Project layout (on `uat`)

| Path | Purpose |
| --- | --- |
| `force-app/` | Salesforce DX source format metadata. |
| `sfdx-project.json` | DX project config (API v66.0, `force-app` default package). |
| `scripts/` | Anonymous Apex and shell helpers for one-off operations. |
| `docs/` | Project documentation and runbooks. |
| `*Jira/` | Per-ticket working notes (RCA analyses, diagnostic logs, migration roadmaps). |

## Common commands

```bash
# Authenticate against a sandbox
sf org login web --alias FortraUAT --instance-url https://test.salesforce.com

# Retrieve metadata into the local project
sf project retrieve start --target-org FortraUAT --metadata <MetadataType>:<Name>

# Validate a deployment without committing
sf project deploy start --target-org FortraUAT --dry-run --source-dir force-app

# Deploy
sf project deploy start --target-org FortraUAT --source-dir force-app
```

## References

- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
