#!/usr/bin/env python3
"""Builds the JumpKey website into site-dist/.

Home page: docs/index.html. Guides: site/content/<slug>.html (article body only), wrapped in
one shared template with nav, related links, call to action, footer, canonical URL and JSON-LD.
Also writes /guides/ (the hub), sitemap.xml, robots.txt and 404.html.

    python3 Scripts/build-site.py https://jumpkey.patrickfreyer.com
"""
import hashlib, html, json, re, shutil, sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "site-dist"
PLACEHOLDER = "https://patrickfreyer.github.io/JumpKey"   # used in docs/index.html
DOWNLOAD = "https://github.com/patrickfreyer/JumpKey/releases/latest/download/JumpKey.zip"
REPO = "https://github.com/patrickfreyer/JumpKey"
UPDATED = "2026-11-25"

# One main search per page. Order = hub order.
PAGES = [
    dict(slug="find-files-on-mac",
         title="How to find a file or folder on Mac: 6 quick ways",
         h1="How to find a file or folder on Mac",
         description="Six ways to find any file or folder on a Mac, from Spotlight and Finder search to Go to Folder, Recents, Terminal and a frecency launcher.",
         blurb="Spotlight, Finder search, Go to Folder, Recents, Terminal and JumpKey, with the shortcut for each.",
         related=["spotlight-not-finding-files", "raycast-vs-alfred", "alfred-alternative"]),
    dict(slug="raycast-vs-alfred",
         title="Raycast vs Alfred vs Spotlight: which Mac launcher to use",
         h1="Raycast vs Alfred vs Spotlight",
         description="A fair comparison of Raycast, Alfred and the macOS 26 Spotlight: price, file search, menu search, clipboard, snippets and extensions.",
         blurb="Price, file and menu search, clipboard history, snippets and extensions, side by side.",
         related=["raycast-alternative", "alfred-alternative", "find-files-on-mac"]),
    dict(slug="raycast-alternative",
         title="A free, open-source Raycast alternative for Mac",
         h1="A free, open-source Raycast alternative",
         description="When a lighter, open-source launcher can replace Raycast on a Mac, and when it can't: menus, windows, files, folders and plain-English search.",
         blurb="When a lighter, open-source launcher is enough, and when you still want Raycast.",
         related=["raycast-vs-alfred", "alfred-alternative", "find-files-on-mac"]),
    dict(slug="alfred-alternative",
         title="A free Alfred alternative for Mac with smarter folder search",
         h1="A free Alfred alternative for Mac",
         description="What Alfred's free version and Powerpack include, and where JumpKey differs: frecency file search, zoxide, windows and menu bar icons.",
         blurb="What Alfred's free version and Powerpack cover, and where JumpKey differs.",
         related=["raycast-vs-alfred", "raycast-alternative", "find-files-on-mac"]),
    dict(slug="spotlight-not-finding-files",
         title="Spotlight not finding files on Mac: 7 fixes to try",
         h1="Spotlight not finding files on your Mac?",
         description="Spotlight missing files or apps after a macOS update? Check indexing, settings and privacy exclusions, then rebuild the index from Settings or Terminal.",
         blurb="Check indexing and privacy exclusions, then rebuild the Spotlight index.",
         related=["find-files-on-mac", "raycast-vs-alfred", "raycast-alternative"]),
]
BY_SLUG = {p["slug"]: p for p in PAGES}
HUB = dict(slug="guides", title="Mac search guides: files, launchers and Spotlight",
           h1="Mac search guides",
           description="Guides to finding files and folders on a Mac, fixing Spotlight, and choosing between Raycast, Alfred, Spotlight and JumpKey.")


def esc(s):
    return html.escape(s, quote=True)


def nav():
    return f'''<nav><div class="wrap">
  <a class="brand" href="/"><img src="/icon-256.png" alt="" width="28" height="28">JumpKey</a>
  <div class="links">
    <a class="hide-s" href="/guides/">Guides</a>
    <a class="hide-s" href="{REPO}">GitHub</a>
    <a class="btn" href="{DOWNLOAD}">Download</a>
  </div>
</div></nav>'''


def footer():
    items = "".join(f'<li><a href="/{p["slug"]}/">{esc(p["h1"])}</a></li>' for p in PAGES)
    return f'''<footer><div class="wrap">
  <ul><li><a href="/">JumpKey</a></li><li><a href="/guides/">Guides</a></li>{items}</ul>
  <span>Free and open source (MIT) · <a href="{REPO}">GitHub</a></span>
</div></footer>'''


def cta():
    return f'''<aside class="cta">
  <img src="/icon-256.png" alt="JumpKey app icon" width="64" height="64">
  <div>
    <h2>Try JumpKey</h2>
    <p>Press <kbd>⌥</kbd> <kbd>Space</kbd> in any app to search its menus, your windows, menu bar icons, files and folders. Free and open source, macOS 26 or later.</p>
    <div class="row"><a class="btn" href="{DOWNLOAD}">Download for Mac</a><a class="btn ghost" href="/">How it works</a></div>
  </div>
</aside>'''


def faq_ld(body):
    """FAQPage from <details><summary>Q</summary><p>A</p></details> blocks, matching the visible text."""
    qa = re.findall(r"<details><summary>(.*?)</summary>\s*<p>(.*?)</p></details>", body, re.S)
    strip = lambda s: re.sub(r"<[^>]+>", "", s).strip()
    if not qa:
        return None
    return {"@context": "https://schema.org", "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": strip(q),
                            "acceptedAnswer": {"@type": "Answer", "text": strip(a)}} for q, a in qa]}


def page(site, css_v, slug, title, h1, description, body, crumbs, ld_extra=(), related=(), show_cta=True):
    url = f"{site}/{slug}/"
    ld = [{"@context": "https://schema.org", "@type": "Article", "headline": h1, "description": description,
           "dateModified": UPDATED, "mainEntityOfPage": url, "image": f"{site}/screenshot-dark.png",
           "author": {"@type": "Person", "name": "Patrick Freyer", "url": "https://patrickfreyer.com"},
           "publisher": {"@type": "Organization", "name": "JumpKey", "logo": {"@type": "ImageObject", "url": f"{site}/icon-256.png"}}},
          {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
              {"@type": "ListItem", "position": i + 1, "name": n, "item": f"{site}{u}"} for i, (n, u) in enumerate(crumbs)]}]
    ld += [x for x in ld_extra if x]
    crumb_html = " › ".join(f'<a href="{u}">{esc(n)}</a>' for n, u in crumbs[:-1]) + f" › {esc(crumbs[-1][0])}"
    rel = ""
    if related:
        rel = '<section class="related"><h2>Related guides</h2><ul>' + "".join(
            f'<li><a href="/{s}/">{esc(BY_SLUG[s]["h1"])}</a></li>' for s in related) + "</ul></section>"
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<meta name="description" content="{esc(description)}">
<link rel="canonical" href="{url}">
<meta property="og:type" content="article">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(description)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{site}/screenshot-dark.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/png" href="/icon-256.png">
<link rel="stylesheet" href="/assets/article.css?v={css_v}">
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
</head>
<body>
{nav()}
<main class="wrap">
<article>
  <p class="crumbs">{crumb_html}</p>
  <h1>{esc(h1)}</h1>
  <p class="meta">Updated {date.fromisoformat(UPDATED):%B %-d, %Y} · for macOS 26 and later</p>
{body}
</article>
{cta() if show_cta else ""}
{rel}
</main>
{footer()}
</body>
</html>
'''


def main():
    site = (sys.argv[1] if len(sys.argv) > 1 else "https://jumpkey.patrickfreyer.com").rstrip("/")
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "assets").mkdir(parents=True)
    css = (ROOT / "site/assets/article.css").read_bytes()
    (OUT / "assets/article.css").write_bytes(css)
    css_v = hashlib.sha256(css).hexdigest()[:8]
    for img in ["icon-256.png", "screenshot-dark.png"]:
        shutil.copy(ROOT / "docs" / img, OUT / img)

    home = (ROOT / "docs/index.html").read_text().replace(PLACEHOLDER, site)
    (OUT / "index.html").write_text(home)

    for p in PAGES:
        body = (ROOT / "site/content" / f'{p["slug"]}.html').read_text()
        crumbs = [("JumpKey", "/"), ("Guides", "/guides/"), (p["h1"], f'/{p["slug"]}/')]
        d = OUT / p["slug"]
        d.mkdir()
        (d / "index.html").write_text(page(site, css_v, p["slug"], p["title"], p["h1"], p["description"], body,
                                           crumbs, ld_extra=[faq_ld(body)], related=p["related"]))

    hub_body = '  <p class="lead">Practical guides to finding things on a Mac, fixing Spotlight, and picking a launcher. Each one is written for macOS 26 and checked against each app\'s own documentation.</p>\n  <ul class="guide-list">\n' + "".join(
        f'    <li><a href="/{p["slug"]}/">{esc(p["h1"])}</a><p>{esc(p["blurb"])}</p></li>\n' for p in PAGES) + "  </ul>"
    hub_ld = {"@context": "https://schema.org", "@type": "CollectionPage", "name": HUB["h1"], "url": f"{site}/guides/",
              "mainEntity": {"@type": "ItemList", "itemListElement": [
                  {"@type": "ListItem", "position": i + 1, "url": f'{site}/{p["slug"]}/', "name": p["h1"]} for i, p in enumerate(PAGES)]}}
    (OUT / "guides").mkdir()
    (OUT / "guides/index.html").write_text(page(site, css_v, "guides", HUB["title"], HUB["h1"], HUB["description"], hub_body,
                                                [("JumpKey", "/"), ("Guides", "/guides/")], ld_extra=[hub_ld]))

    notfound = page(site, css_v, "404", "Page not found | JumpKey", "Page not found",
                    "This page doesn't exist.", '  <p class="lead">This page doesn\'t exist. Try the <a href="/guides/">guides</a> or the <a href="/">home page</a>.</p>',
                    [("JumpKey", "/"), ("Not found", "/404/")])
    notfound = re.sub(r'<link rel="canonical"[^>]*>', '<meta name="robots" content="noindex">', notfound)
    (OUT / "404.html").write_text(notfound)

    urls = [f"{site}/", f"{site}/guides/"] + [f'{site}/{p["slug"]}/' for p in PAGES]
    (OUT / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
                                     "".join(f"  <url><loc>{u}</loc><lastmod>{UPDATED}</lastmod></url>\n" for u in urls) + "</urlset>\n")
    (OUT / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {site}/sitemap.xml\n")
    (OUT / "_headers").write_text("/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n"
                                  "  Permissions-Policy: camera=(), microphone=(), geolocation=()\n")
    print(f"Built {len(urls)} pages into {OUT.relative_to(ROOT)} for {site}")


if __name__ == "__main__":
    main()
