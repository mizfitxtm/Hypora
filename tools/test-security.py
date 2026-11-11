#!/usr/bin/env python3
"""Tests for the risky parts of bin/hypora-theme and bin/hypora-security.
Run: python3 tools/test-security.py

hypora-theme pastes palette values into a sed script, and a colors.toml is something people
share, so its validator is the only thing between a theme and a shell command. The swapfile
code rewrites /etc/fstab as root, where a mistake is a machine that does not boot.
"""
import importlib.machinery
import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(ROOT / "bin" / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class ThemeValidatorTests(unittest.TestCase):
    def run_theme(self, colors):
        with tempfile.TemporaryDirectory() as home:
            d = Path(home) / ".config/hypora/themes/Evil"
            d.mkdir(parents=True)
            (d / "colors.toml").write_text(colors)
            return subprocess.run(["bash", str(ROOT / "bin/hypora-theme"), "Evil"],
                                  env={"HOME": home, "PATH": os.environ["PATH"]},
                                  capture_output=True, text=True)

    def test_refuses_sed_injection(self):
        for bad in ('accent = "#112233|e"', 'font = "x|w /tmp/x"', 'font = "a;b"',
                    'accent = "#12345"'):
            r = self.run_theme(f'name = "Evil"\n{bad}\n')
            self.assertEqual(r.returncode, 1, bad)
            self.assertIn("Refusing theme", r.stderr, bad)

    def test_refuses_bad_theme_name(self):
        r = subprocess.run(["bash", str(ROOT / "bin/hypora-theme"), "../x"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn("Not a plain theme name", r.stderr)


class SwapfileTests(unittest.TestCase):
    def setUp(self):
        self.hs = load("hypora-security")
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.fstab = self.tmp / "fstab"
        self.fstab.write_text("UUID=abc / btrfs defaults 0 0")   # no trailing newline
        self.swap = self.tmp / "swapfile"
        patches = [mock.patch.object(self.hs, "FSTAB", self.fstab),
                   mock.patch.object(self.hs, "SWAPFILE", self.swap),
                   mock.patch.object(self.hs.os, "geteuid", return_value=0),
                   mock.patch.object(self.hs, "run", return_value=(0, ""))]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def state(self, **kw):
        base = {"exists": self.swap.is_file(), "active": False, "rootFs": "btrfs",
                "rootEncrypted": True, "supported": True}
        return {**base, **kw}

    def test_add_then_remove_keeps_other_lines(self):
        def fake_create(st, size):
            self.swap.write_text("x")
        with mock.patch.object(self.hs, "swapfile_state", side_effect=lambda: self.state()), \
             mock.patch.object(self.hs, "_create_swapfile", side_effect=fake_create):
            self.hs.add_swapfile("1g")
            text = self.fstab.read_text()
            self.assertEqual(text.count(f"{self.swap} none swap defaults,nofail 0 0"), 1)
            self.assertIn("UUID=abc / btrfs defaults 0 0\n", text)   # newline was added

            self.hs.remove_swapfile()
        self.assertEqual(self.fstab.read_text(), "UUID=abc / btrfs defaults 0 0\n")
        self.assertFalse(self.swap.exists())

    def test_refuses_plaintext_root_and_bad_size(self):
        with mock.patch.object(self.hs, "swapfile_state",
                               return_value=self.state(rootEncrypted=False)):
            with self.assertRaises(SystemExit):
                self.hs.add_swapfile("1g")
        with self.assertRaises(SystemExit):
            self.hs.add_swapfile("1g; rm -rf /")
        self.assertEqual(self.fstab.read_text(), "UUID=abc / btrfs defaults 0 0")


class RootBoundFileTests(unittest.TestCase):
    """Files that root copies under /usr and /etc come from templates in the user's home, so they are checked first."""
    ROOT_FILES = ("sddm-theme.conf", "plymouth.plymouth", "qt6ct-system.conf")

    def render(self, tamper=None):
        with tempfile.TemporaryDirectory() as home:
            conf = Path(home) / ".config/hypora"
            (conf / "themes/Nord").mkdir(parents=True)
            (conf / "themes/Nord/colors.toml").write_text((ROOT / "themes/Nord/colors.toml").read_text())
            (conf / "templates").mkdir()
            for t in (ROOT / "themes/templates").glob("*.tpl"):
                (conf / "templates" / t.name).write_text(t.read_text())
            for name, extra in (tamper or {}).items():
                with open(conf / "templates" / name, "a") as f:
                    f.write(extra)
            stubs = Path(home) / "stubs"       # keep the test away from the real session
            stubs.mkdir()
            for cmd in ("pkill", "gsettings"):
                (stubs / cmd).write_text("#!/bin/sh\nexit 0\n")
                (stubs / cmd).chmod(0o755)
            r = subprocess.run(["bash", str(ROOT / "bin/hypora-theme"), "Nord"], stdin=subprocess.DEVNULL,
                               env={"HOME": home, "PATH": f"{stubs}:{os.environ['PATH']}"}, capture_output=True, text=True)
            return r, {f for f in self.ROOT_FILES if (conf / "current" / f).exists()}, (conf / "current/kitty.conf").exists()

    def test_shipped_templates_pass(self):
        r, kept, _ = self.render()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(kept, set(self.ROOT_FILES))
        self.assertNotIn("Not installing", r.stderr)

    def test_edited_templates_are_not_offered_to_root(self):
        r, kept, user_file = self.render({"plymouth.plymouth.tpl": "ScriptFile=/home/x/evil.script\n",
                                          "sddm-theme.conf.tpl": 'x="$(id)"\n',
                                          "qt6ct.conf.tpl": "stylesheets=/tmp/x.qss\n"})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(kept, set())
        self.assertTrue(user_file)          # the user's own theme still applies
        for line in ("ScriptFile=/home/x/evil.script", 'x="$(id)"', "stylesheets=/tmp/x.qss"):
            self.assertIn(line, r.stderr)


class SelinuxBootTests(unittest.TestCase):
    def test_disabled_is_refused(self):
        hs = load("hypora-security")
        with mock.patch.object(hs.os, "geteuid", return_value=0):
            with self.assertRaises(SystemExit):
                hs.set_selinux_boot("disabled")


    def set_boot(self, before, mode):
        hs = load("hypora-security")
        with tempfile.TemporaryDirectory() as d:
            conf, mark = Path(d) / "config", Path(d) / "autorelabel"
            conf.write_text(before)
            with mock.patch.object(hs.os, "geteuid", return_value=0), \
                 mock.patch.object(hs, "SELINUX_CONFIG", conf), mock.patch.object(hs, "AUTORELABEL", mark):
                hs.set_selinux_boot(mode)
            return conf.read_text(), mark.exists()

    def test_relabels_only_when_moving_to_enforcing(self):
        self.assertEqual(self.set_boot("SELINUX=permissive\n", "enforcing"), ("SELINUX=enforcing\n", True))
        self.assertEqual(self.set_boot("# no mode yet\n", "enforcing")[1], True)
        self.assertEqual(self.set_boot("SELINUX=enforcing\n", "enforcing"), ("SELINUX=enforcing\n", False))
        self.assertEqual(self.set_boot("SELINUX=enforcing\n", "permissive"), ("SELINUX=permissive\n", False))


class HardenTests(unittest.TestCase):
    """Hardened mode edits the kernel command line and can block USB input, so both directions are checked."""

    def setUp(self):
        self.hs = load("hypora-security")
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.cmdline = self.tmp / "cmdline"
        self.cmdline.write_text("ro rhgb quiet\n")
        self.dns = self.tmp / "resolved.conf.d/hypora-hardened.conf"
        self.rules = self.tmp / "usbguard/rules.conf"
        self.mark = self.tmp / "hypora/hardened"
        self.calls = []
        self.policy = 'allow id 1d6b:0002 serial "x"'

        def fake_run(cmd, timeout=10):
            self.calls.append(cmd)
            return (0, self.policy) if cmd[:2] == ["usbguard", "generate-policy"] else (0, "")

        patches = [mock.patch.object(self.hs, "KERNEL_CMDLINE", self.cmdline),
                   mock.patch.object(self.hs, "STRICT_DNS_CONF", self.dns),
                   mock.patch.object(self.hs, "USBGUARD_RULES", self.rules),
                   mock.patch.object(self.hs, "HARDENED_MARK", self.mark),
                   mock.patch.object(self.hs.os, "geteuid", return_value=0),
                   mock.patch.object(self.hs.shutil, "which", return_value="/usr/bin/usbguard"),
                   mock.patch.object(self.hs, "run", side_effect=fake_run)]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def started_usbguard(self):
        return ["systemctl", "enable", "--now", "usbguard.service"] in self.calls

    def test_on_then_off_puts_everything_back(self):
        self.hs.set_harden("on")
        self.assertEqual(self.cmdline.read_text(), "ro rhgb quiet " + " ".join(self.hs.HARDEN_ARGS) + "\n")
        self.assertIn("DNSOverTLS=yes", self.dns.read_text())
        self.assertTrue(self.mark.is_file())
        self.assertTrue(self.started_usbguard())
        self.assertEqual(self.rules.stat().st_mode & 0o777, 0o600)

        self.hs.set_harden("on")                      # a second "on" must not double the arguments
        self.assertEqual(self.cmdline.read_text().count("vsyscall=none"), 1)

        self.hs.set_harden("off")
        self.assertEqual(self.cmdline.read_text(), "ro rhgb quiet\n")
        self.assertFalse(self.dns.exists())
        self.assertFalse(self.mark.exists())
        self.assertIn("allow", self.rules.read_text())   # rules are kept for next time

    def test_empty_policy_never_starts_usbguard(self):
        self.policy = ""
        self.hs.set_harden("on")
        self.assertFalse(self.started_usbguard())
        self.assertFalse(self.rules.exists())

    def test_existing_usb_rules_are_kept(self):
        self.rules.parent.mkdir(parents=True)
        self.rules.write_text("allow id 046d:c52b\n")
        self.hs.set_harden("on")
        self.assertEqual(self.rules.read_text(), "allow id 046d:c52b\n")
        self.assertTrue(self.started_usbguard())

    def test_grubby_failure_changes_nothing(self):
        with mock.patch.object(self.hs, "run", return_value=(1, "")):
            with self.assertRaises(SystemExit):
                self.hs.set_harden("on")
        self.assertEqual(self.cmdline.read_text(), "ro rhgb quiet\n")
        self.assertFalse(self.dns.exists())

    def test_bad_state_is_refused(self):
        with self.assertRaises(SystemExit):
            self.hs.set_harden("maybe")

    def test_dns_dropdown_writes_and_removes_the_strict_file(self):
        self.hs.set_dns("strict")
        self.assertIn("Domains=~.", self.dns.read_text())     # without it resolved keeps the DHCP resolver
        self.hs.set_dns("opportunistic")
        self.assertFalse(self.dns.exists())
        with self.assertRaises(SystemExit):
            self.hs.set_dns("no")

    def test_strict_dns_file_overrides_the_default_one(self):
        self.assertGreater(self.hs.STRICT_DNS_CONF.name, "hypora-dns.conf")   # resolved reads drop-ins in name order

    def test_network_zone_changes_each_connected_network(self):
        conns = {"connections": [{"uuid": "u1", "device": "wlan0", "zone": "public"}], "zone": "public"}
        with mock.patch.object(self.hs, "network_zone", return_value=conns):
            self.hs.set_network_zone("home")
            self.assertIn(["nmcli", "connection", "modify", "u1", "connection.zone", "home"], self.calls)
            self.assertIn(["nmcli", "device", "reapply", "wlan0"], self.calls)
            with self.assertRaises(SystemExit):
                self.hs.set_network_zone("trusted; rm -rf /")


class UsbWatchTests(unittest.TestCase):
    """The notifier reads text a USB device partly controls, so the parsing and cleaning are checked."""
    WATCH = """[IPC] Connected
[device] PresenceChanged: id=14
 event=Insert
 target=block
 device_rule=block id 0781:5581 serial "4C53" name "Ultra <b>\x07Fit" hash "x" with-interface 08:06:50
[device] PolicyApplied: id=14
 target=block
 device_rule=block id 0781:5581 serial "4C53" name "Ultra <b>\x07Fit" hash "x" with-interface 08:06:50
 rule_id=4294967294
[device] PresenceChanged: id=15
 event=Insert
 target=allow
 device_rule=allow id 046d:c52b name "Receiver"
[device] PolicyChanged: id=14
 target_old=block
 target_new=allow
 device_rule=allow id 0781:5581 name "Ultra Fit"
 rule_id=4294967295
[device] PresenceChanged: id=14
 event=Remove
 target=allow
 device_rule=allow id 0781:5581 name "Ultra Fit"
[device] PresenceChanged: id=14
 event=Insert
 target=block
 device_rule=block id 0781:5581 name "Ultra Fit"
"""

    def setUp(self):
        self.uw = load("hypora-usb-watch")

    def test_asks_once_per_blocked_device_and_again_after_replug(self):
        got = list(self.uw.blocked(self.WATCH.splitlines()))
        self.assertEqual([i for i, _ in got], ["14", "14"])       # not for the allowed one, not twice per insert

    def test_device_name_is_cleaned(self):
        label = list(self.uw.blocked(self.WATCH.splitlines()))[0][1]
        self.assertEqual(label, "Ultra &lt;b&gt;Fit (0781:5581)")   # markup escaped, control character dropped

    def test_allow_uses_the_numeric_id_only(self):
        calls = []
        def fake_run(cmd, **kw):
            calls.append(cmd)
            return mock.Mock(stdout="always\n" if cmd[0] == "notify-send" else "")
        with mock.patch.object(self.uw.subprocess, "run", side_effect=fake_run):
            self.uw.ask("14", "Ultra Fit")
        self.assertEqual(calls[-1], ["usbguard", "allow-device", "14", "-p"])


class HardeningFileTests(unittest.TestCase):
    """A typo in these files fails silently at boot, so their shape is checked here."""

    def lines(self, rel):
        text = (ROOT / "system" / rel).read_text()
        return [l for l in text.splitlines() if l.strip() and not l.startswith("#")]

    def test_sysctl_lines_are_key_value(self):
        for line in self.lines("sysctl.d/60-hypora-hardening.conf"):
            self.assertRegex(line, r"^[a-z0-9_.]+ = \d+$")

    def test_blocklist_lines_disable_one_module(self):
        for line in self.lines("modprobe.d/hypora-blocklist.conf"):
            self.assertRegex(line, r"^install [a-z0-9_-]+ /bin/false$")

    def test_time_servers_all_use_nts(self):
        text = (ROOT / "system/chrony/hypora-nts.conf").read_text()
        self.assertIn("Added by Hypora", text)          # hypora-setup looks for this before appending
        for line in self.lines("chrony/hypora-nts.conf"):
            self.assertRegex(line, r"^server \S+ iburst nts$")

    def test_browser_policy_is_valid_and_marked(self):
        import json
        text = (ROOT / "system/browser/policies.json").read_text()
        self.assertIn("Managed by Hypora", text)        # hypora-setup only replaces a file with this marker
        self.assertIsInstance(json.loads(text)["policies"], dict)


class ReplaceDeConfigTests(unittest.TestCase):
    """The GNOME settings cleanup moves files to a backup and leaves what Hypora uses."""

    def setUp(self):
        self.mod = load("hypora-replace-de")
        self.mod.installed_names = lambda: set()
        self.mod.is_running = lambda name: False
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        for rel in (".local/share/gnome-shell/extensions/x/metadata.json", ".config/gnome-session/saved-session/a",
                    ".config/monitors.xml", ".config/gtk-3.0/settings.ini", ".config/goa-1.0/accounts.conf",
                    ".config/mimeapps.list"):
            f = self.home / rel
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text("data")

    def tearDown(self):
        self.tmp.cleanup()

    def run_config(self):
        return self.mod.cmd_config(assume_yes=True, home=self.home, use_dconf=False)

    def test_moves_gnome_files_to_a_backup(self):
        self.assertEqual(self.run_config(), 0)
        self.assertFalse((self.home / ".local/share/gnome-shell").exists())
        self.assertFalse((self.home / ".config/monitors.xml").exists())
        backups = list((self.home / ".local/share/hypora/removed-gnome-config").iterdir())
        self.assertEqual(len(backups), 1)
        self.assertTrue((backups[0] / ".local/share/gnome-shell/extensions/x/metadata.json").is_file())

    def test_leaves_what_hypora_uses(self):
        self.run_config()
        for keep in (".config/gtk-3.0/settings.ini", ".config/goa-1.0/accounts.conf", ".config/mimeapps.list"):
            self.assertTrue((self.home / keep).is_file(), keep)

    def test_refuses_while_gnome_shell_is_installed(self):
        self.mod.installed_names = lambda: {"gnome-shell"}
        self.assertEqual(self.run_config(), 1)
        self.assertTrue((self.home / ".config/monitors.xml").exists())

    def test_nothing_to_do_is_quiet_success(self):
        self.run_config()
        self.assertEqual(self.run_config(), 0)


class ReplaceDeRunningTests(unittest.TestCase):
    """sudo clears XDG_CURRENT_DESKTOP, so "is it running" must also look at processes."""

    def setUp(self):
        self.mod = load("hypora-replace-de")

    def with_procs(self, procs):
        self.mod.run = lambda cmd, timeout=60: (0, "") if cmd[:2] == ["pgrep", "-x"] and cmd[2] in procs else (1, "")

    def test_shell_process_counts_without_the_environment(self):
        self.with_procs({"gnome-shell"})
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertTrue(self.mod.is_running("GNOME"))

    def test_no_process_means_not_running(self):
        self.with_procs(set())
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertFalse(self.mod.is_running("GNOME"))

    def test_another_desktops_process_does_not_count(self):
        self.with_procs({"plasmashell"})
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertFalse(self.mod.is_running("GNOME"))
            self.assertTrue(self.mod.is_running("KDE Plasma"))

    def test_environment_alone_still_counts(self):
        self.with_procs(set())
        with mock.patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "GNOME"}, clear=True):
            self.assertTrue(self.mod.is_running("GNOME"))


if __name__ == "__main__":
    unittest.main()
