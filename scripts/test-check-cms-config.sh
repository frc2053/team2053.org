#!/usr/bin/env bash
#
# Fixture tests for scripts/check-cms-config.sh.
#
# The checker's whole job is to fail on a config that has drifted away from the
# repository it describes. A checker that quietly passes everything looks
# exactly like a checker that is working, which is how check-site.sh came to
# bless an empty site in slice 03. So every assertion it makes is exercised
# here by breaking the thing it asserts and requiring a failure.
#
# Everything runs against a throwaway copy under $TMPDIR. It never touches the
# real tree.
#
# Shell only, no Node, no npm - the same rule the rest of this repository
# follows.
#
# Usage:  scripts/test-check-cms-config.sh
# Exit 0 if every assertion passed.

# Deliberately no `set -e`: every test has to run so one failure does not hide
# the rest. Failures are counted, and the exit status comes from the count.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECKER="$ROOT/scripts/check-cms-config.sh"

[ -x "$CHECKER" ] || { echo "no executable checker at $CHECKER" >&2; exit 2; }

failures=0
pass()   { printf 'ok    %s\n' "$1"; }
fail()   { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
detail() { printf '        %s\n' "$1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A copy of the real repository's CMS-relevant files: the config and the admin
# page under test, plus the two things the checker cross-references them
# against - the content files they name and the optimizer they have to agree
# with. Copied rather than synthesized, so a test can never pass against a
# fixture that has drifted from the config actually shipping.
new_fixture() {
  local dir="$WORK/$1"
  rm -rf "$dir"
  mkdir -p "$dir/static/admin" "$dir/static/images" "$dir/scripts" "$dir/content/pages"
  cp "$ROOT/static/admin/config.yml" "$dir/static/admin/config.yml"
  cp "$ROOT/static/admin/index.html" "$dir/static/admin/index.html"
  [ "$1" = missing_bundle ] || cp "$ROOT/static/admin/sveltia-cms.js" "$dir/static/admin/sveltia-cms.js"
  cp "$ROOT/scripts/optimize-images.sh" "$dir/scripts/optimize-images.sh"
  # Content only has to exist; the checker asserts presence, never contents.
  cp "$ROOT/content/_index.md" "$dir/content/_index.md"
  cp "$ROOT/content/pages/contact.md" "$dir/content/pages/contact.md"
  printf '%s' "$dir"
}

# Runs the checker in $1 and reports its exit status.
check_in() { ( cd "$1" && "$CHECKER" >"$WORK/out" 2>&1 ); }

# $1 label, $2 fixture dir. Requires the checker to pass.
expect_pass() {
  if check_in "$2"; then pass "$1"; else
    fail "$1"
    while IFS= read -r l; do detail "$l"; done < "$WORK/out"
  fi
}

# $1 label, $2 fixture dir. Requires the checker to fail, and its output to
# mention $3 - so a mutation cannot be "caught" by an unrelated assertion.
expect_fail() {
  if check_in "$2"; then
    fail "$1 (the checker passed)"
  elif ! grep -qi -- "$3" "$WORK/out"; then
    fail "$1 (failed, but not about \"$3\")"
    while IFS= read -r l; do detail "$l"; done < "$WORK/out"
  else
    pass "$1"
  fi
}

# ── The control ───────────────────────────────────────────────────────────
# Every mutation below is only meaningful because this one passes.
expect_pass "the real config passes over an unmutated tree" "$(new_fixture control)"

# ── The config and the content tree agree ─────────────────────────────────
# The failure this catches: a `file:` naming a page that is not in the
# repository. Sveltia shows that entry as an empty form and lets a student
# publish it, which creates a page nobody wrote at a path nobody chose.
d=$(new_fixture missing_content)
rm "$d/content/pages/contact.md"
expect_fail "a configured file that is not in the repository" "$d" "content/pages/contact.md"

d=$(new_fixture retitled_content)
sed -i.bak 's|content/pages/contact\.md|content/pages/contact-us.md|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
expect_fail "a configured file renamed only in the config" "$d" "contact-us.md"

# ── Uploads land where the optimizer looks ────────────────────────────────
# The failure this catches: the CMS writing uploads to a folder
# scripts/optimize-images.sh does not scan. Nothing breaks - the images simply
# stay at full size forever, on every page, with no symptom but a slow site.
d=$(new_fixture media_drift)
sed -i.bak 's|^media_folder: static/images|media_folder: static/uploads|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
mkdir -p "$d/static/uploads"
expect_fail "a media folder the optimizer does not scan" "$d" "static/uploads"

d=$(new_fixture optimizer_drift)
sed -i.bak 's|^MEDIA_ROOT=static/images|MEDIA_ROOT=static/img|' "$d/scripts/optimize-images.sh"
rm -f "$d/scripts/optimize-images.sh.bak"
expect_fail "the optimizer moved without the config" "$d" "static/img"

# ── The bundle is the committed one ───────────────────────────────────────
# The failure this catches: an upgrade done the easy way, by pointing the
# script tag back at the CDN. That silently re-subscribes the site to whatever
# a 0.x project publishes next, which is the one thing the committed bundle
# exists to prevent.
d=$(new_fixture cdn_script)
sed -i.bak 's|<script src="sveltia-cms.js">|<script src="https://unpkg.com/@sveltia/cms/dist/sveltia-cms.js">|' \
  "$d/static/admin/index.html"
rm -f "$d/static/admin/index.html.bak"
expect_fail "the admin page loading the CMS from a CDN" "$d" "unpkg.com"

d=$(new_fixture missing_bundle)
expect_fail "a script tag with no committed bundle behind it" "$d" "sveltia-cms.js"

# ── A publish reaches the site ────────────────────────────────────────────
# Both failures here look identical to the student - they press Publish, it
# succeeds, and the site never changes.
d=$(new_fixture editorial_workflow)
sed -i.bak 's|^publish_mode: simple|publish_mode: editorial_workflow|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
expect_fail "a review gate with nobody to review" "$d" "editorial_workflow"

d=$(new_fixture skip_ci)
sed -i.bak 's|^  auth_methods: \[token\]|  auth_methods: [token]\n  skip_ci: false|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
expect_fail "a skip-CI toggle a student can reach" "$d" "skip_ci"

# ── The upload is normalized on the way in ────────────────────────────────
d=$(new_fixture no_slugify)
sed -i.bak 's|^      slugify_filename: true|      slugify_filename: false|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
# scripts/optimize-images.sh rewrites references with sed and check-site.sh
# resolves them as URLs; both assume [A-Za-z0-9._/-]. Turn this off and
# `Beach Day (2).JPG` reaches the repository intact.
expect_fail "uploads no longer slugified" "$d" "slugify_filename"

d=$(new_fixture no_transform)
sed -i.bak 's|^          width: 1920|          width: 4096|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
expect_fail "the upload transform widened past 1920" "$d" "1920"

d=$(new_fixture tight_cap)
sed -i.bak 's|^      max_file_size: 20971520|      max_file_size: 307200|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
# Verified in Sveltia's source: the cap is measured after the transform, and a
# file over it is listed as oversized and cannot be uploaded at all. A cap at
# the site's 300 KB ceiling therefore strands the student rather than shrinking
# anything - the ceiling belongs to the optimizer, which can step down to it.
expect_fail "a cap tight enough to reject a normalized photo" "$d" "max_file_size"

# ── The prose pages stay undeletable, and the door stays open ─────────────
d=$(new_fixture folder_collection)
python3 - "$d/static/admin/config.yml" <<'MUTATE'
import sys, re
p = sys.argv[1]
s = open(p).read()
# The realistic regression: someone converts Pages to a folder collection to
# add a sixth page, and every prose page becomes deletable in the process.
s = s.replace("    files:\n", "    folder: content/pages\n    create: true\n    delete: true\n    files:\n", 1)
open(p, "w").write(s)
MUTATE
expect_fail "the prose pages made deletable" "$d" "delete"

d=$(new_fixture no_token_auth)
sed -i.bak 's|^  auth_methods: \[token\]|  auth_methods: [oauth]|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
expect_fail "token sign-in switched off" "$d" "token"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed."
  exit 1
fi
echo "all tests passed"
