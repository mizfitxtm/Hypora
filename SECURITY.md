# Security policy

How to report a security problem in Hypora. For what Hypora does about security and privacy, and why, see [Security and privacy](docs/security.md).

## Reporting a vulnerability

Email **security@mizfitxtm.dev**. Please do not open a public issue for a vulnerability: an issue is visible to everyone before a fix exists.

A useful report includes:

- what the problem is and what someone could do with it
- the Hypora version (`rpm -q hypora`) and your Fedora version
- the steps to reproduce it, or the file and line if you found it by reading the code
- whether it needs local access, a malicious file such as a theme or plugin, or only network access

Hypora is maintained by one person, so there is no guaranteed response time. I will confirm that I received the report, tell you whether I can reproduce it, and credit you in the release notes if you want that.

## Supported versions

Only the latest release in the [`mizfitxtm/hypora` COPR](https://copr.fedorainfracloud.org/coprs/mizfitxtm/hypora/) gets fixes. Update with `sudo dnf upgrade hypora`, then run `hypora-setup`.

## What is in scope

Hypora's own code: the installer (`hypora-setup`, `install.sh`), the helpers in `bin/` (above all the ones that run as root, such as `hypora-security`), the Quickshell configuration, the theme renderer and the plugin installer.

Problems in software Hypora installs but does not write belong with that project: Fedora, Hyprland, Quickshell, the browsers, Flatpak apps and USBGuard. If you are not sure which side a problem is on, send it here and I will pass it on.

## Checking what you install

The signing-key fingerprints for the package repositories are in the [readme](readme.md#install) and at [mizfitxtm.dev/hypora/keys](https://mizfitxtm.dev/hypora/keys/).
