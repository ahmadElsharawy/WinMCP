"""
WinMCP Universal File Engine
Provides high-speed, direct file analysis, reading, and editing for all major
file formats (Word, Excel, PowerPoint, PDF, CSV, ZIP, Text, Code, JSON)
without needing desktop UI apps, mouse movements, or screenshots.
"""

import os
import sys
import glob
import json
import csv
import zipfile
import datetime
from typing import Dict, Any, Optional, Tuple, List

# Ensure user site-packages are loaded
user_packages = glob.glob(r"C:\Users\*\AppData\Local\Python\*\Lib\site-packages") + glob.glob(r"C:\Users\*\AppData\Roaming\Python\*\site-packages")
for p in user_packages:
    if os.path.isdir(p) and p not in sys.path:
        sys.path.insert(0, p)


def resolve_file_path(raw_path: str) -> str:
    """Expands environment variables, user homes, active folders, and searches default folders if relative."""
    if not raw_path:
        return ""

    # First attempt smart contextual resolution (open folders, open docs, recent files)
    try:
        from gateway.context_engine import smart_resolve_resource
        smart = smart_resolve_resource(raw_path)
        if smart and os.path.exists(smart):
            return smart
    except Exception:
        try:
            import context_engine
            smart = context_engine.smart_resolve_resource(raw_path)
            if smart and os.path.exists(smart):
                return smart
        except Exception:
            pass

    expanded = os.path.expandvars(os.path.expanduser(str(raw_path).strip()))
    if os.path.isabs(expanded):
        return os.path.normpath(expanded)

    # If relative, check common user locations
    candidates = [
        os.path.normpath(os.path.join(os.getcwd(), expanded)),
        os.path.normpath(os.path.join(os.path.expanduser("~"), "Desktop", expanded)),
        os.path.normpath(os.path.join(os.path.expanduser("~"), "Downloads", expanded)),
        os.path.normpath(os.path.join(os.path.expanduser("~"), "Documents", expanded)),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    # Default to Desktop candidate
    return candidates[1]


def detect_file_encoding(path: str) -> str:
    """Detects encoding for text files with support for Arabic CP1256, UTF-8, and UTF-16."""
    try:
        with open(path, "rb") as f:
            raw = f.read(8192)
        if not raw:
            return "utf-8"

        # Check BOM
        if raw.startswith(b"\xef\xbb\xbf"):
            return "utf-8-sig"
        if raw.startswith(b"\xff\xfe"):
            return "utf-16-le"
        if raw.startswith(b"\xfe\xff"):
            return "utf-16-be"

        try:
            import charset_normalizer
            res = charset_normalizer.from_bytes(raw).best()
            if res and res.encoding:
                return res.encoding
        except Exception:
            pass

        # Try UTF-8 decode
        try:
            raw.decode("utf-8")
            return "utf-8"
        except UnicodeDecodeError:
            pass

        # Arabic Windows ANSI fallback
        return "cp1256"
    except Exception:
        return "utf-8"


# ==========================================
# Specialized Parsers
# ==========================================

def read_docx(path: str) -> Tuple[str, Dict[str, Any]]:
    import docx
    doc = docx.Document(path)
    lines = [f"# Word Document Content: {os.path.basename(path)}\n"]

    non_empty_p = [p.text.strip() for p in doc.paragraphs if p.text.strip()]
    if non_empty_p:
        lines.append(f"## Paragraphs ({len(non_empty_p)} non-empty):")
        for idx, p_text in enumerate(non_empty_p, 1):
            lines.append(f"[{idx}] {p_text}")
        lines.append("")

    if doc.tables:
        lines.append(f"## Tables ({len(doc.tables)} found):")
        for t_idx, table in enumerate(doc.tables, 1):
            lines.append(f"\n### [Table {t_idx}] ({len(table.rows)} rows x {len(table.columns)} cols):")
            for r_idx, row in enumerate(table.rows):
                row_cells = [c.text.replace("\n", " ").strip() for c in row.cells]
                seen = []
                for cell in row_cells:
                    if not seen or cell != seen[-1]:
                        seen.append(cell)
                lines.append(f"  Row {r_idx}: " + " | ".join(seen))

    meta = {"paragraphs_count": len(doc.paragraphs), "tables_count": len(doc.tables)}
    return "\n".join(lines).strip(), meta


def read_excel(path: str, max_rows_per_sheet: int = 100, target_sheet: str = None) -> Tuple[str, Dict[str, Any]]:
    import openpyxl
    wb = openpyxl.load_workbook(path, data_only=True, read_only=True)
    lines = [f"# Excel Workbook: {os.path.basename(path)}\n"]
    lines.append(f"Sheets: {', '.join(wb.sheetnames)}\n")

    sheet_names = [target_sheet] if (target_sheet and target_sheet in wb.sheetnames) else wb.sheetnames
    meta = {"sheets": wb.sheetnames, "sheets_parsed": []}

    for s_name in sheet_names:
        ws = wb[s_name]
        lines.append(f"## Sheet: {s_name}")
        row_count = 0
        table_rows = []

        for row in ws.iter_rows(values_only=True):
            if any(cell is not None for cell in row):
                row_cells = [str(cell).strip() if cell is not None else "" for cell in row]
                table_rows.append(row_cells)
                row_count += 1
                if row_count >= max_rows_per_sheet:
                    break

        if table_rows:
            # Build Markdown table
            headers = table_rows[0]
            lines.append("| " + " | ".join(headers) + " |")
            lines.append("| " + " | ".join(["---"] * len(headers)) + " |")
            for r in table_rows[1:]:
                lines.append("| " + " | ".join(r) + " |")
            if row_count >= max_rows_per_sheet:
                lines.append(f"\n*(Showing first {max_rows_per_sheet} rows. Set max_rows in arguments to view more)*\n")
        else:
            lines.append("*(Sheet is empty)*")
        lines.append("")
        meta["sheets_parsed"].append({"name": s_name, "rows_extracted": row_count})

    wb.close()
    return "\n".join(lines).strip(), meta


def read_pdf(path: str, max_pages: int = 50, start_page: int = 1) -> Tuple[str, Dict[str, Any]]:
    import pypdf
    reader = pypdf.PdfReader(path)
    total_pages = len(reader.pages)
    lines = [f"# PDF Document: {os.path.basename(path)} (Total Pages: {total_pages})\n"]

    end_page = min(start_page + max_pages - 1, total_pages)
    for p_idx in range(start_page - 1, end_page):
        page = reader.pages[p_idx]
        text = page.extract_text() or ""
        lines.append(f"--- Page {p_idx + 1} ---")
        lines.append(text.strip())
        lines.append("")

    if end_page < total_pages:
        lines.append(f"*(Showing pages {start_page} to {end_page} of {total_pages}. Use start_page and max_pages to read further)*")

    meta = {"total_pages": total_pages, "pages_read": f"{start_page}-{end_page}"}
    return "\n".join(lines).strip(), meta


def read_pptx(path: str) -> Tuple[str, Dict[str, Any]]:
    import pptx
    prs = pptx.Presentation(path)
    lines = [f"# PowerPoint Presentation: {os.path.basename(path)} (Slides: {len(prs.slides)})\n"]

    for idx, slide in enumerate(prs.slides, 1):
        title = slide.shapes.title.text.strip() if slide.shapes.title and slide.shapes.title.has_text_frame else f"Slide {idx}"
        lines.append(f"## Slide {idx}: {title}")

        for shape in slide.shapes:
            if shape == slide.shapes.title:
                continue
            if shape.has_text_frame:
                for p in shape.text_frame.paragraphs:
                    p_text = p.text.strip()
                    if p_text:
                        lines.append(f"- {p_text}")
            elif shape.has_table:
                table = shape.table
                lines.append(f"\n[Table ({len(table.rows)}x{len(table.columns)})]:")
                for r in table.rows:
                    row_vals = [c.text.replace('\n', ' ').strip() for c in r.cells]
                    lines.append("  | " + " | ".join(row_vals) + " |")

        # Presenter notes
        if slide.has_notes_slide and slide.notes_slide.notes_text_frame:
            notes = slide.notes_slide.notes_text_frame.text.strip()
            if notes:
                lines.append(f"\n*Speaker Notes:* {notes}")

        lines.append("")

    meta = {"total_slides": len(prs.slides)}
    return "\n".join(lines).strip(), meta


def read_csv_tsv(path: str, max_rows: int = 150) -> Tuple[str, Dict[str, Any]]:
    enc = detect_file_encoding(path)
    lines = [f"# Delimited Table: {os.path.basename(path)}\n"]
    rows = []
    with open(path, "r", encoding=enc, errors="replace") as f:
        # Detect delimiter
        sample = f.read(4096)
        f.seek(0)
        dialect = csv.excel
        if "\t" in sample:
            dialect = csv.excel_tab
        reader = csv.reader(f, dialect)
        for idx, r in enumerate(reader):
            if idx >= max_rows:
                break
            rows.append(r)

    if rows:
        headers = rows[0]
        lines.append("| " + " | ".join(headers) + " |")
        lines.append("| " + " | ".join(["---"] * len(headers)) + " |")
        for r in rows[1:]:
            lines.append("| " + " | ".join(r) + " |")
        if len(rows) >= max_rows:
            lines.append(f"\n*(Showing first {max_rows} rows)*")

    meta = {"rows_extracted": len(rows), "encoding": enc}
    return "\n".join(lines).strip(), meta


def read_zip(path: str, inner_path: str = None) -> Tuple[str, Dict[str, Any]]:
    with zipfile.ZipFile(path, "r") as zf:
        if inner_path:
            if inner_path in zf.namelist():
                content = zf.read(inner_path).decode("utf-8", errors="replace")
                return f"# Archive [{os.path.basename(path)}] -> {inner_path}\n\n{content}", {"inner_path": inner_path}
            return f"File '{inner_path}' not found in archive.", {"error": "not_found"}

        lines = [f"# ZIP Archive Contents: {os.path.basename(path)}\n"]
        lines.append("| File Path | Size (KB) | Compressed (KB) | Date Modified |")
        lines.append("| --- | --- | --- | --- |")
        for info in zf.infolist():
            size_kb = round(info.file_size / 1024, 2)
            comp_kb = round(info.compress_size / 1024, 2)
            dt_str = f"{info.date_time[0]}-{info.date_time[1]:02d}-{info.date_time[2]:02d}"
            lines.append(f"| {info.filename} | {size_kb} | {comp_kb} | {dt_str} |")

        meta = {"files_count": len(zf.infolist())}
        return "\n".join(lines).strip(), meta


def read_plain_text(path: str, start_line: int = 1, max_lines: int = 1500) -> Tuple[str, Dict[str, Any]]:
    enc = detect_file_encoding(path)
    lines = []
    total_lines = 0
    with open(path, "r", encoding=enc, errors="replace") as f:
        for idx, line in enumerate(f, 1):
            total_lines += 1
            if idx >= start_line and idx < start_line + max_lines:
                lines.append(line)

    content = "".join(lines)
    header = f"# File: {os.path.basename(path)} (Encoding: {enc}, Lines: {total_lines})\n\n"
    if total_lines > max_lines:
        footer = f"\n\n*(Showing lines {start_line} to {min(start_line + max_lines - 1, total_lines)} of {total_lines}. Use start_line and max_lines to paginate)*"
        return header + content + footer, {"encoding": enc, "total_lines": total_lines}
    return header + content, {"encoding": enc, "total_lines": total_lines}


# ==========================================
# Universal Read & Edit Dispatcher
# ==========================================

def universal_read_file(path: str, options: Dict[str, Any]) -> Dict[str, Any]:
    """Reads any supported file format and returns structured, clean Markdown."""
    target_path = resolve_file_path(path)
    if not os.path.exists(target_path):
        return {"content": [{"type": "text", "text": f"File not found: {target_path}"}], "isError": True}

    ext = os.path.splitext(target_path)[1].lower()

    try:
        if ext in (".docx", ".dotx"):
            text, meta = read_docx(target_path)
        elif ext in (".xlsx", ".xlsm", ".xltx"):
            max_r = int(options.get("max_rows", 100))
            sheet = options.get("sheet")
            text, meta = read_excel(target_path, max_rows_per_sheet=max_r, target_sheet=sheet)
        elif ext == ".pdf":
            max_p = int(options.get("max_pages", 50))
            start_p = int(options.get("start_page", 1))
            text, meta = read_pdf(target_path, max_pages=max_p, start_page=start_p)
        elif ext == ".pptx":
            text, meta = read_pptx(target_path)
        elif ext in (".csv", ".tsv"):
            max_r = int(options.get("max_rows", 150))
            text, meta = read_csv_tsv(target_path, max_rows=max_r)
        elif ext == ".zip":
            inner = options.get("inner_path")
            text, meta = read_zip(target_path, inner_path=inner)
        else:
            # Plain text, code, logs, configs, json, markdown
            start_l = int(options.get("start_line", 1))
            max_l = int(options.get("max_lines", 1500))
            text, meta = read_plain_text(target_path, start_line=start_l, max_lines=max_l)

        return {"content": [{"type": "text", "text": text}], "isError": False, "metadata": meta}
    except Exception as e:
        return {"content": [{"type": "text", "text": f"Error reading file '{os.path.basename(target_path)}': {str(e)}"}], "isError": True}


def universal_replace_file(path: str, replacements: Dict[str, str], options: Dict[str, Any]) -> Dict[str, Any]:
    """Performs direct in-place or destination search-and-replace across Word, Excel, PPTX, and text files."""
    target_path = resolve_file_path(path)
    if not os.path.exists(target_path):
        return {"content": [{"type": "text", "text": f"File not found: {target_path}"}], "isError": True}

    ext = os.path.splitext(target_path)[1].lower()
    dest = resolve_file_path(options.get("destination") or target_path)

    if not replacements:
        return {"content": [{"type": "text", "text": "No replacements provided."}], "isError": True}

    try:
        # Word (.docx)
        if ext in (".docx", ".dotx"):
            import docx
            doc = docx.Document(target_path)
            count = 0

            def do_replace_p(p):
                nonlocal count
                for old_t, new_t in replacements.items():
                    if old_t in p.text:
                        replaced = False
                        for run in p.runs:
                            if old_t in run.text:
                                run.text = run.text.replace(old_t, new_t)
                                replaced = True
                        if not replaced:
                            p.text = p.text.replace(old_t, new_t)
                        count += 1

            for p in doc.paragraphs:
                do_replace_p(p)
            for table in doc.tables:
                for row in table.rows:
                    for cell in row.cells:
                        for p in cell.paragraphs:
                            do_replace_p(p)

            doc.save(dest)
            return {"content": [{"type": "text", "text": f"Successfully updated Word document: {count} replacement(s) applied. Saved to: {dest}"}], "isError": False}

        # Excel (.xlsx)
        elif ext in (".xlsx", ".xlsm"):
            import openpyxl
            wb = openpyxl.load_workbook(target_path)
            count = 0
            for sname in wb.sheetnames:
                ws = wb[sname]
                for row in ws.iter_rows():
                    for cell in row:
                        if cell.value is not None and isinstance(cell.value, str):
                            for old_t, new_t in replacements.items():
                                if old_t in cell.value:
                                    cell.value = cell.value.replace(old_t, new_t)
                                    count += 1
            wb.save(dest)
            wb.close()
            return {"content": [{"type": "text", "text": f"Successfully updated Excel workbook: {count} cell replacement(s) applied. Saved to: {dest}"}], "isError": False}

        # PowerPoint (.pptx)
        elif ext == ".pptx":
            import pptx
            prs = pptx.Presentation(target_path)
            count = 0
            for slide in prs.slides:
                for shape in slide.shapes:
                    if shape.has_text_frame:
                        for p in shape.text_frame.paragraphs:
                            for old_t, new_t in replacements.items():
                                if old_t in p.text:
                                    p.text = p.text.replace(old_t, new_t)
                                    count += 1
                    elif shape.has_table:
                        for row in shape.table.rows:
                            for cell in row.cells:
                                for old_t, new_t in replacements.items():
                                    if old_t in cell.text:
                                        cell.text = cell.text.replace(old_t, new_t)
                                        count += 1
            prs.save(dest)
            return {"content": [{"type": "text", "text": f"Successfully updated PowerPoint presentation: {count} replacement(s) applied. Saved to: {dest}"}], "isError": False}

        # Plain text / Code / Configs / JSON
        else:
            enc = detect_file_encoding(target_path)
            with open(target_path, "r", encoding=enc, errors="replace") as f:
                content = f.read()

            count = 0
            for old_t, new_t in replacements.items():
                if old_t in content:
                    count += content.count(old_t)
                    content = content.replace(old_t, new_t)

            with open(dest, "w", encoding=enc, errors="replace") as f:
                f.write(content)

            return {"content": [{"type": "text", "text": f"Successfully updated text/code file: {count} replacement(s) applied. Saved to: {dest}"}], "isError": False}

    except Exception as e:
        return {"content": [{"type": "text", "text": f"Error updating file '{os.path.basename(target_path)}': {str(e)}"}], "isError": True}


def universal_stat_file(path: str) -> Dict[str, Any]:
    """Returns rich metadata, file size, permissions, and format info."""
    target_path = resolve_file_path(path)
    if not os.path.exists(target_path):
        return {"content": [{"type": "text", "text": f"File not found: {target_path}"}], "isError": True}

    st = os.stat(target_path)
    is_dir = os.path.isdir(target_path)
    size_bytes = st.st_size
    size_mb = round(size_bytes / (1024 * 1024), 2)
    mtime = datetime.datetime.fromtimestamp(st.st_mtime).isoformat()
    ctime = datetime.datetime.fromtimestamp(st.st_ctime).isoformat()
    ext = os.path.splitext(target_path)[1].lower() if not is_dir else "directory"

    info = f"""# File Info: {os.path.basename(target_path)}
- Full Path: {target_path}
- Type: {'Directory' if is_dir else f'File ({ext})'}
- Size: {size_bytes:,} bytes ({size_mb} MB)
- Last Modified: {mtime}
- Created: {ctime}
"""
    return {"content": [{"type": "text", "text": info.strip()}], "isError": False}
