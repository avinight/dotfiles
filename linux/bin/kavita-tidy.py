#!/usr/bin/env python3
"""Nightly tidy for the Kavita book libraries.

Makes Filebrowser/manual uploads foolproof so Kavita shows clean series names:
  1. RENAME badly-named drops via a LOCAL LLM (ollama). A file whose name
     doesn't already look like "Author - Title" is sent (its embedded metadata
     + first-page text) to a local model, which returns author/title/edition;
     we rename to the Library convention "Author - Title (Nth Ed).ext". Cheap:
     only non-conforming files hit the LLM, it's a local model, temp 0, and the
     prompt is truncated. Nothing leaves the machine.
  2. FOLDERIZE: each loose book file is moved into its own folder (Kavita
     series = leaf folder name). Sheet Music is excluded (managed by hand).
  3. STRIP EMBEDDED TITLES: any PDF still carrying an embedded /Title, /Subject
     or XMP gets it stripped with pikepdf (embedded Title overrides the folder
     name in Kavita). Idempotent — clean PDFs are left untouched.

Kavita mounts these folders read-only; this script is the only writer besides you.
"""
import os, re, sys, json, shutil, subprocess, urllib.request

LIB = "/home/friedrice/Documents/Library"
READING = "/home/friedrice/Documents/Reading"
BOOK_EXT = {".pdf", ".epub", ".djvu", ".mobi", ".azw3", ".cbz"}

OLLAMA = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
MODEL = os.environ.get("KAVITA_TIDY_MODEL", "qwen2.5:1.5b")

# A name already "looks like the convention" if it has an " - " author/title split.
CONVENTION = re.compile(r"^.+\s-\s.+$")

def stem(fn):
    return os.path.splitext(fn)[0]

def folderize_targets():
    targets = [READING]
    for name in sorted(os.listdir(LIB)):
        p = os.path.join(LIB, name)
        if not os.path.isdir(p) or name.startswith((".", "_")):
            continue
        if name == "music":
            tb = os.path.join(p, "Textbooks")
            if os.path.isdir(tb):
                targets.append(tb)
        else:
            targets.append(p)
    return targets

def pdf_text_head(path, chars=3000):
    try:
        out = subprocess.run(["pdftotext", "-f", "1", "-l", "3", path, "-"],
                             capture_output=True, text=True, timeout=60)
        return re.sub(r"\s+", " ", out.stdout)[:chars]
    except Exception:
        return ""

def pdf_meta(path):
    try:
        import pikepdf
        with pikepdf.open(path) as pdf:
            di = pdf.docinfo or {}
            return (str(di.get("/Title", "")), str(di.get("/Author", "")))
    except Exception:
        return ("", "")

def sanitize(s):
    s = re.sub(r'[/\\:\n\r\t]', " ", s).strip()
    s = re.sub(r"\s{2,}", " ", s)
    return s.strip(" .")

def llm_name(path):
    """Ask the local LLM for Author/Title/Edition. Returns a clean stem or None."""
    ext = os.path.splitext(path)[1].lower()
    title, author = pdf_meta(path) if ext == ".pdf" else ("", "")
    text = pdf_text_head(path) if ext == ".pdf" else ""
    if not text and not title:
        return None  # nothing to go on (e.g. epub/djvu with no extractable hint)
    prompt = (
        "You identify a book from its title page. Respond with ONLY a JSON object "
        '{"author":"","title":"","edition":""}. Rules:\n'
        "- title: the MAIN title only (plus a short subtitle after a colon if present). "
        "Max ~80 characters. Do NOT include 'Edited by', editor names, university or "
        "publisher names, affiliations, city, year, or copyright text.\n"
        "- author: up to three authors as natural 'First Last' names joined by ', ' with "
        "a final ' & '. If more than three, use 'First Last et al.'. Empty if unknown.\n"
        "- edition: like '3rd Ed', or '' if none.\n"
        "- If this is clearly NOT a book (a form, worksheet, exam, notes), return empty strings.\n\n"
        f"Embedded metadata title: {title!r}\nEmbedded metadata author: {author!r}\n"
        f"First-page text:\n{text}\n"
    )
    try:
        req = urllib.request.Request(
            f"{OLLAMA}/api/generate",
            data=json.dumps({"model": MODEL, "prompt": prompt, "stream": False,
                             "format": "json", "options": {"temperature": 0}}).encode(),
            headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=180) as r:
            resp = json.load(r)
        data = json.loads(resp.get("response", "{}"))
    except Exception as e:
        print(f"  LLM skip ({e})", file=sys.stderr)
        return None
    author = sanitize(data.get("author", ""))
    title = sanitize(data.get("title", ""))
    edition = sanitize(data.get("edition", ""))
    # Cut common title-page cruft the model sometimes appends to the title.
    title = re.split(r"\s+(?:Edited by|edited by|Edition\b)", title)[0].strip(" .,:")
    if not title:
        return None  # not confident / not a book -> leave name as-is
    # Guardrails: reject a suspicious extraction and fall back to the original name.
    BANNED = ("university", "copyright", "printed", "publish", "press ", "www.", "@",
              "hebrew", "stanford", "@gmail", "chegg")
    low = (title + " " + author).lower()
    if (len(title) > 90 or len(author) > 80 or any(b in low for b in BANNED)):
        print(f"  LLM result rejected (looks unclean): {author!r} / {title!r}", file=sys.stderr)
        return None
    name = f"{author} - {title}" if author else title
    if edition:
        name += f" ({edition})"
    name = sanitize(name)
    return name if len(name) <= 150 else None

def unique(dirpath, name, ext):
    cand = os.path.join(dirpath, name + ext)
    i = 2
    while os.path.exists(cand):
        cand = os.path.join(dirpath, f"{name} ({i}){ext}")
        i += 1
    return cand

def folderize():
    moved = renamed = 0
    for d in folderize_targets():
        if not os.path.isdir(d):
            continue
        for f in list(os.listdir(d)):
            src = os.path.join(d, f)
            if not os.path.isfile(src):
                continue
            ext = os.path.splitext(f)[1].lower()
            if ext not in BOOK_EXT:
                continue
            base = stem(f)
            # LLM-rename only if the name doesn't already follow the convention
            if not CONVENTION.match(base):
                newname = llm_name(src)
                if newname and newname != base:
                    base = newname
                    renamed += 1
                    print(f"renamed: {f} -> {base}{ext}")
            folder = os.path.join(d, base)
            os.makedirs(folder, exist_ok=True)
            dst = unique(folder, base, ext)
            shutil.move(src, dst)
            print(f"folderized: {os.path.relpath(dst, LIB)}")
            moved += 1
    return moved, renamed

def strip_titles():
    import pikepdf
    stripped = 0
    for root in (LIB, READING):
        for dp, _, files in os.walk(root):
            for f in files:
                if not f.lower().endswith(".pdf"):
                    continue
                path = os.path.join(dp, f)
                try:
                    with pikepdf.open(path, allow_overwriting_input=True) as pdf:
                        di = pdf.docinfo
                        has_di = di is not None and ("/Title" in di or "/Subject" in di)
                        has_xmp = "/Metadata" in pdf.Root
                        if not (has_di or has_xmp):
                            continue
                        if has_di:
                            for k in ("/Title", "/Subject"):
                                if k in di:
                                    del di[k]
                        if has_xmp:
                            del pdf.Root.Metadata
                        pdf.save(path)
                        stripped += 1
                except Exception as e:
                    print(f"WARN could not process {path}: {e}", file=sys.stderr)
    return stripped

def main():
    print("=== kavita-tidy start ===")
    m, r = folderize()
    s = strip_titles()
    print(f"=== kavita-tidy done: {m} folderized ({r} LLM-renamed), {s} PDFs stripped ===")

if __name__ == "__main__":
    main()
