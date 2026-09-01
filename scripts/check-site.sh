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

# ── 4. A copyright notice in the footer, and no four-digit year ───────────
# A build frozen in 2029 must not print a stale copyright line, which is why
# getFullYear() was removed. "2053" is the team number, not a year, so it is
# stripped before the year pattern is applied.
#
# Until slice 08 this rejected the notice outright, on the reasoning that the
# whole line was rot. The design says otherwise: the footer carries "Copyright
# © Southern Tier Robotics", hardcoded, with nothing in it that can go out of
# date. So the assertion is now two-sided - the notice must be there, and the
# year must not - which also means the line cannot quietly disappear.
#
# The presence test uses a here-string rather than `printf | grep -q`: under
# pipefail a NEGATED pipeline can be inverted by printf dying of SIGPIPE when
# grep matches and exits early. Slice 04 hit exactly that and the remedy was
# here-strings. The year test above is left in its verified form.
yearly=0
while IFS= read -r f; do
  footer=$(tr '\n' ' ' < "$f" | grep -oE '<footer[^>]*>.*</footer>' | head -1)
  [ -z "$footer" ] && continue
  if printf '%s' "${footer//2053/}" | grep -qE '(19|20)[0-9]{2}'; then
    fail "four-digit year in the footer of $f"
    yearly=$((yearly + 1))
  elif ! grep -qiE '&copy;|©|copyright' <<< "$footer"; then
    fail "no copyright notice in the footer of $f"
    yearly=$((yearly + 1))
  fi
done < <(find "$SITE" -type f -name '*.html' | sort)

[ "$yearly" -eq 0 ] && pass "every footer carries the copyright notice, and no year"

# ── 5. Every sponsor renders with a name and a tier caption ───────────────
# The sponsor grid is the one surface driven entirely by a data file, and every
# way it can go wrong is silent: a tier renamed by hand drops its whole group
# off the page, and a caption that stops rendering leaves fifteen unlabelled
# logos - which is precisely the failure the captions exist to prevent, since
# the logo set has no consistent background and several logos are unreadable on
# their own. So this compares data/sponsors.yaml against what was rendered,
# entry by entry, rather than counting boxes.
SPONSOR_DATA=data/sponsors.yaml
if [ ! -f "$SPONSOR_DATA" ]; then
  fail "no $SPONSOR_DATA, so the sponsor grid has no sponsors to render"
else
  # name<TAB>tier, in file order. Paired by awk rather than by two independent
  # seds, so an entry missing a tier is reported as that entry rather than
  # silently shifting every later name against the wrong tier. \042 and \047
  # are " and ', which cannot be written literally inside this awk program.
  sponsor_rows=$(awk '
    function unquote(s) {
      sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
      if (s ~ /^\042.*\042$/ || s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
      return s
    }
    /^[[:space:]]*-[[:space:]]+name:/ {
      if (name != "") print name "\t"
      sub(/^[[:space:]]*-[[:space:]]+name:/, ""); name = unquote($0); next
    }
    /^[[:space:]]*tier:/ {
      sub(/^[[:space:]]*tier:/, ""); print name "\t" unquote($0); name = ""; next
    }
    END { if (name != "") print name "\t" }
  ' "$SPONSOR_DATA")

  expected=$(grep -c . <<< "$sponsor_rows")
  if [ "$expected" -lt 1 ]; then
    # Nothing to iterate is not the same as nothing wrong - the lesson slice 03
    # learned when an empty site satisfied every assertion in this file.
    fail "$SPONSOR_DATA lists no sponsors, so nothing below could be checked"
  else
    # The page carrying the grid, whichever page that turns out to be. Attribute
    # quotes are normalized away first: `hugo --minify` writes `class=tierlab`
    # and an unminified build writes `class="tierlab"`, and this has to match
    # both. Newlines are folded so a caption is always on one "line".
    grid=$(grep -rlI --include='*.html' -e 'sponsorwrap' "$SITE" 2>/dev/null | head -1)
    if [ -z "$grid" ]; then
      fail "no page in $SITE renders the sponsor grid, but $SPONSOR_DATA lists $expected sponsor(s)"
    else
      rendered=$(tr '\n' ' ' < "$grid" | sed 's/class="\([^"]*\)"/class=\1/g')
      captions=$(grep -o 'class=tierlab' <<< "$rendered" | grep -c .)
      missing=0
      while IFS=$'\t' read -r name tier; do
        [ -z "$name" ] && continue
        # A shell glob, not a regex, so a sponsor name containing regex
        # metacharacters needs no escaping.
        case $rendered in
          *">$name<span class=tierlab>$tier sponsor<"*) ;;
          *)
            fail "sponsor \"$name\" does not render with a name and tier caption"
            [ -n "$tier" ] || detail "no tier in $SPONSOR_DATA for this entry"
            detail "expected in $grid"
            missing=$((missing + 1)) ;;
        esac
      done <<< "$sponsor_rows"

      if [ "$captions" -ne "$expected" ]; then
        fail "$grid renders $captions tier caption(s) for the $expected sponsor(s) in $SPONSOR_DATA"
      elif [ "$missing" -eq 0 ]; then
        pass "all $expected sponsor(s) render with a name and tier caption"
      fi
    fi
  fi
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed. The site still deployed; this is a content problem, not an outage."
  exit 1
fi
echo "all checks passed"
