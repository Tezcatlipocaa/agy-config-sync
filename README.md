# agy-config-sync

[![GitHub Template](https://img.shields.io/badge/GitHub-Template-blue?style=flat&logo=github)](https://github.com/Tezcatlipocaa/agy-config-sync/generate)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Platform: Windows | macOS | Linux](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](https://github.com/Tezcatlipocaa/agy-config-sync)
[![Language: English / Español](https://img.shields.io/badge/Language-English%20%7C%20Espa%C3%B1ol-orange)](README.es.md)

Multi-machine configuration synchronization and AI-assisted curation for **Google Antigravity CLI (`agy`)**.

[👉 Leer documentación en Español (README.es.md)](README.es.md)

---

## Features

- 🔄 **Multi-Machine Sync**: Connect and harmonize $1 \dots N$ computers (work laptops, home PCs, servers) without losing machine-specific setups.
- 🤖 **AI-Assisted Curation**: Open `agy` inside the repo and let the AI analyze snapshots across all your machines to build an optimized master config.
- 🛡️ **Zero-Leak Guardian**: Pre-commit hooks block API keys, tokens, and personal home paths automatically. Secrets stay in `.env.local`.
- ⚡ **Auto-Discovery**: Automatically classifies your installed plugins into direct copy (lightweight), git upstreams with pinned commits, or templated configurations.
- 💻 **Cross-Platform**: Full parity between Windows PowerShell (`sync.ps1`) and macOS/Linux Bash (`sync.sh`).

---

## Quick Start (3 Steps)

### 1. Create your private repository
Click **[Use this template](https://github.com/Tezcatlipocaa/agy-config-sync/generate)** on GitHub to create your own private repository, then clone it:

```bash
# Windows PowerShell:
git clone https://github.com/<your-username>/<your-repo-name>.git C:\Users\<you>\agy-config-sync
cd C:\Users\<you>\agy-config-sync

# macOS / Linux / WSL:
git clone https://github.com/<your-username>/<your-repo-name>.git ~/.agy-config-sync
cd ~/.agy-config-sync
```

### 2. Capture your current machine (Non-destructive)
```bash
# Windows:
.\sync.ps1 snapshot -Profile my-primary-pc

# macOS / Linux:
./sync.sh snapshot my-primary-pc
```
Commit and push your initial snapshot:
```bash
git add .
git commit -m "feat: capture initial snapshot for my-primary-pc"
git push
```

### 3. On any other computer:
Repeat the clone, run `snapshot`, and open `agy` to merge and align your machines:
```bash
# Open Antigravity CLI in this folder:
agy
```
Ask the agent:
> *"Compare the snapshots of all my registered machines and prepare the master staging"*

Finally, close `agy` and apply:
```bash
# Windows:
.\sync.ps1 apply

# macOS / Linux:
./sync.sh apply
```

---

## Commands Reference

| Command (PowerShell / Bash) | Description |
| :--- | :--- |
| `.\sync.ps1 status` / `./sync.sh status` | Show current host, profile, and staging status |
| `.\sync.ps1 add-machine <name>` / `./sync.sh add-machine <name>` | Register a machine alias in `host-map.json` |
| `.\sync.ps1 snapshot` / `./sync.sh snapshot` | Capture `~/.gemini` state cleanly without secrets |
| `.\sync.ps1 stage` / `./sync.sh stage` | Assemble the `staging/` directory for the active machine |
| `.\sync.ps1 apply [-DryRun]` / `./sync.sh apply [--dry-run]` | Apply configuration to `~/.gemini` (requires `agy` closed) |

---

## License
MIT © Dario
