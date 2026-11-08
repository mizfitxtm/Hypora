#!/usr/bin/env bash
# Optional installer. The usual way is the three commands in the readme; this runs them with each COPR's
# signing key checked against a recorded fingerprint first, then runs hypora-setup, which asks about the rest.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$REPO/lib.sh"

trap 'printf "\033[1;31mxx\033[0m Install failed at line %s. Fix the error above and re-run it: it is safe to re-run.\n" "$LINENO" >&2' ERR

# ---------- sanity checks ----------
[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root (sudo is used where needed)."
. /etc/os-release
[ "${ID:-}" = "fedora" ] || die "This script targets Fedora (found: ${ID:-unknown})."

# enable_copr OWNER/PROJECT FINGERPRINT: `copr enable` trusts the first key offered, so check it against a recorded fingerprint.
enable_copr() {
  local repo=$1 fpr=$2 owner=${1%/*} project=${1#*/} key f pinned=0
  log "Enabling COPR $repo"
  dnf_run copr enable -y "$repo"
  key=$(mktemp)
  if curl -fsSL "https://download.copr.fedorainfracloud.org/results/$repo/pubkey.gpg" -o "$key" &&
    key_ok "$key" "$fpr"; then
    sudo rpm --import "$key"
    # Point the repo at the verified key, or dnf would refetch one from the network and accept any key later.
    sudo install -m644 "$key" "/etc/pki/rpm-gpg/RPM-GPG-KEY-hypora-$project"
    for f in /etc/yum.repos.d/_copr*"$owner"*"$project"*.repo; do
      [ -f "$f" ] || continue
      sudo sed -i "s|^gpgkey=.*|gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-hypora-$project|" "$f" &&
        pinned=1
    done
    if [ "$pinned" -eq 1 ]; then
      log "$repo signing key verified and pinned"
    else
      warn "Could not pin the $repo key; dnf may fetch it again"
    fi
  else
    rm -f "$key"
    sudo dnf copr disable -y "$repo" >/dev/null 2>&1 || true
    die "The $repo signing key did not match the expected fingerprint. Stopping."
  fi
  rm -f "$key"
}

free_dnf_lock
log "Preparing repositories"
dnf_install dnf-plugins-core
enable_copr sdegler/hyprland "$HYPRLAND_COPR_FPR"
enable_copr "$HYPORA_COPR" "$HYPORA_COPR_FPR"

log "Installing Hypora (this brings in the required packages)"
dnf_install hypora
# `install` leaves an older copy as it is, so a re-run also upgrades
dnf_run upgrade -y hypora || true

# hypora-setup is the packaged copy and asks about the browser, apps and extras.
exec hypora-setup
