# -*- coding: utf-8 -*-
"""
build_db.py
-------------------------------------------------------------------
يحوّل ملفات القوانين اليمنية إلى قاعدة بيانات SQLite واحدة.
يدعم ملفات النص وملفات DOCX الحقيقية، ويتعامل مع المواد سواء كانت
مفصولة بأسطر فارغة أو موجودة في أسطر متتابعة أو متلاصقة في نفس الفقرة.
-------------------------------------------------------------------
"""
import argparse
import os
import re
import sqlite3
import subprocess
import sys
import zipfile

TATWEEL = "\u0640"

LAW_ORDER = [
    ("دستور_الجمهورية_اليمنية.docx", "دستور الجمهورية اليمنية", "الدستور", "دستوري"),
    ("القانون_المدني.docx", "القانون المدني", "المدني", "مدني"),
    ("القانون_التجاري.docx", "القانون التجاري", "التجاري", "تجاري"),
    ("قانون_الشركات.docx", "قانون الشركات", "الشركات", "تجاري"),
    ("قانون_العمل.docx", "قانون العمل", "العمل", "عمل"),
    ("قانون_الأحوال_الشخصية.docx", "قانون الأحوال الشخصية", "الأحوال الشخصية", "أحوال شخصية"),
    ("قانون_الجرائم_والعقوبات.docx", "قانون الجرائم والعقوبات", "الجرائم والعقوبات", "جزائي"),
    ("قانون_الإجراءات_الجزائية.docx", "قانون الإجراءات الجزائية", "الإجراءات الجزائية", "جزائي"),
    ("قانون_المرافعات.docx", "قانون المرافعات والتنفيذ المدني", "المرافعات", "مرافعات"),
    ("قانون_الاثبات.docx", "قانون الإثبات", "الإثبات", "إثبات"),
    ("قانون_التحكيم.docx", "قانون التحكيم", "التحكيم", "تحكيم"),
    ("قانون_السلطة_القضائية.docx", "قانون السلطة القضائية", "السلطة القضائية", "إداري"),
    ("قانون_الصحافة_والمطبوعات.docx", "قانون الصحافة والمطبوعات", "الصحافة والمطبوعات", "إداري"),
    ("قانون_مزاولة_المهن_الطبية.docx", "قانون مزاولة المهن الطبية والصيدلانية", "المهن الطبية", "إداري"),
    ("قانون_تنظيم_العلاقة_بين_المؤجر_والمستأجر__2021م.docx", "قانون تنظيم العلاقة بين المؤجر والمستأجر", "المؤجر والمستأجر", "مدني"),
    ("قانون_المرور_اليمني.docx", "قانون المرور اليمني", "المرور", "مرور"),
    ("قانون_الوقف_الشرعي.docx", "قانون الوقف الشرعي", "الوقف الشرعي", "وقف"),
    ("قانون_تنظيم_السجون.docx", "قانون تنظيم مصلحة السجون", "السجون", "جزائي"),
    ("قانون_تنظيم_مهنة_المحاماة.docx", "قانون تنظيم مهنة المحاماة", "المحاماة", "إداري"),
    ("قانون_اراضي_وعقارات_الدولة.docx", "قانون أراضي وعقارات الدولة", "أراضي وعقارات الدولة", "مدني"),
]

HEADING_PATTERNS = [
    (re.compile(r"^(الكتاب|كتاب)\b(.*)$"), 1, "كتاب"),
    (re.compile(r"^(القسم|قسم)\b(.*)$"), 2, "قسم"),
    (re.compile(r"^(الباب|باب)\b(.*)$"), 3, "باب"),
    (re.compile(r"^(الفصل|فصل)\b(.*)$"), 4, "فصل"),
]

ARTICLE_PATTERN = re.compile(
    r"^(?:ال)?ماد[ةه]\s*\(\s*(\d+(?:\s*مكرر)?)\s*\)\s*[:\-\.]?\s*(.*)$"
)

ARTICLE_START_PATTERN = re.compile(
    r"(?:^|\s)(?:ال)?ماد[ةه]\s*\(\s*\d+(?:\s*مكرر)?\s*\)"
)


def clean_text(raw: str) -> str:
    raw = raw.replace(TATWEEL, "")
    raw = raw.replace("\r\n", "\n").replace("\r", "\n")
    return raw


def normalize_spaces(text: str) -> str:
    text = text.replace("\u00a0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


def strip_markdown(p: str) -> str:
    p = p.strip()
    p = re.sub(r"^\*\*(.*)\*\*$", r"\1", p.strip())
    return p.strip()


def read_file_text(path: str) -> str:
    """يقرأ الملف كنص عادي، أو يستخرجه بـ pandoc إن كان DOCX حقيقيًا."""
    if zipfile.is_zipfile(path):
        try:
            out = subprocess.run(
                ["pandoc", "-t", "plain", "--wrap=none", path],
                capture_output=True, text=True, check=True
            )
            return out.stdout
        except Exception as e:
            print(f"  تحذير: تعذر استخراج {path} عبر pandoc: {e}", file=sys.stderr)
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def split_paragraphs(text: str):
    """
    تقسيم النص إلى وحدات تحليل حقيقية.

    السبب: بعض ملفات Word لا تضع سطرًا فارغًا بين المواد، ولذلك كان
    المحلل القديم يرى عدة مواد كفقرة واحدة. هنا نفصل أيضًا عند بداية
    مادة أو عنوان معروف حتى لو لم يوجد سطر فارغ.
    """
    text = clean_text(text)
    lines = text.split("\n")
    parts = []
    buffer = []

    def flush():
        if buffer:
            value = normalize_spaces(" ".join(buffer))
            value = strip_markdown(value)
            if value:
                parts.append(value)
            buffer.clear()

    for raw_line in lines:
        line = normalize_spaces(raw_line)
        if not line:
            flush()
            continue

        is_heading = any(rx.match(line) for rx, _, _ in HEADING_PATTERNS)
        is_article = bool(ARTICLE_PATTERN.match(line))

        if (is_heading or is_article) and buffer:
            flush()

        buffer.append(line)

    flush()
    return parts


def match_heading(p: str):
    """يعيد (level, level_name, label, inline_title) إذا كانت الفقرة عنوانًا."""
    p = normalize_spaces(p)
    if len(p) > 120 or "ماد" in p[:8]:
        return None

    for rx, level, name in HEADING_PATTERNS:
        m = rx.match(p)
        if m:
            rest = m.group(2).strip()
            if rest and not rest.startswith("ال") and not rest.startswith("تمهيدي"):
                continue
            label = p
            title = None
            if ":" in p:
                label, title = p.split(":", 1)
                label = label.strip()
                title = title.strip() or None
            return level, name, label, title
    return None


def parse_law(text: str):
    """
    يعيد شجرة العناصر (كتاب/قسم/باب/فصل) وقائمة المواد لكل قانون.
    يدعم وجود أكثر من مادة في نفس الفقرة إذا التصقت بسبب تنسيق Word.
    """
    paragraphs = split_paragraphs(text)

    root = {
        "level": 0,
        "name": "root",
        "label": None,
        "title": None,
        "children": [],
        "articles": [],
    }
    stack = [root]
    started = False

    i = 0
    n = len(paragraphs)

    while i < n:
        p = paragraphs[i]
        heading = match_heading(p)
        art = ARTICLE_PATTERN.match(p)

        if heading:
            started = True
            level, name, label, title = heading

            if title is None and i + 1 < n:
                nxt = paragraphs[i + 1]
                if (
                    not match_heading(nxt)
                    and not ARTICLE_PATTERN.match(nxt)
                    and len(nxt) < 120
                ):
                    title = nxt
                    i += 1

            while len(stack) > 1 and stack[-1]["level"] >= level:
                stack.pop()

            node = {
                "level": level,
                "name": name,
                "label": label,
                "title": title,
                "children": [],
                "articles": [],
            }
            stack[-1]["children"].append(node)
            stack.append(node)
            i += 1
            continue

        if art:
            started = True
            number = art.group(1).strip()
            body_lines = [art.group(2).strip()]

            j = i + 1
            while (
                j < n
                and not match_heading(paragraphs[j])
                and not ARTICLE_PATTERN.match(paragraphs[j])
            ):
                body_lines.append(paragraphs[j])
                j += 1

            body = "\n".join(b for b in body_lines if b).strip()
            if body:
                stack[-1]["articles"].append({"number": number, "body": body})
            i = j
            continue

        if not started:
            i += 1
            continue

        # إذا احتوت الفقرة على أكثر من مادة ولم تبدأ بالمادة مباشرة،
        # استخرج جميع المواد بدل إسقاط ما بعد المادة الأولى.
        matches = list(ARTICLE_START_PATTERN.finditer(p))
        if matches:
            for k, match in enumerate(matches):
                article_start = match.start()
                article_end = matches[k + 1].start() if k + 1 < len(matches) else len(p)
                chunk = p[article_start:article_end].strip()
                art2 = ARTICLE_PATTERN.match(chunk)
                if art2:
                    body = art2.group(2).strip()
                    if body:
                        stack[-1]["articles"].append({
                            "number": art2.group(1).strip(),
                            "body": body,
                        })
            i += 1
            continue

        target = stack[-1]
        if target["articles"]:
            target["articles"][-1]["body"] += "\n" + p
        i += 1

    return root


def insert_law_tree(conn, law_id, node, parent_bab_id, current_bab_id, current_fasl_id, order_counter):
    """يُدرج شجرة القانون والمواد بشكل تكراري."""
    cur = conn.cursor()

    for art in node["articles"]:
        order_counter[0] += 1
        cur.execute(
            "INSERT INTO mawad (law_id, fasl_id, bab_id, number, body, order_num) VALUES (?,?,?,?,?,?)",
            (
                law_id,
                current_fasl_id,
                current_bab_id if current_fasl_id is None else None,
                art["number"],
                art["body"],
                order_counter[0],
            ),
        )

    for child in node["children"]:
        order_counter[0] += 1

        if child["level"] in (1, 2, 3):
            cur.execute(
                "INSERT INTO abwab (law_id, parent_bab_id, level, label, title, order_num) VALUES (?,?,?,?,?,?)",
                (
                    law_id,
                    parent_bab_id,
                    child["name"],
                    child["label"],
                    child["title"],
                    order_counter[0],
                ),
            )
            new_bab_id = cur.lastrowid
            insert_law_tree(
                conn,
                law_id,
                child,
                new_bab_id,
                new_bab_id,
                None,
                order_counter,
            )

        elif child["level"] == 4:
            cur.execute(
                "INSERT INTO fusul (law_id, bab_id, label, title, order_num) VALUES (?,?,?,?,?)",
                (
                    law_id,
                    current_bab_id,
                    child["label"],
                    child["title"],
                    order_counter[0],
                ),
            )
            new_fasl_id = cur.lastrowid
            insert_law_tree(
                conn,
                law_id,
                child,
                parent_bab_id,
                current_bab_id,
                new_fasl_id,
                order_counter,
            )


SCHEMA = """
CREATE TABLE laws (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    short_name TEXT,
    category TEXT,
    order_num INTEGER,
    articles_count INTEGER DEFAULT 0
);

CREATE TABLE abwab (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    law_id INTEGER NOT NULL REFERENCES laws(id) ON DELETE CASCADE,
    parent_bab_id INTEGER REFERENCES abwab(id) ON DELETE CASCADE,
    level TEXT,
    label TEXT,
    title TEXT,
    order_num INTEGER
);

CREATE TABLE fusul (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    law_id INTEGER NOT NULL REFERENCES laws(id) ON DELETE CASCADE,
    bab_id INTEGER REFERENCES abwab(id) ON DELETE CASCADE,
    label TEXT,
    title TEXT,
    order_num INTEGER
);

CREATE TABLE mawad (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    law_id INTEGER NOT NULL REFERENCES laws(id) ON DELETE CASCADE,
    fasl_id INTEGER REFERENCES fusul(id) ON DELETE CASCADE,
    bab_id INTEGER REFERENCES abwab(id) ON DELETE CASCADE,
    number TEXT,
    body TEXT NOT NULL,
    order_num INTEGER
);

CREATE TABLE favorites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mada_id INTEGER NOT NULL REFERENCES mawad(id) ON DELETE CASCADE,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(mada_id)
);

CREATE TABLE article_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mada_id INTEGER NOT NULL REFERENCES mawad(id) ON DELETE CASCADE,
    note_text TEXT NOT NULL,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(mada_id)
);

CREATE TABLE reading_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mada_id INTEGER NOT NULL REFERENCES mawad(id) ON DELETE CASCADE,
    opened_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE search_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    query TEXT NOT NULL,
    searched_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE feedback_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    body TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    sent INTEGER DEFAULT 0
);

CREATE VIRTUAL TABLE mawad_fts USING fts5(
    body, number, content='mawad', content_rowid='id'
);

CREATE TRIGGER mawad_ai AFTER INSERT ON mawad BEGIN
    INSERT INTO mawad_fts(rowid, body, number) VALUES (new.id, new.body, new.number);
END;

CREATE INDEX idx_abwab_law ON abwab(law_id);
CREATE INDEX idx_abwab_parent ON abwab(parent_bab_id);
CREATE INDEX idx_fusul_law ON fusul(law_id);
CREATE INDEX idx_fusul_bab ON fusul(bab_id);
CREATE INDEX idx_mawad_law ON mawad(law_id);
CREATE INDEX idx_mawad_fasl ON mawad(fasl_id);
CREATE INDEX idx_mawad_bab ON mawad(bab_id);
"""


def build(src_dir: str, out_path: str):
    if os.path.exists(out_path):
        os.remove(out_path)

    conn = sqlite3.connect(out_path)
    conn.executescript(SCHEMA)
    conn.commit()

    order = 0

    for filename, display_name, short_name, category in LAW_ORDER:
        path = os.path.join(src_dir, filename)

        if not os.path.exists(path):
            print(
                f"تحذير: الملف غير موجود، سيتم تخطيه: {filename}",
                file=sys.stderr,
            )
            continue

        order += 1
        print(f"[{order:02d}] معالجة: {display_name}")

        raw = clean_text(read_file_text(path))
        tree = parse_law(raw)

        cur = conn.cursor()
        cur.execute(
            "INSERT INTO laws (name, short_name, category, order_num, articles_count) VALUES (?,?,?,?,0)",
            (display_name, short_name, category, order),
        )
        law_id = cur.lastrowid
        conn.commit()

        counter = [0]
        insert_law_tree(conn, law_id, tree, None, None, None, counter)
        conn.commit()

        cur.execute("SELECT COUNT(*) FROM mawad WHERE law_id=?", (law_id,))
        count = cur.fetchone()[0]
        cur.execute(
            "UPDATE laws SET articles_count=? WHERE id=?",
            (count, law_id),
        )
        conn.commit()

        print(f"     -> {count} مادة")

        if count == 0:
            print(
                f"     تحذير: لم يتم استخراج أي مادة من {filename}",
                file=sys.stderr,
            )

    conn.commit()
    conn.execute("INSERT INTO mawad_fts(mawad_fts) VALUES ('rebuild')")
    conn.commit()
    conn.close()

    print(f"\nتم إنشاء قاعدة البيانات: {out_path}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="مجلد يحتوي ملفات القوانين")
    ap.add_argument("--out", default="app_database.db", help="مسار ملف قاعدة البيانات الناتج")
    args = ap.parse_args()
    build(args.src, args.out)
