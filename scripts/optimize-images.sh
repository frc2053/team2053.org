#!/usr/bin/env bash
#
# Shrinks every image in the repository to fit 1920x1920 and stay under a hard
# 300 KiB ceiling, converts it to WebP, rewrites every reference to it
# repo-wide, and commits the lot ONCE - atomically, or not at all.
#
# WHY A CEILING RATHER THAN A QUALITY SETTING
# A dimension cap does not cap bytes: a 1920px photo of a noisy scene can still
# be 2 MB. 300 KiB is a number a human can check in 2032 with `ls -la`.
#
# WHY ATOMIC
# The job this replaces optimized in stages - upload to S3, then rewrite the
# MDX - so a half-failure left markdown pointing at a file that was not there.
# This one fails as "not optimized", never as "broken". Every conversion
# happens in a temporary directory first; nothing in the repository moves until
# all of them have succeeded; and if anything at all goes wrong after that, the
# tree is put back exactly as it was found.
#
# WHY IT SCANS THE WHOLE REPOSITORY FOR REFERENCES
# A directory allowlist is a promise that no future page will ever mention an
# image from somewhere new. That promise gets broken by the first student who
# adds a page, and the symptom is a broken image nobody left here can debug.
# So: every tracked text file is scanned, and the run aborts to a no-op if a
# single reference to the old filename survives.
#
# WHY SHELL, AND WHY libwebp SPECIFICALLY
# No Node, no npm, no `setup-node`. cwebp has had the same command-line
# interface for over a decade and comes from Debian's `webp` package, which is
# about the smallest dependency that can do this job.
#
# Usage:  scripts/optimize-images.sh
#
# Environment:
#   IMAGE_MAX_BYTES   byte ceiling, default 307200 (300 KiB). Exists so the
#                     tests can drive the ladder without a pathological
#                     fixture; the default is the real policy.
#
# Exit 0: nothing needed doing, or one commit was made.
# Exit 1: nothing was changed and the tree is exactly as it was found.

# Deliberately no `set -e`. Every failure below has to route through `die` so
# that the tree gets put back; a bare exit part-way through would leave it
# half-rewritten, which is the one outcome this script exists to prevent.
set -uo pipefail

MAX_BYTES=${IMAGE_MAX_BYTES:-307200}

# Tried in order until one produces a file inside the ceiling. Each rung is
# `longest-edge:quality`. The first rung is the policy - fit 1920x1920 at
# quality 85 - and the quality-only rungs under it are the "step down until it
# fits" the ceiling requires.
#
# The last four rungs give up resolution as well, and are a deliberate last
# resort: without them an image that cannot reach the ceiling at 1920px fails
# the whole run, which means nothing gets optimized and the workflow is red
# until a human intervenes - and there is no human. A photograph slightly
# narrower than 1920 is a Tier 2 blemish; a red workflow nobody can clear is
# not. Every rung that fires is printed, so it is never silent.
LADDER='1920:85 1920:75 1920:65 1920:55 1920:45 1536:45 1280:40 1024:35 800:30'

# One source of truth for both limits: the top rung is the policy.
TOP_RUNG=${LADDER%% *}
MAX_EDGE=${TOP_RUNG%%:*}
TOP_QUALITY=${TOP_RUNG##*:}

# Where the CMS puts uploads, which is the only way an image reaches this
# repository. Not an argument: nothing has ever needed to pass a different one,
# and a constant is one less thing to get wrong. check-site.sh independently
# asserts the ceiling over the whole generated site, so an image that somehow
# lands outside this directory is reported rather than silently skipped.
MEDIA_ROOT=static/images

# Where references are rewritten: every tracked text file EXCEPT the committed
# CMS bundle under static/admin/.
#
# This is not the directory allowlist the comment above refuses. It is one
# denylist entry for 2 MB of minified third-party JavaScript that cannot
# legitimately reference an image in this repository - and which does contain
# the literal string `image.png`, about the likeliest name a student's upload
# could carry. In scope, a single upload called image.png would edit the CMS
# bundle and report a successful optimization; the alternative outcome, if the
# edit did not take, is the coverage check aborting every run from then on.
# Everything a page can actually be written in stays in scope.
REF_SCOPE=(. ':(exclude)static/admin')

TAB=$(printf '\t')

say()  { printf 'optimize-images: %s\n' "$*"; }
warn() { printf 'optimize-images: %s\n' "$*" >&2; }

# Set the moment the repository is first written to, cleared once the commit
# has landed. While it is set, any exit at all rolls the tree back.
MUTATED=0
START_COMMIT=
TMP=

rollback() {
  [ "$MUTATED" = 1 ] || return 0
  MUTATED=0
  warn "putting the tree back to $START_COMMIT - nothing was optimized"
  git reset -q --hard "$START_COMMIT"
  # Safe because the run refuses to start on a dirty tree: everything untracked
  # here was created by this script.
  git clean -qfd
}

finish() {
  rollback
  [ -n "$TMP" ] && rm -rf "$TMP"
  return 0
}

# A cancelled workflow run and a Ctrl-C both arrive as a signal, and bash does
# not run an EXIT trap for an untrapped fatal signal. Without these the tree
# could be left half-rewritten by the one thing this script promises can never
# leave it half-rewritten.
trap finish EXIT
trap 'finish; exit 130' INT TERM HUP

die() { warn "$*"; exit 1; }

for tool in cwebp webpinfo git; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed (Debian/Ubuntu: apt-get install webp)"
done

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$TOPLEVEL" || die "cannot enter $TOPLEVEL"

# The rollback is `git reset --hard`, so uncommitted work must never be in
# range of it.
[ -z "$(git status --porcelain)" ] || die "the working tree has uncommitted changes; refusing to run"
START_COMMIT=$(git rev-parse HEAD) || die "the repository has no commits"

# A mistyped media root would otherwise report "nothing to do" and exit 0
# forever, which is the quietest possible way for this to stop working.
[ -d "$MEDIA_ROOT" ] || die "no such directory: $MEDIA_ROOT"

TMP=$(mktemp -d) || die "cannot create a temporary directory"

# Width and height of a WebP, as "W H". webpinfo labels the extended format
# "Canvas Width", so the first match of each wins rather than the last.
webp_dims() {
  webpinfo "$1" 2>/dev/null | awk '/Width:/ && !w {w=$NF} /Height:/ && !h {h=$NF} END {print w" "h}'
}

bytes_of() { wc -c < "$1" | tr -d ' '; }

# Encodes $1 into $2, stepping down the ladder until the result is inside both
# limits. Returns 1 if the source cannot be read or the ceiling is unreachable.
#
# `-metadata none` is cwebp's default and is passed anyway: it is what strips
# the GPS coordinates out of a student's phone photo, and that should not
# depend on an upstream default staying put.
encode() {
  local src=$1 out=$2 w h longest rung width quality

  # A probe at the top quality with no resize, which doubles as the finished
  # article for anything already inside 1920x1920 and the ceiling.
  cwebp -quiet -metadata none -m 6 -q "$TOP_QUALITY" "$src" -o "$out" 2>/dev/null || return 1
  read -r w h <<< "$(webp_dims "$out")"
  [ -n "$w" ] && [ -n "$h" ] || return 1
  if [ "$w" -le "$MAX_EDGE" ] && [ "$h" -le "$MAX_EDGE" ] && [ "$(bytes_of "$out")" -le "$MAX_BYTES" ]; then
    return 0
  fi

  longest=$w
  [ "$h" -gt "$longest" ] && longest=$h

  for rung in $LADDER; do
    width=${rung%%:*}
    quality=${rung##*:}

    # Never enlarge: a rung wider than the source is a quality-only rung.
    if [ "$longest" -gt "$width" ]; then
      if [ "$w" -ge "$h" ]; then set -- -resize "$width" 0; else set -- -resize 0 "$width"; fi
    else
      set --
    fi

    cwebp -quiet -metadata none -m 6 -q "$quality" "$@" "$src" -o "$out" 2>/dev/null || return 1
    [ "$(bytes_of "$out")" -le "$MAX_BYTES" ] || continue
    read -r w h <<< "$(webp_dims "$out")"
    [ -n "$w" ] && [ -n "$h" ] || return 1
    [ "$w" -le "$MAX_EDGE" ] && [ "$h" -le "$MAX_EDGE" ] && return 0
  done

  return 1
}

# Escapes a string for use as an ERE pattern, and as a sed replacement.
ere_escape() { printf '%s' "$1" | sed 's/[][\.^$*+?(){}|\/]/\\&/g'; }
rep_escape() { printf '%s' "$1" | sed 's/[\/&\\]/\\&/g'; }

# An ERE matching basename $1 only where it is a whole filename. Bounded on the
# left so that renaming `logo.png` never touches `oldlogo.png`; the extension
# bounds it on the right.
#
# The rewrite and the verification that follows it MUST use this same pattern.
# A fixed-string check in either place is a defect: in the rewrite it silently
# corrupts an unrelated mention, and in the verification it aborts every run
# for as long as that mention exists - which is images never optimized again,
# plus a permanently red workflow, from one innocent sentence in a page.
#
# Left only, deliberately. A right-hand boundary would have to CONSUME the
# character after the match, and two references sharing one separator - the
# `"a.jpg","a.jpg"` in a list - would then leave the second one unrewritten,
# which aborts the run. Trading a rare wrong rewrite (`hero.jpg.bak`) for a
# realistic permanent failure is the wrong way round; the extension already
# bounds the right in every reference shape this site actually uses, and
# check-site.sh catches a reference that ends up pointing at nothing.
bounded_pattern() { printf '(^|[^A-Za-z0-9_-])%s' "$(ere_escape "$1")"; }

# Rewrites every reference to basename $1 into basename $2, across every
# tracked text file in the repository.
rewrite_refs() {
  local old=$1 new=$2 pattern replacement file
  pattern=$(bounded_pattern "$old")
  replacement=$(rep_escape "$new")

  # Exit 1 is "no matches"; anything above that is a failure, and treating it
  # as "no matches" would rewrite nothing and report success.
  git grep -l -I -F -z -e "$old" -- "${REF_SCOPE[@]}" > "$TMP/hits"
  case $? in 0|1) ;; *) return 1 ;; esac

  while IFS= read -r -d '' file; do
    sed -E "s/$pattern/\1$replacement/g" "$file" > "$TMP/rewritten" || return 1
    cat "$TMP/rewritten" > "$file" || return 1
  done < "$TMP/hits"
}

# ── 1. Which images need work ─────────────────────────────────────────────
# Tracked files only, so a file the CMS has not committed yet is never half
# handled. SVGs and GIFs are absent by design: an SVG has no pixels to shrink,
# and libwebp cannot resize an animation, so both pass through untouched.
#
# Filenames are assumed free of newlines. The repatriated corpus guarantees
# [A-Za-z0-9._/-], and the CMS slugifies uploads.
git -c core.quotePath=false ls-files -- "$MEDIA_ROOT" \
  | grep -iE '\.(jpe?g|png|webp)$' \
  | sort > "$TMP/tracked"

: > "$TMP/todo"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case $(printf '%s' "$f" | tr '[:upper:]' '[:lower:]') in
    *.webp)
      # Already the right format: only over-budget or over-size files are work.
      read -r w h <<< "$(webp_dims "$f")"
      [ -n "$w" ] && [ -n "$h" ] || die "$f is not a readable WebP"
      if [ "$(bytes_of "$f")" -le "$MAX_BYTES" ] && [ "$w" -le "$MAX_EDGE" ] && [ "$h" -le "$MAX_EDGE" ]; then
        continue
      fi
      ;;
  esac
  printf '%s\n' "$f" >> "$TMP/todo"
done < "$TMP/tracked"

if [ ! -s "$TMP/todo" ]; then
  say "every image under $MEDIA_ROOT is already WebP, within ${MAX_EDGE}x${MAX_EDGE}, and under $MAX_BYTES bytes"
  exit 0
fi

# ── 2. Convert everything, into the temporary directory ───────────────────
# Nothing in the repository is touched in this phase, so a source that cannot
# be read costs the run and nothing else.
# Every tracked basename in the repository, for the uniqueness guard below.
git -c core.quotePath=false ls-files | sed 's|.*/||' | sort > "$TMP/basenames"

n=0
: > "$TMP/plan"
while IFS= read -r src; do
  n=$((n + 1))
  dst="${src%.*}.webp"
  new="$TMP/$n.webp"

  if [ "$dst" != "$src" ] && [ -e "$dst" ]; then
    die "cannot rename $src to $dst: that file already exists"
  fi

  # References are rewritten by basename, so a basename that is not unique in
  # the repository would have this rename reach into some other directory's
  # references too. The repository already contains one such pair
  # (static/images/vestal-logo.webp and static/images/sponsor/vestal-logo.webp),
  # so refusing is the difference between "not optimized" and "two pages now
  # point at the wrong photograph".
  if [ "$dst" != "$src" ]; then
    if [ "$(grep -c -x -F -e "$(basename "$src")" "$TMP/basenames")" -gt 1 ]; then
      die "$src does not have a unique filename in this repository; rename it before it can be optimized"
    fi
    if [ "$(grep -c -x -F -e "$(basename "$dst")" "$TMP/basenames")" -gt 0 ]; then
      die "$src would become $(basename "$dst"), which another file in this repository is already called"
    fi
  fi

  encode "$src" "$new" || die "cannot fit $src under $MAX_BYTES bytes at $MAX_EDGE px or smaller"
  printf '%s\t%s\t%s\n' "$src" "$dst" "$new" >> "$TMP/plan"
  # Dimensions are printed, not just bytes, so that a photograph which only
  # fit under the ceiling by dropping below $MAX_EDGE says so in the log
  # rather than losing resolution silently.
  read -r ow oh <<< "$(webp_dims "$new")"
  say "$src -> $dst ($(bytes_of "$src") -> $(bytes_of "$new") bytes, ${ow}x${oh})"
done < "$TMP/todo"

# ── 3. Apply: references first, then the files themselves ─────────────────
# References are rewritten while the old file is still present so that git's
# view of the tree stays consistent throughout.
MUTATED=1

while IFS="$TAB" read -r src dst new; do
  [ "$src" = "$dst" ] && continue
  rewrite_refs "$(basename "$src")" "$(basename "$dst")" \
    || die "failed rewriting references to $(basename "$src")"
done < "$TMP/plan"

while IFS="$TAB" read -r src dst new; do
  cat "$new" > "$dst" || die "failed writing $dst"
  [ "$src" = "$dst" ] || rm -f "$src" || die "failed removing $src"
done < "$TMP/plan"

git add -A || die "git add failed"

# ── 4. Verify before committing ───────────────────────────────────────────
# The coverage rule: a single surviving reference to an old filename is a
# broken image on the live site, so it aborts the whole run instead.
while IFS="$TAB" read -r src dst new; do
  [ -f "$dst" ] || die "$dst was not written"
  [ "$(bytes_of "$dst")" -le "$MAX_BYTES" ] || die "$dst is over $MAX_BYTES bytes"
  read -r w h <<< "$(webp_dims "$dst")"
  [ -n "$w" ] && [ -n "$h" ] || die "$dst is not a readable WebP"
  [ "$w" -le "$MAX_EDGE" ] && [ "$h" -le "$MAX_EDGE" ] || die "$dst is larger than ${MAX_EDGE}x${MAX_EDGE}"

  [ "$src" = "$dst" ] && continue
  [ -e "$src" ] && die "$src is still present alongside $dst"
  # Same three-way status. A `git grep` that errors here and is read as "clean"
  # is the one path in this script that can publish a broken image.
  git grep -q -I -E -e "$(bounded_pattern "$(basename "$src")")" -- "${REF_SCOPE[@]}"
  case $? in
    0) die "references to $(basename "$src") survive; aborting rather than publishing a broken image" ;;
    1) ;;
    *) die "could not verify that references to $(basename "$src") are gone" ;;
  esac
done < "$TMP/plan"

# ── 5. One commit ─────────────────────────────────────────────────────────
if git diff --cached --quiet; then
  say "the optimized files are byte-identical to what was already committed; nothing to do"
  MUTATED=0
  exit 0
fi

{
  printf 'Optimize images\n\n'
  printf 'Fitted to %sx%s, converted to WebP, and shrunk under %s bytes.\n' "$MAX_EDGE" "$MAX_EDGE" "$MAX_BYTES"
  printf 'Every reference was rewritten in the same commit.\n\n'
  while IFS="$TAB" read -r src dst new; do printf '  %s -> %s\n' "$src" "$dst"; done < "$TMP/plan"
} > "$TMP/message"

git commit -q -F "$TMP/message" || die "git commit failed"
MUTATED=0

say "committed $(wc -l < "$TMP/plan" | tr -d ' ') optimized image(s) as $(git rev-parse --short HEAD)"
