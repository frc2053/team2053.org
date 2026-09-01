#!/usr/bin/env bash
#
# Fixture tests for the derived nav: the `menus.main` and `cascade` blocks in
# hugo.yaml, the `range site.Menus.main` in layouts/partials/header.html, and
# section 5 of scripts/check-site.sh.
#
# The nav is derived from the set of pages rather than edited - there is no
# order field and no "show in nav" box anywhere - so the claims worth testing
# are the ones nobody can test by looking at today's site, because today's site
# does not have all eight pages yet: Blog and History arrive with slices 06 and
# 07, and About, Current Season and Sponsors with slice 11. Every fixture here
# builds a throwaway site out of the REAL hugo.yaml and the REAL layouts with
# those pages present, so the eight-item order, the appending of a ninth and a
# tenth page, and the removal of a deleted one are all proven now.
#
# The mutations after them exist for the reason slice 03 found the hard way: a
# checker that quietly passes everything looks exactly like a checker that
# works. Each one breaks a thing section 5 asserts and requires it to notice.
#
# Everything runs against a throwaway tree under $TMPDIR. It never touches the
# real site.
#
# Shell only, no Node, no npm - the same rule the rest of this repository
# follows. It does need Hugo, which the check job has already installed.
#
# Usage:  scripts/test-nav.sh
# Exit 0 if every assertion passed.

# Deliberately no `set -e`: every test has to run so one failure does not hide
# the rest. Failures are counted, and the exit status comes from the count.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECKER="$ROOT/scripts/check-site.sh"
HUGO=${HUGO:-hugo}

[ -x "$CHECKER" ] || { echo "no executable checker at $CHECKER" >&2; exit 2; }
command -v "$HUGO" >/dev/null || { echo "no hugo on PATH (set HUGO=/path/to/hugo)" >&2; exit 2; }

failures=0
pass()   { printf 'ok    %s\n' "$1"; }
fail()   { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
detail() { printf '        %s\n' "$1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Writes a content file. $1 fixture dir, $2 path under content/, $3 title.
page() {
  mkdir -p "$(dirname "$1/content/$2")"
  printf -- '---\ntitle: %s\n---\n\nFixture prose.\n' "$3" > "$1/content/$2"
}

# A throwaway site carrying the real configuration and the real templates, so a
# test can never pass against a fixture that has drifted from what ships. The
# content is synthesized rather than copied: these tests are about which pages
# are in the nav, and the real pages drag 28 MB of photographs behind them.
#
# static/ is copied down to the stylesheet, the fonts and the favicon - what
# check-site.sh has to resolve - and deliberately not static/admin, whose 2 MB
# bundle would be copied once per fixture for nothing.
new_site() {
  local dir="$WORK/$1"
  rm -rf "$dir"
  mkdir -p "$dir/static"
  cp "$ROOT/hugo.yaml" "$dir/hugo.yaml"
  cp -R "$ROOT/layouts" "$dir/layouts"
  cp -R "$ROOT/static/css" "$dir/static/css"
  cp -R "$ROOT/static/fonts" "$dir/static/fonts"
  cp "$ROOT/static/favicon.png" "$dir/static/favicon.png"
  # The one content file that is structural rather than prose: it is what keeps
  # /pages/ itself from being published as a section.
  mkdir -p "$dir/content/pages"
  cp "$ROOT/content/pages/_index.md" "$dir/content/pages/_index.md"
  page "$dir" _index.md "Southern Tier Robotics"
  printf '%s' "$dir"
}

# The eight pages the finished site has, across four slices.
all_eight() {
  local dir
  dir=$(new_site "$1")
  page "$dir" blog/_index.md Blog
  page "$dir" history/_index.md History
  page "$dir" pages/about.md About
  page "$dir" pages/current-season.md "Current Season"
  page "$dir" pages/sponsors.md Sponsors
  page "$dir" pages/contact.md Contact
  printf '%s' "$dir"
}

# Builds $1 and leaves the output in $1/_site. enableGitInfo is switched off by
# environment rather than by editing the copied config, so the config under test
# stays byte-identical to the one that ships: with it on, Hugo refuses to build
# anything outside a git repository.
build() {
  ( cd "$1" && HUGO_ENABLEGITINFO=false "$HUGO" --gc --minify ) > "$WORK/build" 2>&1
}

# One `label href` line per nav item of $1's home page, in document order. The
# same reading as check-site.sh: --minify emits attributes quoted, unquoted and
# bare, and all three have to come back as the href they mean.
nav_of() {
  tr '\n' ' ' < "$1/_site/index.html" \
    | grep -oE '<nav[^>]*>.*</nav>' \
    | awk '{
        n = split($0, a, /<a /)
        for (i = 2; i <= n; i++) {
          s = a[i]
          h = s
          if (sub(/^[^>]*href="/, "", h))     { sub(/".*$/, "", h) }
          else if (sub(/^[^>]*href=/, "", h)) { sub(/[> ].*$/, "", h) }
          else                                { h = "" }
          l = s; sub(/^[^>]*>/, "", l); sub(/<\/a>.*$/, "", l)
          printf "%s %s\n", l, h
        }
      }'
}

# Rewrites file $1 through the awk program $2. Used instead of `sed -i` for the
# mutations that insert lines: BSD and GNU sed disagree about `\n` in a
# replacement, and these tests run on a developer's Mac as well as in CI.
edit() {
  awk "$2" "$1" > "$1.edited" && mv "$1.edited" "$1"
}

# Runs check-site.sh in $1 and reports its exit status. Truncated before the
# run, not by it: if the build failed, the redirect would never happen and the
# next assertion would read the PREVIOUS test's output.
check_in() { : > "$WORK/out"; ( cd "$1" && "$CHECKER" >"$WORK/out" 2>&1 ); }

# $1 label, $2 fixture. Requires the build to succeed and the checker to pass.
expect_pass() {
  if ! build "$2"; then
    fail "$1 (hugo failed)"
    while IFS= read -r l; do detail "$l"; done < "$WORK/build"
    return
  fi
  if check_in "$2"; then pass "$1"; else
    fail "$1"
    while IFS= read -r l; do detail "$l"; done < "$WORK/out"
  fi
}

# $1 label, $2 fixture, $3 a string the failure has to mention - so a mutation
# cannot be "caught" by an unrelated assertion.
expect_fail() {
  if ! build "$2"; then
    fail "$1 (hugo failed, so the checker never ran)"
    while IFS= read -r l; do detail "$l"; done < "$WORK/build"
    return
  fi
  if check_in "$2"; then
    fail "$1 (the checker passed)"
    while IFS= read -r l; do detail "$l"; done < "$WORK/out"
  elif ! grep -qi -- "$3" "$WORK/out"; then
    fail "$1 (failed, but not about \"$3\")"
    while IFS= read -r l; do detail "$l"; done < "$WORK/out"
  else
    pass "$1"
  fi
}

# $1 label, $2 fixture, $3 the expected `label href` lines.
expect_nav() {
  local got
  got=$(nav_of "$2")
  if [ "$got" = "$3" ]; then pass "$1"; else
    fail "$1"
    detail "expected:"
    while IFS= read -r l; do detail "  $l"; done <<< "$3"
    detail "got:"
    while IFS= read -r l; do detail "  $l"; done <<< "$got"
  fi
}

# Read out of the real config rather than written down, because the site is
# staged under a subdirectory today and moves to the domain root at cutover -
# and these expectations have to be about the nav, not about which of the two
# hosts is current.
BASE=$(sed -n 's/^baseURL:[[:space:]]*//p' "$ROOT/hugo.yaml" | head -1 | tr -d "\"' " | sed -E 's|^[a-z]+://[^/]*||')
[ -z "$BASE" ] && BASE="/"
case "$BASE" in */) ;; *) BASE="$BASE/" ;; esac

EIGHT="Home $BASE
Blog ${BASE}blog/
About ${BASE}about/
Current Season ${BASE}current-season/
History ${BASE}history/
Merch Store https://shop.team2053.org/
Sponsors ${BASE}sponsors/
Contact ${BASE}contact/"

# ── The design, with every page present ───────────────────────────────────

# This is the acceptance criterion the finished site is judged on, and the one
# that cannot be seen on today's site because five of the eight pages have not
# been written yet. The interleaving is the whole point: 10/20/50/60 come from
# `menus.main` in hugo.yaml and 30/40/70/80 from the `cascade` block, and Hugo
# merges and sorts them into one menu with no template code doing anything
# about it.
EIGHT_DIR=$(all_eight eight)
expect_pass "the eight-page site builds and checks clean" "$EIGHT_DIR"
expect_nav  "the nav renders all eight items in order, Merch Store external" "$EIGHT_DIR" "$EIGHT"

# Creating a page links it. There is no field to fill in and no box to tick, so
# the stranding failure - a page that exists and nothing points at it - has
# nowhere to come from. An unweighted entry sorts to the end of the menu.
NINE=$(all_eight nine)
page "$NINE" pages/robotics-camp.md "Robotics Camp"
expect_pass "a ninth page with no weight builds and checks clean" "$NINE"
expect_nav  "a ninth page appends itself to the end of the nav, linked" "$NINE" \
  "$EIGHT
Robotics Camp ${BASE}robotics-camp/"

# Ten items is what the header was laid out to absorb: the row wraps rather
# than reordering, so it gets one line taller with no hamburger and no
# breakpoint. Unweighted entries tiebreak alphabetically, so Alumni precedes
# Robotics Camp.
TEN=$(all_eight ten)
page "$TEN" pages/robotics-camp.md "Robotics Camp"
page "$TEN" pages/alumni.md Alumni
expect_pass "a ten-item nav builds and checks clean" "$TEN"
expect_nav  "a tenth page appends too, alphabetically among the unweighted" "$TEN" \
  "$EIGHT
Alumni ${BASE}alumni/
Robotics Camp ${BASE}robotics-camp/"

# The wrap is a stylesheet property, not a template one, and it is what keeps
# ten items from overflowing the header.
if grep -A1 '^\.nav{' "$ROOT/static/css/site.css" | grep -q 'flex-wrap:wrap'; then
  pass "the nav row is set to wrap, so a tenth item makes the header taller rather than wider"
else
  fail "static/css/site.css does not set flex-wrap:wrap on .nav"
  detail "without it a ninth and tenth nav item overflow the header instead of wrapping"
fi

# Deleting a page unlinks it, and touches nothing else. The dangling failure -
# a nav entry pointing at a page that is gone, on every page of the site - has
# nowhere to come from either.
SEVEN=$(all_eight seven)
rm "$SEVEN/content/pages/about.md"
expect_pass "the site still builds and checks clean with a page deleted" "$SEVEN"
expect_nav  "deleting a page removes its nav entry and changes nothing else" "$SEVEN" \
  "$(printf '%s\n' "$EIGHT" | grep -v '^About ')"

# ── Mutations: every assertion in section 5, broken on purpose ─────────────

# Stranding, which is the sharpest usability failure on the site this replaces.
# Narrowing the catch-all cascade target is how it would realistically happen -
# somebody scoping the rule to the page they were thinking about.
STRANDED=$(all_eight stranded)
sed -i.bak 's|path: /pages/\*\*|path: /pages/contact|' "$STRANDED/hugo.yaml"
expect_fail "a page built but left out of the nav is caught" "$STRANDED" \
  "is in this build but"

# A config entry whose pageRef names nothing. header.html drops it rather than
# render <a href="">, so the nav is short one item while the page it should
# have pointed at is published and unreachable - which section 5 reports from
# the page's side.
TYPO=$(all_eight typo)
sed -i.bak 's|pageRef: /blog$|pageRef: /blogg|' "$TYPO/hugo.yaml"
expect_fail "a mistyped pageRef in hugo.yaml is caught" "$TYPO" \
  'blog/index.html is in this build but'

# The one entry that points off this site, and so the one nobody's build would
# ever notice was wrong.
SHOP=$(all_eight shop)
sed -i.bak 's|url: https://shop.team2053.org/|url: https://example.com/|' "$SHOP/hugo.yaml"
expect_fail "the Merch Store entry pointing somewhere else is caught" "$SHOP" \
  "not https://shop.team2053.org/"

# The interleaved order is the thing a weight edit can silently undo.
ORDER=$(all_eight order)
sed -i.bak 's|weight: 30|weight: 75|' "$ORDER/hugo.yaml"
expect_fail "the nav rendered out of order is caught" "$ORDER" \
  "out of order"

# An added page must land at the END. A weight given to it puts it among the
# eight, which is the design being edited rather than derived.
MIDDLE=$(all_eight middle)
page "$MIDDLE" pages/robotics-camp.md "Robotics Camp"
edit "$MIDDLE/hugo.yaml" '
  /^cascade:$/ {
    print
    print "  - target:"
    print "      path: /pages/robotics-camp"
    print "    weight: 35"
    next
  }
  { print }'
expect_fail "an added page sorted into the middle of the nav is caught" "$MIDDLE" \
  "instead of onto the end"

# No nav at all. This is the empty-set hole slice 03 found in check-site.sh and
# slice 05 found twice in check-cms-config.sh: nothing to iterate is not the
# same as nothing wrong.
NONAV=$(all_eight nonav)
printf '<header class="head"><a class="mark" href="/">x</a></header>\n' \
  > "$NONAV/layouts/partials/header.html"
expect_fail "a site whose pages have no nav is caught" "$NONAV" \
  "no nav links in"

# "on every page" is half of the criterion, and a template can satisfy the
# other half on the home page alone.
UNEVEN=$(all_eight uneven)
edit "$UNEVEN/layouts/partials/header.html" '
  /<\/nav>/ { print "{{ if $.IsHome }}<a href=\"/\">Extra</a>{{ end }}" }
  { print }'
expect_fail "a nav that differs between pages is caught" "$UNEVEN" \
  "not the same on every page"

# Why header.html guards on .URL at all. Hugo resolves a pageRef that names no
# page to an empty URL, without a warning and without failing the build; the
# markup that falls out is a link on every page of the site that goes to the
# page you are already on.
EMPTY=$(new_site empty)
page "$EMPTY" pages/contact.md Contact
edit "$EMPTY/layouts/partials/header.html" '
  /{{ if \.URL }}/            { dropping = 1; next }
  dropping && /^[ \t]*{{ end }}[ \t]*$/ { dropping = 0; next }
  { print }'
expect_fail "an unguarded nav entry resolving to an empty href is caught" "$EMPTY" \
  "empty href"

# One naming fix. The nav label of a cascaded page IS its title, and so is its
# URL - `/:slug/` - so reverting to the old name moves the page as well as the
# label, and the nav follows both without ever going dangling. What that hides
# is the whole point of the fix: nobody looking for sponsors searches for
# "Support Us".
SUPPORT=$(all_eight support)
page "$SUPPORT" pages/sponsors.md "Support Us"
expect_fail "the sponsors page retitled \"Support Us\" is caught" "$SUPPORT" \
  'Support Us'

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed."
  exit 1
fi
echo "all tests passed"
