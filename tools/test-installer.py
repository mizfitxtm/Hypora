#!/usr/bin/env python3
"""Tests for the installer's browser menu and dnf_install skip.
Run: python3 tools/test-installer.py
"""
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = "".join((ROOT / f).read_text() for f in ("install.sh", "hypora-setup", "lib.sh"))


def func(name):
    return re.search(rf"^{name}\(\) \{{.*?^\}}", SRC, re.S | re.M).group(0)


def func_from_file(path, name):
    return re.search(rf"^{name}\(\) \{{.*?^\}}", (ROOT / path).read_text(), re.S | re.M).group(0)


def bash(script, stdin=None, env=None):
    return subprocess.run(["bash", "-c", script], input=stdin, capture_output=True, text=True,
                          env={"PATH": os.environ["PATH"], **(env or {})})


class BrowserTests(unittest.TestCase):
    def pick(self, env=None):
        # No terminal here, so the menu itself is not reached; the env var and the default are.
        # flatpak is stubbed so an installed browser on this machine cannot change the answer
        return bash(f"flatpak() {{ return 1; }}\n{func('pick_browser')}\npick_browser", stdin="", env=env).stdout.strip()

    def test_env_choice(self):
        for b in ("firefox", "chromium", "zen", "brave", "trivalent"):
            self.assertEqual(self.pick({"BROWSER": b}), b)

    def test_default_and_junk_fall_back_to_firefox(self):
        self.assertEqual(self.pick(), "firefox")
        self.assertEqual(self.pick({"BROWSER": "netscape"}), "firefox")

    def test_every_choice_maps_to_a_flatpak(self):
        for b, app in (("chromium", "org.chromium.Chromium"), ("zen", "app.zen_browser.zen"),
                       ("brave", "com.brave.Browser"), ("trivalent", "trivalent"),
                       ("firefox", "org.mozilla.firefox")):
            self.assertRegex(SRC, rf"{b if b != 'firefox' else r'\*'}\) BROWSER_APP={re.escape(app)} ;;")


class DnfInstallTests(unittest.TestCase):
    def run_install(self, installed, *pkgs):
        with tempfile.TemporaryDirectory() as d:
            log = Path(d) / "calls"
            script = (
                f"rpm() {{ shift; [ \"$1\" = --whatprovides ] && shift; case ' {installed} ' in *\" $1 \"*) return 0 ;; esac; return 1; }}\n"
                f"sudo() {{ echo \"$*\" >> {log}; }}\nwarn() {{ :; }}\n{func('dnf_run')}\n{func('dnf_install')}\n"
                f"dnf_install {' '.join(pkgs)}")
            bash(script)
            return log.read_text() if log.exists() else ""

    def test_skips_dnf_when_all_installed(self):
        self.assertEqual(self.run_install("a b", "--skip-unavailable", "a", "b"), "")

    def test_runs_dnf_when_one_missing(self):
        self.assertIn("dnf install -y --skip-unavailable a c", self.run_install("a", "--skip-unavailable", "a", "c"))


class DnfRunTests(unittest.TestCase):
    def run_fake(self, fake):
        # sudo here runs a fake dnf; the real one is never called
        script = (f"sudo() {{ shift; exec bash -c '{fake}'; }}\nwarn() {{ echo WARN \"$*\"; }}\n"
                  f"{func('dnf_run')}\nDNF_HANG_WAIT=1\ndnf_run install -y x; echo rc=$?")
        return bash(script).stdout

    def test_stops_a_hang_after_nothing_to_do(self):
        out = self.run_fake("echo Nothing to do.; sleep 60")
        self.assertIn("WARN dnf hung", out)
        self.assertIn("rc=0", out)

    def test_passes_through_failure(self):
        self.assertIn("rc=3", self.run_fake("echo broke; exit 3"))

    def test_clean_run_no_warning(self):
        out = self.run_fake("echo Nothing to do.")
        self.assertNotIn("WARN", out)
        self.assertIn("rc=0", out)


class CoprKeyTests(unittest.TestCase):
    def check(self, keys, fpr):
        # rpm is stubbed to list the keys it "holds": "<version> <summary>" per line
        script = (f"rpm() {{ printf '%s\\n' {keys}; }}\n{func('check_copr_key')}\n"
                  f"check_copr_key mizfitxtm/hypora {fpr}; echo rc=$?")
        return bash(script).stdout.strip()

    GOOD = "387bfc4e4d37eadd33056eb41602d18e965bcec2"

    def test_matching_full_fingerprint(self):
        self.assertEqual(self.check(f"'{self.GOOD} gpg(mizfitxtm_hypora (None))'", self.GOOD.upper()), "rc=0")

    def test_matching_short_id(self):
        self.assertEqual(self.check(f"'{self.GOOD[-8:]} gpg(mizfitxtm_hypora (None))'", self.GOOD), "rc=0")

    def test_other_key_for_the_same_copr_fails(self):
        self.assertEqual(self.check("'deadbeef gpg(mizfitxtm_hypora (None))'", self.GOOD), "rc=1")

    def test_keys_for_other_coprs_are_ignored(self):
        self.assertEqual(self.check("'deadbeef gpg(someone_else (None))'", self.GOOD), "rc=0")


class DropWeakDepTests(unittest.TestCase):
    def run_drop(self, installed=True, reason="Weak Dependency", required=False):
        # rpm and dnf are stubbed: rpm -q PKG, rpm -q --whatrequires PKG (exit 0 = something requires it)
        script = (
            f"rpm() {{ case \"$*\" in '-q wofi') return {0 if installed else 1};; '-q --whatrequires wofi') return {0 if required else 1};; esac; }}\n"
            f"dnf() {{ echo '{reason}'; }}\nlog() {{ :; }}\nwarn() {{ :; }}\n"
            f"dnf_run() {{ echo \"REMOVED $*\"; }}\n{func('drop_weak_dep')}\ndrop_weak_dep wofi")
        return bash(script).stdout

    def test_removes_a_weak_dependency_nothing_requires(self):
        self.assertIn("REMOVED remove -y --setopt=clean_requirements_on_remove=False wofi", self.run_drop())

    def test_keeps_a_package_you_installed(self):
        self.assertEqual(self.run_drop(reason="User"), "")

    def test_keeps_a_hard_dependency(self):
        self.assertEqual(self.run_drop(reason="Dependency"), "")

    def test_keeps_it_when_something_requires_it(self):
        self.assertEqual(self.run_drop(required=True), "")

    def test_does_nothing_when_not_installed(self):
        self.assertEqual(self.run_drop(installed=False), "")


class UpdateCheckTests(unittest.TestCase):
    """hypora-update-check with fake dnf and notify-send programs, in a throwaway HOME."""

    def run_check(self, names, args=("--notify",), runs=1):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "bin").mkdir()
            (d / "bin/dnf").write_text(f"#!/bin/sh\nprintf '%s\\n' {names}\n")
            (d / "bin/notify-send").write_text(f"#!/bin/sh\necho \"$@\" >> {d}/notes\n")
            for f in ("dnf", "notify-send"):
                (d / "bin" / f).chmod(0o755)
            env = {"HOME": str(d), "PATH": f"{d}/bin:/usr/bin:/bin"}
            outs = [subprocess.run(["bash", str(ROOT / "bin/hypora-update-check"), *args],
                                   env=env, capture_output=True, text=True).stdout for _ in range(runs)]
            notes = (d / "notes").read_text().splitlines() if (d / "notes").exists() else []
            return outs[-1], notes

    def test_says_how_many_are_waiting_and_notifies(self):
        out, notes = self.run_check("a b b c")
        self.assertIn("3 update(s) waiting", out)
        self.assertEqual(len(notes), 1)

    def test_same_count_is_not_announced_twice(self):
        self.assertEqual(len(self.run_check("a b", runs=2)[1]), 1)

    def test_no_updates_is_quiet(self):
        out, notes = self.run_check("")
        self.assertIn("No updates waiting", out)
        self.assertEqual(notes, [])

    def test_without_the_flag_it_only_prints(self):
        out, notes = self.run_check("a b", args=())
        self.assertIn("2 update(s) waiting", out)
        self.assertEqual(notes, [])

    def test_a_changed_count_is_announced_again(self):
        func_src = func_from_file("bin/hypora-update-check", "should_notify")
        script = f"REMIND_AFTER=604800\n{func_src}\nshould_notify 5 3 1000 2000 && echo yes || echo no; should_notify 3 3 1000 2000 && echo yes || echo no; should_notify 3 3 1000 700000 && echo yes || echo no; should_notify 0 3 1000 700000 && echo yes || echo no"
        self.assertEqual(bash(script).stdout.split(), ["yes", "no", "yes", "no"])


class LoginThemeTests(unittest.TestCase):
    def test_session_lookup_does_not_use_display_role(self):
        # SDDM's SessionModel has no DisplayRole: it returned "" for every row, so the first session
        # (GNOME Classic, on a Workstation install) was chosen instead of Hyprland.
        qml = (ROOT / "system/sddm/hypora/Main.qml").read_text()
        lookups = [l for l in qml.splitlines() if "sessionModel.data(" in l]
        self.assertTrue(lookups)
        for line in lookups:
            self.assertNotIn("DisplayRole", line)


class SyntaxTests(unittest.TestCase):
    def test_scripts_parse(self):
        for f in ("install.sh", "hypora-setup", "lib.sh"):
            r = subprocess.run(["bash", "-n", str(ROOT / f)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, f"{f}: {r.stderr}")


if __name__ == "__main__":
    unittest.main()
