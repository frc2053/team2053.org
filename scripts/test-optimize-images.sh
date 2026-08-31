#!/usr/bin/env bash
#
# Fixture tests for scripts/optimize-images.sh.
#
# The optimizer is the one piece of this repository that rewrites files
# repo-wide and then commits them, so it is the one piece that can turn a
# student's photo upload into a site full of broken images. That failure is
# silent, repo-wide, and would otherwise only ever be observed in production -
# which is why this is the only unit-ish test in the project.
#
# Everything here runs against a throwaway git repository under $TMPDIR. It
# never touches the real content tree.
#
# Shell only, no Node, no npm - the same rule the optimizer itself follows.
# Needs cwebp and webpinfo (Debian/Ubuntu: `webp`, macOS: `brew install webp`).
#
# Usage:  scripts/test-optimize-images.sh
# Exit 0 if every assertion passed.

# Deliberately no `set -e`: every test has to run so one failure does not hide
# the rest. Failures are counted, and the exit status comes from the count.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OPTIMIZER="$ROOT/scripts/optimize-images.sh"
FIXTURE_JPEG="$ROOT/scripts/fixtures/oversized.jpg"
WORKFLOW="$ROOT/.github/workflows/publish.yml"

for tool in cwebp webpinfo; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool is not installed; cannot run these tests" >&2
    exit 2
  }
done
[ -x "$OPTIMIZER" ] || { echo "no executable optimizer at $OPTIMIZER" >&2; exit 2; }
[ -f "$FIXTURE_JPEG" ] || { echo "no fixture image at $FIXTURE_JPEG" >&2; exit 2; }
[ -f "$WORKFLOW" ] || { echo "no workflow at $WORKFLOW" >&2; exit 2; }

# Fixture repositories see no global or system git config, so a test never
# depends on how the machine running it is set up.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

failures=0
pass()   { printf 'ok    %s\n' "$1"; }
fail()   { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
detail() { printf '        %s\n' "$1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# webp_dims and bytes_of below are deliberately re-implemented rather than
# sourced from the optimizer: a test that borrows its subject's helpers cannot
# catch a bug inside them.
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Every file in the tree and its hash, .git excluded. Two trees with the same
# manifest are the same tree, which is how "completely unchanged" is asserted.
tree_manifest() {
  ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(sha_of "$f")" "$f"
    done )
}

webp_dims() { webpinfo "$1" 2>/dev/null | awk '/Width:/ && !w {w=$NF} /Height:/ && !h {h=$NF} END {print w" "h}'; }
bytes_of()  { wc -c < "$1" | tr -d ' '; }

# A fixture tree with one oversized JPEG, one SVG, one already-conformant WebP,
# and two files referencing the JPEG - one under content/, one outside it, so
# that a rewrite limited to a directory allowlist fails these tests.
make_fixture() {
  local dir="$1"
  mkdir -p "$dir/static/images" "$dir/content" "$dir/data"
  cp "$FIXTURE_JPEG" "$dir/static/images/oversized.jpg"
  printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>' \
    > "$dir/static/images/logo.svg"
  cwebp -quiet -q 60 -resize 800 0 "$FIXTURE_JPEG" -o "$dir/static/images/already.webp" 2>/dev/null

  cat > "$dir/content/page.md" <<'MD'
---
title: A page
heroImage: /images/oversized.jpg
---

![the robot](/images/oversized.jpg) and ![the logo](/images/logo.svg)
MD

  cat > "$dir/data/extra.yaml" <<'YAML'
# Outside content/ on purpose: the rewrite scans the whole repository.
logo: images/oversized.jpg
YAML

  git -C "$dir" init -q
  git -C "$dir" config user.name 'Fixture'
  git -C "$dir" config user.email 'fixture@example.invalid'
  git -C "$dir" add -A
  git -C "$dir" commit -qm 'fixture'
}

run_optimizer() { ( cd "$1" && shift && "$OPTIMIZER" "$@" >"$WORK/out.log" 2>&1 ); }

# ── 1. The happy path: one oversized JPEG, one commit ─────────────────────
R="$WORK/happy"
make_fixture "$R"
before_commits=$(git -C "$R" rev-list --count HEAD)
if run_optimizer "$R"; then
  pass "the optimizer exits 0 on a tree with one oversized JPEG"
else
  fail "the optimizer exits 0 on a tree with one oversized JPEG"
  while IFS= read -r l; do detail "$l"; done < "$WORK/out.log"
fi

OUT="$R/static/images/oversized.webp"
if [ -f "$OUT" ]; then
  pass "the JPEG became a WebP at the same path"

  read -r w h <<< "$(webp_dims "$OUT")"
  if [ -n "$w" ] && [ -n "$h" ] && [ "$w" -le 1920 ] && [ "$h" -le 1920 ]; then
    pass "the result fits 1920x1920 (${w}x${h})"
  else
    fail "the result fits 1920x1920 (got '${w}x${h}')"
  fi

  size=$(bytes_of "$OUT")
  if [ "$size" -le 307200 ]; then
    pass "the result is under the 300 KiB ceiling ($size bytes)"
  else
    fail "the result is under the 300 KiB ceiling ($size bytes)"
  fi
else
  fail "the JPEG became a WebP at the same path"
fi

if [ -e "$R/static/images/oversized.jpg" ]; then
  fail "the original is replaced, not kept alongside"
else
  pass "the original is replaced, not kept alongside"
fi

if grep -rIl -F -e 'oversized.jpg' "$R" --exclude-dir=.git >/dev/null 2>&1; then
  fail "zero references to the old filename survive"
  while IFS= read -r f; do detail "$f"; done < <(grep -rIl -F -e 'oversized.jpg' "$R" --exclude-dir=.git)
else
  pass "zero references to the old filename survive"
fi

rewritten=0
for f in "$R/content/page.md" "$R/data/extra.yaml"; do
  grep -q -F 'oversized.webp' "$f" || { fail "the new filename is written into $(basename "$f")"; rewritten=1; }
done
[ "$rewritten" -eq 0 ] && pass "both referencing files - inside and outside content/ - point at the new filename"

after_commits=$(git -C "$R" rev-list --count HEAD)
if [ "$after_commits" -eq $((before_commits + 1)) ]; then
  pass "exactly one commit was made"
else
  fail "exactly one commit was made (went from $before_commits to $after_commits)"
fi

if [ -z "$(git -C "$R" status --porcelain)" ]; then
  pass "the working tree is clean afterwards - the rename and the rewrite are in the same commit"
else
  fail "the working tree is clean afterwards"
  while IFS= read -r l; do detail "$l"; done < <(git -C "$R" status --porcelain)
fi

# ── 2. An SVG passes through byte-identical ───────────────────────────────
R2="$WORK/svg"
make_fixture "$R2"
svg_before=$(sha_of "$R2/static/images/logo.svg")
webp_before=$(sha_of "$R2/static/images/already.webp")
run_optimizer "$R2"
if [ "$(sha_of "$R2/static/images/logo.svg")" = "$svg_before" ]; then
  pass "the SVG passes through byte-identical"
else
  fail "the SVG passes through byte-identical"
fi
if [ "$(sha_of "$R2/static/images/already.webp")" = "$webp_before" ]; then
  pass "a WebP already inside both limits is left byte-identical"
else
  fail "a WebP already inside both limits is left byte-identical"
fi

# ── 3. A second run is a no-op ────────────────────────────────────────────
before2=$(git -C "$R2" rev-list --count HEAD)
if run_optimizer "$R2"; then
  after2=$(git -C "$R2" rev-list --count HEAD)
  if [ "$after2" -eq "$before2" ]; then
    pass "a second run makes no commit"
  else
    fail "a second run makes no commit (went from $before2 to $after2)"
  fi
else
  fail "a second run exits 0"
  while IFS= read -r l; do detail "$l"; done < "$WORK/out.log"
fi

# ── 4. The ceiling is a ceiling, not a quality setting ────────────────────
# A 40 KB ceiling is unreachable at the top of the quality ladder, so this
# only passes if the optimizer actually steps down until it fits.
R3="$WORK/ceiling"
make_fixture "$R3"
if ( cd "$R3" && IMAGE_MAX_BYTES=40000 "$OPTIMIZER" >"$WORK/out.log" 2>&1 ); then
  size=$(bytes_of "$R3/static/images/oversized.webp")
  if [ "$size" -le 40000 ]; then
    pass "quality steps down until the file is under the ceiling ($size <= 40000)"
  else
    fail "quality steps down until the file is under the ceiling ($size > 40000)"
  fi
else
  fail "the optimizer reaches a 40 KB ceiling"
  while IFS= read -r l; do detail "$l"; done < "$WORK/out.log"
fi

# ── 5. A failure during conversion leaves the tree unchanged ──────────────
R4="$WORK/broken"
make_fixture "$R4"
printf 'this is not an image\n' > "$R4/static/images/zz-broken.jpg"
git -C "$R4" add -A
git -C "$R4" commit -qm 'add an unreadable image'
before_manifest=$(tree_manifest "$R4")
before_head=$(git -C "$R4" rev-parse HEAD)
if run_optimizer "$R4"; then
  fail "an unreadable image fails the run"
else
  pass "an unreadable image fails the run"
fi
if [ "$(tree_manifest "$R4")" = "$before_manifest" ] && [ "$(git -C "$R4" rev-parse HEAD)" = "$before_head" ]; then
  pass "after a conversion failure the fixture tree is completely unchanged"
else
  fail "after a conversion failure the fixture tree is completely unchanged"
  while IFS= read -r l; do detail "$l"; done < <(diff <(printf '%s\n' "$before_manifest") <(tree_manifest "$R4"))
fi

# ── 6. A failure after the tree has been rewritten also leaves it unchanged ─
# The commit itself is made to fail, which is the only failure that can strike
# after every file has already been renamed and every reference rewritten.
# This is the assertion that exercises the rollback rather than the ordering.
R5="$WORK/rollback"
make_fixture "$R5"
git -C "$R5" config user.useConfigOnly true
git -C "$R5" config --unset user.email
before_manifest=$(tree_manifest "$R5")
before_head=$(git -C "$R5" rev-parse HEAD)
if run_optimizer "$R5"; then
  fail "a failing commit fails the run"
else
  pass "a failing commit fails the run"
fi
if [ "$(tree_manifest "$R5")" = "$before_manifest" ] && [ "$(git -C "$R5" rev-parse HEAD)" = "$before_head" ]; then
  pass "after a mid-run failure the fixture tree is completely unchanged"
else
  fail "after a mid-run failure the fixture tree is completely unchanged"
  while IFS= read -r l; do detail "$l"; done < <(diff <(printf '%s\n' "$before_manifest") <(tree_manifest "$R5"))
fi

# ── 7. A dirty tree is refused ────────────────────────────────────────────
# The rollback is `git reset --hard`, so running over uncommitted work would
# destroy it. Refusing is what makes the rollback safe.
R6="$WORK/dirty"
make_fixture "$R6"
printf 'work in progress\n' > "$R6/content/draft.md"
before_manifest=$(tree_manifest "$R6")
if run_optimizer "$R6"; then
  fail "a dirty working tree is refused"
else
  pass "a dirty working tree is refused"
fi
if [ "$(tree_manifest "$R6")" = "$before_manifest" ]; then
  pass "the refused run changed nothing"
else
  fail "the refused run changed nothing"
fi

# ── 8. A rename never touches a longer filename that contains it ──────────
# Renaming `logo.png` must leave `oldlogo.png` alone - both in the rewrite and
# in the verification that follows it. A fixed-string check in either place
# turns an innocent mention elsewhere in the repository into either a silent
# corruption or a run that can never succeed again.
R7="$WORK/boundary"
make_fixture "$R7"
cp "$FIXTURE_JPEG" "$R7/static/images/logo.png"
cat > "$R7/content/other.md" <<'MD'
Our old mark lived at oldlogo.png, and the current one is /images/logo.png.
MD
git -C "$R7" add -A
git -C "$R7" commit -qm 'add a png whose name is a suffix of another name'
if run_optimizer "$R7"; then
  pass "a rename alongside a superstring filename completes"
else
  fail "a rename alongside a superstring filename completes"
  while IFS= read -r l; do detail "$l"; done < "$WORK/out.log"
fi
if grep -q -F 'oldlogo.png' "$R7/content/other.md"; then
  pass "oldlogo.png was left alone while logo.png was rewritten"
else
  fail "oldlogo.png was left alone while logo.png was rewritten"
  detail "$(cat "$R7/content/other.md")"
fi
if grep -q -F '/images/logo.webp' "$R7/content/other.md"; then
  pass "the bounded reference to logo.png was rewritten"
else
  fail "the bounded reference to logo.png was rewritten"
fi

# ── 9. A rename that would overwrite an existing file is refused ──────────
R8="$WORK/collision"
make_fixture "$R8"
cp "$FIXTURE_JPEG" "$R8/static/images/twin.jpg"
cwebp -quiet -q 60 -resize 800 0 "$FIXTURE_JPEG" -o "$R8/static/images/twin.webp" 2>/dev/null
git -C "$R8" add -A
git -C "$R8" commit -qm 'add a jpg whose webp name is taken'
before_manifest=$(tree_manifest "$R8")
if run_optimizer "$R8"; then
  fail "a rename onto an existing file is refused"
else
  pass "a rename onto an existing file is refused"
fi
if [ "$(tree_manifest "$R8")" = "$before_manifest" ]; then
  pass "the refused collision changed nothing"
else
  fail "the refused collision changed nothing"
fi

# ── 10. A basename shared by two directories is refused ───────────────────
# References are rewritten by basename, so two images called the same thing in
# different folders would cross-contaminate each other's references. The real
# repository already has one such pair (static/images/vestal-logo.webp and
# static/images/sponsor/vestal-logo.webp), so this is not hypothetical.
R9="$WORK/samename"
make_fixture "$R9"
mkdir -p "$R9/static/images/sponsor"
cp "$FIXTURE_JPEG" "$R9/static/images/shared.png"
cp "$FIXTURE_JPEG" "$R9/static/images/sponsor/shared.png"
git -C "$R9" add -A
git -C "$R9" commit -qm 'the same basename in two directories'
before_manifest=$(tree_manifest "$R9")
if run_optimizer "$R9"; then
  fail "an image whose basename is not unique is refused"
else
  pass "an image whose basename is not unique is refused"
fi
if [ "$(tree_manifest "$R9")" = "$before_manifest" ]; then
  pass "the refused basename clash changed nothing"
else
  fail "the refused basename clash changed nothing"
fi

# ── 11. The pipeline stays shell-only ─────────────────────────────────────
# Node is what made the old S3 job rot: a `setup-node` pin and an npm install
# of sharp on every push. Its absence is a property worth asserting.
node_hits=$(grep -nHE 'setup-node|npm |npx |node ' "$WORKFLOW" "$OPTIMIZER" | grep -vE ':[0-9]+:[[:space:]]*#')
if [ -n "$node_hits" ]; then
  fail "the workflow and the optimizer are free of Node"
  while IFS= read -r l; do detail "$l"; done <<< "$node_hits"
else
  pass "the workflow and the optimizer are free of Node"
fi

# ── 12. A failed optimize still deploys, and is still checked ─────────────
# Structural properties of the workflow that no local run can exercise, so
# they are asserted against the job blocks that carry them - not against the
# whole file, where a stray `if: always()` on any step would satisfy a naive
# grep and the assertion could never fail.
job_block() { awk -v job="  $1:" '$0 == job {inside=1; next} /^  [a-z]/ {inside=0} inside' "$WORKFLOW"; }

# Anchored at four spaces: that is the job's own `if:`. A step's `if:` sits at
# eight, and matching one of those is how this assertion silently stops being
# able to fail.
#
# Every assertion below feeds grep with a here-string rather than a pipe.
# Under `set -o pipefail`, `printf "%s" "$(cmd)" | grep -q` reports the
# PIPELINE as failed whenever grep matches early and exits, because printf
# then dies of SIGPIPE - so the assertion fails precisely when the thing it
# looks for IS present. Observed here, deterministically, on the check job.
build_block=$(job_block build)
check_block=$(job_block check)
deploy_block=$(job_block deploy)
if grep -qE '^    if: always\(\)' <<< "$build_block"; then
  pass "build runs even when optimize failed"
else
  fail "build runs even when optimize failed"
fi
if grep -qF 'needs.optimize.outputs.sha || github.sha' <<< "$build_block"; then
  pass "build uses optimize's commit, falling back to the pushed one"
else
  fail "build uses optimize's commit, falling back to the pushed one"
fi

# `needs:` alone would skip this job whenever optimize failed, taking these
# very tests with it. Only a status function lifts that skip.
if grep -qE '^    if: .*always\(\)' <<< "$check_block"; then
  pass "check still runs when optimize failed"
else
  fail "check still runs when optimize failed"
fi

if grep -qE '^    needs: build$' <<< "$deploy_block"; then
  pass "deploy hangs off build, so a failed build deploys nothing"
else
  fail "deploy hangs off build, so a failed build deploys nothing"
fi

# ── 13. The committed CMS bundle is never rewritten ───────────────────────
# static/admin/sveltia-cms.js is 2 MB of minified third-party JavaScript, and
# it happens to contain the string `image.png`. `image.png` is also about the
# most likely name a student's upload could carry. Left in scope, the rewrite
# would edit that string inside the bundle - silently corrupting the CMS while
# reporting a successful optimization.
R="$WORK/vendored"
make_fixture "$R"
mkdir -p "$R/static/admin"
cp "$ROOT/static/admin/sveltia-cms.js" "$R/static/admin/sveltia-cms.js"
cp "$FIXTURE_JPEG" "$R/static/images/image.png"
printf 'hero: /images/image.png\n' > "$R/content/uploaded.md"
git -C "$R" add -A
git -C "$R" commit -qm 'an upload named like a string inside the CMS bundle'

bundle_before=$(sha_of "$R/static/admin/sveltia-cms.js")
if run_optimizer "$R"; then
  pass "the optimizer exits 0 with the CMS bundle in the tree"
else
  fail "the optimizer exits 0 with the CMS bundle in the tree"
  while IFS= read -r l; do detail "$l"; done < "$WORK/out.log"
fi

if [ "$(sha_of "$R/static/admin/sveltia-cms.js")" = "$bundle_before" ]; then
  pass "the committed CMS bundle is byte-identical after a rewrite of image.png"
else
  fail "the committed CMS bundle is byte-identical after a rewrite of image.png"
  detail "the rewrite edited 2 MB of vendored third-party JavaScript"
fi

# The real reference still has to have been rewritten, or the test above would
# pass just as well against an optimizer that gave up entirely.
if [ -f "$R/static/images/image.webp" ] && grep -qF '/images/image.webp' "$R/content/uploaded.md"; then
  pass "the upload was still converted and its real reference rewritten"
else
  fail "the upload was still converted and its real reference rewritten"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed."
  exit 1
fi
echo "all checks passed"
