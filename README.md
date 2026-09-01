# team2053.org

This is the website of Southern Tier Robotics, FIRST&reg; Robotics Competition
team 2053 in Vestal, New York. The site is built from the files in this
repository: anything committed to `main` is published automatically by GitHub
Actions and is live about a minute later.

## Editing the site

1. Open **<https://team2053.org/admin/>** and bookmark it.
2. Click **Sign In with Token** and paste the editing token from the team
   Bitwarden. You do this **once per browser, ever** — it survives closing the
   browser and restarting the computer.
3. Pick the thing you want to change. Everything editable is listed down the
   left-hand side.
4. Type. Click **Publish**.
5. Wait a minute, then reload the page on the site.

That is the whole loop. No GitHub account, no approval step, nothing to install.

### If a banner picture looks wrong

The wide picture across the top of a page is cropped to fit, which is right for
an ordinary photograph and wrong for a logo or for a photo taller than it is
wide — those get cut in half. Every form that takes a banner has a **Banner
shape** box under it. Switch it to **Show the whole picture** and nothing is
cut off. That is the only image setting on this site, and leaving it alone is
the right answer nearly every time.

## Your edits aren't showing

The one thing that can go wrong quietly is a **failed build**: your edit is
saved, but the site never rebuilds, so the page you changed keeps showing the
old version. When that happens the team's mailbox gets an email with the
subject **"Run failed: Publish the website"**. That email is the only warning
the site will ever give you, which is why it is worth opening.

**When you get it, do one thing first: open <https://team2053.org>.**

**If the site loads normally** — this is the ordinary case, and it is working as
designed. The site is *frozen*, not broken: it keeps serving the last version
that built successfully, and nothing is lost. Everything anyone has published
since is saved in this repository and will appear the moment the site builds
again. Nobody receiving that email can fix the build, and **there is nothing
you need to do.** The email's entire value is turning *"the website is ignoring
us"* into *"the website is stuck, and we know."*

**If the site does not load at all** — that is a different and much rarer
problem. See [If the site is dark](#if-the-site-is-dark) at the end of this
file.

There is one cause you *can* fix, and it is the common one: **text pasted into
a page from somewhere else**. Some punctuation — `{{` above all — stops the
site building. If you pasted something and then this email arrived, open that
same page in the CMS again, delete what you pasted, retype it by hand, and
publish. Publishing keeps working the whole time the build is broken; only the
build is stuck. Do this promptly: while it is broken, **nobody's** edits reach
the site, not just yours.

Anything else: **southerntierrobotics@gmail.com**.

## Getting something back

There is **no undo**. The entries under **Pages** in the CMS are undeletable by
construction — they have no delete button at all. Everything else in the CMS
can be deleted, and deleting it is permanent as far as the CMS is concerned:
the confirmation box is the only thing standing in front of it.

Nothing is really gone, though. Every change ever published is kept, and
reading them needs no login, no GitHub account and no software:

1. Open <https://github.com/frc2053/team2053.org/commits/main>.
2. Find the change. The newest is at the top, and each one is named after what
   it did and which entry it did it to.
3. Click it. Removed text is shown in red, added text in green.
4. Copy the old text out and retype it into the CMS.

## Building locally

Nobody needs this to edit the site. It is here for anyone who wants to run the
site on their own machine.

The site is built by [Hugo](https://gohugo.io). **Which version, which edition
and which exact file are pinned in
[`.github/workflows/publish.yml`](.github/workflows/publish.yml)** — it names
the release it downloads, and it is the only place any of that is written down.
Read it there, then take the matching release from
<https://github.com/gohugoio/hugo/releases>.

On **macOS**, Hugo ships only a `.pkg` installer — `hugo_<version>_darwin-universal.pkg`,
one file for both Intel and Apple Silicon. There is no macOS `.tar.gz` to
unpack, so the download command in the workflow is not the one to copy: it is
the Linux build. Take the `.pkg` for the pinned version and open it.

Then, from the top of this repository:

```
hugo server
```

and open <http://localhost:1313>.

## Credentials

This file is public. What is written here is safe to publish; what is missing
from it is missing deliberately.

**The editing token** — the one step 2 above asks for — is in the
student-readable collection of the team Bitwarden.

**If that token is ever revoked or stops working**, it has to be minted again.
This is the one procedure with no other source, so here it is in full. Signed
in to GitHub as `str-coder`: **Settings → Developer settings → Personal access
tokens → Fine-grained tokens → Generate new token**, then

- **Resource owner:** `frc2053` — the organization, *not* the personal account.
- **Repository access:** Only select repositories → `frc2053/team2053.org`.
- **Repository permissions:** **Contents: Read and write**, and nothing else.
  In particular **not Workflows** — a token holding that could rewrite the
  publishing workflow itself.
- **Expiration:** No expiration.

Generate it, replace the value in the Bitwarden item, and paste the new token
at `/admin/` in each browser that was using the old one.

**Account recovery material for the `str-coder` account is in the team
Bitwarden.** It is not described here and its location is not given here,
because this file is public and that material is the whole organization.

## If the site is dark

"Dark" means <https://team2053.org> does not load at all — a browser error
rather than an out-of-date page. This is rare, and it is not the same as the
frozen site described above. There are exactly three causes, and this is the
only section of this file that can reverse one.

**1. The domain lapsed.** `team2053.org` is registered at NameSilo with
auto-renew switched on. Auto-renew is not the thing that fails — **the card
behind it** is, and a card expires long before the domain does. Sign in to
NameSilo, confirm the registration is current, and confirm the payment method
on file has not expired.

**2. GitHub renumbered Pages.** An apex domain cannot be a CNAME, so the DNS
zone points `team2053.org` at eight fixed GitHub addresses:

```
A     185.199.108.153
A     185.199.109.153
A     185.199.110.153
A     185.199.111.153
AAAA  2606:50c0:8000::153
AAAA  2606:50c0:8001::153
AAAA  2606:50c0:8002::153
AAAA  2606:50c0:8003::153
```

If GitHub ever changes them the site goes dark with no warning anywhere.
GitHub publishes the current set under "Configuring an apex domain" in
[Managing a custom domain for your GitHub Pages site](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site).
Compare it against the eight records in the NameSilo zone and correct any that
differ. (`www.team2053.org` is a CNAME to `frc2053.github.io` and is not
affected by this.)

**3. The `frc2053` organization lost its owners.** This repository and the
Pages site that serves it belong to the `frc2053` GitHub organization, which
has two owners on purpose so that losing one is survivable: Drew Williams,
dormant, and the `str-coder` machine account, whose recovery material is
described under **Credentials** above. Regaining either one restores control of
the site. The contents of the site are the markdown files in this repository
regardless, and they are readable by anyone.
