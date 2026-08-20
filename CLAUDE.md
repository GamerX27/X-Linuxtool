# X-Linuxtool

Interactive launcher for X27's Linux setup/tooling scripts. `X-Linuxtool.sh` is
the menu entrypoint; it fetches and runs the picked script from `Desktop/`
(desktop setup: Fedora, Bazzite, Gaming, Flatpak, Browser, Tools) or
`Homelab/` (server/Docker scripts). Scripts are plain bash, fetched from
Codeberg (primary) with a GitHub mirror fallback, and are meant to be run via
`curl | bash` as well as locally. The project is built around bash scripting,
with JSON files used here and there (e.g. for config/data).

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
  decorative section banners.
- **Never `git commit` or `git push` without the user explicitly asking for
  it in that moment.** Making changes to files is fine; committing/pushing is
  not implied by that and always needs a direct go-ahead first.
