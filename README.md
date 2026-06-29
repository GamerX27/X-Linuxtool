# X-Linuxtool

A simple interactive launcher for X27's collection of Linux setup and tooling scripts. Pick an option from the menu and the matching script is downloaded and run for you.

Scripts are fetched from **Codeberg** (primary) with an automatic fallback to the **GitHub** mirror.

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
| 1 | Fedora Desktop | Fedora desktop setup from the Linux Desktop Toolbox |
| 2 | HomeLab | HomeLab setup script |
| 3 | Brave Debloat | Debloat / harden the Brave browser |
| 4 | YT-DLP-Easy Installer | Install the YT-DLP-Easy script |
| 5 | Kron4ek Wine Installer | Install Wine builds from Kron4ek |
| 6 | Proton CachyOS Installer | Install Proton-CachyOS |
| 7 | Gigabyte Sleep Fix | Fix sleep issues on Gigabyte boards |
| 8 | Custom Fastfetch Config | Apply a custom Fastfetch configuration |
| 9 | Virtualization Setup | Set up virtualization (KVM/QEMU/libvirt) |

## Requirements

- A Linux system with `bash`
- `curl` or `wget` (used to fetch the sub-scripts)
- `apt` or `dnf` for automatic dependency installation (otherwise install `wget`, `git`, and `curl` manually)
- `sudo` access for options that perform system changes

The script checks for `wget`, `git`, and `curl` on startup and attempts to install any that are missing.
