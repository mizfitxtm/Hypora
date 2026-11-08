#!/usr/bin/env bash
# Hypora installer: run as your normal user on fresh Fedora; safe to re-run.
# Enables the COPRs, installs the hypora package, adds the optional apps, then runs hypora-setup.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$REPO/lib.sh"

# With `set -e` a failure ends the script silently, so print what happened and that the install is partial.
trap 'printf "\033[1;31mxx\033[0m Install failed at line %s. Fix the error above and re-run it: it is safe to re-run.\n" "$LINENO" >&2' ERR

# ---------- sanity checks ----------
[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root (sudo is used where needed)."
. /etc/os-release
[ "${ID:-}" = "fedora" ] || die "This script targets Fedora (found: ${ID:-unknown})."

# Baseline: encryption and btrfs cannot be added later, so only report what is missing.

# is_encrypted MOUNTPOINT: true if it is mounted from a dm-crypt (LUKS) volume
is_encrypted() {
  local src type
  src=$(findmnt -fno SOURCE "$1" 2>/dev/null) || return 1
  [ -n "$src" ] || return 1
  src=${src%%[*} # btrfs reports the source as /dev/x[/subvol]
  type=$(lsblk -no TYPE "$src" 2>/dev/null | head -1)
  [ "$type" = crypt ]
}

baseline_note() {
  local missing=0
  # -f (first only): a path can have several mount entries, which would break the tests
  if [ "$(findmnt -fno FSTYPE / 2>/dev/null)" != btrfs ]; then
    warn "/ is not btrfs, so there will be no snapshots (cannot be converted later)"
    missing=1
  fi
  # Judge encryption by where your files are: an encrypted /home protects them even if / is not.
  if [ "$(findmnt -fno TARGET /home 2>/dev/null)" = /home ]; then
    if ! is_encrypted /home; then
      warn "/home is not encrypted, so your files can be read by anyone holding the drive"
      missing=1
    fi
  elif ! is_encrypted /; then
    # no separate /home, so / holds everything
    warn "The disk is not encrypted, so your files can be read by anyone holding the drive"
    missing=1
  fi
  if ! is_encrypted /; then
    log "  note: / is not encrypted. /etc (where NetworkManager keeps Wi-Fi keys) and"
    log "  /var/log stay readable, and the system can be modified by someone with the"
    log "  drive — weaker than full-disk encryption, but not nothing."
  fi
  if rpm -q gnome-shell >/dev/null 2>&1; then
    warn "gnome-shell is installed; Hypora will use its own session but GNOME stays on disk"
    missing=1
  fi
  [ "$missing" -eq 0 ] && log "Baseline looks right: btrfs, encrypted, no competing desktop"
  return 0
}
baseline_note

# Stop the background dnf services first: they hold dnf's lock and every dnf command would wait forever.
for svc in dnf5daemon-server packagekit; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    log "Stopping $svc so it releases the dnf lock (D-Bus restarts it on demand)"
    sudo timeout 60 systemctl stop "$svc" ||
      warn "Could not stop $svc; dnf steps may stall waiting for its lock"
  fi
done

log "Preparing repositories"
dnf_install dnf-plugins-core

# Fedora ships no Hyprland or uwsm; the sdegler/hyprland COPR does and tracks current releases.
sudo dnf copr disable -y solopasha/hyprland >/dev/null 2>&1 || true
# `copr enable` trusts the first key offered, so check it against a recorded fingerprint before installing.
HYPRLAND_COPR_FPR=64BBBF013D1CA5E4BE5B0552C043104207862204
log "Enabling COPR sdegler/hyprland"
sudo dnf copr enable -y sdegler/hyprland
copr_key=$(mktemp)
if curl -fsSL "https://download.copr.fedorainfracloud.org/results/sdegler/hyprland/pubkey.gpg" -o "$copr_key" &&
  key_ok "$copr_key" "$HYPRLAND_COPR_FPR"; then
  sudo rpm --import "$copr_key"
  # Point the repo at the verified key, or dnf would refetch one from the network and accept any key later.
  sudo install -m644 "$copr_key" /etc/pki/rpm-gpg/RPM-GPG-KEY-hypora-hyprland
  copr_pinned=0
  for repo in /etc/yum.repos.d/_copr*sdegler*hyprland*.repo; do
    [ -f "$repo" ] || continue
    sudo sed -i 's|^gpgkey=.*|gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-hypora-hyprland|' "$repo" &&
      copr_pinned=1
  done
  [ "$copr_pinned" -eq 1 ] || warn "Could not pin the Hyprland COPR key; dnf may fetch it again"
  log "Hyprland COPR signing key verified and pinned"
else
  rm -f "$copr_key"
  sudo dnf copr disable -y sdegler/hyprland >/dev/null 2>&1 || true
  die "The Hyprland COPR signing key did not match the expected fingerprint. Stopping."
fi
rm -f "$copr_key"
available quickshell || die "quickshell not found in enabled repos (it ships in Fedora 42+)."

# Extras (virtualization, network tools) are asked about, not default; INSTALL_EXTRAS=yes|no answers ahead.
want_extras() {
  case "${INSTALL_EXTRAS:-}" in
  yes | y | 1) return 0 ;;
  no | n | 0) return 1 ;;
  esac
  rpm -q libvirt-daemon >/dev/null 2>&1 && return 0
  if [ ! -t 0 ]; then
    log "Skipping virtualization and network tools (no terminal to ask; set INSTALL_EXTRAS=yes)"
    return 1
  fi
  printf '\n%s\n%s\n' \
    "Optional: virtualization (libvirt, QEMU, virt-manager) and network tools (nmap," \
    "aircrack-ng, wireshark). Adds you to the libvirt and wireshark groups." >&2
  read -r -p "Install them? [y/N] " answer
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}
if want_extras; then EXTRAS=yes; else EXTRAS=no; fi

# Bundled apps past the core desktop are asked about; INSTALL_APPS answers ahead, and no terminal means yes.
want_apps() {
  case "${INSTALL_APPS:-}" in
  yes | y | 1) return 0 ;;
  no | n | 0) return 1 ;;
  esac
  [ -t 0 ] || return 0
  printf '\n%s\n%s\n' \
    "Optional: extra apps (Bitwarden, LocalSend, RustDesk, Lutris, Spotify, Flatseal," \
    "Warehouse). The core desktop, including a browser, is installed either way." >&2
  read -r -p "Install them? [Y/n] " answer
  case "$answer" in [Nn]*) return 1 ;; *) return 0 ;; esac
}
if want_apps; then APPS=yes; else APPS=no; fi

# Browser (a sandboxed flatpak): BROWSER=firefox|chromium|zen|brave answers ahead; no terminal means Firefox.
pick_browser() {
  case "${BROWSER:-}" in
  firefox | chromium | zen | brave)
    echo "$BROWSER"
    return
    ;;
  esac
  if [ ! -t 0 ]; then
    echo firefox
    return
  fi
  printf '\n%s\n  1) Firefox (default)\n  2) Chromium\n  3) Zen\n  4) Brave\n' "Choose a browser:" >&2
  read -r -p "Number [1]: " answer
  case "$answer" in 2) echo chromium ;; 3) echo zen ;; 4) echo brave ;; *) echo firefox ;; esac
}
BROWSER=$(pick_browser)
case "$BROWSER" in
chromium) BROWSER_APP=org.chromium.Chromium ;;
zen) BROWSER_APP=app.zen_browser.zen ;;
brave) BROWSER_APP=com.brave.Browser ;;
*) BROWSER_APP=org.mozilla.firefox ;;
esac


# Hypora's own COPR. HYPORA_COPR_FPR is the repo key's fingerprint, filled in once the COPR exists; empty skips the check.
HYPORA_COPR=${HYPORA_COPR:-mizfitxtm/hypora}
HYPORA_COPR_FPR=
log "Enabling COPR $HYPORA_COPR"
dnf_run copr enable -y "$HYPORA_COPR"
[ -n "$HYPORA_COPR_FPR" ] || warn "The Hypora COPR key is not pinned yet, so dnf trusts whatever key the COPR offers"

log "Installing Hypora (this brings in the required packages)"
dnf_install hypora
# `install` leaves an older copy as it is, so a re-run also upgrades
dnf_run upgrade -y hypora || true
DATA=/usr/share/hypora

# Only installed if you opt in (see want_extras)
EXTRAS_PKGS=(nmap aircrack-ng wireshark wireshark-cli)

if [ "$EXTRAS" = yes ]; then
  log "Installing virtualization (@virtualization group)"
  # Without virt-viewer: its remote-viewer duplicates RustDesk and virt-manager has its own console.
  dnf_run group install -y virtualization --exclude=virt-viewer ||
    warn "Could not install the virtualization group"
  dnf_install --skip-unavailable "${EXTRAS_PKGS[@]}" ||
    warn "Some network tools could not be installed"
fi
# Remove virt-viewer if an earlier install added it (nothing depends on it)
if rpm -q virt-viewer >/dev/null 2>&1; then
  log "Removing virt-viewer (remote-viewer); RustDesk replaces it"
  sudo dnf remove -y virt-viewer || warn "Could not remove virt-viewer"
fi

# An earlier version installed RustDesk's unsigned RPM. The Flathub build replaces it.
if rpm -q rustdesk >/dev/null 2>&1; then
  log "Removing the RustDesk RPM (the verified Flathub build replaces it)"
  sudo dnf remove -y rustdesk || warn "Could not remove the RustDesk RPM"
fi

# GNOME Help documents a shell that is not running; hypora-replace-de removes it only while a desktop is detected.
if rpm -q yelp >/dev/null 2>&1; then
  log "Removing GNOME Help (yelp)"
  sudo dnf remove -y yelp || warn "Could not remove yelp"
fi

# Flatpak: Flathub is added as a system remote, installed apps are skipped, SKIP_FLATPAKS=1 installs none.
log "Setting up Flatpak"
dnf_install flatpak
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo ||
  warn "Could not add the Flathub remote"

# Apps handling untrusted input (the browser) are sandboxed flatpaks; the rest are native.
FLATPAKS=(
  "$BROWSER_APP" # Firefox is publisher-verified by Mozilla; the others come from Flathub as published
)
# Bundled apps, installed only when want_apps said yes
APP_FLATPAKS=(
  io.github.flattool.Warehouse # manage installed flatpaks and their leftover data
  com.github.tchx84.Flatseal   # review and change each flatpak's permissions
  com.bitwarden.desktop
  com.yubico.yubioath # Yubico Authenticator: one-time codes from a YubiKey
  org.localsend.localsend_app
  # Remote desktop from Flathub: publisher-verified, unlike the project's unsigned RPM.
  com.rustdesk.RustDesk
  # Steam is native (installed below) because the flatpak sandbox gets in the way of controllers and game libraries.
  net.lutris.Lutris
  com.spotify.Client # sandboxed, rather than an unmaintained terminal client
)
if [ "${SKIP_FLATPAKS:-0}" = "1" ]; then
  log "Skipping Flatpak apps (SKIP_FLATPAKS=1)"
else
  log "Installing Flatpak apps (this pulls a few GB the first time)"
  [ "$APPS" = yes ] && FLATPAKS+=("${APP_FLATPAKS[@]}")
  for app in "${FLATPAKS[@]}"; do
    if flatpak info "$app" >/dev/null 2>&1; then
      log "  $app is already installed"
    else
      sudo flatpak install -y --noninteractive flathub "$app" ||
        warn "Could not install $app"
    fi
  done
  # Only a fresh install gets a default; Default Apps overrides it and hyprland.lua's SUPER+B reads it.
  if [ -z "$(xdg-mime query default text/html 2>/dev/null)" ]; then
    xdg-mime default "$BROWSER_APP.desktop" text/html x-scheme-handler/http x-scheme-handler/https ||
      warn "Could not set $BROWSER as the default browser"
  fi
fi

# Another desktop is offered before setup; hypora-replace-de refuses while you run it, so rerun after rebooting into Hypora.
if "$DATA/bin/hypora-replace-de" list >/dev/null 2>&1; then
  printf '\n'
  "$DATA/bin/hypora-replace-de" list >&2
  printf '\n%s\n%s\n%s\n' \
    "Hypora can remove that desktop: its session, the packages it left lying around," \
    "and the orphaned libraries behind them. The applications and settings schemas" \
    "Hypora itself uses are kept — it is built on some of them and would break." >&2
  if [ -t 0 ] && [ "${REPLACE_DE:-}" != no ]; then
    read -r -p "Remove it now? [y/N] " answer
    case "$answer" in
    [Yy]*) sudo "$DATA/bin/hypora-replace-de" remove ||
      warn "Could not remove the other desktop" ;;
    *) log "Left it alone — run: sudo hypora-replace-de remove" ;;
    esac
  else
    log "Leaving it alone; run: sudo hypora-replace-de remove"
  fi
fi

# Optional repos: RPM Fusion (codecs, NVIDIA) is a separate trust decision, off unless ENABLE_RPMFUSION=yes.
want_rpmfusion() {
  case "${ENABLE_RPMFUSION:-}" in
  yes | y | 1) return 0 ;;
  no | n | 0) return 1 ;;
  esac
  if [ ! -t 0 ]; then
    log "Skipping RPM Fusion (no terminal to ask; set ENABLE_RPMFUSION=yes to enable it)"
    return 1
  fi
  printf '\n%s\n%s\n%s\n' \
    "RPM Fusion (free and nonfree) carries packages Fedora cannot: media codecs," \
    "NVIDIA's own graphics driver, and firmware for some Broadcom and Realtek chips." \
    "It is a third-party repository, so this is your trust decision, not Hypora's." >&2
  printf '  Remove later with: sudo dnf remove rpmfusion-free-release rpmfusion-nonfree-release\n' >&2
  read -r -p "Enable RPM Fusion? [y/N] " answer
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

if rpm -q rpmfusion-free-release >/dev/null 2>&1; then
  log "RPM Fusion already enabled"
elif want_rpmfusion; then
  log "Enabling RPM Fusion"
  rel=$(rpm -E %fedora)
  dnf_run install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$rel.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$rel.noarch.rpm" ||
    warn "Could not enable RPM Fusion"
else
  log "Skipping RPM Fusion"
fi

# Steam is native, not the flatpak, because the sandbox hurts controllers and libraries; it needs rpmfusion-nonfree.
if rpm -q steam >/dev/null 2>&1; then
  log "Steam already installed natively"
elif rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 && available steam; then
  log "Installing Steam (native)"
  dnf_install steam || warn "Could not install Steam"
else
  warn "Steam not installed: it needs RPM Fusion nonfree, which is not enabled"
  warn "  Enable it and run: sudo dnf install steam"
  warn "  Or use the flatpak instead: flatpak install flathub com.valvesoftware.Steam"
fi

# Remove the old Steam flatpak once native Steam is there, never with --delete-data (the library can be hundreds of GB).
if flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
  if rpm -q steam >/dev/null 2>&1; then
    log "Removing the Steam flatpak (native Steam is installed)"
    sudo flatpak uninstall -y com.valvesoftware.Steam ||
      warn "Could not remove the Steam flatpak; you now have two Steams installed"
    warn "The flatpak's games are still at ~/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    warn "  Add that as a library folder in native Steam (Settings > Storage) to reuse them,"
    warn "  or delete it once you are sure: rm -rf ~/.var/app/com.valvesoftware.Steam"
  else
    warn "Keeping the Steam flatpak: native Steam is not installed, so removing it"
    warn "  would leave you with no Steam at all"
  fi
fi

# AI tools (optional): Claude Code installs only on yes; INSTALL_CLAUDE answers ahead, and non-interactive runs skip it.
CLAUDE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

# Claude Code can arrive via Anthropic's script or npm, so check all three locations before asking.
claude_installed() {
  rpm -q claude-code >/dev/null 2>&1 && return 0
  command -v claude >/dev/null 2>&1 && return 0
  [ -x "$HOME/.local/bin/claude" ]
}

want_claude() {
  case "${INSTALL_CLAUDE:-}" in
  yes | y | 1) return 0 ;;
  no | n | 0) return 1 ;;
  esac
  if [ ! -t 0 ]; then
    log "Skipping Claude Code (no terminal to ask; set INSTALL_CLAUDE=yes to install it)"
    return 1
  fi
  printf '\n%s\n%s\n' \
    "Claude Code is an AI coding assistant from Anthropic. It needs a paid Claude plan." \
    "It installs from Anthropic's signed dnf repository and can be removed later with:" >&2
  printf '  sudo dnf remove claude-code && sudo rm /etc/yum.repos.d/claude-code.repo\n' >&2
  read -r -p "Install Claude Code? [y/N] " answer
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

if claude_installed; then
  log "Claude Code already installed"
elif want_claude; then
  log "Installing Claude Code"
  # Check the signing key against Anthropic's published fingerprint before rpm trusts it
  key=$(mktemp)
  if curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o "$key" &&
    key_ok "$key" "$CLAUDE_KEY_FPR"; then
    sudo rpm --import "$key"
    # The repo file points at this verified copy, not at a key URL (see the COPR above)
    sudo install -m644 "$key" /etc/pki/rpm-gpg/RPM-GPG-KEY-claude-code
    sudo install -m644 "$REPO/system/yum.repos.d/claude-code.repo" /etc/yum.repos.d/claude-code.repo
    dnf_install claude-code || warn "Could not install claude-code"
  else
    warn "Claude Code signing key missing or fingerprint mismatch; skipped Claude Code"
  fi
  rm -f "$key"
else
  log "Skipping Claude Code"
fi


if [ ${#WARNINGS[@]} -gt 0 ]; then
  printf '\n\033[1;33m %d warning(s) so far:\033[0m\n' "${#WARNINGS[@]}"
  for w in "${WARNINGS[@]}"; do printf '   \033[1;33m!!\033[0m %s\n' "$w"; done
fi

# Last step: hypora-setup prints the final summary and the reboot note.
exec hypora-setup
