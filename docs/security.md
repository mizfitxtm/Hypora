# Security and privacy

What Hypora does about your privacy, what the Security window shows, where its software comes from, and how it handles secrets, firmware and updates.

[← back to the readme](../readme.md)

## What privacy means in Hypora

Specific things, not a slogan:

- **Nothing phones home.** No telemetry, no analytics, no update pings of our own.
- **The weather widget never geolocates you.** You pick a city by name; the search sends only that name, the forecast sends only that city's coordinates, and until you pick one no weather request is made at all.
- **AI tooling is opt-in.** The installer asks before installing Claude Code, and the default answer is no. Decline, and the menu has no Claude entry at all — nothing advertises it back at you.
- **Your security state is visible and adjustable** — Secure Boot, firmware checks, SELinux, camera, microphone, location and file history all in one window, with each switch saying plainly what it does and does not cover.
- **Flatpak apps come with the tools to audit them:** Flatseal for permissions, Warehouse for what's installed and what data it left behind. Firefox and Spotify run sandboxed rather than as system packages.
- **Everything downloaded is verified.** Each file fetched outside dnf is pinned to a release and checked against a recorded SHA-256; the Hyprland COPR's signing key is checked against a pinned fingerprint before anything installs from it; Claude Code's repository key likewise. HTTPS proves which host answered, not what it sent.
- **The firewall is on, and closed by default.** Fedora's workstation zone leaves ports 1025-65535 open on TCP and UDP; Hypora uses `public`, which allows only ssh, mDNS and DHCPv6. LocalSend, the one app here that listens, has its port (53317) opened in the `home` zone only, which holds no network until you put a trusted one there with `nmcli connection modify "<name>" connection.zone home` (only when LocalSend is installed; pass `LOCALSEND_LAN=no` to skip the port). It is never opened in `public`.
- **DNS is encrypted where it can be, and stays yours.** systemd-resolved with DNS-over-TLS in opportunistic mode, following the network rather than overriding it — which is what keeps a resolver you run yourself in charge. [Quad9](https://quad9.net) is the fallback. See [DNS](network.md#dns).
- **Your MAC address doesn't follow you between networks.** Scanning is randomized, and each network sees a per-network address rather than the card's permanent serial. See [MAC addresses](network.md#mac-addresses).
- **Security updates install themselves, and the third-party repo doesn't.** Fedora security advisories and flatpak updates apply daily; the Hyprland COPR is deliberately excluded, so the compositor never changes under you. See [Automatic updates](#automatic-updates).
- **The kernel and login are tightened beyond Fedora's defaults**, and the settings that can break things sit behind one switch. See [Kernel and login hardening](#kernel-and-login-hardening) and [Hardened mode](#hardened-mode).
- **The screen locks on its own.** Ten minutes to lock, fifteen to blank, and it locks before suspending.
- **Full-disk encryption is checked, not assumed.** The Security window reports whether this system is on an encrypted volume, and warns about swap reaching the disk in the clear. Encryption itself has to be chosen when Fedora is installed — see [Requirements](reference.md#requirements).
- **Secrets stay out of argv and privileged paths stay out of `$HOME`.** Wi-Fi passwords go to `nmcli` on stdin, never as an argument any process could read from `/proc`; every helper that runs as root lives in a root-owned directory, never in `~/.local/bin` — a script you can write that something runs with `sudo` is a way to become root, not a convenience.

## The Security and Privacy window

**Security & Privacy (`SecuritySettings.qml`).** Two sections. **Security**: Secure Boot, disk encryption and unencrypted swap (with **Add swapfile** — see [Swap](storage.md#swap)), firmware checks (see [Firmware updates](#firmware-updates)), encrypted DNS, MAC randomization, the firewall's zone, automatic updates, SELinux, the kernel and login hardening and Hardened mode. **Privacy**: location (masks GeoClue), camera (unloads `uvcvideo`), microphone (mutes it in PipeWire) and GTK file history, with a Clear button. Grouped by subject rather than by component — a camera is about you, a firewall is about the machine. Security settings with a choice are changed with a dropdown (the same one Display Settings uses): SELinux, Hardened mode, the encrypted DNS mode and the connected network's firewall zone. The privacy settings are plain switches, and buttons are kept for one-off actions such as adding a swapfile. **Opening it never asks for a password**; the two readings that need root sit behind one **Run the deeper checks** prompt rather than one per service. There is no periodic refresh, because re-reading on a timer turned one prompt into one every fifteen seconds; instead a change moves its own switch straight away and the window re-reads when the change finishes

The shell is never run as root, and shouldn't be. Quickshell is a single process — the Security window is not separable from the bar, launcher and notification daemon — and it loads its QML from `~/.config/quickshell/`, which you can write. Privileged code must not sit on a path its own user can edit, which is why `hypora-security`, `hypora-console`, `hypora-hardware`, `hypora-grub`, `hypora-power`, `hypora-replace-de` and `hypora-greeter` are root-owned in `/usr/local/bin` and reached through pkexec. `hypora-security deep` deliberately re-reads none of your per-user settings, so running it as root can't substitute root's configuration for yours, and it reads firewalld's zone from `/etc/firewalld` directly rather than over D-Bus so that half can't raise a second prompt. Run `hypora-security status` to see exactly what it reads.

## The browser

The browser is where most hostile input arrives, so it gets three things of its own.

- **A policy file for Firefox and Zen** (`system/browser/policies.json`): telemetry, studies and sponsored content off; HTTPS-Only mode and tracking protection on; Firefox's own DNS-over-HTTPS off, so lookups follow the system resolver described in [DNS](network.md#dns) instead of bypassing it; and uBlock Origin installed from addons.mozilla.org. Settings that can be left adjustable are not locked. The Flatpak reads it from `/var/lib/flatpak/extension/<app id>.systemconfig/x86_64/stable/policies/policies.json`; check what applied at `about:policies`. `hypora-setup` replaces the file only while its "Managed by Hypora" line is there, so delete that line to keep your own edits, or pass `BROWSER_POLICY=no` to skip it.
- **Firefox loses its X11 socket** (`flatpak override --system --nosocket=x11`). Under Hyprland it runs on Wayland, and X11 access would let it read the input of every X11 window. `fallback-x11` stays for a session with no Wayland.
- **Trivalent as a choice.** [Trivalent](https://github.com/secureblue/Trivalent) is secureblue's hardened Chromium, carrying GrapheneOS Vanadium's patches. It is an RPM, not a Flatpak, because Flatpak replaces part of Chromium's own sandbox. It comes from secureblue's repository, which is a third party and describes use outside secureblue as unsupported: the key is checked against a recorded fingerprint, the repository is limited to `trivalent*`, and the daily Flatpak update timer also updates it, because the repository publishes no advisories for `dnf-automatic` to act on. If it cannot be installed, Firefox is installed instead. Extensions and the JavaScript JIT are off by default in Trivalent.

Chromium and Brave get no policy file: their Flatpaks offer no supported place for one.

## Network exposure

- **Each network is Public or Private.** The Firewall row's **This network** dropdown moves the connected Wi-Fi or ethernet network between firewalld's `public` zone and its `home` zone (shown as Private), where LocalSend's port is open. It is the same as `nmcli connection modify "<name>" connection.zone home`, is remembered per network, and does not change the default zone, so a network you have never seen starts as Public. `hypora-security network-zone public|home` does it from a terminal.
- **Encrypted DNS is Opportunistic or On.** Opportunistic follows the network's resolver and encrypts when it can. On writes `/etc/systemd/resolved.conf.d/hypora-hardened.conf`, which sends every lookup to Quad9 over TLS with DNSSEC and never falls back to plaintext; it is the same file Hardened mode writes, so switching Hardened mode off also returns DNS to Opportunistic. `sudo hypora-security dns opportunistic|strict` does it from a terminal. See [DNS](network.md#dns).

- **The SSH server is switched off** and port 22 closed, because it is the one service on a stock Fedora desktop reachable from the network. Pass `KEEP_SSH=yes` to keep it; the installer keeps it automatically if you are installing *over* SSH. Re-enable with `sudo systemctl enable --now sshd`

## Where software comes from

**Why most packages stay native.** Flatpak sandboxing earns its keep for software that handles hostile input, which is why Firefox and Spotify are flatpaks. **Steam is native**, not a flatpak: the sandbox fights controller access and reaching game libraries stored outside it. That has a cost worth stating — native Steam comes from `rpmfusion-nonfree-steam`, so declining RPM Fusion means no Steam, where the flatpak would have worked. It does nothing for the rest: the compositor, shell, terminal and portals *are* the session and cannot sandbox themselves; `kitty` and `fastfetch` have no maintained Flathub build at all; the file manager and Disks need the host filesystem and `udisks` to be any use; and `nmap`, `aircrack-ng`, `wireshark` and `virt-manager` need raw sockets, capture privileges or host libvirt, so a sandboxed build would have to be handed the host anyway — paying the integration cost for none of the benefit.

**Remote desktop** — **RustDesk**, as a Flathub flatpak that is publisher-verified via `rustdesk.com`. Chosen over the project's own RPM, which ships unsigned: a pinned hash there would prove the bytes hadn't changed since someone looked at them, but nothing about who built them. Being sandboxed, it reaches the screen and input through the desktop portals rather than the raw session.

One thing to know: **Nautilus hard-requires `localsearch`**, a background indexer that reads your home directory to make search work. It stays on the machine and talks to nothing over the network, but it is a daemon that reads your files. To see what it installed and mask it: `systemctl --user list-units '*localsearch*'`.

**Optional, offered at the end of the install, both defaulting to no**

- **RPM Fusion** carries what Fedora won't ship — media codecs, NVIDIA's own driver, firmware for some Broadcom and Realtek chips. Answer ahead with `ENABLE_RPMFUSION=yes hypora-setup`. It is a different trust decision from the rest of Hypora: the release RPMs come over HTTPS from rpmfusion.org and can't be pinned to a fingerprint the way the Hyprland COPR and Anthropic's repository are, because both the package and its key change with every Fedora release. Packages from it are GPG-checked normally once it's enabled. Remove with `sudo dnf remove rpmfusion-free-release rpmfusion-nonfree-release`
- **Claude Code** comes from Anthropic's signed dnf repository (stable channel; `sudo dnf upgrade claude-code` to update) and needs a paid Claude plan. Answer ahead with `INSTALL_CLAUDE=yes hypora-setup`; a non-interactive run skips it, and a re-run detects an existing install rather than asking again. Run `claude` to log in; remove with `sudo dnf remove claude-code && sudo rm /etc/yum.repos.d/claude-code.repo`. The menu's **Tools > Claude Code** entry appears only when `claude` is on your `PATH`
- Nothing else AI-related is installed, and nothing is installed without asking

### Who you trust for updates

Hypora installs from two COPR repositories, so updates to the desktop come from two people who are not Fedora: `mizfitxtm/hypora` (this project) and `sdegler/hyprland` (Hyprland and uwsm, which run your whole session). COPR packages are signed with each project's own key and are not reviewed by Fedora. What that means in practice:

- **A stolen account is the main risk.** Whoever controls either COPR, or the GitHub account behind this one, can publish a package that `hypora-setup` later runs with `sudo`. Hypora packages are built from tagged releases, not from every commit, so a stray push does not reach users.
- **Compare the key before you accept it.** dnf imports a COPR key the first time it is used and shows the fingerprint. The readme lists both, and [mizfitxtm.dev/hypora/keys](https://mizfitxtm.dev/hypora/keys/) repeats them from a separate host. If the three disagree, stop. `hypora-setup` re-checks the keys afterwards and warns on a mismatch; the optional `install.sh` checks them before installing anything.
- **Updates are not automatic for these packages.** Automatic updates are limited to security advisories (`upgrade_type = security`), and COPR packages carry none, so `hypora` and Hyprland change only when you run `sudo dnf upgrade`. Keep that setting.
- **The source is the same public repository.** The RPM is built from this repo (`hypora.spec`), and `/usr/share/hypora` is root-owned, which is safer than the earlier install from a clone in your home directory.
- **What the repositories can see:** dnf contacts COPR and its mirrors for updates, so they see your IP address and which packages you request, as any repository would. The packages themselves send nothing.

## Secrets and the keyring

Fedora Workstation starts `gnome-keyring` from the GNOME session. Hyprland starts nothing, and an app that asks the Secret Service API where to keep a token and finds no provider at all may fall back to writing it to disk unencrypted — so Hypora installs `gnome-keyring` and starts it from `hyprland.lua` with `--components=secrets,ssh`. `SSH_AUTH_SOCK` is set in `config/uwsm/env` so everything in the session agrees on one agent socket.

### Auto-unlock

The keyring is a file encrypted with a password, so something has to supply that password. Hypora adds three lines to `/etc/pam.d/sddm` so your login password does it, which is what GDM does — the same three lines are in `/etc/pam.d/gdm-password` on any Fedora Workstation:

```
-auth      optional  pam_gnome_keyring.so
-password  optional  pam_gnome_keyring.so use_authtok
-session   optional  pam_gnome_keyring.so auto_start
```

Each one earns its place. `auth` captures the password you just typed; `session` uses it to unlock the keyring; `password` re-keys the keyring when you change your account password — **without that third line, changing your password orphans the keyring** behind a password you no longer know, and the only way out is to delete it and lose what was in it.

This edits the file that decides whether you can log in, so it is done carefully:

- **Appended, not inserted.** PAM keeps a separate stack per module type and runs each in file order, so a line at the end of the file joins the end of its own type's stack. Hypora therefore never has to parse or reorder what Fedora put there. The side effect is that the `auth` and `password` lines sit below the `session` block in the file, which looks odd and reads fine to PAM.
- **`-` and `optional` together.** The dash skips the line silently if the module is missing; `optional` makes PAM ignore its result either way. Neither can turn a working login into a failing one.
- **The original is backed up** to `/etc/pam.d/sddm.hypora-<timestamp>` before anything is written, and the installer prints the path.
- **It is idempotent** — a second run detects the lines and leaves them alone.

The `password` line goes in `/etc/authselect/system-auth` (what `/etc/pam.d/system-auth` links to) **before** the `pam_unix` password line, not after: `pam_unix` is `sufficient`, so a successful change ends the stack there and a line placed after it never runs. `authselect apply-changes` rewrites that file; re-run `hypora-setup` to put the line back.

Skip it with `KEYRING_AUTOUNLOCK=no hypora-setup`, or undo it by deleting those three lines.

If you are **still** asked for a keyring password after this, the usual cause is a login keyring that already exists with a *different* password — PAM is offering your login password and the keyring wants the old one. Either change the keyring's password to match your login password in Seahorse (`gnome-keyring` ships it as **Passwords and Keys**), or delete `~/.local/share/keyrings/login.keyring` and let it be recreated, which loses whatever was stored in it.

## Firmware updates

**Menu > Security > Check for firmware updates** opens a floating, pinned terminal running `bin/hypora-firmware`, which refreshes from the [Linux Vendor Firmware Service](https://fwupd.org) and installs whatever applies to the machine:

```
fwupdmgr refresh --force
fwupdmgr get-updates --no-unreported-check
fwupdmgr update -y --no-reboot-check
```

This is a button rather than part of the automatic updates on purpose. Firmware is written to the hardware itself, some of it only takes effect after a restart, and a motherboard update interrupted half way is how machines get bricked — so it happens when you ask, in a window you can watch. fwupd asks polkit before touching any device, so Hypora's password prompt appears before anything is written.

The window is `float` + `pin` so it stays in front and remains visible if you change workspace mid-update. It's matched on its title, and the Security window passes `--title` when launching the terminal: Hyprland decides float and pin at the moment a window is **mapped**, so a title the program sets afterwards arrives too late and the window ends up tiled. The script prints the title escape sequence too, which covers running `hypora-firmware` yourself in a terminal started without the flag. This assumes a terminal that accepts `--title` — kitty, alacritty and foot all do.

Two things worth knowing:

- **Checking contacts fwupd.org.** It's the one part of Hypora that reaches an outside server without you typing something first, which is why it isn't done in the background. Devices whose vendors don't publish to LVFS never appear — those update from the vendor's own tool or the UEFI setup screen.
- **"No updates" is a success, not a failure.** `fwupdmgr` exits 2 for "ran fine, nothing to do" and 3 for "not found". The script treats both as success; reading them as errors is what would make a fully-updated machine look broken.

## Automatic updates

Nothing covers both halves of this system, so there are two timers.

**System packages** go through `dnf5-automatic.timer` (daily at 06:00, up to an hour of jitter, catching up on missed runs), configured in `/etc/dnf/automatic.conf`. Both timers are enabled but not started by the installer, so they begin at the reboot it ends with:

```ini
[commands]
apply_updates = yes
download_updates = yes
upgrade_type = security
reboot = never
```

`upgrade_type = security` limits unattended installs to packages carrying a Fedora security advisory, which has two consequences:

- **It excludes the Hyprland COPR.** Third-party repositories publish no advisory metadata, so nothing from them can ever match — meaning the compositor this desktop depends on never updates while you're using it. COPR updates stay a decision you make by running `sudo dnf upgrade` yourself.
- **It also excludes real fixes** that Fedora shipped as a bugfix or enhancement update rather than a security one, which happens often enough to matter. This narrows the window on the worst holes; it is not a substitute for updating.

`reboot = never`, because a desktop deciding on its own to restart is worse than a kernel that waits. `dnf5 needs-restarting -r` says when a reboot is due.

**Flatpak apps** — including Firefox, where most of the day-to-day risk actually lives — are invisible to dnf, so `hypora-flatpak-update.timer` runs `flatpak update --system` daily at 07:00. Old runtimes aren't cleaned up automatically; `flatpak uninstall --unused` does that, or Warehouse.

**Update notifications.** Because the security-only setting leaves out the Hyprland COPR and non-advisory fixes, Hypora adds a daily, read-only check: the user timer `hypora-update-check.timer` runs `hypora-update-check`, which counts the dnf packages with a newer version and sends one desktop notification (not repeated for the same count within a week) saying to run `sudo dnf upgrade`. It downloads and installs nothing, and it talks to the same mirrors dnf-automatic already does. Turn it off with `systemctl --user disable --now hypora-update-check.timer`; `hypora-setup` keeps it off on re-runs. Run `hypora-update-check` by hand to see the count.

GNOME Software is installed, so *Restart & Update* (offline updates) and `dnf system-upgrade` still work, but its own background "updates available" popup runs only inside the GNOME session, which is why the timer above exists.

Check both:

```bash
systemctl list-timers 'dnf*' 'hypora*'
journalctl -u dnf5-automatic -u hypora-flatpak-update
sudo systemctl start hypora-flatpak-update.service   # run the flatpak one now
sudo dnf5 automatic --no-installupdates              # see what the package one would do
```

To go back to updating by hand, `sudo systemctl disable --now dnf5-automatic.timer hypora-flatpak-update.timer`. To install everything rather than security advisories only, set `upgrade_type = default` in `system/dnf/automatic.conf` and re-run the installer — understanding that this includes the COPR.

## Kernel and login hardening

`hypora-setup` adds five things on top of Fedora's defaults. Each was chosen because it rarely breaks anything; `HARDENING=no hypora-setup` skips all of them.

| What | Where | What it costs you |
|---|---|---|
| Stricter kernel settings | `/etc/sysctl.d/60-hypora-hardening.conf` | Attaching `gdb` or `strace` to a program that is already running needs `sudo`; `kdump` cannot load a crash kernel |
| Rarely used kernel modules blocked | `/etc/modprobe.d/hypora-blocklist.conf` | FireWire devices, SCTP, ATM and the HFS and JFFS2 filesystems do not load |
| No core dumps kept | `/etc/systemd/coredump.conf.d/hypora.conf` | `coredumpctl` and crash reporters have nothing to show |
| Login lockout | authselect feature `with-faillock`, `deny = 5` in `/etc/security/faillock.conf` | Five wrong passwords lock the account for ten minutes, at the login screen, the lock screen and `sudo` alike |
| Authenticated time | three NTS servers appended to `/etc/chrony.conf` | A network that blocks TCP port 4460 leaves the clock unsynchronised while you are on it |

Why each one:

- **Kernel settings.** Kernel addresses are hidden from every user, a process can trace only its own children (so one compromised app cannot read another's memory), setuid programs never dump core, the running kernel cannot be replaced without a reboot, and IPv6 uses temporary addresses. The file lists only what differs from Fedora 45's own defaults, and each line says what it does.
- **Module blocklist.** The kernel loads a protocol or filesystem driver the first time anything asks for it, including an unprivileged program. Rare drivers are where old bugs sit, so the ones a desktop almost never needs are replaced with `/bin/false`. To use one, comment its line out.
- **Core dumps.** A dump is a copy of a crashed program's memory, with whatever passwords and keys it held, written to disk.
- **Login lockout.** Fedora's default is three attempts, which is easy to hit at the lock screen, so Hypora sets five. `sudo faillock --user <name> --reset` clears a lock early from another account or a root shell.
- **Authenticated time.** Plain NTP can be forged by the network, and a wrong clock breaks certificate checks. The servers are `time.cloudflare.com`, `nts.netnod.se` and `ptbtime1.ptb.de`, and they see your IP address the way Fedora's pool does. `/etc/chrony.conf` is backed up to `/etc/chrony.conf.hypora-<timestamp>` first, and the lines are appended, not inserted.

To undo one, delete its file (or the appended lines) and reboot; `sudo authselect disable-feature with-faillock` undoes the lockout. The Security window's **Kernel and login hardening** row shows how many of the five are in place.

## Hardened mode

One On/Off setting in the Security window (or `sudo hypora-security harden on`) for the settings that are worth having and can break things. It is off by default, and switching it off puts everything back, which also makes it the first thing to rule out when something stops working.

| What it does | What it can break |
|---|---|
| Adds the kernel arguments `init_on_free=1 page_alloc.shuffle=1 vsyscall=none debugfs=off` | A few percent of performance in memory-heavy programs and games; very old binaries that need vsyscall; tools that read debugfs |
| Sends every DNS lookup to Quad9 over TLS with DNSSEC, with no plaintext fallback | Captive portals, a Pi-hole or router resolver, and names only your network's DNS knows |
| Starts USBGuard, allowing the USB devices plugged in at that moment and blocking new ones | A new flash drive, phone or dock does nothing until you allow it |

- **The kernel arguments need a restart**, in both directions. The window says so until the running kernel matches. They are written to every boot entry and to `/etc/kernel/cmdline`, so later kernels keep them. Only arguments Fedora's kernel does not already default to are listed.
- **Allowing a USB device:** `usbguard list-devices -b` shows what is blocked, and `sudo usbguard allow-device <number> -p` allows one permanently. Plug in everything you use, including devices behind a KVM switch or dock, before switching Hardened mode on.
- **A notification asks about each newly blocked device**, with **Allow once** (until it is unplugged), **Always allow** (adds a rule) and **Keep blocked**. It stays on screen until you answer, and shows even with Do Not Disturb on; clicking the card itself dismisses it and leaves the device blocked. It comes from `hypora-usb-watch`, a user service that runs only while Hardened mode is on (`hypora-usb-watch.path` starts it when `/etc/hypora/hardened` exists). Turn it off with `systemctl --user disable --now hypora-usb-watch.path`. It needs no root, because USBGuard lets members of the `wheel` group decide. The device's name is chosen by the device, so read the ID before allowing something you did not plug in.
- **USBGuard never starts with an empty policy**, because that would block the keyboard. Rules that already exist in `/etc/usbguard/rules.conf` are kept, and switching Hardened mode off stops the service and leaves the rules in place.
- **Captive portals:** the per-interface `resolvectl dnsovertls` workaround does not help here, because lookups are pinned to Quad9. Switch Hardened mode off to sign in, then on again.

## Known limitations

These are the security and network trade-offs, kept in one place. The rest are in the [reference](reference.md#known-limitations).

- DNS-over-TLS is opportunistic, not strict, so a network blocking port 853 silently gets plaintext queries. Strict mode is a two-line change (or [Hardened mode](#hardened-mode)) but breaks captive portals — see [DNS](network.md#dns)
- The login lockout applies at the lock screen too, so anyone at the keyboard can lock your account for ten minutes with five wrong passwords
- MAC randomization changes each card's address once, which breaks existing DHCP reservations until they're updated — see [MAC addresses](network.md#mac-addresses)
- Automatic updates only install packages Fedora tagged as security advisories, which misses fixes shipped as bugfix updates. Run `sudo dnf upgrade` periodically anyway
- LocalSend fails with "No route to host" until a network is in the `home` zone. The installer preconfigures the port (53317, TCP and UDP) in `home`, but `public` blocks it and the sender gets an ICMP "host prohibited" reply that looks like a routing fault. To add a trusted network by hand: `nmcli connection show`, then `nmcli connection modify "<name>" connection.zone home` (quote names with spaces, e.g. `"Wired connection 1"`), then `nmcli connection up "<name>"`, and check with `firewall-cmd --get-active-zones`. If the port is somehow closed, `sudo firewall-cmd --permanent --zone=home --add-port=53317/tcp --add-port=53317/udp && sudo firewall-cmd --reload`. Don't open it in `public`: the installer closes it again and it would be open on every network you join. Wired and Wi-Fi on the same subnet can also confuse discovery, so try one at a time
