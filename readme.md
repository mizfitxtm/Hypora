<p align="center">
  <img src="docs/images/hypora-logo.svg" width="128" alt="The Hypora logo: a hexagon holding an H with a wavy crossbar">
</p>

<h1 align="center">Hypora</h1>

<p align="center">A privacy-focused Hyprland desktop for Fedora.</p>

<p align="center">
  <img src="docs/images/banner.png" width="800" alt="A terminal showing fastfetch: the Hypora logo, Hypora Linux, Hyprland, kitty and the Gruvbox theme">
</p>

Hypora is installed with a single post-install script on top of a stock Fedora install (no custom ISO). The shell is built on [Quickshell](https://quickshell.org): a custom bar, control center, notification daemon and polkit prompt, all themeable from one palette file.

The aim is an "install it and it just looks good" experience that doesn't take control away from you: a small, readable codebase of plain shell scripts and QML with no framework on top, one place to change colours, and AI tooling that is offered but never assumed.

> **Version 1.0.** Installed and tested on Fedora 44 and 45, on Workstation and the Everything netinstall. Known issues are listed in [Known issues](docs/reference.md#known-issues); please [report what you find](#reporting-bugs).

## Screenshots

All shown in **Gruvbox**; every theme drives the same widgets from its own palette.

<p>
<img src="docs/images/menu-sections-gruvbox.png" alt="The Hypora menu, showing its six sections" width="330">
<img src="docs/images/menu-apps-gruvbox.png" alt="The menu's Apps section, listing installed apps with their icons" width="330">
</p>

<img src="docs/images/theme-picker-gruvbox.png" alt="The Hypora theme picker with the Cyberpunk, Duck and Fantasy themes" width="800">

The picker shows my own themes, Cyberpunk, Duck and Fantasy, made from wallpapers with [Cosmos](https://github.com/mizfitxtm/Cosmos). Hypora ships with the six below.

The logo in the bar and on the boot screen takes its colours from the active theme. Here it is in each shipped theme: Nord, Tokyo Night, Catppuccin Mocha, Gruvbox, Kanagawa and Osaka Jade.

<img src="docs/images/logo-themes.png" alt="The Hypora logo drawn in the colours of each of the six shipped themes" width="800">

More in the [reference](docs/reference.md#screenshots).

## Requirements

Installed from the COPR and tested on **Fedora 44** and **Fedora 45**, each from both **Fedora Workstation** and the **Everything netinstall**, with **"Encrypt my data"** ticked and **btrfs** as the filesystem. You also need an internet connection and a user with `sudo`.

On a **Workstation** install GNOME is still there when `hypora-setup` finishes. Removing the desktop you are logged in to would take the session down, so Hypora offers to remove it (and the settings it left in your home folder) the first time you log in to Hypora. Other spins (KDE, Xfce, COSMIC and so on) are untested: Hypora should install over them, but their login-manager settings and leftover files are not cleaned up the way GNOME's are.

Packages are also built for **Rawhide**, Fedora's development branch that the next release is cut from. It is kept and expected to work, but it changes daily and is not one of the tested releases, so don't put it on a machine you rely on. Fedora 43 is end of life and not supported. Details: [Fedora releases](docs/copr.md#fedora-releases-and-rawhide).

None of those three install choices is enforced, but skipping encryption or btrfs can't be fixed later without reinstalling. Full details: [Requirements](docs/reference.md#requirements).

## Install

Three commands, as your normal user. The Hypora COPR pulls in the Hyprland COPR it depends on, and `hypora-setup` does the rest: it asks about a browser, apps and extras, then configures the machine and your account.

```bash
sudo dnf copr enable mizfitxtm/hypora
sudo dnf install hypora
hypora-setup
```

When dnf asks to import a signing key, check the fingerprint on screen against these:

| COPR | Fingerprint |
|---|---|
| mizfitxtm/hypora | `387B FC4E 4D37 EADD 3305 6EB4 1602 D18E 965B CEC2` |
| sdegler/hyprland | `64BB BF01 3D1C A5E4 BE5B 0552 C043 1042 0786 2204` |

The same table is published at [mizfitxtm.dev/hypora/keys](https://mizfitxtm.dev/hypora/keys/), a separate place from this repository, so one compromised account cannot change both. `hypora-setup` checks them again afterwards. It is safe to re-run, and anything it replaces is saved as `<name>.bak.<timestamp>`. Pick a theme with `THEME=TokyoNight hypora-setup`. To update, run `sudo dnf upgrade hypora` and then `hypora-setup`.

**Optional: the installer script.** `install.sh` in this repo does the same three steps, but checks each key against the recorded fingerprint *before* installing anything. Clone the repo and run `./install.sh` if you prefer that. The details are in [Installing in detail](docs/reference.md#installing-in-detail) and [COPR](docs/copr.md).

Reboot when it finishes. SDDM shows the Hypora login screen and starts the **Hyprland (uwsm-managed)** session. No login screen? Start it from a text console with `uwsm start hyprland-uwsm.desktop`.

## What you get

- **Hyprland** (started through `uwsm`) with **Quickshell** as the shell: bar, menu, control center, launcher, notifications and a polkit prompt. It replaces Waybar, Mako and a standalone polkit agent
- **Six themes**: Nord, Tokyo Night, Catppuccin Mocha, Gruvbox, Kanagawa and Osaka Jade, each with wallpapers. One `colors.toml` per theme drives everything, and **SUPER + ALT + T** switches ([make your own](docs/theming.md), or build one from any wallpaper with [Cosmos](https://github.com/mizfitxtm/Cosmos))
- **Settings windows** for Network, Bluetooth, Sound, Display, Default Apps, and Security & Privacy
- **Privacy and security by default**: DNS-over-TLS where the network allows it, a closed firewall, MAC randomization, automatic security updates and no telemetry ([details](docs/security.md))
- **Plugins** for the bar, with every file and script shown to you before anything is installed ([plugins](docs/plugins.md))
- **Terminal tools**: kitty, zsh with Oh My Zsh, eza, Neovim with LazyVim, and fastfetch

Everything, component by component: [What you get](docs/reference.md#what-you-get).

## Keys

| Keys | Action |
|---|---|
| SUPER + Enter | Terminal |
| SUPER + R | App launcher |
| SUPER + A | Hypora menu |
| SUPER + ALT + T | Theme picker |
| SUPER + L | Lock |
| SUPER + Q | Close window |
| SUPER + 1-0 | Switch workspace |

Every shortcut can be rebound from **menu > Help > Keybindings**. The full list: [Keybindings](docs/reference.md#keybindings).

## Documentation

The reasoning behind each subsystem (what it does, why it is done that way, and what the trade-offs are) lives in `docs/`:

| Document | Covers |
|---|---|
| [Reference](docs/reference.md) | Requirements, installing in detail, every component, keybindings, repository layout |
| [Security and privacy](docs/security.md) | What privacy means here, the Security window, where software comes from, the keyring, firmware and updates |
| [Boot](docs/boot.md) | The GRUB menu, the Plymouth splash and the themed text console |
| [Storage](docs/storage.md) | btrfs snapshots with snapper, and why Hypora would rather you had no swap partition |
| [Network](docs/network.md) | DNS-over-TLS where the network allows it, and per-network MAC randomization |
| [Power](docs/power.md) | Measuring what a laptop draws, and the profiles that reduce it |
| [Hardware](docs/hardware.md) | Finding hardware that came up without a driver, firmware or radio |
| [Desktop](docs/desktop.md) | Workspaces and monitors, the main display, customizing, and replacing another desktop |
| [Plugins](docs/plugins.md) | Installing a plugin, what you are agreeing to, and writing one |
| [Making a theme](docs/theming.md) | The 31 palette keys, the contrast checker, wallpapers, and adding a template |

## Known limitations

- Hyprland comes from a third-party COPR, so builds can lag behind or break after Fedora updates
- The Hyprland config is Lua, which is new. If something misbehaves after an update, check `hyprctl configerrors`
- LocalSend fails with "No route to host" until a network is in the `home` firewall zone ([the fix](docs/security.md#known-limitations))
- Only Fedora 44 has been tested

More: [Known limitations](docs/reference.md#known-limitations).

## Reporting bugs

File bugs and feature requests as [GitHub issues](https://github.com/mizfitxtm/Hypora/issues); the menu's **Help > Report a bug** opens the form. A useful report says which Fedora version you run and whether it is bare metal or a VM, and includes `hyprctl configerrors` for compositor or keybind problems, the output of `qs` run from a terminal for shell problems, or `hypora-security status` for the Security window. The full checklist: [what to include](docs/reference.md#reporting-bugs-what-to-include).

## License

See [LICENSE](LICENSE).

## A note on AI assistance

The code here was written and reviewed by me, with help from [Claude Code](https://claude.com/claude-code). I decide what gets built and why, read every change before it lands, and test it on real hardware.

Either way, read the code rather than trust it. This is a desktop that configures your firewall, your DNS, your firmware updates and a helper that runs as root; the installer is plain shell and the shell layer is plain QML, both commented to explain *why* rather than *what*, specifically so that reading them is practical.
