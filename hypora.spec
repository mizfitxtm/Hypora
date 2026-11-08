Name:           hypora
Version:        0.1.0
Release:        1%{?dist}
Summary:        A privacy-focused Hyprland desktop for Fedora
License:        GPL-3.0-or-later
URL:            https://github.com/misfitxtm/Hypora
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch

# Hyprland and uwsm come from the sdegler/hyprland COPR; hypora-setup and install.sh enable it.
Requires:       hyprland
Requires:       hyprland-guiutils
Requires:       hyprlock
Requires:       hypridle
Requires:       hyprsunset
Requires:       uwsm
Requires:       quickshell
Requires:       kitty
Requires:       git
Requires:       zsh
Requires:       zsh-autosuggestions
Requires:       zsh-syntax-highlighting
Requires:       fastfetch
Requires:       neovim
Requires:       ripgrep
Requires:       fd-find
Requires:       eza
Requires:       polkit
Requires:       sddm
Requires:       qt6-qtsvg
Requires:       gnupg2
Requires:       curl
Requires:       tar
Requires:       xz
Requires:       unzip
Requires:       firewalld
Requires:       gnome-keyring
Requires:       gnome-keyring-pam
Requires:       gcr
Requires:       liberation-sans-fonts
Requires:       liberation-serif-fonts
Requires:       adwaita-icon-theme
Requires:       papirus-icon-theme
Requires:       breeze-icon-theme
Requires:       adw-gtk3-theme
Requires:       qt6ct
Requires:       qt5ct
Requires:       qt6-qtimageformats
Requires:       xdg-desktop-portal-hyprland
Requires:       xdg-desktop-portal-gtk
Requires:       xdg-user-dirs
Requires:       xdg-utils
Requires:       xdg-terminal-exec
Requires:       NetworkManager
Requires:       NetworkManager-tui
Requires:       NetworkManager-wifi
Requires:       pipewire
Requires:       wireplumber
Requires:       pipewire-pulseaudio
Requires:       wiremix
Requires:       bluez
Requires:       upower
Requires:       pcsc-lite
Requires:       pcsc-lite-ccid
Requires:       opensc
Requires:       nss-tools
Requires:       yubikey-manager
Requires:       fido2-tools
Requires:       fwupd
Requires:       mokutil
Requires:       policycoreutils
Requires:       nautilus
Requires:       gvfs
Requires:       gnome-calculator
Requires:       gnome-disk-utility
Requires:       gnome-software
Requires:       gnome-calendar
Requires:       baobab
Requires:       simple-scan
Requires:       papers
Requires:       loupe
Requires:       gnome-text-editor
Requires:       mpv
Requires:       cliphist
Requires:       wl-clipboard
Requires:       grim
Requires:       slurp
Recommends:     iw
Recommends:     pamixer
Recommends:     playerctl
Recommends:     google-noto-emoji-fonts
Recommends:     plymouth
Recommends:     plymouth-plugin-two-step
Recommends:     plymouth-scripts

%description
Hyprland, a Quickshell bar and settings windows, themes, a login screen and
privacy-minded defaults for Fedora. This package installs the files under
/usr/share/hypora; run hypora-setup afterwards to configure the machine and
your account.

%prep
%autosetup

%build

%install
install -d %{buildroot}%{_datadir}/hypora %{buildroot}%{_bindir}
cp -a bin config themes system applications %{buildroot}%{_datadir}/hypora/
chmod 755 %{buildroot}%{_datadir}/hypora/bin/*
find %{buildroot}%{_datadir}/hypora -name __pycache__ -prune -exec rm -rf {} +
install -m644 lib.sh %{buildroot}%{_datadir}/hypora/lib.sh
install -m755 hypora-setup %{buildroot}%{_bindir}/hypora-setup

%files
%license LICENSE
%doc readme.md docs
%{_datadir}/hypora
%{_bindir}/hypora-setup

%changelog
* Sun Nov 08 2026 mizfitxtm <noreply@users.noreply.github.com> - 0.1.0-1
- First COPR build
