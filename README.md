# Terminolgy Widgets

Widget scripts, monitoring dashboards, and companion tools for [Terminolgy](https://github.com/PhenixStar/Terminlogy).

## Scripts

| Script | Purpose |
|--------|---------|
| ssh-health.ps1 | SSH connection health monitor |
| docker-manager.sh | Docker container status via SSH |
| cf-tunnel-status.sh | Cloudflare tunnel health |
| mikrotik-dashboard.sh | MikroTik router dashboard |
| git-sync-status.sh | Multi-machine git sync status |
| quick-connect.sh | SSH bookmark menu |
| companion.sh | Interactive tool picker |
| ctx-launch.sh | Context-aware tool launcher |
| remote-browse.sh | Open URLs through SSH tunnel |
| deploy-companion.sh | Deploy scripts to remote machines |

## Shared Libraries

- `lib/colors.sh` — ANSI color codes and status icons
- `lib/ssh-helper.sh` — Resilient SSH connection wrapper
- `lib/widget-state.sh` — Widget state management

## Installation

```bash
git clone https://github.com/PhenixStar/terminolgy-widgets.git ~/terminolgy-widgets
```

Then add widget entries to Terminolgy's `~/.config/terminolgy/widgets.json`.

## Configuration

### widgets.json

A sample `widgets.json` with all widget definitions is included at `config/widgets.json`.
Copy the entries you want into your Terminolgy config.

### Workspace automation

Run `scripts/apply-workspace-ids.ps1` to scope widgets to workspaces.

## License

Apache-2.0
