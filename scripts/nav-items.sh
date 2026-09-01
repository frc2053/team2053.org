# Reading the rendered main nav out of a built page. Sourced, never run: both
# scripts/check-site.sh and scripts/test-nav.sh need it, and two copies would
# mean the tests exercising the same parser bug they exist to catch.
#
# nav_items <html-file> emits one `href|label` line per anchor in the page's
# MAIN nav, in document order, and nothing at all if the page has no main nav.
#
# Scoped to <nav class="nav">, and to the first </nav> after it, rather than
# taken as everything between the first <nav> and the last </nav>. This page is
# not the only <nav> a page can hold - slice 08's footer puts the social links
# in one, and a paginated blog index would be a second - and a greedy match
# across them reads the whole page body as nav items, which reports as the nav
# differing between pages rather than as the parser being wrong.
#
# Attributes are read quoted, unquoted and bare, because `--minify` emits all
# three: `<a href="/contact/">` ships as `<a href=/contact/>`, and an EMPTY href
# ships as `<a href>`. That last shape is the one worth naming - read carelessly
# it parses as the href "href", which is a broken link reported as a working
# one. Newlines are flattened first: the minified nav still spans them, which is
# what defeated a single-line grep during slice 03.
nav_items() {
  tr '\n' ' ' < "$1" | awk '{
    rest = $0
    found = 0
    while (match(rest, /<nav[^>]*>/)) {
      tag  = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      if (tag ~ /class="?nav"?[[:space:]>]/) { found = 1; break }
    }
    if (!found) next
    end = index(rest, "</nav>")
    if (end > 0) rest = substr(rest, 1, end - 1)

    n = split(rest, a, /<a /)
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
