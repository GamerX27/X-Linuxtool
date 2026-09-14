# X-Linuxtool

A simple interactive launcher for X27's collection of Linux setup and tooling scripts. Pick an option from the menu and the matching script is downloaded and run for you.

Scripts are fetched from **Codeberg** (primary) with an automatic fallback to the **GitHub** mirror.

## Repository layout

The Desktop and HomeLab toolboxes used to live in their own repos
(`X27-Linux-Desktop-Toolbox`, `X27-Homelab-ToolBox`); they are now merged into
this repo (full history preserved) so everything ships from one place:

- `Desktop/` — desktop setup scripts: dispatchers in `Desktop/Scripts/`
  (`Desktop-Linux.sh`, `GamingTools.sh`), leaf scripts by category in
  `Desktop/Linux-Desktop/` (Fedora, Bazzite, Gaming, Flatpak, Browser)
- `Homelab/` — server / homelab scripts (Docker, updates)
- `Tools/` — shared utilities (Fastfetch, Sleep Fix, Virtualization)
- `X-Linuxtool.sh` — the menu launcher, which fetches the option you pick from `Desktop/`, `Homelab/`, or `Tools/`

`YTDLP-Easy-Script` remains a separate repo and is fetched from its own location.

## Run it

Run directly from the web with `curl ... | bash`.

**GitHub:**

```bash
curl -fsSL https://raw.githubusercontent.com/GamerX27/X-Linuxtool/refs/heads/main/X-Linuxtool.sh | bash
```

**Codeberg:**

```bash
curl -fsSL https://codeberg.org/X27/X-Linuxtool/raw/branch/main/X-Linuxtool.sh | bash
```

> [!NOTE]
> Pipe to `bash`, not `sh` — the script uses bash-specific features.

### Run locally

```bash
git clone https://codeberg.org/X27/X-Linuxtool.git
cd X-Linuxtool
chmod +x X-Linuxtool.sh
./X-Linuxtool.sh
```

## Menu options

| # | Option | Description |
|---|--------|-------------|
| 1 | Desktop-Linux | Opens a submenu (`Desktop/Scripts/Desktop-Linux.sh`) — see below |
| 2 | HomeLab | HomeLab setup script (`Homelab/X27-Homelab.sh`) |
| 3 | YT-DLP | Install the YT-DLP-Easy script |
| 4 | Fastfetch | Apply a custom Fastfetch configuration |
| 5 | Virtualization | Set up virtualization (KVM/QEMU/libvirt) |

### Desktop-Linux submenu

| # | Option | Description |
|---|--------|-------------|
| 1 | Fedora Post-Setup | Fedora desktop post-install setup |
| 2 | Fedora-Kinoite-Setup | Fedora Kinoite (atomic) setup |
| 3 | Bazzite Setup | Bazzite setup |
| 4 | Brave | Debloat / harden the Brave browser |
| 5 | Proton/Wine & Gaming | Opens a further submenu — Proton-CachyOS, Kron4ek Wine builds, or the full gaming stack (Steam, Wine, MangoHud, Lutris, Heroic, Discord) |
| 6 | Sleep Fix | Fix sleep issues on Gigabyte boards |
| 7 | Flatpak Apps | Install a curated set of Flatpak apps |
| 8 | Flatpak Updates | Schedule Flatpak updates via a systemd timer |

## Requirements

- A Linux system with `bash`
- `curl` or `wget` (used to fetch the sub-scripts)
- `apt` or `dnf` for automatic dependency installation (otherwise install `wget`, `git`, and `curl` manually)
- `sudo` access for options that perform system changes

The script checks for `wget`, `git`, and `curl` on startup and attempts to install any that are missing.
