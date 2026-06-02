#!/usr/bin/env python3
"""Deterministically convert Workday Revenue Management v46.1 operation-detail HTML
pages into field-level markdown references. No LLM, no truncation: parses the raw
HTML (incl. validation tables nested inside each field's Validations cell)."""
import re, html as H
from html.parser import HTMLParser

BASE = "https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1"
DATE = "2026-06-01"
SKIP_ANCHORS = {"webservice", "Request", "Response", "elements", "top"}

# ---------- nested table model ----------
class Cell:
    def __init__(self): self.parts = []          # list of str | Table
class Row:
    def __init__(self): self.cells = []; self.is_header = False
class Table:
    def __init__(self): self.rows = []

class TableParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tables, self.tstack, self.rstack, self.cstack = [], [], [], []
    def handle_starttag(self, tag, attrs):
        if tag == "table":
            t = Table()
            (self.cstack[-1].parts.append(t) if self.cstack else self.tables.append(t))
            self.tstack.append(t)
        elif tag == "tr" and self.tstack:
            r = Row(); self.tstack[-1].rows.append(r); self.rstack.append(r)
        elif tag in ("td", "th") and self.rstack:
            c = Cell(); self.rstack[-1].cells.append(c); self.cstack.append(c)
            if tag == "th": self.rstack[-1].is_header = True
        elif tag == "br" and self.cstack:
            self.cstack[-1].parts.append("\n")
    def handle_endtag(self, tag):
        if tag == "table" and self.tstack: self.tstack.pop()
        elif tag == "tr" and self.rstack: self.rstack.pop()
        elif tag in ("td", "th") and self.cstack: self.cstack.pop()
    def handle_data(self, data):
        if self.cstack: self.cstack[-1].parts.append(data)

def clean(s):
    s = H.unescape(s).replace("\xa0", " ")
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\s*\n\s*", "\n", s).strip()
    return s

def md_cell(text):
    return clean(text).replace("|", "\\|").replace("\n", "<br>")

def render_nested(t):
    """Render a nested table (e.g. Validation|Description) inline for a cell."""
    out = []
    for r in t.rows:
        if r.is_header: continue
        vals = [clean("".join(p for p in c.parts if isinstance(p, str))) for c in r.cells]
        vals = [v for v in vals if v]
        if vals: out.append(" — ".join(vals))
    return "<br>".join(out)

def cell_to_md(cell):
    buf = []
    for p in cell.parts:
        buf.append(p if isinstance(p, str) else "\n" + render_nested(p))
    return md_cell("".join(buf))

def render_table(t):
    rows = t.rows
    if not rows: return ""
    hdr = next((r for r in rows if r.is_header), None)
    body = [r for r in rows if r is not hdr]
    if hdr:
        headers = [clean("".join(p for p in c.parts if isinstance(p, str))) for c in hdr.cells]
    else:
        headers = [f"col{i+1}" for i in range(max(len(r.cells) for r in body))]
    ncol = len(headers)
    lines = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * ncol) + "|"]
    for r in body:
        cells = [cell_to_md(c) for c in r.cells]
        cells += [""] * (ncol - len(cells))
        lines.append("| " + " | ".join(cells[:ncol]) + " |")
    return "\n".join(lines)

def slug(name):
    return re.sub(r"[^\w\- ]", "", name.lower()).replace(" ", "-")

# ---------- section extraction ----------
SEC_RE = re.compile(
    r'<a name="([^"]+)">\s*&nbsp;\s*</a>\s*<h4 class="ws-title">(.*?)</h4>'
    r'(.*?)(?=<a name="[^"]+">\s*&nbsp;\s*</a>\s*<h4 class="ws-title">|<h3 class="ws-title">|\Z)',
    re.S)

def parse_page(html):
    sections = []
    for m in SEC_RE.finditer(html):
        anchor = m.group(1)
        if anchor in SKIP_ANCHORS:
            continue
        # Anchor is the reliable identifier: "<TypeName>Type" for data/reference types,
        # "<Name>ReferenceEnumeration" for enums. The h4 text is unreliable
        # (e.g. "Request Element: Submit_..._Request"), so derive the name from the anchor.
        name = anchor[:-4] if anchor.endswith("Type") else anchor
        body = m.group(3)
        preamble = body.split("<table", 1)[0]
        partof = []
        po_m = re.search(r'part of:(.*?)(?:<div|$)', preamble, re.S)
        if po_m:
            seen = set()
            for a in re.findall(r'<a [^>]*>(.*?)</a>', po_m.group(1)):
                nm = clean(re.sub(r"<[^>]+>", "", a)).strip().rstrip(",").strip()
                if nm and nm not in seen:
                    seen.add(nm); partof.append(nm)
        desc = ""
        for d in re.findall(r"<div>(.*?)</div>", preamble, re.S):
            dt = clean(re.sub(r"<[^>]+>", "", d))
            if dt and dt != "":
                desc = dt; break
        p = TableParser(); p.feed(body)
        tables = p.tables
        is_base = bool(tables and tables[0].rows and tables[0].rows[0].is_header and
                       [clean("".join(x for x in c.parts if isinstance(x, str))) for c in tables[0].rows[0].cells] == ["Base Type"])
        if is_base:
            cat = "enumeration"
        elif name.endswith("ObjectID") or name.endswith("Object"):
            cat = "reference"
        else:
            cat = "primary"
        sections.append(dict(anchor=anchor, name=name, partof=partof, desc=desc, tables=tables, cat=cat))
    return sections

def wsdl_links(html):
    out = {}
    for fn in re.findall(r'href="(Revenue_Management\.(?:wsdl|xsd))"', html):
        out[fn.split(".")[-1]] = f"{BASE}/{fn}"
    return out

def build(operation, purpose, fname):
    html = open(f"{fname}.html", encoding="utf-8", errors="replace").read()
    secs = parse_page(html)
    url = f"{BASE}/{fname}.html"
    links = wsdl_links(html)
    nprim = sum(1 for s in secs if s["cat"] == "primary")
    nref = sum(1 for s in secs if s["cat"] == "reference")
    nenum = sum(1 for s in secs if s["cat"] == "enumeration")
    names = {s["name"] for s in secs}

    L = []
    L.append(f"# {operation} — Workday Revenue Management API (v46.1)")
    L.append("")
    L.append(f"> **Operation:** `{operation}`  ")
    L.append(f"> **Purpose (per SC-3143):** {purpose}  ")
    L.append(f"> **Source:** {url}  ")
    if links:
        L.append(f"> **Schema:** [WSDL]({links.get('wsdl','')}) · [XSD]({links.get('xsd','')})  ")
    L.append(f"> **API version:** v46.1 (Workday Community public docs)  ")
    L.append(f"> **Extracted:** {DATE} — deterministic parse of the source HTML (fields + nested per-field validation rules; lossless).  ")
    L.append(f"> **Data types documented:** {len(secs)} ({nprim} primary, {nref} reference, {nenum} enumeration)")
    L.append("")
    L.append("## Data type index")
    L.append("")
    L.append("| # | Data type | Category |")
    L.append("|---|---|---|")
    for i, s in enumerate(secs, 1):
        L.append(f"| {i} | [{s['name']}](#{slug(s['name'])}) | {s['cat']} |")
    L.append("")
    L.append("---")
    L.append("")
    for s in secs:
        L.append(f"## {s['name']}")
        L.append("")
        meta = []
        if s["partof"]:
            meta.append("Part of: " + ", ".join(f"[{p}](#{slug(p)})" if p in names else p for p in s["partof"]))
        if s["desc"]:
            meta.append(s["desc"])
        if meta:
            L.append("*" + " — ".join(meta) + "*")
            L.append("")
        for t in s["tables"]:
            L.append(render_table(t))
            L.append("")
    return "\n".join(L), dict(total=len(secs), prim=nprim, ref=nref, enum=nenum)

PAGES = [
    ("Submit_Customer_Contract", "Contract Data", "Submit_Customer_Contract"),
    ("Submit_Billing_Schedule", "Billing Schedule Data", "Submit_Billing_Schedule"),
    ("Put_Multiple-Element_Revenue_Allocation", "Revenue Data (MEA)", "Put_Multiple-Element_Revenue_Allocation"),
]
OUT = "/Users/liamjeong/Documents/Code/Fortra/*Jira/sc3143(epic | integration)/workday-api-reference"
if __name__ == "__main__":
    for op, purpose, fn in PAGES:
        md, stats = build(op, purpose, fn)
        open(f"{OUT}/{fn}.md", "w", encoding="utf-8").write(md)
        print(f"{fn}.md  chars={len(md):>7}  types={stats['total']} (prim={stats['prim']} ref={stats['ref']} enum={stats['enum']})")
