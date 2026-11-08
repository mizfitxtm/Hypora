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

1. Create the project and add this repo as an SCM package: type `git`, spec `hypora.spec`, "make srpm" with `.copr/Makefile`, chroots for the Fedora releases you support. Tick **Auto-rebuild** on the package and add the webhook from Settings → Integrations to the GitHub repo.
2. **Settings → Runtime dependencies:** `copr://sdegler/hyprland`. This puts the Hyprland COPR in the repo file users get from `dnf copr enable`, so `dnf install hypora` finds `hyprland` and `uwsm` with no second command. Check it with `curl https://copr.fedorainfracloud.org/coprs/mizfitxtm/hypora/repo/fedora-44/mizfitxtm-hypora-fedora-44.repo`: it should list the sdegler repo too.
3. The recorded fingerprints are in `lib.sh` (`HYPORA_COPR_FPR`, `HYPRLAND_COPR_FPR`) and in the readme. If the COPR project is deleted and recreated its key changes, so update both.
4. Bump `Release` (or `Version`) and add a `%changelog` line in `hypora.spec` for every rebuild, or dnf will not see it as an update.

## Trust

`dnf` imports a COPR's key the first time it is used, so the readme tells users to compare the fingerprint on screen. `hypora-setup` then checks the keys rpm holds for both COPRs and warns on a mismatch. `install.sh` is stricter: it checks each key before enabling the repo and stops on a mismatch.

## Updating

`dnf upgrade` updates the files under `/usr/share/hypora`; run `hypora-setup` again to copy them into your account.
