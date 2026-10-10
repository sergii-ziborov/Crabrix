#!/usr/bin/env python3
"""Export canonical website legal copy and repository licenses for offline use.

Only the <main> body is exported. Contact buttons become the same support URL;
relative links become absolute. Original third-party texts are never rewritten.
Run --check before an archive or website release to detect stale copies.
"""
import argparse
import hashlib
import json
import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin

ROOT = Path(__file__).resolve().parents[1]
UPDATED = "2026-10-10"


class Node:
    def __init__(self, tag="", attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []


class Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node()
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in {"br", "img", "hr", "input", "meta", "link"}:
            self.stack.append(node)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                self.stack = self.stack[:i]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def inline(node):
    if isinstance(node, str):
        return re.sub(r"\s+", " ", node)
    value = "".join(inline(child) for child in node.children)
    if node.tag == "code":
        return "`" + value.strip() + "`"
    if node.tag in {"strong", "b"}:
        return "**" + value.strip() + "**"
    if node.tag in {"em", "i"}:
        return "*" + value.strip() + "*"
    if node.tag == "a":
        return f'[{value.strip()}]({urljoin("https://crabrix.com/", node.attrs["href"])})'
    if node.tag == "button" and "data-mail" in node.attrs:
        return f'[{value.strip()}](https://crabrix.com/support/)'
    return value


def blocks(node):
    if isinstance(node, str):
        return []
    if node.tag in {"h1", "h2", "h3", "p", "li"}:
        return [{"kind": node.tag, "text": inline(node).strip()}]
    # About's feature cards have prose directly inside a div.
    if node.tag == "div" and any(isinstance(c, Node) and c.tag == "strong" for c in node.children):
        return [{"kind": "p", "text": inline(node).strip()}]
    return [block for child in node.children for block in blocks(child)]


def outputs():
    documents = []
    for slug, title in [("about", "About Crabrix"), ("privacy", "Privacy Policy"), ("terms", "Terms of Use")]:
        source = (ROOT / f"site/{slug}.html").read_text()
        main = re.search(r"<main>(.*?)</main>", source, re.S)
        if not main:
            raise ValueError(f"Missing main in {slug}")
        tree = Tree()
        tree.feed(main[1])
        exported = [b for b in blocks(tree.root) if b["text"] and b["kind"] != "h1"]
        documents.append({"id": slug, "title": title, "updated": UPDATED,
                          "sourceURL": f"https://crabrix.com/{slug}/", "blocks": exported})
    for slug, title, source in [("source-license", "Application source license", "LICENSE"),
                                ("content-license", "Educational content rights", "CONTENT-LICENSE.md")]:
        documents.append({"id": slug, "title": title, "updated": UPDATED,
                          "sourceURL": "https://crabrix.com/licenses/",
                          "blocks": [{"kind": "pre", "text": (ROOT / source).read_text().strip()}]})
    generated = {ROOT / "Crabrix/Resources/LegalDocuments.json": json.dumps(documents, indent=2, ensure_ascii=False) + "\n"}
    for d in documents:
        paragraphs = []
        for b in d["blocks"]:
            prefix = {"h2": "## ", "h3": "### ", "li": "- "}.get(b["kind"], "")
            paragraphs.append(prefix + b["text"])
        generated[ROOT / f'docs/legal/{d["id"]}.md'] = f'# {d["title"]}\n\nUpdated: {d["updated"]} · [Website copy]({d["sourceURL"]})\n\n' + "\n\n".join(paragraphs) + "\n"
    generated[ROOT / "site/content/legal-documents.json"] = generated[ROOT / "Crabrix/Resources/LegalDocuments.json"]
    notices = (ROOT / "Crabrix/Resources/ThirdPartyNotices.md").read_text()
    generated[ROOT / "site/public/licenses/ThirdPartyNotices.md"] = notices
    for path in (ROOT / "Crabrix/Resources/Licenses").glob("*.txt"):
        generated[ROOT / "site/public/licenses" / path.name] = path.read_text()
    catalog = (ROOT / "Crabrix/UI/LicensesView.swift").read_text().split("static let all:", 1)[1].split("static func text", 1)[0]
    entries = []
    for match in re.finditer(r'BundledLicense\(\s*id: "([^"]+)",\s*name: "([^"]+)",\s*summary: "([^"]+)",\s*documents: \[([^\]]+)\]', catalog):
        entries.append({"id": match[1], "name": match[2], "summary": match[3],
                        "documents": re.findall(r'"([^"]+)"', match[4])})
    pins = json.loads((ROOT / "Dependencies/Package.resolved").read_text())["pins"]
    for pin in pins:
        identity = {"crabrix-runtime": "WasmKit", "zipfoundation": "ZIPFoundation"}.get(pin["identity"], pin["identity"])
        entry = next(e for e in entries if e["id"] == identity)
        if "version" in pin["state"] and pin["state"]["version"] not in entry["name"]:
            raise ValueError(f"License catalog does not match resolved version: {identity}")
    generated[ROOT / "site/content/license-index.json"] = json.dumps(entries, indent=2) + "\n"
    provenance = json.loads((ROOT / "docs/legal/toolchain-notice-provenance.json").read_text())
    for original, bundled in [("licenses.zip", "ToolchainLicenses.zip"), ("vendor-notices.zip", "ToolchainVendorNotices.zip")]:
        data = (ROOT / "Crabrix/Resources/Licenses" / bundled).read_bytes()
        expected = provenance["files"][original]
        if len(data) != expected["bytes"] or hashlib.sha256(data).hexdigest() != expected["sha256"]:
            raise ValueError(f"Pinned notice archive changed: {bundled}")
        generated[ROOT / "site/public/licenses" / bundled] = data
    return generated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    for path, content in outputs().items():
        existing = (path.read_bytes() if isinstance(content, bytes) else path.read_text()) if path.exists() else None
        if existing != content:
            if args.check:
                stale.append(str(path.relative_to(ROOT)))
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                if isinstance(content, bytes):
                    path.write_bytes(content)
                else:
                    path.write_text(content)
    if stale:
        raise SystemExit("Stale legal copies; run scripts/sync_legal_documents.py:\n" + "\n".join(stale))
    print("Legal copies match website and repository sources." if args.check else "Legal copies synchronized.")


if __name__ == "__main__":
    main()
