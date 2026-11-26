#!/usr/bin/env python3
"""Builds the Dozer website into ./public from the fragments in ./src.

Every page gets the same header, footer and icon sprite. Docs pages also get
the sidebar, an "On this page" list built from their <h2> headings, and
prev/next links.

    python3 website/build.py          # writes website/public/**/index.html
    npx -y wrangler@4.166.0 deploy    # from the repo root
"""
import html
import re
from pathlib import Path

ROOT = Path(__file__).parent
SRC = ROOT / "src"
OUT = ROOT / "public"

SITE = "https://dozer.shakatec.co.za"
REPO = "https://github.com/sekophungula/Dozer"
DMG = f"{REPO}/releases/latest/download/Dozer.dmg"
VERSION = "1.6.0"

# (path, source fragment, nav key, title, description)
PAGES = [
    ("", "home.html", "home", "Dozer: keep your Mac awake while your work runs",
     "Dozer is a free macOS menu bar app that keeps your Mac awake while exports, renders, downloads, builds and AI agents run, then lets it sleep the moment they're done."),
    ("watches/", "watches.html", "watches", "What Dozer watches",
     "The apps, transfers, terminal commands and AI agents that keep your Mac awake with Dozer."),
    ("changelog/", "changelog.html", "changelog", "Changelog · Dozer",
     "Every Dozer release: new features, improvements and fixes."),
    ("download/", "download.html", "download", "Download Dozer",
     "Download Dozer for macOS, or build it from source."),
]

# Docs, in sidebar order: (group, slug, title, blurb)
DOCS = [
    ("Start here", "", "What is Dozer?", "A menu bar app that keeps your Mac awake exactly as long as your work runs."),
    ("Start here", "install", "Install", "Download, allow it once, and pick what to watch."),
    ("Start here", "menu-bar", "The menu bar", "What the eye means and what each switch does."),
    ("What it watches", "apps", "Apps", "Final Cut Pro, Premiere, Blender and other apps while they export, render or build."),
    ("What it watches", "downloads", "Downloads & uploads", "Big file transfers, cloud syncs and backups."),
    ("What it watches", "terminal", "Terminal & CLI agents", "Commands and agents running in any terminal."),
    ("What it watches", "claude-code", "Claude Code", "Exact start and stop through Claude Code hooks."),
    ("Using Dozer", "settings", "Settings", "Keep-awake, display, grace period and notifications."),
    ("Using Dozer", "control-center", "Control Center & login", "Put the toggle where you want it and start with your Mac."),
    ("Using Dozer", "updates", "Updates", "How Dozer updates itself."),
    ("Help", "troubleshooting", "Troubleshooting", "Fixes for common problems."),
    ("Help", "how-it-works", "How it works", "What Dozer checks, and what it changes on your Mac."),
    ("Help", "build-from-source", "Build from source", "Compile Dozer yourself."),
]

# Eye icons match the menu bar icons in the app.
SPRITE = """<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <defs><clipPath id="eye-open"><path d="M1.8 6.84C5.69 13.32 12.31 13.32 16.2 6.84Z"/></clipPath></defs>
  <symbol id="eye-dozing" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-linecap="round">
    <path d="M1.8 6.84C5.69 13.32 12.31 13.32 16.2 6.84" stroke-width="1.98"/>
    <path d="M4.54 9.83L3.65 12.71M9 11.7V14.58M13.46 9.83L14.35 12.71" stroke-width="1.68"/>
  </symbol>
  <symbol id="eye-awake" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-linecap="round">
    <circle cx="9" cy="6.84" r="3.24" fill="currentColor" stroke="none" clip-path="url(#eye-open)"/>
    <path d="M1.8 6.84C5.69 13.32 12.31 13.32 16.2 6.84" stroke-width="1.98"/>
    <path d="M1.26 6.84H16.74" stroke-width="2.18"/>
    <path d="M4.54 9.83L3.65 12.71M9 11.7V14.58M13.46 9.83L14.35 12.71" stroke-width="1.68"/>
  </symbol>
  <symbol id="i-dl" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12M7 10l5 5 5-5M5 21h14"/></symbol>
  <symbol id="i-gh" viewBox="0 0 24 24" fill="currentColor"><path d="M12 .5a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2.2c-3.3.7-4-1.4-4-1.4-.6-1.4-1.4-1.8-1.4-1.8-1.1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1.1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.8-1.6-2.7-.3-5.5-1.3-5.5-5.9 0-1.3.5-2.4 1.2-3.2-.1-.3-.5-1.5.1-3.2 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.6 18.3 5 18.3 5c.7 1.7.2 2.9.1 3.2.8.8 1.2 1.9 1.2 3.2 0 4.6-2.8 5.6-5.5 5.9.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A12 12 0 0 0 12 .5z"/></symbol>
  <symbol id="i-arrow" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></symbol>
  <symbol id="i-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></symbol>
  <symbol id="i-check" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></symbol>
  <symbol id="i-app" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="4"/><path d="M10 8.5v7l5.5-3.5z"/></symbol>
  <symbol id="i-net" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 4v14M4 14l4 4 4-4M16 20V6M12 10l4-4 4 4"/></symbol>
  <symbol id="i-term" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M7 9l3 3-3 3M13 15h4"/></symbol>
  <symbol id="i-spark" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5L18 18M6 18l2.5-2.5M15.5 8.5L18 6"/></symbol>
</svg>"""


def header(active: str) -> str:
    def link(href, key, label):
        cls = ' class="on"' if key == active else ""
        return f'<a href="{href}"{cls}>{label}</a>'
    return f"""
{SPRITE}

<header class="nav">
  <div class="container">
    <div class="nav-left">
      <a class="brand" href="/"><img src="/assets/icon-512.png" alt="">Dozer</a>
      <nav class="nav-links">
        {link("/docs/", "docs", "Docs")}
        {link("/watches/", "watches", "What it watches")}
        {link("/changelog/", "changelog", "Changelog")}
        {link("/download/", "download", "Download")}
      </nav>
    </div>
    <div class="nav-right">
      <a class="gh" href="{REPO}"><svg><use href="#i-gh"/></svg><span>GitHub</span></a>
      <a class="btn btn-light" href="/download/"><svg><use href="#i-dl"/></svg>Download</a>
    </div>
  </div>
</header>"""


FOOTER = f"""
<footer>
  <div class="container">
    <div class="foot">
      <div><a class="brand" href="/"><img src="/assets/icon-512.png" alt="">Dozer</a><p>Keeps your Mac awake while your work runs. Free and open source for macOS.</p></div>
      <div><h4>Product</h4><ul><li><a href="/download/">Download</a></li><li><a href="/watches/">What it watches</a></li><li><a href="/changelog/">Changelog</a></li></ul></div>
      <div><h4>Docs</h4><ul><li><a href="/docs/">What is Dozer?</a></li><li><a href="/docs/install/">Install</a></li><li><a href="/docs/troubleshooting/">Troubleshooting</a></li></ul></div>
      <div><h4>Community</h4><ul><li><a href="{REPO}">GitHub</a></li><li><a href="{REPO}/issues">Report an issue</a></li><li><a href="{REPO}/blob/main/LICENSE">MIT License</a></li></ul></div>
    </div>
    <div class="legal"><span>© 2026 <a href="https://shakatec.co.za">ShakaTec</a>. Not affiliated with Anthropic.</span><span>v{VERSION}</span></div>
  </div>
</footer>"""

SCRIPT = """
<script>
  document.querySelectorAll('[data-copy]').forEach(function (b) {
    b.addEventListener('click', function () {
      var t = b.parentNode.querySelector('code').textContent;
      if (!navigator.clipboard) return;
      navigator.clipboard.writeText(t).then(function () { b.textContent = 'Copied'; setTimeout(function () { b.textContent = 'Copy'; }, 1500); });
    });
  });
  var q = document.querySelector('[data-docsearch]');
  if (q) q.addEventListener('input', function () {
    var v = q.value.toLowerCase();
    document.querySelectorAll('.docs-nav a').forEach(function (a) { a.hidden = v && a.textContent.toLowerCase().indexOf(v) < 0; });
  });
</script>"""

EXTERNAL_LINK = re.compile(r'<a\b([^>]*?)\bhref="(https?://[^"]+)"([^>]*)>')


def external_links(doc: str) -> str:
    """Links that leave the site open in a new tab, except direct downloads."""
    def fix(m):
        before, href, after = m.groups()
        attrs = before + after
        if "dozer.shakatec.co.za" in href or href.endswith((".dmg", ".zip")) or "target=" in attrs:
            return m.group(0)
        return f'<a{before}href="{href}"{after} target="_blank" rel="noopener">'
    return EXTERNAL_LINK.sub(fix, doc)


def page(title, desc, active, body, url):
    return external_links(f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc)}">
<link rel="canonical" href="{SITE}/{url}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Dozer">
<meta property="og:title" content="{html.escape(title)}">
<meta property="og:description" content="{html.escape(desc)}">
<meta property="og:image" content="{SITE}/assets/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Dozer: keeps your Mac awake while your work runs">
<meta property="og:url" content="{SITE}/{url}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="{SITE}/assets/og.png">
<meta name="theme-color" content="#08090a">
<link rel="icon" type="image/svg+xml" href="/assets/favicon.svg">
<link rel="icon" type="image/png" href="/assets/favicon.png">
<link rel="apple-touch-icon" href="/assets/icon-512.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/styles.css">
</head>
<body>{header(active)}
{body}
{FOOTER}
{SCRIPT}
</body>
</html>
""")


def fill(text: str) -> str:
    return text.replace("{{DMG}}", DMG).replace("{{REPO}}", REPO).replace("{{VERSION}}", VERSION)


def slugify(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r"<[^>]+>", "", s).lower()).strip("-")


def docs_page(i: int) -> str:
    group, slug, title, blurb = DOCS[i]
    content = fill((SRC / "docs" / f"{slug or 'index'}.html").read_text())

    # Give every <h2> an id and collect them for "On this page".
    toc = []
    def add_id(m):
        text = m.group(1)
        hid = slugify(text)
        toc.append((hid, re.sub(r"<[^>]+>", "", text)))
        return f'<h2 id="{hid}">{text}</h2>'
    content = re.sub(r"<h2>(.*?)</h2>", add_id, content)

    nav, last = [], None
    for g, s, t, _ in DOCS:
        if g != last:
            nav.append(f"<h4>{g}</h4>")
            last = g
        on = ' class="on"' if s == slug else ""
        nav.append(f'<a href="/docs/{s + "/" if s else ""}"{on}>{html.escape(t)}</a>')

    prev_l = next_l = ""
    if i > 0:
        p = DOCS[i - 1]
        prev_l = f'<a class="pn" href="/docs/{p[1] + "/" if p[1] else ""}"><small>← Previous</small>{html.escape(p[2])}</a>'
    if i < len(DOCS) - 1:
        n = DOCS[i + 1]
        next_l = f'<a class="pn next" href="/docs/{n[1]}/"><small>Next →</small>{html.escape(n[2])}</a>'

    toc_html = "".join(f'<a href="#{h}">{t}</a>' for h, t in toc)
    edit = f"{REPO}/edit/main/website/src/docs/{slug or 'index'}.html"
    body = f"""
<main class="container">
  <div class="docs">
    <aside class="docs-side">
      <input class="docs-search" type="search" placeholder="Search docs" aria-label="Search docs" data-docsearch>
      <nav class="docs-nav">{''.join(nav)}</nav>
    </aside>
    <article class="docs-body">
      <span class="eyebrow">{group}</span>
      <h1>{html.escape(title)}</h1>
      <p class="docs-lead">{blurb}</p>
      <div class="prose">{content}</div>
      <div class="pn-row">{prev_l}{next_l}</div>
      <a class="edit" href="{edit}">Edit this page on GitHub →</a>
    </article>
    <aside class="docs-toc">{'<h4>On this page</h4>' + toc_html if toc else ''}</aside>
  </div>
</main>"""
    return page(f"{title} · Dozer Docs", blurb, "docs", body, f"docs/{slug + '/' if slug else ''}")


def main():
    for path, src, key, title, desc in PAGES:
        body = fill((SRC / src).read_text())
        out = OUT / path / "index.html"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(page(title, desc, key, body, path))
        print("wrote", out.relative_to(ROOT))
    for i, d in enumerate(DOCS):
        out = OUT / "docs" / d[1] / "index.html"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(docs_page(i))
        print("wrote", out.relative_to(ROOT))
    nf = page("Not found · Dozer", "This page doesn't exist.", "", fill((SRC / "404.html").read_text()), "404")
    (OUT / "404.html").write_text(nf)
    print("wrote public/404.html")


if __name__ == "__main__":
    main()
