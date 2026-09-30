# -*- coding: utf-8 -*-
"""
build_db.py
-------------------------------------------------------------------
يحوّل ملفات القوانين اليمنية (نصوص مستخرجة من Word) إلى قاعدة بيانات
SQLite واحدة (app_database.db) تُستخدم كأصل (asset) جاهز داخل تطبيق
فلاتر "موسوعة القوانين اليمنية".

الاستخدام:
    python3 build_db.py --src /path/to/docx_folder --out app_database.db

يتوقع السكربت أن كل قانون عبارة عن ملف نصي (قد يكون بامتداد .docx لكنه
نص عادي UTF-8، أو ملف .txt حقيقي). إن كان الملف .docx حقيقيًا (ZIP)
يتم استخراج نصه تلقائيًا عبر pandoc إن وجد.

منطق التحليل:
    1) إزالة أحرف المطّ العربي (ـ / TATWEEL) لأنها تكسر التعرف على
       كلمات مثل "المــادة".
    2) تقسيم النص إلى فقرات (سطر فارغ يفصل بين الفقرات).
    3) تجاهل كل ما قبل أول عنوان (كتاب/قسم/باب/فصل) أو أول مادة
       (الديباجة/الاستهلال).
    4) عند رصد فقرة عنوان (كتاب/قسم/باب/فصل) يتم إغلاق كل المستويات
       الأدنى منها وفتح عنصر جديد بالمستوى المناسب (شجرة عبر
       parent_bab_id لجدول "أبواب" ليدعم كتاب/قسم/باب في نفس الجدول).
    5) عند رصد فقرة "مادة(رقم)" يتم إنشاء مادة جديدة مرتبطة بأعمق
       عنصر شجري حالي (فصل إن وجد، وإلا باب، وإلا مباشرة بالقانون).
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

# ترتيب أسماء القانون كما يجب أن تظهر في التطبيق (نفس ترتيب الملفات الأصلية)
# العنصر الرابع هو التصنيف (يُستخدم في نظام تصنيف القوانين Filtering System)
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
    ("قانون_تنظيم_العلاقة_بين_المؤجر_والمستأجر__2021م.docx",
     "قانون تنظيم العلاقة بين المؤجر والمستأجر", "المؤجر والمستأجر", "مدني"),
    # --- إضافات لاحقة (بعد الدفعة الأولى المكوّنة من 15 قانونًا) ---
    ("قانون_المرور_اليمني.docx", "قانون المرور اليمني", "المرور", "مرور"),
    ("قانون_الوقف_الشرعي.docx", "قانون الوقف الشرعي", "الوقف الشرعي", "وقف"),
    ("قانون_تنظيم_السجون.docx", "قانون تنظيم مصلحة السجون", "السجون", "جزائي"),
    ("قانون_تنظيم_مهنة_المحاماة.docx", "قانون تنظيم مهنة المحاماة", "المحاماة", "إداري"),
    ("قانون_اراضي_وعقارات_الدولة.docx", "قانون أراضي وعقارات الدولة", "أراضي وعقارات الدولة", "مدني"),
]

HEADING_PATTERNS = [
    # (regex, level)  المستويات: 1 كتاب  2 قسم  3 باب  4 فصل
    (re.compile(r"^(الكتاب|كتاب)\b(.*)$"), 1, "كتاب"),
    (re.compile(r"^(القسم|قسم)\b(.*)$"), 2, "قسم"),
    (re.compile(r"^(الباب|باب)\b(.*)$"), 3, "باب"),
    (re.compile(r"^(الفصل|فصل)\b(.*)$"), 4, "فصل"),
]

ARTICLE_PATTERN = re.compile(r"^(?:ال)?ماد[ةه]\s*\(\s*(\d+(?:\s*مكرر)?)\s*\)\s*[:\-\.]?\s*(.*)$")


def clean_text(raw: str) -> str:
    raw = raw.replace(TATWEEL, "")
    raw = raw.replace("\r\n", "\n").replace("\r", "\n")
    return raw


def strip_markdown(p: str) -> str:
    p = p.strip()
    p = re.sub(r"^\*\*(.*)\*\*$", r"\1", p.strip())
    p = p.strip()
    return p


def read_file_text(path: str) -> str:
    """يقرأ الملف كنص عادي، أو يستخرجه بـ pandoc إن كان docx حقيقيًا (ZIP)."""
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
    parts = re.split(r"\n\s*\n", text)
    return [strip_markdown(p) for p in parts if strip_markdown(p)]


def match_heading(p: str):
    """يعيد (level, level_name, label, inline_title) إن كانت الفقرة عنوانًا.

    ملاحظة مهمة: بعض القوانين تستخدم كلمات مثل "القسم" أو "الفصل" كمصطلح
    مُعرَّف داخل مادة التعريفات، وهذا ليس عنوان تقسيم فعليًا.
    """
    if len(p) > 90 or "ماد" in p[:6]:
        return None
    for rx, level, name in HEADING_PATTERNS:
        m = rx.match(p)
        if m:
            rest = p[m.end(1):].strip()
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


# يبحث عن "مادة(رقم)" في أي موضع من الفقرة.
INLINE_ARTICLE_SEARCH = re.compile(r"(?:ال)?ماد[ةه]\s*\(\s*\d+(?:\s*مكرر)?\s*\)")

def parse_law(text: str):
    """
    يعيد شجرة العناصر (أبواب متداخلة + فصول) وقائمة المواد لكل قانون.
    البنية المرجعة: list of top-level nodes، كل عقدة:
       {level, name, label, title, children:[...], articles:[...]}
    والعناصر خارج أي عنوان توضع في articles على مستوى الجذر.
    """
    paragraphs = split_paragraphs(text)

    root = {"level": 0, "name": "root", "label": None, "title": None,
            "children": [], "articles": []}
    stack = [root]
    started = False  # هل بدأنا فعليًا (بعد أول عنوان أو أول مادة)؟

    i = 0
    n = len(paragraphs)
    while i < n:
        p = paragraphs[i]

        heading = match_heading(p)
        art = ARTICLE_PATTERN.match(p)

        if heading:
            started = True
            level, name, label, title = heading
            # إن لم يوجد عنوان ضمن نفس الفقرة (لا يوجد ":")، تحقق من
            # الفقرة التالية: إن لم تكن عنوانًا ولا مادة، فهي عنوان فرعي (title)
            if title is None and i + 1 < n:
                nxt = paragraphs[i + 1]
                if not match_heading(nxt) and not ARTICLE_PATTERN.match(nxt) and len(nxt) < 120:
                    title = nxt
                    i += 1
            # أغلق كل المستويات الأعمق من أو تساوي المستوى الحالي
            # (المقارنة على "مستوى" العنصر أعلى المكدس لا على عمق المكدس،
            # لأن بعض القوانين تقفز مباشرة إلى "باب" دون "كتاب/قسم")
            while stack[-1]["level"] >= level:
                stack.pop()
            node = {"level": level, "name": name, "label": label,
                    "title": title, "children": [], "articles": []}
            stack[-1]["children"].append(node)
            stack.append(node)
            i += 1
            continue

        if art:
            started = True
            number = art.group(1).strip()
            body_lines = [art.group(2).strip()]
            # اجمع الفقرات التالية التي لا تبدأ عنوانًا أو مادة جديدة (فقرات فرعية/تعداد)
            j = i + 1
            while j < n and not match_heading(paragraphs[j]) and not ARTICLE_PATTERN.match(paragraphs[j]):
                body_lines.append(paragraphs[j])
                j += 1
            body = "\n".join([b for b in body_lines if b]).strip()
            stack[-1]["articles"].append({"number": number, "body": body})
            i = j
            continue

        # فقرة عادية (ديباجة/استهلال) قبل أي هيكلة: تجاهلها
        if not started:
            i += 1
            continue

        # حالة نادرة: عنوان فرعي التصق بأول مادة في نفس الفقرة.
        inline = INLINE_ARTICLE_SEARCH.search(p)
        if inline:
            article_part = p[inline.start():]
            art2 = ARTICLE_PATTERN.match(article_part)
            if art2:
                number = art2.group(1).strip()
                body_lines = [art2.group(2).strip()]
                j = i + 1
                while j < n and not match_heading(paragraphs[j]) and not ARTICLE_PATTERN.match(paragraphs[j]):
                    body_lines.append(paragraphs[j])
                    j += 1
                body = "\n".join([b for b in body_lines if b]).strip()
                stack[-1]["articles"].append({"number": number, "body": body})
                i = j
                continue

        # فقرة نصية لم تُلتقط (نادر) - ألحقها بآخر مادة إن وجدت
        target = stack[-1]
        if target["articles"]:
            target["articles"][-1]["body"] += "\n" + p
        i += 1

    return root


def insert_law_tree(conn, law_id, node, parent_bab_id, current_bab_id, current_fasl_id, order_counter):
    """يُدرج الأشجار (أبواب/فصول) والمواد في القاعدة بشكل تكراري."""
    cur = conn.cursor()

    # أولاً أدرج مواد هذا المستوى (تتعلق بأعمق باب/فصل حاليين)
    for art in node["articles"]:
        order_counter[0] += 1
        cur.execute(
            "INSERT INTO mawad (law_id, fasl_id, bab_id, number, body, order_num) "
            "VALUES (?,?,?,?,?,?)",
            (law_id, current_fasl_id, current_bab_id if current_fasl_id is None else None,
             art["number"], art["body"], order_counter[0])
        )

    for child in node["children"]:
        order_counter[0] += 1
        if child["level"] in (1, 2, 3):  # كتاب / قسم / باب -> جدول abwab (شجرة موحدة)
            cur.execute(
                "INSERT INTO abwab (law_id, parent_bab_id, level, label, title, order_num) "
                "VALUES (?,?,?,?,?,?)",
                (law_id, parent_bab_id, child["name"], child["label"], child["title"], order_counter[0])
            )
            new_bab_id = cur.lastrowid
            insert_law_tree(conn, law_id, child, new_bab_id, new_bab_id, None, order_counter)
        elif child["level"] == 4:  # فصل -> جدول fusul
            cur.execute(
                "INSERT INTO fusul (law_id, bab_id, label, title, order_num) VALUES (?,?,?,?,?)",
                (law_id, current_bab_id, child["label"], child["title"], order_counter[0])
            )
            new_fasl_id = cur.lastrowid
            insert_law_tree(conn, law_id, child, parent_bab_id, current_bab_id, new_fasl_id, order_counter)


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

-- ملاحظة شخصية للمستخدم على مادة معيّنة (مستقلة عن قسم "الملاحظات والاقتراحات" العام)
CREATE TABLE article_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mada_id INTEGER NOT NULL REFERENCES mawad(id) ON DELETE CASCADE,
    note_text TEXT NOT NULL,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(mada_id)
);

-- سجل "آخر ما قرأت": يسجَّل تلقائيًا عند فتح أي مادة
CREATE TABLE reading_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mada_id INTEGER NOT NULL REFERENCES mawad(id) ON DELETE CASCADE,
    opened_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- سجل عمليات البحث (للتوسع المستقبلي: اقتراحات بحث، إحصاءات استخدام)
CREATE TABLE search_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    query TEXT NOT NULL,
    response TEXT,
    source TEXT NOT NULL DEFAULT 'local_db',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    searched_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- قسم "الملاحظات والاقتراحات" العام (مرسل إلى المطوّر): يُخزَّن محليًا دائمًا،
-- وتُحدَّث حالة sent إلى 1 فقط عند نجاح الإرسال الفعلي حين يتوفر اتصال إنترنت.
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
            print(f"تحذير: الملف غير موجود، سيتم تخطيه: {filename}", file=sys.stderr)
            continue
        order += 1
        print(f"[{order:02d}] معالجة: {display_name}")
        raw = clean_text(read_file_text(path))
        tree = parse_law(raw)

        cur = conn.cursor()
        cur.execute(
            "INSERT INTO laws (name, short_name, category, order_num, articles_count) VALUES (?,?,?,?,0)",
            (display_name, short_name, category, order)
        )
        law_id = cur.lastrowid
        conn.commit()

        counter = [0]
        insert_law_tree(conn, law_id, tree, None, None, None, counter)
        conn.commit()

        cur.execute("SELECT COUNT(*) FROM mawad WHERE law_id=?", (law_id,))
        count = cur.fetchone()[0]
        cur.execute("UPDATE laws SET articles_count=? WHERE id=?", (count, law_id))
        conn.commit()
        print(f"     -> {count} مادة")

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
