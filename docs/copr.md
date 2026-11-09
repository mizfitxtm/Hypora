# Hypora as a COPR package

Users run three commands: `sudo dnf copr enable mizfitxtm/hypora`, `sudo dnf install hypora`, `hypora-setup`. The RPM carries the files; `hypora-setup` configures the machine and the user's account from them.

| Piece | Job |
|---|---|
| `hypora.spec` | Installs `bin/`, `config/`, `themes/`, `system/`, `applications/` and `lib.sh` to `/usr/share/hypora`, and `hypora-setup` to `/usr/bin`. `Requires:` is the required-package list, `Recommends:` the optional one. |
| `hypora-setup` | Everything that needs a user or a prompt: the browser, Flatpak apps and extras, per-user files (copied with the edit-safe manifest), services, firewall, login screen, boot theme, snapshots, RPM Fusion, Steam, Claude Code. Re-runnable. |
| `install.sh` | Optional. Enables both COPRs with each key checked against a recorded fingerprint, installs `hypora`, runs `hypora-setup`. |
| `lib.sh` | Helpers both scripts use, and the recorded COPR fingerprints. |
| `.copr/Makefile` | Lets COPR build the source RPM from a git checkout. |

## One-time COPR setup

1. Create the project and add this repo as an SCM package: type `git`, spec `hypora.spec`, "make srpm" with `.copr/Makefile`, chroots for the Fedora releases you support (44, 45 and optionally rawhide; not 43, which is end of life and which the Hyprland COPR does not build for). Tick **Auto-rebuild** on the package and add the webhook from Settings → Integrations to the GitHub repo.
2. **Settings → Runtime dependencies:** `copr://sdegler/hyprland`. This puts the Hyprland COPR in the repo file users get from `dnf copr enable`, so `dnf install hypora` finds `hyprland` and `uwsm` with no second command. Check it with `curl https://copr.fedorainfracloud.org/coprs/mizfitxtm/hypora/repo/fedora-44/mizfitxtm-hypora-fedora-44.repo`: it should list the sdegler repo too.
3. The recorded fingerprints are in `lib.sh` (`HYPORA_COPR_FPR`, `HYPRLAND_COPR_FPR`) and in the readme. If the COPR project is deleted and recreated its key changes, so update both.
4. Bump `Release` (or `Version`) and add a `%changelog` line in `hypora.spec` for every rebuild, or dnf will not see it as an update.

## Fedora releases and Rawhide

The package builds for Fedora 44, 45 and Rawhide (x86_64). Fedora 44 and 45 have each been installed and tested from the COPR on Workstation and the Everything netinstall. Fedora 43 is not built: it is end of life, and the Hyprland COPR does not build for it.

**Rawhide** is Fedora's development branch. Every numbered release is cut from it, and it keeps moving afterwards: newest kernel, libraries and desktop packages first. Fedora itself warns it can break, with packages that will not install for a day or two or builds that fail when a library changes. For Hypora that means:

- The `hypora` package is only files, so it builds there. A Rawhide machine gets Hyprland from the Hyprland COPR's Rawhide build, and anything depending on a library or a Quickshell version can break when Rawhide shifts.
- A failed Rawhide build or a Rawhide bug report is often someone else's change, not a mistake in Hypora.
- Its value is early warning: a Rawhide breakage shows up months before it reaches the next stable release.

It is built but **not supported**. Drop the chroot if its failures cost more time than the warning is worth.

## Trust

`dnf` imports a COPR's key the first time it is used, so the readme tells users to compare the fingerprint on screen. `hypora-setup` then checks the keys rpm holds for both COPRs and warns on a mismatch. `install.sh` is stricter: it checks each key before enabling the repo and stops on a mismatch.

## Updating

`dnf upgrade` updates the files under `/usr/share/hypora`; run `hypora-setup` again to copy them into your account.
