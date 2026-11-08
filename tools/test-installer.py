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
SRC = (ROOT / "install.sh").read_text()


def func(name):
    return re.search(rf"^{name}\(\) \{{.*?^\}}", SRC, re.S | re.M).group(0)


def bash(script, stdin=None, env=None):
    return subprocess.run(["bash", "-c", script], input=stdin, capture_output=True, text=True,
                          env={"PATH": os.environ["PATH"], **(env or {})})


class BrowserTests(unittest.TestCase):
    def pick(self, env=None):
        # No terminal here, so the menu itself is not reached; the env var and the default are.
        return bash(f"{func('pick_browser')}\npick_browser", stdin="", env=env).stdout.strip()

    def test_env_choice(self):
        for b in ("firefox", "chromium", "zen", "brave"):
            self.assertEqual(self.pick({"BROWSER": b}), b)

    def test_default_and_junk_fall_back_to_firefox(self):
        self.assertEqual(self.pick(), "firefox")
        self.assertEqual(self.pick({"BROWSER": "netscape"}), "firefox")

    def test_every_choice_maps_to_a_flatpak(self):
        for b, app in (("chromium", "org.chromium.Chromium"), ("zen", "app.zen_browser.zen"),
                       ("brave", "com.brave.Browser"), ("firefox", "org.mozilla.firefox")):
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


class SyntaxTests(unittest.TestCase):
    def test_scripts_parse(self):
        for f in ("install.sh", "install-copr.sh", "hypora-setup", "lib.sh"):
            r = subprocess.run(["bash", "-n", str(ROOT / f)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, f"{f}: {r.stderr}")


if __name__ == "__main__":
    unittest.main()
