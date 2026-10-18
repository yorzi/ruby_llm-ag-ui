#!/usr/bin/env python3
"""Check rendered local links in all documentation channels, without a server."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import sys

site = Path(sys.argv[1] if len(sys.argv) > 1 else 'docs/_site').resolve()
config = Path('docs/_config.yml').read_text()
origin = re.search(r'^url:\s*(\S+)', config, re.M).group(1).strip('\"\'')
host = urlsplit(origin).netloc


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        if tag in ('a', 'link', 'script', 'img'):
            for key in ('href', 'src'):
                if key in attrs:
                    self.links.append(attrs[key])


pages = {}
for file in site.rglob('*.html'):
    page = Links()
    page.feed(file.read_text())
    pages[file] = page
if not pages:
    raise SystemExit('No rendered documentation. Run docs/bin/build.sh first.')
errors, checked = [], 0
for file, page in pages.items():
    for link in page.links:
        uri = urlsplit(link)
        if uri.scheme and uri.scheme not in ('http', 'https'):
            continue
        if uri.netloc and uri.netloc != host:
            continue
        path = unquote(uri.path)
        target = (site / path.lstrip('/') if path.startswith('/') else file.parent / path).resolve() if path else file
        if target.is_dir():
            target /= 'index.html'
        checked += 1
        if not target.is_relative_to(site) or not target.is_file():
            errors.append(f'{file.relative_to(site)}: missing {link}')
        elif uri.fragment and uri.fragment.lower() != 'top' and target in pages and unquote(uri.fragment) not in pages[target].ids:
            errors.append(f'{file.relative_to(site)}: missing anchor {link}')
for error in errors[:30]:
    print(error)
print(f'DOC_LINKS: {checked} links in {len(pages)} pages, {len(errors)} errors')
raise SystemExit(bool(errors))
