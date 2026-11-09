# Shared by install.sh and hypora-setup (sourced, not run). Needs `set -euo pipefail` from the caller.

log() { printf '\033[1;34m==>\033[0m \033[2m%s\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
# Warnings print as they happen and are saved, so the summary at the end can repeat them
WARNINGS=()
warn() {
  WARNINGS+=("$*")
  printf '\033[1;33m!!\033[0m %s\n' "$*" >&2
}
die() {
  printf '\033[1;31mxx\033[0m %s\n' "$*" >&2
  exit 1
}

# dnf gets no stdin: something in its run waited for Enter even with -y. sudo reads its password from the tty, so this is safe.
sudo() {
  case " $* " in
  *" dnf "*) command sudo "$@" </dev/null ;;
  *) command sudo "$@" ;;
  esac
}

# available PKG: true if dnf can find the package
available() { [ -n "$(dnf repoquery --quiet "$1" 2>/dev/null </dev/null)" ]; }

# dnf_run ARGS: runs dnf as root; if it hangs 30 s after "Nothing to do" (as it did on some machines), stops it and warns.
dnf_run() {
  local log pid tailpid rc hung=0 _
  log=$(mktemp)
  sudo dnf "$@" >"$log" 2>&1 &
  pid=$!
  tail -n +1 -f "$log" --pid="$pid" 2>/dev/null &
  tailpid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if grep -q "Nothing to do" "$log"; then
      # Give dnf up to 30 s to exit, checking every second so a normal exit costs nothing
      for _ in $(seq "${DNF_HANG_WAIT:-30}"); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        hung=1
      fi
      break
    fi
    sleep 1
  done
  rc=0
  wait "$pid" 2>/dev/null || rc=$?
  wait "$tailpid" 2>/dev/null || true
  rm -f "$log"
  # "Nothing to do" means the work was already done, so a stop after it is not a failure
  if [ "$hung" -eq 1 ]; then
    warn "dnf hung after 'Nothing to do' (dnf $*); stopped it and went on"
    return 0
  fi
  return "$rc"
}

# dnf install that skips the call when every package is present.
dnf_install() {
  local args=() missing=0 a
  for a in "$@"; do
    args+=("$a")
    case "$a" in -*) ;; *) rpm -q --whatprovides "$a" >/dev/null 2>&1 || missing=1 ;; esac
  done
  [ "$missing" -eq 0 ] || dnf_run install -y "${args[@]}"
}

# fetch_verified URL DEST SHA256: refuse a download whose hash differs, since HTTPS does not prove it is the reviewed file.
fetch_verified() {
  local url=$1 dest=$2 want=$3 got
  curl -fsSL "$url" -o "$dest" || {
    warn "Could not download $url"
    return 1
  }
  got=$(sha256sum "$dest" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
    rm -f "$dest"
    warn "Checksum mismatch for $url"
    warn "  expected $want"
    warn "  got      $got"
    return 1
  fi
}

# key_ok FILE FINGERPRINT: `rpm --import` trusts every key in a file, so check every primary key's fingerprint.
key_ok() {
  local fprs
  fprs=$(gpg --show-keys --with-colons "$1" 2>/dev/null |
    awk -F: '$1 == "pub" { p = 1; next } p && $1 == "fpr" { print $10; p = 0 }')
  [ -n "$fprs" ] && [ "$fprs" = "$2" ]
}

# pin_clone URL COMMIT DEST: check out one reviewed commit; the final rev-parse is what makes it a real pin.
pin_clone() {
  local url=$1 commit=$2 dest=$3
  rm -rf "$dest"
  git init -q "$dest" 2>/dev/null || {
    warn "Could not create $dest"
    return 1
  }
  git -C "$dest" remote add origin "$url" || return 1
  if ! git -C "$dest" fetch -q --depth 1 origin "$commit" 2>/dev/null; then
    rm -rf "$dest"
    warn "Could not fetch $commit from $url"
    return 1
  fi
  git -C "$dest" checkout -q FETCH_HEAD || {
    rm -rf "$dest"
    return 1
  }
  if [ "$(git -C "$dest" rev-parse HEAD)" != "$commit" ]; then
    rm -rf "$dest"
    warn "$url did not check out $commit"
    return 1
  fi
}

# Recorded COPR identities. The Hypora fingerprint changes if that COPR project is deleted and recreated.
HYPRLAND_COPR_FPR=64BBBF013D1CA5E4BE5B0552C043104207862204
HYPORA_COPR=${HYPORA_COPR:-mizfitxtm/hypora}
HYPORA_COPR_FPR=387BFC4E4D37EADD33056EB41602D18E965BCEC2

# check_copr_key OWNER/PROJECT FINGERPRINT: fails if rpm holds a key for that COPR that is not the recorded one (newer rpm names a key by its full fingerprint, older by the last 8 digits).
check_copr_key() {
  local fpr=${2,,} tag=${1/\//_} id line
  while read -r id line; do
    case "$line" in *"$tag"*) [ "$id" = "$fpr" ] || [ "$id" = "${fpr: -8}" ] || return 1 ;; esac
  done < <(rpm -qa 'gpg-pubkey*' --qf '%{VERSION} %{SUMMARY}\n')
  return 0
}

# free_dnf_lock: stop the background dnf services, which hold dnf's lock so every dnf command would wait forever.
free_dnf_lock() {
  for svc in dnf5daemon-server packagekit; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      log "Stopping $svc so it releases the dnf lock (D-Bus restarts it on demand)"
      sudo timeout 60 systemctl stop "$svc" ||
        warn "Could not stop $svc; dnf steps may stall waiting for its lock"
    fi
  done
}

# drop_weak_dep PKG: remove PKG if it only came along as a recommendation and nothing requires it; one you installed yourself stays.
drop_weak_dep() {
  local pkg=$1 reason
  rpm -q "$pkg" >/dev/null 2>&1 || return 0
  reason=$(dnf repoquery --installed --qf '%{reason}\n' "$pkg" 2>/dev/null </dev/null | head -1 | tr 'A-Z' 'a-z')
  case "$reason" in *weak*) ;; *) return 0 ;; esac
  # rpm exits 0 when some package requires it
  ! rpm -q --whatrequires "$pkg" >/dev/null 2>&1 || return 0
  log "Removing $pkg: it only came along as a recommendation and Hypora does not use it"
  # No orphan sweep: a package that served only this one is harmless, an over-eager sweep is not
  dnf_run remove -y --setopt=clean_requirements_on_remove=False "$pkg" || warn "Could not remove $pkg"
}
