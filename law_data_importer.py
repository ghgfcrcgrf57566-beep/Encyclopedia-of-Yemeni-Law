#!/usr/bin/env python3
"""
استخراج نصوص القوانين من ملفات Word وإدراجها في قاعدة البيانات SQLite
متوافق بالكامل مع واجهة التطبيق
Extract laws from Word documents and import into SQLite database
Compatible with app UI (LawDetailScreen, ArticleListScreen, etc.)
"""

import sqlite3
import re
import os
from pathlib import Path
from docx import Document
from typing import List, Dict, Optional, Tuple

class LawImporter:
    """استيراد القوانين من ملفات Word إلى قاعدة البيانات بشكل متوافق مع الواجهة"""
    
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.connection = None
        self.cursor = None
    
    def connect(self):
        """الاتصال بقاعدة البيانات"""
        self.connection = sqlite3.connect(self.db_path)
        self.cursor = self.connection.cursor()
        print(f"✓ متصل بـ: {self.db_path}")
    
    def close(self):
        """إغلاق الاتصال وحفظ التغييرات"""
        if self.connection:
            self.connection.commit()
            self.connection.close()
            print("✓ تم حفظ قاعدة البيانات")
    
    def get_next_law_order(self) -> int:
        """الحصول على أعلى رقم order_num للقوانين + 1"""
        self.cursor.execute("SELECT MAX(order_num) FROM laws")
        max_order = self.cursor.fetchone()[0]
        return (max_order or 0) + 1
    
    def count_articles(self, law_id: int) -> int:
        """عد المواد القانونية للقانون"""
        self.cursor.execute("SELECT COUNT(*) FROM mawad WHERE law_id = ?", (law_id,))
        return self.cursor.fetchone()[0]
    
    def insert_law(self, name: str, category: str = "أخرى") -> int:
        """إدراج قانون جديد وإرجاع ID (متوافق مع جدول laws)"""
        order = self.get_next_law_order()
        self.cursor.execute(
            """INSERT INTO laws (name, category, order_num, articles_count) 
               VALUES (?, ?, ?, 0)""",
            (name, category, order)
        )
        return self.cursor.lastrowid
    
    def update_law_articles_count(self, law_id: int):
        """تحديث عدد المواد في القانون"""
        count = self.count_articles(law_id)
        self.cursor.execute(
            "UPDATE laws SET articles_count = ? WHERE id = ?",
            (count, law_id)
        )
    
    def insert_bab(self, law_id: int, label: str, level: str, 
                   order_num: int, parent_bab_id: Optional[int] = None) -> int:
        """إدراج باب/كتاب/قسم (متوافق مع جدول abwab)"""
        self.cursor.execute(
            """INSERT INTO abwab (law_id, parent_bab_id, label, level, order_num) 
               VALUES (?, ?, ?, ?, ?)""",
            (law_id, parent_bab_id, label, level, order_num)
        )
        return self.cursor.lastrowid
    
    def insert_fasl(self, law_id: int, bab_id: Optional[int], 
                   label: str, order_num: int) -> int:
        """إدراج فصل (متوافق مع جدول fusul)"""
        self.cursor.execute(
            """INSERT INTO fusul (law_id, bab_id, label, order_num) 
               VALUES (?, ?, ?, ?)""",
            (law_id, bab_id, label, order_num)
        )
        return self.cursor.lastrowid
    
    def insert_madda(self, law_id: int, number: str, body: str,
                    bab_id: Optional[int] = None, 
                    fasl_id: Optional[int] = None,
                    order_num: int = 0) -> int:
        """إدراج مادة قانونية (متوافق مع جدول mawad)"""
        self.cursor.execute(
            """INSERT INTO mawad (law_id, number, body, bab_id, fasl_id, order_num) 
               VALUES (?, ?, ?, ?, ?, ?)""",
            (law_id, number, body, bab_id, fasl_id, order_num)
        )
        return self.cursor.lastrowid
    
    def extract_docx_paragraphs(self, file_path: str) -> List[str]:
        """استخراج جميع الفقرات من ملف Word"""
        try:
            doc = Document(file_path)
            paragraphs = [p.text.strip() for p in doc.paragraphs if p.text.strip()]
            print(f"  ✓ تم استخراج {len(paragraphs)} فقرة")
            return paragraphs
        except Exception as e:
            print(f"  ✗ خطأ في قراءة الملف: {e}")
            return []
    
    def is_bab_header(self, text: str) -> Optional[Tuple[str, str, str]]:
        """
        التحقق من أن النص عنوان باب/كتاب/قسم
        يرجع: (النوع، الرقم/الاسم، العنوان الكامل) أو None
        
        الأنماط المدعومة:
        - الباب الأول: ...
        - الكتاب الثاني: ...
        - القسم الثالث: ...
        """
        patterns = [
            (r'^(الباب|الكتاب|القسم)\s+(\w+)\s*:\s*(.*)', 'باب'),
            (r'^(BOOK|CHAPTER|SECTION)\s+(\d+)\s*:\s*(.*)', 'باب'),
        ]
        
        for pattern, level in patterns:
            match = re.match(pattern, text, re.IGNORECASE)
            if match:
                return (level, match.group(2), match.group(3) or match.group(2))
        return None
    
    def is_fasl_header(self, text: str) -> Optional[Tuple[str, str]]:
        """
        التحقق من أن النص عنوان فصل
        يرجع: (الرقم/الاسم، العنوان الكامل) أو None
        """
        patterns = [
            r'^الفصل\s+(\w+)\s*:\s*(.*)',
            r'^CHAPTER\s+(\d+)\s*:\s*(.*)',
        ]
        
        for pattern in patterns:
            match = re.match(pattern, text, re.IGNORECASE)
            if match:
                return (match.group(1), match.group(2) or match.group(1))
        return None
    
    def is_madda_header(self, text: str) -> Optional[Tuple[str, str]]:
        """
        التحقق من أن النص عنوان مادة
        يرجع: (رقم المادة، نص المادة) أو None
        
        الأنماط المدعومة:
        - المادة 1: ...
        - المادة رقم 1: ...
        - Article 1: ...
        """
        patterns = [
            r'^المادة\s+(?:رقم\s+)?(\d+)\s*:\s*(.*)',
            r'^Article\s+(\d+)\s*:\s*(.*)',
        ]
        
        for pattern in patterns:
            match = re.match(pattern, text, re.IGNORECASE)
            if match:
                return (match.group(1), match.group(2) or "")
        return None
    
    def parse_law_structure(self, paragraphs: List[str]) -> Dict:
        """
        تحليل بنية القانون من الفقرات
        
        يدعم الهياكل التالية:
        1. باب > فصول > مواد
        2. باب > مواد
        3. فصول > مواد (بدون أبواب)
        4. مواد مباشرة (بدون أبواب أو فصول)
        
        يرجع قاموس يحتوي على البنية الهرمية
        """
        structure = {
            'abwab': [],      # قائمة الأبواب
            'fusul': [],      # قائمة الفصول
            'mawad': []       # قائمة المواد
        }
        
        current_bab = None
        current_fasl = None
        madda_count = 0
        fasl_count = 0
        bab_count = 0
        
        for i, paragraph in enumerate(paragraphs):
            # فحص عنوان الباب
            bab_result = self.is_bab_header(paragraph)
            if bab_result:
                level_type, number, title = bab_result
                bab_count += 1
                current_bab = {
                    'level': level_type,
                    'number': number,
                    'title': title,
                    'order': bab_count,
                    'fusul': []
                }
                structure['abwab'].append(current_bab)
                current_fasl = None
                madda_count = 0
                print(f"    ✓ {level_type}: {title}")
                continue
            
            # فحص عنوان الفصل
            fasl_result = self.is_fasl_header(paragraph)
            if fasl_result:
                number, title = fasl_result
                fasl_count += 1
                current_fasl = {
                    'number': number,
                    'title': title,
                    'order': fasl_count,
                    'parent_bab': current_bab,
                    'mawad': []
                }
                structure['fusul'].append(current_fasl)
                madda_count = 0
                print(f"      ✓ فصل: {title}")
                continue
            
            # فحص عنوان المادة
            madda_result = self.is_madda_header(paragraph)
            if madda_result:
                number, body = madda_result
                madda_count += 1
                madda = {
                    'number': number,
                    'body': body[:500] if len(body) > 500 else body,  # حد أقصى 500 حرف للعرض
                    'full_body': body,  # النص الكامل
                    'parent_fasl': current_fasl,
                    'parent_bab': current_bab,
                    'order': madda_count
                }
                structure['mawad'].append(madda)
                continue
            
            # إذا لم يكن عنوانًا ولم نكن في مادة، قد يكون محتوى مادة سابقة
            if structure['mawad'] and not self.is_madda_header(paragraph):
                # إضافة إلى نص آخر مادة
                structure['mawad'][-1]['full_body'] += "\n" + paragraph
                structure['mawad'][-1]['body'] = structure['mawad'][-1]['full_body'][:500]
        
        return structure
    
    def import_from_word(self, file_path: str, law_name: str, category: str = "أخرى"):
        """
        استيراد قانون كامل من ملف Word
        يضمن التوافق الكامل مع واجهة التطبيق
        """
        print(f"\n{'='*60}")
        print(f"📄 جاري استيراد: {law_name}")
        print(f"{'='*60}")
        
        # التحقق من وجود الملف
        if not os.path.exists(file_path):
            print(f"✗ لم يتم العثور على الملف: {file_path}")
            return False
        
        # استخراج الفقرات
        print(f"⏳ استخراج المحتوى...")
        paragraphs = self.extract_docx_paragraphs(file_path)
        if not paragraphs:
            print(f"✗ لم يتم استخراج محتوى من الملف")
            return False
        
        # تحليل البنية
        print(f"⏳ تحليل البنية...")
        structure = self.parse_law_structure(paragraphs)
        
        # إدراج القانون
        print(f"⏳ إدراج البيانات في قاعدة البيانات...")
        law_id = self.insert_law(law_name, category)
        print(f"✓ تم إدراج القانون: {law_name}")
        print(f"  ID: {law_id} | الفئة: {category}")
        
        # قاموس لتخزين IDs الأبواب والفصول لسهولة الربط
        bab_ids = {}  # key: bab object id, value: db id
        fasl_ids = {} # key: fasl object id, value: db id
        
        # إدراج الأبواب
        if structure['abwab']:
            print(f"\n📚 الأبواب ({len(structure['abwab'])}):")
            for bab in structure['abwab']:
                bab_id = self.insert_bab(
                    law_id, 
                    bab['title'], 
                    bab['level'], 
                    bab['order']
                )
                bab_ids[id(bab)] = bab_id
        
        # إدراج الفصول
        if structure['fusul']:
            print(f"\n📖 الفصول ({len(structure['fusul'])}):")
            for fasl in structure['fusul']:
                parent_bab_id = None
                if fasl['parent_bab']:
                    parent_bab_id = bab_ids.get(id(fasl['parent_bab']))
                
                fasl_id = self.insert_fasl(
                    law_id,
                    parent_bab_id,
                    fasl['title'],
                    fasl['order']
                )
                fasl_ids[id(fasl)] = fasl_id
        
        # إدراج المواد
        if structure['mawad']:
            print(f"\n📄 المواد ({len(structure['mawad'])}):")
            for i, madda in enumerate(structure['mawad'], 1):
                parent_bab_id = None
                parent_fasl_id = None
                
                if madda['parent_bab']:
                    parent_bab_id = bab_ids.get(id(madda['parent_bab']))
                
                if madda['parent_fasl']:
                    parent_fasl_id = fasl_ids.get(id(madda['parent_fasl']))
                
                self.insert_madda(
                    law_id,
                    madda['number'],
                    madda['full_body'],
                    bab_id=parent_bab_id,
                    fasl_id=parent_fasl_id,
                    order_num=madda['order']
                )
                
                if i % 10 == 0 or i == 1:
                    print(f"  ✓ تم إدراج {i}/{len(structure['mawad'])} مادة")
            
            print(f"  ✓ اكتمل إدراج {len(structure['mawad'])} مادة")
        
        # تحديث عدد المواد في جدول laws
        self.update_law_articles_count(law_id)
        
        # الإحصائيات النهائية
        print(f"\n{'='*60}")
        print(f"✓ اكتمل الاستيراد بنجاح!")
        print(f"{'='*60}")
        print(f"📊 الإحصائيات:")
        print(f"  • القانون: {law_name}")
        print(f"  • الأبواب: {len(structure['abwab'])}")
        print(f"  • الفصول: {len(structure['fusul'])}")
        print(f"  • المواد: {len(structure['mawad'])}")
        print(f"{'='*60}\n")
        
        return True


def main():
    """البرنامج الرئيسي"""
    
    # مسار قاعدة البيانات
    db_path = "assets/db/app_database.db"
    
    # التحقق من وجود المسار
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    
    importer = LawImporter(db_path)
    importer.connect()
    
    # قائمة الملفات والقوانين المراد استيرادها
    # (اسم الملف، اسم القانون، الفئة/التصنيف)
    laws_to_import = [
        ("قانون اراضي وعقارات الدولة.docx", "قانون أراضي وعقارات الدولة", "القانون الإداري"),
        ("قانون التحكيم.docx", "قانون التحكيم", "القانون الإجرائي"),
        ("قانون الجرائم والعقوبات العسكرية.docx", "قانون الجرائم والعقوبات العسكرية", "القانون الجنائي"),
        ("قانون المرور اليمني.docx", "قانون المرور اليمني", "قانون المرور"),
        ("قانون الوقف الشرعي.docx", "قانون الوقف الشرعي", "القانون المدني"),
        ("قانون تنظيم السجون.docx", "قانون تنظيم السجون", "القانون الإجرائي"),
        ("قانون تنظيم مهنة المحاماة.docx", "قانون تنظيم مهنة المحاماة", "قانون الأنشطة المهنية"),
        ("قانون مزاولة المهن الطبية.docx", "قانون مزاولة المهن الطبية", "القانون الطبي"),
    ]
    
    print("\n")
    print("╔════════════════════════════════════════════════════════════╗")
    print("║      استيراد القوانين اليمنية إلى التطبيق                 ║")
    print("║   Law Importer - Compatible with Flutter App UI           ║")
    print("╚════════════════════════════════════════════════════════════╝")
    
    success_count = 0
    failed_count = 0
    
    for file_name, law_name, category in laws_to_import:
        if importer.import_from_word(file_name, law_name, category):
            success_count += 1
        else:
            failed_count += 1
    
    importer.close()
    
    # النتيجة النهائية
    print("\n")
    print("╔════════════════════════════════════════════════════════════╗")
    print("║                    النتيجة النهائية                       ║")
    print("╚════════════════════════════════════════════════════════════╝")
    print(f"✓ تم استيراد: {success_count} قانون بنجاح")
    if failed_count > 0:
        print(f"✗ فشل: {failed_count} قانون")
    print("\n✓ جاهزة قاعدة البيانات للاستخدام في التطبيق!")
    print("✓ Database ready for Flutter app!\n")


if __name__ == "__main__":
    main()
