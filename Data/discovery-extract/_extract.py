#!/usr/bin/env python3
"""Extract plain text from every text-bearing file in 'Fortra Discovery Documentation'.

Mirrors the source tree under Data/discovery-extract/text/, one .txt per source file.
Writes manifest.tsv summarizing status + extracted char count per file.

Handles: docx, pptx, xlsx, csv, txt, sql, json, url, rdl, drawio, vsdx (XML),
and shells out to pdftotext for pdf. Binary/opaque types (mp4, pbix, png, jpg, zip)
are recorded in the manifest with a note but not extracted here.
"""
import os, sys, csv, json, zipfile, subprocess, re, traceback
import xml.etree.ElementTree as ET

SRC = "Fortra Discovery Documentation"
OUT = "Data/discovery-extract/text"
MANIFEST = "Data/discovery-extract/manifest.tsv"

os.makedirs(OUT, exist_ok=True)

class EncryptedFile(Exception):
    pass

# ---------- helpers ----------
def strip_ns(tag):
    return tag.split('}')[-1] if '}' in tag else tag

def xml_all_text(data):
    """Return all text nodes from an XML byte string, space-joined, deduped of blanks."""
    try:
        root = ET.fromstring(data)
    except Exception:
        # try to recover by stripping a BOM / leading junk
        try:
            root = ET.fromstring(data.decode('utf-8', 'ignore'))
        except Exception:
            return None
    parts = []
    for el in root.iter():
        if el.text and el.text.strip():
            parts.append(el.text.strip())
    return parts

# ---------- per-format extractors ----------
def ex_docx(path):
    import docx
    d = docx.Document(path)
    out = []
    for p in d.paragraphs:
        t = p.text.strip()
        if t:
            out.append(t)
    for ti, tbl in enumerate(d.tables):
        out.append(f"\n[TABLE {ti+1}]")
        for row in tbl.rows:
            cells = [c.text.strip().replace("\n", " ") for c in row.cells]
            if any(cells):
                out.append(" | ".join(cells))
    return "\n".join(out)

def ex_pptx(path):
    """python-pptx not installed; parse slide XML directly + speaker notes."""
    out = []
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        slide_files = sorted(
            [n for n in names if re.match(r"ppt/slides/slide\d+\.xml$", n)],
            key=lambda n: int(re.search(r"(\d+)", n).group(1)))
        note_files = {int(re.search(r"(\d+)", n).group(1)): n
                      for n in names if re.match(r"ppt/notesSlides/notesSlide\d+\.xml$", n)}
        for sf in slide_files:
            num = int(re.search(r"(\d+)", sf).group(1))
            out.append(f"\n===== SLIDE {num} =====")
            txt = xml_all_text(z.read(sf))
            if txt:
                out.extend(txt)
            nf = note_files.get(num)
            if nf:
                notes = xml_all_text(z.read(nf))
                # filter out boilerplate placeholder numbers
                notes = [t for t in (notes or []) if not t.isdigit()]
                if notes:
                    out.append("[SPEAKER NOTES] " + " ".join(notes))
    return "\n".join(out)

def ex_xls_legacy(path, max_rows=400):
    """Legacy OLE2/BIFF .xls (mislabeled .xlsx) via xlrd<2.0."""
    import xlrd
    book = xlrd.open_workbook(path)
    out = []
    for sh in book.sheets():
        out.append(f"\n===== SHEET: {sh.name} ({sh.nrows}r x {sh.ncols}c) =====")
        n = 0
        for ri in range(sh.nrows):
            vals = []
            for ci in range(sh.ncols):
                v = sh.cell_value(ri, ci)
                if isinstance(v, float) and v == int(v):
                    v = int(v)
                vals.append("" if v == "" else str(v).strip().replace("\n", " "))
            if not any(vals):
                continue
            while vals and vals[-1] == "":
                vals.pop()
            out.append("\t".join(vals))
            n += 1
            if n >= max_rows:
                out.append(f"... [truncated at {max_rows} non-empty rows; sheet has {sh.nrows} rows]")
                break
    return "\n".join(out)

def _is_encrypted_ole(path):
    try:
        import olefile
        if not olefile.isOleFile(path):
            return False
        ole = olefile.OleFileIO(path)
        enc = ole.exists("EncryptionInfo") and ole.exists("EncryptedPackage")
        meta = {}
        try:
            si = ole.get_metadata()
            for k in ("title", "author", "last_saved_by", "create_time", "last_saved_time"):
                v = getattr(si, k, None)
                if v:
                    meta[k] = str(v)
        except Exception:
            pass
        ole.close()
        return ("ENCRYPTED", meta) if enc else False
    except Exception:
        return False

def ex_xlsx(path, max_rows=400):
    import openpyxl
    try:
        wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    except Exception:
        enc = _is_encrypted_ole(path)
        if enc:
            metastr = "; ".join(f"{k}={v}" for k, v in enc[1].items())
            raise EncryptedFile(metastr)
        # mislabeled legacy .xls
        return ex_xls_legacy(path, max_rows)
    out = []
    for ws in wb.worksheets:
        dims = f"{ws.max_row}r x {ws.max_column}c" if ws.max_row else "empty"
        out.append(f"\n===== SHEET: {ws.title} ({dims}) =====")
        n = 0
        for row in ws.iter_rows(values_only=True):
            vals = ["" if v is None else str(v).strip().replace("\n", " ") for v in row]
            if not any(vals):
                continue
            # trim trailing empties
            while vals and vals[-1] == "":
                vals.pop()
            out.append("\t".join(vals))
            n += 1
            if n >= max_rows:
                out.append(f"... [truncated at {max_rows} non-empty rows; sheet has {ws.max_row} rows]")
                break
    wb.close()
    return "\n".join(out)

def ex_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

def ex_csv(path):
    out = []
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as f:
        try:
            sample = f.read(4096); f.seek(0)
            dialect = csv.Sniffer().sniff(sample) if sample else csv.excel
        except Exception:
            dialect = csv.excel
        r = csv.reader(f, dialect)
        for i, row in enumerate(r):
            out.append("\t".join(c.strip() for c in row))
            if i >= 2000:
                out.append("... [csv truncated at 2000 rows]"); break
    return "\n".join(out)

def ex_json(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        try:
            data = json.load(f)
            return json.dumps(data, indent=2, ensure_ascii=False)
        except Exception:
            f.seek(0); return f.read()

def ex_xml_generic(path):
    with open(path, "rb") as f:
        data = f.read()
    parts = xml_all_text(data)
    if parts is None:
        return None
    return "\n".join(parts)

def ex_rdl(path):
    """SSRS report: pull dataset CommandText (SQL) + field names + all text."""
    with open(path, "rb") as f:
        data = f.read()
    out = []
    # CommandText (the SQL queries) - regex is robust to namespace soup
    for m in re.finditer(r"<CommandText>(.*?)</CommandText>", data.decode("utf-8", "ignore"), re.S):
        out.append("[QUERY]\n" + m.group(1).strip() + "\n")
    fields = re.findall(r'<Field Name="([^"]+)"', data.decode("utf-8", "ignore"))
    if fields:
        out.append("[FIELDS] " + ", ".join(sorted(set(fields))))
    txt = xml_all_text(data) or []
    # keep only human-ish text nodes (skip pure numbers/style tokens)
    human = [t for t in txt if len(t) > 1 and not re.fullmatch(r"[\d.\-pt#a-fA-F]+", t)]
    if human:
        out.append("\n[TEXT NODES]\n" + "\n".join(human[:400]))
    return "\n".join(out)

def ex_vsdx(path):
    out = []
    with zipfile.ZipFile(path) as z:
        pages = sorted([n for n in z.namelist() if re.match(r"visio/pages/page\d+\.xml$", n)])
        for p in pages:
            out.append(f"\n===== {p} =====")
            t = xml_all_text(z.read(p))
            if t:
                out.extend(t)
    return "\n".join(out)

def ex_drawio(path):
    # drawio xml may have base64-deflated <diagram>; try plain text first
    with open(path, "rb") as f:
        data = f.read()
    txt = data.decode("utf-8", "ignore")
    # extract any value="..." labels (uncompressed diagrams)
    labels = re.findall(r'value="([^"]+)"', txt)
    labels = [re.sub(r"<[^>]+>", " ", l).strip() for l in labels]
    labels = [l for l in labels if l]
    if labels:
        return "[NODE LABELS]\n" + "\n".join(labels)
    return "[drawio diagram is compressed; see the .pdf export of the same diagram]"

PDF_NOTE = None
def ex_pdf(path, outpath):
    # use pdftotext -layout; write directly to outpath
    r = subprocess.run(["pdftotext", "-layout", path, outpath],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, r.stderr.strip()[:200]
    try:
        with open(outpath, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        return len(content.strip()), None
    except Exception as e:
        return None, str(e)

OPAQUE = {"mp4": "video recording (no transcript tooling)",
          "pbix": "Power BI binary (model not text-extractable here)",
          "png": "image - read with vision tool",
          "jpg": "image - read with vision tool",
          "zip": "archive - inspect separately"}

EXTRACTORS = {
    "docx": ex_docx, "pptx": ex_pptx, "xlsx": ex_xlsx,
    "csv": ex_csv, "txt": ex_text, "sql": ex_text, "url": ex_text,
    "json": ex_json, "rdl": ex_rdl, "vsdx": ex_vsdx, "drawio": ex_drawio,
}

# ---------- walk ----------
rows = []
for dirpath, dirnames, filenames in os.walk(SRC):
    for fn in sorted(filenames):
        if fn.startswith("~$") or fn == ".DS_Store":
            continue
        src = os.path.join(dirpath, fn)
        rel = os.path.relpath(src, SRC)
        ext = fn.rsplit(".", 1)[-1].lower() if "." in fn else ""
        outpath = os.path.join(OUT, rel) + ".txt"
        os.makedirs(os.path.dirname(outpath), exist_ok=True)
        status, chars, note = "", 0, ""
        try:
            if ext == "pdf":
                chars, err = ex_pdf(src, outpath)
                if chars is None:
                    status, note = "ERROR", err or "pdftotext failed"
                else:
                    status = "ok" if chars > 20 else "empty(scanned?)"
            elif ext in EXTRACTORS:
                content = EXTRACTORS[ext](src)
                if content is None:
                    status, note = "ERROR", "extractor returned None"
                else:
                    with open(outpath, "w", encoding="utf-8") as f:
                        f.write(content)
                    chars = len(content.strip())
                    status = "ok" if chars > 0 else "empty"
            elif ext in OPAQUE:
                status, note = "skip-binary", OPAQUE[ext]
            else:
                status, note = "skip-unknown", f"no extractor for .{ext}"
        except EncryptedFile as e:
            status, note = "encrypted", f"password-protected; {e}"
            with open(outpath, "w", encoding="utf-8") as f:
                f.write(f"[ENCRYPTED / PASSWORD-PROTECTED WORKBOOK]\nMetadata: {e}\n"
                        f"Content cannot be extracted without the password.\n")
        except Exception as e:
            status, note = "ERROR", f"{type(e).__name__}: {e}"
            sys.stderr.write(f"ERR {rel}: {traceback.format_exc()[-300:]}\n")
        rows.append((status, str(chars), ext, rel, note))

with open(MANIFEST, "w", encoding="utf-8") as f:
    f.write("status\tchars\text\trelpath\tnote\n")
    for r in rows:
        f.write("\t".join(r) + "\n")

# summary to stdout
from collections import Counter
c = Counter(r[0] for r in rows)
print("=== EXTRACTION SUMMARY ===")
for k, v in sorted(c.items()):
    print(f"  {k}: {v}")
print(f"  total files: {len(rows)}")
errs = [r for r in rows if r[0] == "ERROR"]
if errs:
    print("=== ERRORS ===")
    for r in errs:
        print(f"  {r[3]} -> {r[4]}")
