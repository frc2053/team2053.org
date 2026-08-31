#!/usr/bin/env bash
#
# Assertions over the committed Sveltia CMS at static/admin/.
#
# Usage:  scripts/check-cms-config.sh
# Run from the repository root.

# Deliberately no `set -e`: every check has to run so one failure does not hide
# the rest. Failures are counted, and the exit status comes from the count.
set -uo pipefail

CONFIG=static/admin/config.yml
ADMIN_PAGE=static/admin/index.html

for f in "$CONFIG" "$ADMIN_PAGE"; do
  [ -f "$f" ] || {
    echo "check-cms-config.sh must be run from the repository root (no $f here)" >&2
    exit 2
  }
done

failures=0
pass()   { printf 'ok    %s\n' "$1"; }
fail()   { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
detail() { printf '        %s\n' "$1"; }

# The config with every `# comment` removed. Every assertion below reads this
# rather than the file, so a line that only *mentions* a setting - and this
# config explains at length why two of them are absent - is never mistaken for
# a line that sets it.
BARE=$(mktemp)
trap 'rm -f "$BARE"' EXIT
sed 's/[[:space:]]*#.*$//' "$CONFIG" > "$BARE"

# ── 1. Every configured file is in the repository ─────────────────────────
# A `file:` naming a page that does not exist is not an error in Sveltia: the
# entry opens as an empty form and publishes happily, creating a page nobody
# wrote. The five prose pages arrive over several slices, so this list and the
# content tree drift apart in the ordinary course of the work.
missing=0
while IFS= read -r target; do
  [ -z "$target" ] && continue
  if [ ! -f "$target" ]; then
    fail "config names a file that is not in the repository: $target"
    missing=$((missing + 1))
  fi
done < <(sed -n 's/^[[:space:]]*file:[[:space:]]*//p' "$BARE" | tr -d "\"' ")

[ "$missing" -eq 0 ] && pass "every file named in $CONFIG is in the repository"

# Reads a top-level scalar out of the comment-stripped config, dropping quotes.
# Enough for the handful of settings below; not a YAML parser. The same trick
# check-site.sh uses on hugo.yaml.
read_key() { sed -n "s/^$1:[[:space:]]*//p" "$BARE" | head -1 | tr -d "\"' "; }

# ── 2. Uploads land where the optimizer looks ─────────────────────────────
# These two constants are the seam between the CMS and the image pipeline, and
# they are written down in two files. When they disagree nothing breaks and
# nothing is reported: uploads simply never get shrunk, on every page, forever.
OPTIMIZER=scripts/optimize-images.sh
media_folder=$(read_key media_folder)
if [ ! -f "$OPTIMIZER" ]; then
  fail "no $OPTIMIZER to compare the media folder against"
elif [ -z "$media_folder" ]; then
  fail "$CONFIG sets no media_folder"
else
  media_root=$(sed -n 's/^MEDIA_ROOT=//p' "$OPTIMIZER" | head -1 | tr -d "\"' ")
  if [ "$media_folder" != "$media_root" ]; then
    fail "the CMS uploads to $media_folder, which $OPTIMIZER does not scan"
    detail "$OPTIMIZER optimizes $media_root"
  elif [ ! -d "$media_folder" ]; then
    fail "media_folder $media_folder is not a directory in this repository"
  else
    pass "uploads land in $media_folder, which $OPTIMIZER scans"
  fi
fi

# ── 3. The bundle is the committed one ────────────────────────────────────
# The realistic regression is an upgrade done the easy way - point the script
# tag back at the CDN and the version pin is gone, along with the property that
# makes this site indifferent to what the project publishes next.
remote=$(grep -oE '<script[^>]+src="[^"]*"' "$ADMIN_PAGE" \
  | sed -E 's/.*src="([^"]*)".*/\1/' \
  | grep -E '^(https?:)?//' )
if [ -n "$remote" ]; then
  fail "$ADMIN_PAGE loads a script from somewhere other than this repository"
  while IFS= read -r u; do detail "$u"; done <<< "$remote"
else
  pass "no script in $ADMIN_PAGE is loaded from a CDN"
fi

# And the local one it does load is actually there. A script tag pointing at a
# file nobody committed is an admin page that loads to a blank screen.
local_missing=0
while IFS= read -r src; do
  [ -z "$src" ] && continue
  case "$src" in "/"*) target="${src#/}" ;; *) target="$(dirname "$ADMIN_PAGE")/$src" ;; esac
  if [ ! -f "$target" ]; then
    fail "$ADMIN_PAGE loads $src, which is not in this repository"
    local_missing=$((local_missing + 1))
  fi
done < <(grep -oE '<script[^>]+src="[^"]*"' "$ADMIN_PAGE" \
  | sed -E 's/.*src="([^"]*)".*/\1/' | grep -vE '^(https?:)?//')

[ "$local_missing" -eq 0 ] && pass "every script $ADMIN_PAGE loads is committed here"

# ── 4. A publish reaches the site ─────────────────────────────────────────
# Both of these fail the same way from the student's chair: Publish succeeds,
# and the site never changes.
publish_mode=$(read_key publish_mode)
if [ "$publish_mode" = simple ]; then
  pass "publish_mode is simple - no review gate"
else
  fail "publish_mode is \"$publish_mode\", not simple"
  detail "a review gate with no reviewer turns published-immediately into never-published"
fi

# `skip_ci` and its deprecated spelling put a toggle on the Publish button
# whichever value they carry - the value only decides which way it starts.
# Absent, the toggle does not render and every publish builds the site.
ci_toggle=$(grep -nE '^[[:space:]]*(skip_ci|automatic_deployments)[[:space:]]*:' "$BARE")
if [ -n "$ci_toggle" ]; then
  fail "$CONFIG sets skip_ci or automatic_deployments"
  detail "either one adds a skip-CI toggle to Publish; a student who flips it publishes an edit the site never builds"
  while IFS= read -r l; do detail "line $l"; done <<< "$ci_toggle"
else
  pass "no skip_ci setting, so no skip-CI toggle on the Publish button"
fi

# Reads a nested scalar by name from anywhere in the comment-stripped config.
# The media settings live four levels deep and there is exactly one of each,
# so matching on the key alone is unambiguous here and stays readable.
read_nested() { sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" "$BARE" | head -1 | tr -d "\"' "; }

# ── 5. The upload is normalized on the way in ─────────────────────────────
# Sveltia rewrites the photo in the browser, before it enters git. This is the
# boundary that keeps a 12 MB camera original out of the history for good -
# the optimizer downstream can only shrink what has already been committed.
if [ "$(read_nested slugify_filename)" = true ]; then
  pass "uploads are slugified"
else
  fail "slugify_filename is not true"
  detail "$OPTIMIZER rewrites references with sed and check-site.sh resolves them as URLs;"
  detail "both assume filenames match [A-Za-z0-9._/-], which only this setting guarantees"
fi

t_format=$(read_nested format)
t_width=$(read_nested width)
t_quality=$(read_nested quality)
if [ "$t_format" = webp ] && [ "$t_width" = 1920 ] && [ "$t_quality" = 85 ]; then
  pass "uploads are transformed to ${t_width}px ${t_format} at quality ${t_quality}"
else
  fail "the upload transform is not webp/1920/85"
  detail "found format=$t_format width=$t_width quality=$t_quality"
fi

# The cap is measured against the file AFTER the transform - verified in
# Sveltia's source, services/assets/process.js - and a file over it is listed
# as oversized and cannot be uploaded at all. Set anywhere near the site's
# 300 KB ceiling it therefore strands the student instead of shrinking
# anything. Held generously; the ceiling is the optimizer's job.
cap=$(read_nested max_file_size)
if [ -n "$cap" ] && [ "$cap" -ge 10485760 ] 2>/dev/null; then
  pass "max_file_size is $cap bytes - generous enough that a phone photo is never refused"
else
  fail "max_file_size is \"$cap\", under the 10 MiB floor this design needs"
  detail "the cap applies to the transformed file, and a file over it cannot be uploaded at all;"
  detail "the 300 KB ceiling belongs to $OPTIMIZER, which can step quality down to reach it"
fi

# ── 6. The prose pages stay undeletable ───────────────────────────────────
# Pages is a FILE collection, and a file collection has no create button and no
# delete button - the options do not exist in its shape. The realistic
# regression is somebody converting it to a folder collection to add a sixth
# page, which makes all of them deletable on the way past. Sveltia has no undo:
# recovery from a deleted page is retyping it out of the commit list.
structure=$(grep -nE '^[[:space:]]*(folder|create|delete|duplicate)[[:space:]]*:' "$BARE")
if [ -n "$structure" ]; then
  fail "$CONFIG has folder-collection options in it"
  detail "the prose pages are undeletable only for as long as Pages is a file collection"
  while IFS= read -r l; do detail "line $l"; done <<< "$structure"
else
  pass "no folder, create or delete option - the prose pages cannot be deleted"
fi

# ── 7. The token sign-in is still there ───────────────────────────────────
# It is the only sign-in this site has: there is no OAuth client behind the
# other one. Losing it locks every student out of the CMS at once.
auth=$(sed -n 's/^[[:space:]]*auth_methods:[[:space:]]*//p' "$BARE" | head -1)
case "$auth" in
  *token*) pass "sign-in with a token is enabled" ;;
  "")      fail "auth_methods is unset, so the login screen offers OAuth as well"
           detail "there is no OAuth client behind that button; it can only ever fail" ;;
  *)       fail "auth_methods is $auth, which does not include token"
           detail "the token is the only sign-in this site has - students hold no login" ;;
esac

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed. The site still deployed; this is a configuration problem, not an outage."
  exit 1
fi
echo "all checks passed"
