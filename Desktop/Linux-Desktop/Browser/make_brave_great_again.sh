#!/bin/bash
# It may say in the privacy settings the mic and camera are still on, but they are blocked from being accessed.
set -e

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_BLUE=$'\033[34m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_GREEN=$'\033[32m'
    C_MAGENTA=$'\033[35m'
else
    C_RESET="" C_BOLD="" C_DIM=""
    C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA=""
fi

ui_info()    { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()      { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()    { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()     { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step()    { printf '\n%s  ➤ %s%s\n' "$C_MAGENTA$C_BOLD" "$1" "$C_RESET"; }
ui_rule()    { printf '%s──────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"; }

has_brave_flatpak() {
  command -v flatpak >/dev/null 2>&1 && flatpak info com.brave.Browser >/dev/null 2>&1
}
brave_flatpak_scope() {
  # returns "system" or "user"
  flatpak info com.brave.Browser 2>/dev/null | awk -F': *' '/^Installation:/ {print tolower($2)}'
}

sudo mkdir -p /etc/brave/policies/managed

sudo tee /etc/brave/policies/managed/make_brave_great_again.json >/dev/null <<'JSON'
{
  "RestoreOnStartup": 5,
  "BraveAIChatEnabled": false,
  "BraveWalletDisabled": true,
  "TorDisabled": true,
  "BraveRewardsDisabled": true,

  "BraveP3AEnabled": false,
  "BraveStatsPingEnabled": false,
  "BraveWebDiscoveryEnabled": false,

  "MetricsReportingEnabled": false,
  "BackgroundModeEnabled": false,
  "SafeBrowsingExtendedReportingEnabled": false,
  "UrlKeyedAnonymizedDataCollectionEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "PromotionsEnabled": false,
  
  "PasswordManagerEnabled": false,
  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false,

  "SpellCheckServiceEnabled": false,
  "SpellcheckEnabled": false,
  "TranslateEnabled": false,

  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Qwant",
  "DefaultSearchProviderSearchURL": "https://www.qwant.com/?q={searchTerms}",
  "DefaultSearchProviderSuggestURL": "https://api.qwant.com/v3/suggest?q={searchTerms}",

  "BraveVPNDisabled": true,
  "BraveNewsDisabled": true,
  "BraveTalkDisabled": true,

  "DefaultGeolocationSetting": 2,
  "DefaultNotificationsSetting": 2,
  "VideoCaptureAllowed": false,
  "AudioCaptureAllowed": false,

  "DefaultJavaScriptOptimizerSetting": 2,
  "ChromeVariations": 2,
  "DefaultSensorsSetting": 2,
  "SafeBrowsingProxiedRealTimeChecksAllowed": false,
  "SafeBrowsingProtectionLevel": 0,
  "DefaultPopupsSetting": 2,
  "ForcedLanguages": ["no-NB"],
  "EnableMediaRouter": false,

  "URLBlocklist": [
    "https://variations.brave.com/*",
    "https://safebrowsing.brave.com/*"
  ]
}
JSON

ui_ok "Brave policies written: /etc/brave/policies/managed/make_brave_great_again.json"

if has_brave_flatpak; then
  scope="$(brave_flatpak_scope)"
  if [ "$scope" = "system" ]; then
    ui_info "Detected Brave (Flatpak, system install) — applying filesystem override..."
    sudo flatpak override --system com.brave.Browser --filesystem=/etc/brave/policies/managed:ro
  else
    ui_info "Detected Brave (Flatpak, user install) — applying filesystem override..."
    flatpak override --user com.brave.Browser --filesystem=/etc/brave/policies/managed:ro
  fi
  ui_ok "Flatpak override applied."
else
  ui_warn "Brave Flatpak not detected — no Flatpak override needed."
fi

ui_step "Adding Brave telemetry domains to /etc/hosts"
ui_info " - variations.brave.com"
ui_info " - safebrowsing.brave.com"
ui_info " - analytics.brave.com"

if ! grep -q "variations.brave.com" /etc/hosts; then
  ui_info "Adding variations.brave.com..."
  echo -e "0.0.0.0 variations.brave.com\n:: variations.brave.com" | sudo tee -a /etc/hosts >/dev/null
  ui_ok "variations.brave.com entries added."
else
  ui_warn "variations.brave.com already exists in /etc/hosts. Skipping."
fi

if ! grep -q "safebrowsing.brave.com" /etc/hosts; then
  ui_info "Adding safebrowsing.brave.com..."
  echo -e "0.0.0.0 safebrowsing.brave.com\n:: safebrowsing.brave.com" | sudo tee -a /etc/hosts >/dev/null
  ui_ok "safebrowsing.brave.com entries added."
else
  ui_warn "safebrowsing.brave.com already exists in /etc/hosts. Skipping."
fi

if ! grep -q "analytics.brave.com" /etc/hosts; then
  ui_info "Adding analytics.brave.com..."
  echo -e "0.0.0.0 analytics.brave.com\n:: analytics.brave.com" | sudo tee -a /etc/hosts >/dev/null
  ui_ok "analytics.brave.com entries added."
else
  ui_warn "analytics.brave.com already exists in /etc/hosts. Skipping."
fi


ui_ok "All done."


# Credits
# Chromium Policy: https://chromeenterprise.google/policies/
# Brave Policy: https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy
