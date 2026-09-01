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
  # A placeholder, not the real 2 MB bundle: every assertion here is about the
  # script tag pointing at a file that exists, never about its contents, and
  # fourteen real copies is 28 MB of pointless I/O per CI run. The one fixture
  # that wants it absent gets it absent.
  [ "$1" = missing_bundle ] || : > "$dir/static/admin/sveltia-cms.js"
  cp "$ROOT/scripts/optimize-images.sh" "$dir/scripts/optimize-images.sh"
  # Content only has to exist; the checker asserts presence, never contents.
  cp "$ROOT/content/_index.md" "$dir/content/_index.md"
  cp "$ROOT/content/pages/contact.md" "$dir/content/pages/contact.md"
  printf '%s' "$dir"
}

# Runs the checker in $1 and reports its exit status.
# Truncated before the run, not by it: if `cd` failed, the redirect would never
# happen and the next expect_fail would grep the PREVIOUS test's output - a
# test passing on evidence from a different test.
check_in() { : > "$WORK/out"; ( cd "$1" && "$CHECKER" >"$WORK/out" 2>&1 ); }

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

# Both of these passed silently until the review caught them, and both are the
# same shape as the empty-tree hole slice 03 found in check-site.sh: an
# assertion that iterates a set is satisfied by the set being empty.
d=$(new_fixture no_script_at_all)
printf '<!doctype html>\n<html><head><title>x</title></head><body></body></html>\n' \
  > "$d/static/admin/index.html"
expect_fail "an admin page that loads no script at all" "$d" "no script at all"

d=$(new_fixture single_quoted_cdn)
printf '<!doctype html>\n<html><body><script src=%s></script></body></html>\n' \
  "'https://unpkg.com/@sveltia/cms/dist/sveltia-cms.js'" > "$d/static/admin/index.html"
expect_fail "a CDN script tag written with single quotes" "$d" "unpkg.com"

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
# Matched on the found value, not on "1920": the checker's failure line reads
# "the upload transform is not webp/1920/85", so matching "1920" would be
# satisfied by the message itself whatever the mutation did.
expect_fail "the upload transform widened past 1920" "$d" "width=4096"

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
# The realistic regression: someone converts Pages to a folder collection to
# add a sixth page, and every prose page becomes deletable in the process.
awk '!done && /^    files:$/ {
       print "    folder: content/pages"; print "    create: true"
       print "    delete: true"; done = 1
     } { print }' "$d/static/admin/config.yml" > "$WORK/mutated"
cat "$WORK/mutated" > "$d/static/admin/config.yml"
expect_fail "the prose pages made deletable" "$d" "delete"

# ...but a folder collection that is NOT Pages is exactly what slices 06 and 07
# add. Post and History are meant to be creatable and deletable; only the prose
# pages are not. A checker that forbids `create` config-wide would block the
# next two slices, so this asserts the guard is scoped to Pages rather than to
# the word.
d=$(new_fixture sibling_folder_collection)
cat >> "$d/static/admin/config.yml" <<'YAML'
  - name: posts
    label: Blog
    folder: content/blog
    create: true
    delete: true
    fields:
      - name: title
        widget: string
YAML
mkdir -p "$d/content/blog"
expect_pass "a sibling folder collection, as slices 06 and 07 add" "$d"

d=$(new_fixture no_token_auth)
sed -i.bak 's|^  auth_methods: \[token\]|  auth_methods: [oauth]|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
expect_fail "token sign-in switched off" "$d" "token"

# ── Tags and authors stay gone ────────────────────────────────────────────
# The realistic regression is somebody adding either field back to be helpful.
# Neither would produce a page - hugo.yaml disables the taxonomy and term kinds
# - so all a student filling one in would get is the belief that it does
# something. The control above is what proves the checker reads past the long
# comment in the config that names both fields while declining them.
#
# All four shapes are exercised, because a guard that only catches the way the
# field is usually typed reads exactly like a guard that catches the field.
d=$(new_fixture tags_field)
cat >> "$d/static/admin/config.yml" <<'YAML'
      - name: tags
        label: Tags
        widget: list
YAML
expect_fail "a tags field added back to a collection" "$d" "tags or authors"

d=$(new_fixture authors_field)
cat >> "$d/static/admin/config.yml" <<'YAML'
      - name: authors
        label: Authors
        widget: list
YAML
expect_fail "an authors field added back to a collection" "$d" "tags or authors"

d=$(new_fixture quoted_tags_field)
cat >> "$d/static/admin/config.yml" <<'YAML'
      - name: "tags"
        widget: list
YAML
expect_fail "a tags field written with quotes" "$d" "tags or authors"

d=$(new_fixture flow_tags_field)
cat >> "$d/static/admin/config.yml" <<'YAML'
      - {name: tags, label: Tags, widget: list}
YAML
expect_fail "a tags field written in flow style" "$d" "tags or authors"
# ── Next season is still addable, at the right address ────────────────────
# History is the one open, recurring type. Both of these break silently: one
# removes the only way to add a season, the other moves every future season to
# an address the other twelve years do not share.
d=$(new_fixture history_uncreatable)
sed -i.bak 's|^    create: true|    create: false|' "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
expect_fail "no way left to add next season" "$d" "create: true"

d=$(new_fixture history_slug_dropped)
sed -i.bak "s|^    slug: '{{fields.robotYear}}'||" "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
expect_fail "the year-based address dropped" "$d" "robotYear"

d=$(new_fixture history_slug_retitled)
sed -i.bak "s|^    slug: '{{fields.robotYear}}'|    slug: '{{title}}'|" "$d/static/admin/config.yml"
rm -f "$d/static/admin/config.yml.bak"
expect_fail "a season addressed by its title instead of its year" "$d" "robotYear"

d=$(new_fixture history_collection_gone)
awk '/^  - name: history$/ { skip = 1 } skip && /^  - name: / && !/^  - name: history$/ { skip = 0 }
     !skip { print }' "$d/static/admin/config.yml" > "$WORK/mutated"
cat "$WORK/mutated" > "$d/static/admin/config.yml"
expect_fail "the history collection removed entirely" "$d" "no collection called"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed."
  exit 1
fi
echo "all tests passed"
