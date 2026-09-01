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

# ── 5. The nav ────────────────────────────────────────────────────────────
# The nav is derived from the page set rather than edited: four structural
# entries in hugo.yaml's `menus.main`, and every page under content/pages/
# joining through the `cascade` block. Nobody types an order and nobody ticks a
# "show in nav" box, so the two silent failures the old site had are meant to be
# impossible - a page that exists and is unreachable (stranding), and a nav entry
# pointing at a page that is gone (dangling).
#
# "Meant to be" is what this section checks. Stranding is caught by requiring
# every expected page that is IN this build to be in the nav; dangling is caught
# here and again by section 3, which resolves every href on every page.

# label|target. The target is a directory under the site root, `.` for the home
# page, or `@` followed by a literal URL for an external entry.
#
# An entry whose page is not in this build is REPORTED, not failed: Blog,
# History and the prose pages arrive over several later slices, and a check that
# went red for a page nobody has written yet would be red for weeks and then
# ignored. The assertion binds itself the moment the page lands - there is no
# allowance here for anyone to remember to take out.
NAV_EXPECTED='Home|.
Blog|blog
About|about
Current Season|current-season
History|history
Merch Store|@https://shop.team2053.org/
Sponsors|sponsors
Contact|contact'

# Emits one `href|label` line per anchor in a page's nav, in document order.
#
# Attributes are read quoted, unquoted and bare, because `--minify` rewrites all
# three: `<a href="/contact/">` is emitted as `<a href=/contact/>`, and an EMPTY
# href as `<a href>`. That last shape is the one worth naming - read carelessly
# it parses as the href "href", which is a broken link reported as a working
# one. Newlines are flattened first: the minified nav still spans them, which is
# what defeated a single-line grep during slice 03.
nav_items() {
  tr '\n' ' ' < "$1" \
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
          printf "%s|%s\n", h, l
        }
      }'
}

# The page's own heading, which for every page but Home is its title - and, via
# the `/:slug/` permalink, its URL as well.
page_h1() {
  tr '\n' ' ' < "$1" | grep -oE '<h1[^>]*>[^<]*</h1>' | head -1 | sed -E 's|<h1[^>]*>||; s|</h1>||'
}

# Sveltia's own page is copied into the site verbatim out of static/admin/. It
# is a third-party application, not a page of this website, and carries no site
# chrome by design - the one HTML file here not expected to have a nav.
nav_pages=0
nav_ref=""
nav_ref_file=""
old_name=0
while IFS= read -r f; do
  case "$f" in "$SITE"/admin/*) continue ;; esac

  # The nav says "Sponsors" and the page it points at says "Support Us" on the
  # site this replaces. "Sponsors" wins in both places, because that is the word
  # people look for. This is checked over every page rather than over
  # /sponsors/, because the title is also the slug: reverting the name moves the
  # page to /support-us/ and takes the nav label with it, so the nav stays
  # perfectly consistent and perfectly unfindable.
  if [ "$(page_h1 "$f")" = "Support Us" ]; then
    fail "$f is headed \"Support Us\""
    detail "\"Sponsors\" is the word in the nav and it has to be the word on the page"
    old_name=$((old_name + 1))
  fi

  items=$(nav_items "$f")
  if [ -z "$items" ]; then
    fail "no nav links in $f"
    continue
  fi
  nav_pages=$((nav_pages + 1))
  if [ -z "$nav_ref_file" ]; then
    nav_ref="$items"
    nav_ref_file="$f"
  elif [ "$items" != "$nav_ref" ]; then
    fail "the nav is not the same on every page"
    detail "$nav_ref_file and $f render different nav items"
  fi
done < <(find "$SITE" -type f -name '*.html' | sort)

# Counted FIRST, for the reason slice 03 found the hard way: every assertion
# below iterates something, and nothing to iterate is not the same as nothing
# wrong. A site whose pages have no nav must not report a clean nav.
if [ "$nav_pages" -lt 1 ]; then
  fail "no page in $SITE has a nav to check"
else
  pass "the same nav renders on all $nav_pages page(s)"

  nav_labels=$(printf '%s\n' "$nav_ref" | sed 's/^[^|]*|//')

  # Reads the href of the nav item labelled $1.
  nav_href() { printf '%s\n' "$nav_ref" | awk -F'|' -v l="$1" '$2 == l { print $1; exit }'; }

  # An empty href is a link back to the page you are already on. It is what a
  # config entry naming a page that does not exist produces, and header.html
  # drops such an entry rather than render it - so reaching here means that
  # guard has gone.
  if printf '%s\n' "$nav_ref" | grep -q '^|'; then
    fail "a nav item has an empty href, so it links to the page it is on"
  else
    pass "every nav item has a real href"
  fi

  deferred=""
  wrong=0
  last_expected=0
  while IFS='|' read -r label target; do
    [ -z "$label" ] && continue
    idx=$(printf '%s\n' "$nav_labels" | grep -nxF "$label" | head -1 | cut -d: -f1)

    if [ "${target#@}" != "$target" ]; then
      # External, so it depends on nothing being built and is always required.
      want="${target#@}"
      if [ -z "$idx" ]; then
        fail "the nav has no \"$label\" entry"
        wrong=$((wrong + 1))
      elif [ "$(nav_href "$label")" != "$want" ]; then
        fail "\"$label\" links to $(nav_href "$label"), not $want"
        wrong=$((wrong + 1))
      fi
    else
      case "$target" in
        .) page="$SITE/index.html";          want="$BASE_PATH" ;;
        *) page="$SITE/$target/index.html";  want="$BASE_PATH$target/" ;;
      esac
      if [ ! -f "$page" ]; then
        deferred="$deferred $label"
        if [ -n "$idx" ]; then
          fail "the nav links to \"$label\", but $page is not in this build"
          wrong=$((wrong + 1))
        fi
      elif [ -z "$idx" ]; then
        # Stranding: the page is published and nothing links to it. The sharpest
        # usability failure on the site this replaces.
        fail "$page is in this build but \"$label\" is not in the nav"
        wrong=$((wrong + 1))
      elif [ "$(nav_href "$label")" != "$want" ]; then
        fail "\"$label\" links to $(nav_href "$label"), not to $want where the page is"
        wrong=$((wrong + 1))
      fi
    fi

    if [ -n "$idx" ]; then
      if [ "$idx" -le "$last_expected" ]; then
        fail "the nav renders \"$label\" out of order"
        detail "expected: Home, Blog, About, Current Season, History, Merch Store, Sponsors, Contact"
        wrong=$((wrong + 1))
      fi
      last_expected=$idx
    fi
  done <<< "$NAV_EXPECTED"

  [ "$wrong" -eq 0 ] && pass "every expected nav item this build contains is present, linked and in order"
  [ -n "$deferred" ] && detail "not in this build, so not checked:$deferred"

  # Anything else in the nav is a prose page somebody added, which is this
  # design working rather than failing. Such a page carries no weight, so it
  # must have sorted to the END - one turning up among the expected eight means
  # the weights have drifted.
  stray=0
  n=0
  while IFS= read -r label; do
    n=$((n + 1))
    [ "$n" -le "$last_expected" ] || continue
    printf '%s\n' "$NAV_EXPECTED" | cut -d'|' -f1 | grep -qxF "$label" && continue
    stray=$((stray + 1))
  done <<< "$nav_labels"
  total=$(printf '%s\n' "$nav_labels" | grep -c .)
  if [ "$stray" -gt 0 ]; then
    fail "$stray added page(s) sorted into the middle of the nav instead of onto the end"
  elif [ "$total" -gt "$last_expected" ]; then
    pass "the $((total - last_expected)) added page(s) appended to the end of the nav"
  fi
fi

if [ -f "$SITE/sponsors/index.html" ]; then
  h1=$(page_h1 "$SITE/sponsors/index.html")
  if [ "$h1" = "Sponsors" ]; then
    pass "the sponsors page is headed \"Sponsors\", the same word the nav uses"
  else
    fail "the sponsors page is headed \"$h1\", not \"Sponsors\""
    detail "the nav label is the page title, so these two cannot be left to disagree"
  fi
elif [ "$old_name" -eq 0 ]; then
  pass "no page is headed \"Support Us\" - the nav's word for it is \"Sponsors\""
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed. The site still deployed; this is a content problem, not an outage."
  exit 1
fi
echo "all checks passed"
