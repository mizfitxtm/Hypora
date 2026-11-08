# Hypora as a COPR package

The `hypora` RPM carries the files; `hypora-setup` configures the machine and your account from them.

| Piece | Job |
|---|---|
| `hypora.spec` | Installs `bin/`, `config/`, `themes/`, `system/`, `applications/` and `lib.sh` to `/usr/share/hypora`, and `hypora-setup` to `/usr/bin`. `Requires:` is the old `REQUIRED` list, `Recommends:` the old `OPTIONAL` one. |
| `hypora-setup` | The configuring half of the old installer: copies per-user files with the edit-safe manifest, sets up services, firewall, login screen, boot theme, snapshots. Re-runnable. |
| `install-copr.sh` | Enables the Hyprland and Hypora COPRs, installs `hypora`, then the opt-in parts (virtualization, Flatpak apps and browser, RPM Fusion, Steam, Claude Code), then runs `hypora-setup`. |
| `lib.sh` | Helpers both scripts use (`log`, `warn`, `dnf_run`, `dnf_install`, ...). |
| `.copr/Makefile` | Lets COPR build the source RPM from a git checkout. |

## One-time COPR setup

1. Create the project (COPR user = your Fedora account name) and add this repo as an SCM source: type `git`, spec `hypora.spec`, "make srpm" with `.copr/Makefile`, chroots for the Fedora releases you support.
2. The repo key fingerprint is pinned in `HYPORA_COPR_FPR` in `install-copr.sh`; update it if the COPR project is ever deleted and recreated (the key changes).
3. Bump `Version:` in `hypora.spec` for each release and add a `%changelog` line.

## Updating

`dnf upgrade` updates the files under `/usr/share/hypora`; run `hypora-setup` again to copy them into your account.
