"""tools/publish.sh against stub xcrun/git/gh/scp/curl/ssh-rc on a temporary PATH.
Nothing real is touched: every stub appends its arguments to a call log and answers from env vars."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
V = "9.8.7"

# One stub body, installed under each command name; behaviour comes from STUB_* env vars.
STUB = r'''#!/bin/bash
name=$(basename "$0")
echo "$name $*" >> "$CALL_LOG"
case "$name $*" in
  "xcrun stapler validate"*) exit "${STUB_STAPLE_RC:-0}" ;;
  "git symbolic-ref"*) echo "${STUB_BRANCH:-main}"; exit 0 ;;
  "git status"*) [ -n "${STUB_DIRTY:-}" ] && echo " M tracked.py"; exit 0 ;;
  "git rev-parse"*) [ -n "${STUB_LOCAL_TAG:-}" ] && exit 0; exit 1 ;;
  "git ls-remote"*) [ -n "${STUB_REMOTE_TAG:-}" ] && echo "abc123	refs/tags/Beat-Key-9.8.7"; exit 0 ;;
  "git tag"*|"git push"*) exit 0 ;;
  "gh release view"*)
    if [ -n "${STUB_RELEASE_EXISTS:-}" ]; then echo '{"tagName":"Beat-Key-9.8.7"}'; exit 0; fi
    if [ -n "${STUB_GH_DOWN:-}" ]; then echo "dial tcp: network is unreachable" >&2; exit 1; fi
    echo "release not found" >&2; exit 1 ;;
  "gh release create"*) exit 0 ;;
  "scp "*) exit 0 ;;
  "curl "*) printf '%s' "${STUB_HTTP:-303}"; exit 0 ;;
  "ssh-rc js-mac-pro true") [ -n "${STUB_SERVER_DOWN:-}" ] && exit 255; exit 0 ;;
  "ssh-rc js-mac-pro test ! -e"*) [ -n "${STUB_DMG_ON_SERVER:-}" ] && exit 1; exit 0 ;;
  "ssh-rc js-mac-pro printf"*) echo '{"version": "9.8.7"}'; exit 0 ;;
  "ssh-rc js-mac-pro cat"*)
    if [ -n "${STUB_JSON:-}" ]; then echo "$STUB_JSON"; else echo '{"version": "9.8.7"}'; fi; exit 0 ;;
esac
echo "unexpected stub call: $name $*" >&2; exit 99
'''

APPCAST = """<rss><channel><item>
<sparkle:version>{v}</sparkle:version>
<sparkle:shortVersionString>{v}</sparkle:shortVersionString>
<enclosure url="https://github.com/thuhmadhatter42/beat_dl/releases/download/Beat-Key-{v}/Beat-Key-{v}.dmg" />
</item></channel></rss>
"""

PUBLISH_CMDS = ("git tag", "git push", "scp", "gh release create", "ssh-rc js-mac-pro printf")


class PublishShTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="publish-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        (self.tmp / "tools").mkdir()
        shutil.copy(ROOT / "tools" / "publish.sh", self.tmp / "tools" / "publish.sh")
        (self.tmp / "VERSION").write_text(V + "\n")
        (self.tmp / "app" / "build").mkdir(parents=True)
        (self.tmp / "app" / "build" / f"Beat-Key-{V}.dmg").write_text("dmg")
        (self.tmp / "app" / "build" / "appcast.xml").write_text(APPCAST.format(v=V))
        (self.tmp / "friends-page").mkdir()
        (self.tmp / "friends-page" / "index.html").write_text("<html>")
        self.bin = self.tmp / "stubbin"
        self.bin.mkdir()
        for n in ("xcrun", "git", "gh", "scp", "curl", "ssh-rc"):
            p = self.bin / n
            p.write_text(STUB)
            p.chmod(0o755)
        self.log = self.tmp / "calls.log"
        self.log.write_text("")

    def run_publish(self, **env_extra):
        env = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.tmp),
               "CALL_LOG": str(self.log), "SSH_RC": str(self.bin / "ssh-rc")}
        env.update(env_extra)
        r = subprocess.run(["/bin/bash", str(self.tmp / "tools" / "publish.sh")],
                           capture_output=True, text=True, env=env, timeout=60)
        calls = self.log.read_text().splitlines()
        self.assertNotIn("unexpected stub call", r.stdout + r.stderr)
        return r, r.stdout + r.stderr, calls

    def assert_nothing_public(self, calls):
        bad = [c for c in calls if c.startswith(PUBLISH_CMDS)]
        self.assertEqual(bad, [], f"publish-phase command ran: {bad}")

    def test_a_everything_good(self):
        r, out, calls = self.run_publish()
        self.assertEqual(r.returncode, 0, out)
        self.assertIn(f"PUBLISHED {V}", out)
        pub = [c for c in calls if c.startswith(PUBLISH_CMDS)]
        order = ["git tag", "git push origin main", "git push origin Beat-Key", "scp app/build/Beat-Key",
                 "ssh-rc js-mac-pro printf", "scp friends-page", "gh release create"]
        self.assertEqual(len(pub), len(order), pub)
        for c, want in zip(pub, order):
            self.assertTrue(c.startswith(want), (c, want))
        # check phase strictly before publish phase
        first_pub = min(i for i, c in enumerate(calls) if c.startswith(PUBLISH_CMDS))
        for want in ("xcrun stapler", "git ls-remote", "gh release view", "ssh-rc js-mac-pro test"):
            self.assertTrue(any(c.startswith(want) for c in calls[:first_pub]), want)
        self.assertNotIn("git tag -f", " ".join(calls))
        # log file got timestamped lines
        logtxt = (self.tmp / "app" / "build" / f"publish-{V}.log").read_text()
        self.assertRegex(logtxt, r"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d == phase 3")
        self.assertIn(f"PUBLISHED {V}", logtxt)

    def check_fails(self, expect, mutate=None, **env):
        if mutate:
            mutate()
        r, out, calls = self.run_publish(**env)
        self.assertNotEqual(r.returncode, 0, out)
        self.assertNotIn("PUBLISHED", out)
        self.assertIn(expect, out)
        self.assertIn("completed: none", out)
        self.assert_nothing_public(calls)

    def test_b_dmg_missing(self):
        self.check_fails("missing", lambda: (self.tmp / "app/build" / f"Beat-Key-{V}.dmg").unlink())

    def test_b_not_stapled(self):
        self.check_fails("not stapled", STUB_STAPLE_RC="1")

    def test_b_appcast_missing(self):
        self.check_fails("appcast.xml missing", lambda: (self.tmp / "app/build/appcast.xml").unlink())

    def test_b_appcast_other_version(self):
        self.check_fails("does not name", lambda: (self.tmp / "app/build/appcast.xml").write_text(APPCAST.format(v="9.8.6")))

    def test_b_appcast_prefix_of_version(self):
        # 9.8.70 must not satisfy 9.8.7
        self.check_fails("does not name", lambda: (self.tmp / "app/build/appcast.xml").write_text(APPCAST.format(v="9.8.70")))

    def test_b_not_on_main(self):
        self.check_fails("not on branch main", STUB_BRANCH="feature")

    def test_b_dirty_tree(self):
        self.check_fails("uncommitted", STUB_DIRTY="1")

    def test_b_local_tag_exists(self):
        self.check_fails("exists locally", STUB_LOCAL_TAG="1")

    def test_b_remote_tag_exists(self):
        self.check_fails("exists on origin", STUB_REMOTE_TAG="1")

    def test_b_release_exists(self):
        self.check_fails("release Beat-Key-9.8.7 already exists", STUB_RELEASE_EXISTS="1")

    def test_b_github_unreachable(self):
        self.check_fails("could not ask GitHub", STUB_GH_DOWN="1")

    def test_b_server_down(self):
        self.check_fails("not reachable", STUB_SERVER_DOWN="1")

    def test_b_dmg_on_server(self):
        self.check_fails("already holds", STUB_DMG_ON_SERVER="1")

    def test_b_friends_page_missing(self):
        self.check_fails("friends-page/index.html missing", lambda: (self.tmp / "friends-page/index.html").unlink())

    def final_fails(self, expect, **env):
        r, out, calls = self.run_publish(**env)
        self.assertNotEqual(r.returncode, 0, out)
        self.assertNotIn("PUBLISHED", out)
        self.assertIn(expect, out)
        for step in ("tag Beat-Key-9.8.7", "push main", "push tag", "DMG to js-mac-pro",
                     "beat-key-latest.json", "friends page", "GitHub release"):
            self.assertIn(f"[{step}]", out.split("FAILED")[-1])
        self.assertTrue(any(c.startswith("gh release create") for c in calls))

    def test_c_wrong_http_status(self):
        self.final_fails("answered 200, expected 303", STUB_HTTP="200")

    def test_c_wrong_version_in_json(self):
        self.final_fails("expected version 9.8.7", STUB_JSON='{"version": "9.8.6"}')

    def test_publish_step_failure_names_state(self):
        # scp failing mid-publish: tag and pushes done, DMG step reported as the one in progress
        (self.bin / "scp").write_text("#!/bin/bash\necho \"scp $*\" >> \"$CALL_LOG\"; exit 1\n")
        r, out, calls = self.run_publish()
        self.assertNotEqual(r.returncode, 0)
        tail = out.split("FAILED")[-1]
        self.assertIn("[push tag]", tail)
        self.assertIn("Stopped during: DMG to js-mac-pro", tail)
        self.assertFalse(any(c.startswith("gh release create") for c in calls))


if __name__ == "__main__":
    unittest.main()
