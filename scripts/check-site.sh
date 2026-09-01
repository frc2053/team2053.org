#!/usr/bin/env bash
#
# Assertions over the site Hugo generated. Shell only, no Node, no npm.
#
# This NEVER gates the deploy. It runs as its own job in
# .github/workflows/publish.yml so that a failure here emails the team and
# shows red in the Actions tab while the site still publishes. A blocking
# check would turn one bad image on one page into a site-wide publishing
# freeze that nobody left here could diagnose.
#
# Usage:  scripts/check-site.sh [site-directory]
# Run from the repository root; the defaults come out of hugo.yaml.

# Deliberately no `set -e`: every check has to run so one failure does not hide
# the rest. Failures are counted, and the exit status comes from the count.
set -uo pipefail

CONFIG=hugo.yaml
if [ ! -f "$CONFIG" ]; then
  echo "check-site.sh must be run from the repository root (no $CONFIG here)" >&2
  exit 2
fi

# Reads a top-level scalar out of hugo.yaml, dropping quotes and any trailing
# `# comment`. Enough for baseURL and publishDir; not a YAML parser.
read_key() {
  sed -n "s/^$1:[[:space:]]*//p" "$CONFIG" | head -1 | sed 's/[[:space:]]*#.*$//' | tr -d "\"' "
}

SITE="${1:-$(read_key publishDir)}"
SITE="${SITE:-public}"
SITE="${SITE%/}"

# The site is staged under a subdirectory (frc2053.github.io/team2053.org/) and
# moves to the domain root at cutover. Links are checked against whichever the
# config says, so a reference that only works at one of them is caught here.
BASE_PATH=$(read_key baseURL | sed -E 's|^[a-z]+://[^/]*||')
[ -z "$BASE_PATH" ] && BASE_PATH="/"
case "$BASE_PATH" in */) ;; *) BASE_PATH="$BASE_PATH/" ;; esac

if [ ! -d "$SITE" ]; then
  echo "no site to check: $SITE does not exist (run hugo first)" >&2
  exit 2
fi

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
detail() { printf '        %s\n' "$1"; }

# Fails if $2 (a grep pattern) appears anywhere in the site.
assert_absent() {
  local label="$1" pattern="$2" hits
  shift 2
  hits=$(grep -rlI "$@" -e "$pattern" "$SITE" 2>/dev/null)
  if [ -n "$hits" ]; then
    fail "$label"
    while IFS= read -r f; do detail "$f"; done <<< "$hits"
  else
    pass "no $label"
  fi
}

# ── 0. The site is not empty ──────────────────────────────────────────────
# Hugo exits 0 and writes no HTML at all if a layout is missing, and every
# other check below reports ok over an empty tree. Without this the whole
# script blesses a blank deploy, which is the Tier 0 failure it exists to
# prevent.
pages=$(find "$SITE" -type f -name '*.html' | wc -l | tr -d ' ')
if [ "$pages" -lt 1 ]; then
  fail "the build produced no HTML pages at all"
  echo
  echo "1 check failed. Nothing else was checked: there is no site to check."
  exit 1
fi
pass "the build produced $pages HTML page(s)"

# ── 1. Nothing is served from CloudFront ──────────────────────────────────
# The highest-value assertion here: it is the difference between the image
# repatriation being complete and being 95% complete.
assert_absent "cloudfront.net reference anywhere in $SITE" 'cloudfront\.net'

# ── 2. No unrendered template syntax ──────────────────────────────────────
# Catches MDX and shortcode leftovers that survived migration without
# breaking the build.
assert_absent "literal {{ in rendered HTML" '{{' -F --include='*.html'

# ── 3. Every local reference resolves to something on disk ────────────────
# Catches a mistyped image path, a deleted-but-still-referenced image, and a
# nav entry pointing at a page that no longer exists.
broken=0
while IFS= read -r f; do
  dir=$(dirname "$f")
  case "$f" in
    *.html) raw=$(grep -oE '(src|href)=("[^"]*"|[^[:space:]>]+)' "$f" | sed -E 's/^(src|href)=//; s/^"//; s/"$//') ;;
    *.css)  raw=$(grep -oE 'url\([^)]*\)' "$f" | sed -E 's/^url\(//; s/\)$//; s/^["'"'"']//; s/["'"'"']$//') ;;
    *)      continue ;;
  esac

  while IFS= read -r ref; do
    ref=${ref%%#*}
    ref=${ref%%\?*}
    # Repatriation guarantees every filename matches [A-Za-z0-9._/-], so a
    # space is the only percent-encoding this has to undo.
    ref=${ref//%20/ }
    [ -z "$ref" ] && continue
    # Skip anything with a scheme (http:, mailto:, tel:, data:) and //host refs.
    case "$ref" in
      //*) continue ;;
      *:*) case "$ref" in */*:*) ;; *) continue ;; esac ;;
    esac

    if [ "${ref#/}" != "$ref" ]; then
      # Quoted so a base path is matched literally, never as a glob.
      if [ "${ref#"$BASE_PATH"}" = "$ref" ] && [ "$BASE_PATH" != "/" ]; then
        fail "reference outside the site base path $BASE_PATH: $ref"
        detail "in $f"
        broken=$((broken + 1))
        continue
      fi
      target="$SITE/${ref#"$BASE_PATH"}"
    else
      target="$dir/$ref"
    fi

    if [ ! -e "$target" ] && [ ! -e "$target/index.html" ]; then
      fail "dangling reference: $ref"
      detail "in $f"
      broken=$((broken + 1))
    fi
  done <<< "$raw"
done < <(find "$SITE" -type f \( -name '*.html' -o -name '*.css' \) | sort)

[ "$broken" -eq 0 ] && pass "every local src/href/url() resolves to a file in $SITE"

# ── 4. No four-digit year in the footer ───────────────────────────────────
# A build frozen in 2029 must not print a stale copyright line, which is why
# getFullYear() was removed. "2053" is the team number, not a year, so it is
# stripped before the year pattern is applied.
yearly=0
while IFS= read -r f; do
  footer=$(tr '\n' ' ' < "$f" | grep -oE '<footer[^>]*>.*</footer>' | head -1)
  [ -z "$footer" ] && continue
  if printf '%s' "${footer//2053/}" | grep -qE '(19|20)[0-9]{2}'; then
    fail "four-digit year in the footer of $f"
    yearly=$((yearly + 1))
  elif printf '%s' "$footer" | grep -qiE '&copy;|©|copyright'; then
    fail "copyright notice in the footer of $f"
    yearly=$((yearly + 1))
  fi
done < <(find "$SITE" -type f -name '*.html' | sort)

[ "$yearly" -eq 0 ] && pass "no year and no copyright notice in any footer"

# ── 5. Every video embed carries a bare 11-character YouTube ID ───────────
# A history year stores the video ID and layouts/history/page.html builds the
# address, so the one way this goes wrong is a value that is not an ID: a link
# pasted into the field, or an ID that lost a character on its way through a
# migration. Either produces an iframe that renders a YouTube error inside an
# otherwise perfectly fine page - invisible to the build, and to anyone who
# does not scroll down and press play.
#
# The query string is stripped first, the same way check 3 strips one. Hugo's
# OWN {{< youtube >}} shortcode - which slice 10 uses for the one embed that
# lives inside a post body - emits
# `/embed/wv1_1sGGmfQ?autoplay=0&controls=1&...`, and a check that rejected
# that would turn the workflow red over correct output.
#
# `#*/embed/` and not `##*/embed/`: the shortest match, so a whole address
# pasted into the field - which builds `/embed/https://youtu.be/xxx` - is read
# as one bad value rather than having its own trailing ID picked out and
# blessed.
embeds=0
bad_embeds=0
while IFS= read -r src; do
  [ -z "$src" ] && continue
  embeds=$((embeds + 1))
  id=${src#*/embed/}
  id=${id%%\?*}
  id=${id%%#*}
  if ! printf '%s' "$id" | grep -qE '^[A-Za-z0-9_-]{11}$'; then
    fail "video embed is not a bare 11-character YouTube ID: $id"
    bad_embeds=$((bad_embeds + 1))
  fi
done < <(grep -rhoE "youtube(-nocookie)?\.com/embed/[^\"'<> ]*" "$SITE" --include='*.html' | sort -u)

# Counted distinct, because two years could legitimately share one video and
# the loop above only needs to judge each value once.
[ "$bad_embeds" -eq 0 ] && pass "all $embeds distinct video embed(s) carry a bare 11-character YouTube ID"

# ...and every history year actually has one. Without this, the assertion
# above is satisfied by there being no embeds at all - the same vacuous shape
# slices 03 and 05 were each caught by. Renaming the field, or dropping the
# `with` block from layouts/history/page.html, silently takes the video off
# every year at once while the pages still render and the build still passes.
#
# The CMS marks the video required, so a year without one is drift rather than
# a choice, and this reports it the way check-cms-config.sh reports a config
# that has drifted from the content tree: a red run and an email, never a gate.
yearless=0
years=0
while IFS= read -r f; do
  years=$((years + 1))
  if ! grep -qE "youtube(-nocookie)?\.com/embed/" "$f"; then
    fail "history year with no game video: $f"
    yearless=$((yearless + 1))
  fi
done < <(find "$SITE/history" -mindepth 2 -name 'index.html' 2>/dev/null | sort)

if [ "$years" -lt 1 ]; then
  pass "no history year pages in $SITE yet"
elif [ "$yearless" -eq 0 ]; then
  pass "all $years history year page(s) render a game video"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed. The site still deployed; this is a content problem, not an outage."
  exit 1
fi
echo "all checks passed"
