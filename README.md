# Nexus Node Installer

Automated Nexus node installer for Linux.

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/titbm/nexus-node-installer/main/nexus-install.sh | bash
```

## Requirements

- Debian/Ubuntu with apt package manager
- sudo privileges
- internet connection

## Management

```bash
# View logs
tmux a -t nexus

# Stop node
tmux kill-session -t nexus

# Exit logs (Ctrl+B, D)
```

## Troubleshooting

### Dependencies
```bash
sudo apt update && sudo apt install curl tmux jq cron -y
```

### Sessions
```bash
tmux list-sessions
tmux kill-session -t nexus
```
