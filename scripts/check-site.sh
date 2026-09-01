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

# Reads a scalar out of hugo.yaml by name, dropping quotes and any trailing
# `# comment`. Enough for the handful of settings below; not a YAML parser.
#
# Indentation is allowed rather than anchored to column zero, so one function
# serves both the top-level keys (baseURL, publishDir) and the ones nested
# under `params:` (contactEmail). That is only safe because each of those names
# appears exactly once in the file, and the first match is taken.
read_key() {
  sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" "$CONFIG" | head -1 | sed 's/[[:space:]]*#.*$//' | tr -d "\"' "
}

# The <main> element of page $1, flattened onto one line, or empty if it has
# none. Every section that asks about a page's BODY goes through this: the
# header and the footer are on every page of the site, so an unscoped grep
# cannot tell "the page says this" from "the chrome around it does".
main_of() {
  tr '\n' ' ' < "$1" | grep -oE '<main[^>]*>.*</main>' | head -1
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

# ── 6. No tag or category routes ──────────────────────────────────────────
# The content model has no tags and no authors; why is written out once, in
# the DELIBERATELY ABSENT block on the posts collection in
# static/admin/config.yml. The old site's tag routes had rotted into more tag
# pages than it had posts.
#
# hugo.yaml disables the taxonomy and term kinds, so this asserts the outcome
# rather than the setting - which makes it fair to ask whether it can fail at
# all. It was drilled both ways before it was committed: a `tags:` line put
# back into a post's front matter produces no directory and this still passes,
# and `disableKinds: []` produces _site/tags and _site/categories and this
# fails on both. It is the config regression it catches, not the content one.
taxo=$(find "$SITE" -type d \( -name tags -o -name categories -o -name authors \) | sort)
if [ -n "$taxo" ]; then
  fail "tag, category or author routes in $SITE"
  detail "the content model has none of these; hugo.yaml disables the taxonomy and term kinds"
  while IFS= read -r d; do detail "$d"; done <<< "$taxo"
else
  pass "no tag, category or author route anywhere in $SITE"
fi

# ── 7. Every video embed carries a bare 11-character YouTube ID ───────────
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

# ── 8. The nav ────────────────────────────────────────────────────────────
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

NAV_ORDER=$(printf '%s\n' "$NAV_EXPECTED" | cut -d'|' -f1 | paste -sd'|' - | tr '|' ',' | sed 's/,/, /g')

# The nav parser, shared with scripts/test-nav.sh so the tests cannot exercise a
# second copy of it. Resolved next to this script, not next to the caller's
# working directory: test-nav.sh runs this checker from inside a fixture.
NAV_LIB="$(dirname "$0")/nav-items.sh"
if [ ! -f "$NAV_LIB" ]; then
  echo "check-site.sh cannot find $NAV_LIB" >&2
  exit 2
fi
# shellcheck source=scripts/nav-items.sh
. "$NAV_LIB"

# Sveltia's own page is copied into the site verbatim out of static/admin/. It
# is a third-party application, not a page of this website, and carries no site
# chrome by design - the one HTML file here not expected to have a nav.
nav_pages=0
nav_differs=0
nav_ref=""
nav_ref_file=""
while IFS= read -r f; do
  case "$f" in "$SITE"/admin/*) continue ;; esac
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
    nav_differs=$((nav_differs + 1))
  fi
done < <(find "$SITE" -type f -name '*.html' | sort)

# Counted FIRST, for the reason slice 03 found the hard way: every assertion
# below iterates something, and nothing to iterate is not the same as nothing
# wrong. A site whose pages have no nav must not report a clean nav.
if [ "$nav_pages" -lt 1 ]; then
  fail "no page in $SITE has a nav to check"
else
  [ "$nav_differs" -eq 0 ] && pass "the same nav renders on all $nav_pages page(s)"

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
  checked=0
  last_expected=0
  while IFS='|' read -r label target; do
    [ -z "$label" ] && continue
    idx=$(printf '%s\n' "$nav_labels" | grep -nxF "$label" | head -1 | cut -d: -f1)

    if [ "${target#@}" != "$target" ]; then
      # External, so it depends on nothing being built and is always required.
      want="${target#@}"
      checked=$((checked + 1))
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
          checked=$((checked + 1))
          fail "the nav links to \"$label\", but $page is not in this build"
          wrong=$((wrong + 1))
        fi
      else
        checked=$((checked + 1))
        if [ -z "$idx" ]; then
          # Stranding: the page is published and nothing links to it. The
          # sharpest usability failure on the site this replaces.
          fail "$page is in this build but \"$label\" is not in the nav"
          wrong=$((wrong + 1))
        elif [ "$(nav_href "$label")" != "$want" ]; then
          fail "\"$label\" links to $(nav_href "$label"), not to $want where the page is"
          wrong=$((wrong + 1))
        fi
      fi
    fi

    if [ -n "$idx" ]; then
      if [ "$idx" -le "$last_expected" ]; then
        fail "the nav renders \"$label\" out of order"
        detail "expected: $NAV_ORDER"
        wrong=$((wrong + 1))
      fi
      last_expected=$idx
    fi
  done <<< "$NAV_EXPECTED"

  # Counted, not assumed. Every branch above is inside a loop over the expected
  # items, and a build containing none of them would satisfy all of them.
  if [ "$checked" -lt 1 ]; then
    fail "not one expected nav item was checked - nothing this nav should contain is in this build"
  elif [ "$wrong" -eq 0 ]; then
    pass "all $checked expected nav item(s) this build contains are present, linked and in order"
  fi
  [ -n "$deferred" ] && detail "not in this build, so not checked:$deferred"

  # Anything else in the nav is a prose page somebody added, which is this
  # design working rather than failing. Such a page carries no weight, so it
  # must have sorted to the END - one turning up among the expected eight means
  # the weights have drifted.
  #
  # Only meaningful once something expected has been located: with
  # last_expected still 0 every item is "after the expected ones" and this would
  # bless a nav of pure junk.
  total=$(printf '%s\n' "$nav_labels" | grep -c .)
  if [ "$last_expected" -ge 1 ]; then
    stray=0
    n=0
    while IFS= read -r label; do
      n=$((n + 1))
      [ "$n" -le "$last_expected" ] || continue
      printf '%s\n' "$NAV_EXPECTED" | cut -d'|' -f1 | grep -qxF "$label" && continue
      stray=$((stray + 1))
    done <<< "$nav_labels"
    if [ "$stray" -gt 0 ]; then
      fail "$stray added page(s) sorted into the middle of the nav instead of onto the end"
    elif [ "$total" -gt "$last_expected" ]; then
      pass "the $((total - last_expected)) added page(s) appended to the end of the nav"
    fi
  fi
fi

# ── 9. "Sponsors" is the word in both places ──────────────────────────────
# The nav says "Sponsors" and the page it points at says "Support Us" on the
# site this replaces. "Sponsors" wins in both places, because that is what
# people look for.
#
# Checked over every page rather than over /sponsors/, and this is the reason:
# the title is also the slug, so reverting the name moves the page to
# /support-us/ AND takes the nav label with it. Nothing dangles, nothing is
# stranded, section 5 stays green - and the page is unfindable. Label drift in
# the other direction, a page still at /sponsors/ under some other name, is
# already section 5's stranding case.
old_name=0
h1_pages=0
while IFS= read -r f; do
  case "$f" in "$SITE"/admin/*) continue ;; esac
  h1_pages=$((h1_pages + 1))
  h1=$(tr '\n' ' ' < "$f" | grep -oE '<h1[^>]*>[^<]*</h1>' | head -1 | sed -E 's|<h1[^>]*>||; s|</h1>||')
  if [ "$h1" = "Support Us" ]; then
    fail "$f is headed \"Support Us\""
    detail "\"Sponsors\" is the word in the nav, and it has to be the word on the page"
    old_name=$((old_name + 1))
  fi
done < <(find "$SITE" -type f -name '*.html' | sort)

if [ "$h1_pages" -lt 1 ]; then
  fail "no page in $SITE to check the sponsors naming over"
elif [ "$old_name" -eq 0 ]; then
  pass "no page is headed \"Support Us\" - across $h1_pages page(s), the word is \"Sponsors\""
fi

# ── 10. Contact is an email address, and there is no form anywhere ────────
# The old site's contact form posted to /contact-thank-you, a route that
# existed nowhere, with no backend and no form provider behind it. Every
# message anyone sent through it since it was built went nowhere, and the team
# never found out. Deleting it cost nothing, and it must not come back: a form
# on a static site with no form provider is not a channel, it is a channel that
# silently is not there.
#
# The form is checked for site-wide rather than on /contact/, because the one
# it replaced also appeared on the home page. Sveltia's own page under /admin/
# is excluded, the same exclusion every other site-wide section here makes: it
# is a third-party application, and its forms are its own.
assert_absent "form in $SITE - email is the whole contact channel" \
  '<form' --include='*.html' --exclude-dir=admin

# ...and the address that replaced it is actually on the page.
#
# THE ADDRESS IS WRITTEN IN FOUR PLACES - hugo.yaml, for the footer on every
# page, and the body of Contact, Sponsors and Current Season - which is not
# something this check can fix, and is exactly why it is worth making. It reads
# the config's address and requires the Contact page to carry the same one, so
# a half-done change of address turns the run red naming both sides instead of
# leaving the site quietly handing out two different addresses.
#
# Scoped to <main>, deliberately: the footer prints the config's address on
# every page, so an unscoped grep would pass over a Contact page that had lost
# its entire body.
CONTACT_PAGE="$SITE/contact/index.html"
contact_email=$(read_key contactEmail)
if [ ! -f "$CONTACT_PAGE" ]; then
  fail "no contact page at $CONTACT_PAGE"
elif [ -z "$contact_email" ]; then
  fail "$CONFIG sets no contactEmail, so there is no address to check the contact page for"
else
  contact_main=$(main_of "$CONTACT_PAGE")
  if [ -z "$contact_main" ]; then
    fail "$CONTACT_PAGE has no <main> element"
  elif ! grep -qF "mailto:$contact_email" <<< "$contact_main"; then
    fail "$CONTACT_PAGE does not offer $contact_email"
    detail "the footer prints $contact_email on every page, out of $CONFIG's contactEmail;"
    detail "the Contact page's own body has to offer that same address, or the site gives out two"
  else
    pass "$CONTACT_PAGE offers $contact_email, the address $CONFIG puts in every footer"
  fi
fi

# ── 11. The calendar leads Current Season, and carries no year ────────────
# The Google Calendar embed is the only element on this site that stays current
# without anyone touching the repository, which is why it is hardcoded in
# layouts/pages/current-season/page.html and is not a field. Three ways it goes
# wrong are silent, and this is the section that is not silent about them. All
# three are pinned by mutations in scripts/test-nav.sh: the embed dropped from
# the template, a paragraph moved above it, and `title=2026%20Events` put back.
CS_PAGE="$SITE/current-season/index.html"
if [ ! -f "$CS_PAGE" ]; then
  fail "no current season page at $CS_PAGE"
else
  cs_main=$(main_of "$CS_PAGE")
  cal=$(grep -oE 'calendar\.google\.com/calendar/embed[^"'"'"'<> ]*' <<< "$cs_main" | head -1)
  if [ -z "$cal" ]; then
    # The embed dropped from the template takes the page's whole point with it
    # and leaves prose that still says "the calendar above".
    fail "$CS_PAGE renders no Google Calendar embed"
  else
    # The calendar LEADS the page. It empties rather than lying, which prose
    # about which days we meet cannot do - so it goes above the prose, and a
    # paragraph before it means that has been reversed.
    # `<p[ >]` and not `<p`, which would also match <pre>, <path> and <picture>.
    if grep -qE '<p[ >]' <<< "${cs_main%%calendar.google.com*}"; then
      fail "$CS_PAGE puts prose above the calendar"
      detail "the calendar leads: it empties rather than going out of date, and the prose does not"
    else
      pass "$CS_PAGE leads with the calendar, above the prose"
    fi

    # No year in the address. It carried `title=2026%20Events`, and a year
    # label frozen into a template still reads 2026 in 2031, over a calendar
    # showing 2031's meetings. The `src` parameter is the opaque calendar ID
    # and is stripped before the pattern is applied, the same way the team
    # number is stripped in section 4 - a year inside a base64 blob would be a
    # coincidence, not a label.
    cal_labels=$(sed -E 's/src=[^&]*//g' <<< "$cal")
    if grep -qE '(19|20)[0-9]{2}' <<< "$cal_labels"; then
      fail "the calendar embed address carries a year"
      detail "$cal"
      detail "a hardcoded year label outlives the season it names; the calendar is named in Google"
    else
      pass "the calendar embed address carries no year label"
    fi
  fi
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed. The site still deployed; this is a content problem, not an outage."
  exit 1
fi
echo "all checks passed"
