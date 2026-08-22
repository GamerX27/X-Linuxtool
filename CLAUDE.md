# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# X-Linuxtool

Interactive launcher for X27's Linux setup/tooling scripts. `X-Linuxtool.sh` is
the menu entrypoint; it fetches and runs the picked script from `Desktop/`
(desktop setup: Fedora, Bazzite, Gaming, Flatpak, Browser, Tools) or
`Homelab/` (server/Docker scripts). Scripts are plain bash, fetched from
Codeberg (primary) with a GitHub mirror fallback, and are meant to be run via
`curl | bash` as well as locally. The project is built around bash scripting,
with JSON files used here and there (e.g. for config/data).

There is no build, lint, or test tooling (no package.json, Makefile, CI, or
shellcheck config) — this is pure bash. To verify a change, run the affected
script directly: `bash Desktop/<area>/<Script>.sh` for a leaf script, or
`./X-Linuxtool.sh` locally to drive it through the full menu chain.

## Architecture

**Dispatch chain.** `X-Linuxtool.sh` shows the top-level menu, downloads the
chosen script to `/tmp`, and runs it. Several `Desktop/`/`Homelab/` scripts are
themselves dispatchers with their own submenu (`Fedora.sh` → Fedora
Post-Setup/Kinoite/Bazzite; `GamingTools.sh` → Proton-CachyOS/Wine/Gaming
Setup; `Homelab/X27-Homelab.sh` → Docker Install/Auto-Update/Compose Updater),
fetching and running the next script in the same way. Expect multi-hop
downloads before reaching the script that actually does work.

**Fetching.** Every dispatcher script defines its own `_download`/`fetch_file`
(or `fetch_repo_file`) pair: try Codeberg raw URL, fall back to the GitHub
mirror on failure. `X-Linuxtool.sh` additionally detects when it's running
from a local clone (via `BASH_SOURCE`) and exports `X27_LOCAL_ROOT`; every
downstream script checks that env var first and copies the on-disk file
instead of re-downloading, so local edits take effect immediately when
testing through the menu.

**Self-contained scripts, by design.** Nearly every script duplicates the same
Nord-palette color setup and logging helpers (`ui_info`/`ui_ok`/`ui_warn`/
`ui_err` in menu/dispatcher scripts, `log`/`ok`/`warn`/`err` in some leaf
scripts like `Fedora-PostSetup.sh`) instead of sourcing a shared lib. This is
intentional, not an oversight — each script must keep working when piped
directly via `curl | bash` on its own, so it can't depend on other files
existing on disk. Don't "DRY up" this duplication across files.

**Interactive input under `curl | bash`.** When a script is piped into bash,
stdin is consumed by the pipe itself. Menu/dispatcher scripts work around this
with an `INPUT` variable that prefers `/dev/tty` (falling back to
`/dev/stdin`) and pass it down explicitly (`bash sub.sh < "$INPUT"`) so
prompts still read from the real terminal. Any new interactive `read` in a
script that gets chained this way needs the same treatment.

**Privilege model varies by script — match the existing one, don't invent a
third.** Some scripts are invoked already-elevated by their dispatcher
(`sudo bash script.sh`, e.g. Homelab scripts, Kinoite/Bazzite setup, Gaming
Setup). Others are meant to run as the normal user and manage sudo
internally — `Fedora-PostSetup.sh` calls `sudo -v` once up front, then runs a
backgrounded `sudo -n true` keepalive loop so root-requiring steps never
re-prompt while user-level steps (shell config, Konsole/dotfiles) run
unauthenticated.

## Rules

- **No unnecessary changes.** Touch only what the task requires. Don't
  refactor, rename, reformat, or "improve" code that wasn't asked about.
- **Keep it straightforward.** Don't add abstractions, flags, or config
  options for hypothetical future needs. If a bug fix is 3 lines, write 3
  lines.
- **Keep the code clean.** Match the existing style in each file (Nord color
  helpers, `ui_info`/`ui_ok`/`ui_warn`/`ui_err` output functions, function
  naming) rather than introducing a new pattern.
- **Minimal comments.** Default to no comments. Only add one when it explains
  a non-obvious WHY (a workaround, a distro/env quirk, a magic number) —
  never a comment that just restates what the next line does, and never
  decorative section banners. This includes file-top header comments that
  restate the filename or summarize what the script does (that belongs in
  the commit message / this doc, not the file) and comments repeating a
  function's own signature (`# foo <arg1> <arg2>`).
- **Never `git commit` or `git push` without the user explicitly asking for
  it in that moment.** Making changes to files is fine; committing/pushing is
  not implied by that and always needs a direct go-ahead first.
