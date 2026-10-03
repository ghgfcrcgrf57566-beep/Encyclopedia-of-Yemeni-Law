#!/usr/bin/env python3
"""
استخراج نصوص القوانين من ملفات Word وإدراجها في قاعدة البيانات SQLite
Extract laws from Word documents and import into SQLite database
"""

import sqlite3
import re
import os
from pathlib import Path
from docx import Document
from typing import List, Dict, Optional, Tuple

class LawImporter:
    """استيراد القوانين من ملفات Word إلى قاعدة البيانات"""
    
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
        """إغلاق الاتصال"""
        if self.connection:
            self.connection.commit()
            self.connection.close()
            print("✓ قاعدة البيانات مُغلقة")
    
    def get_next_law_order(self) -> int:
        """الحصول على أعلى رقم order_num للقوانين + 1"""
        self.cursor.execute("SELECT MAX(order_num) FROM laws")
        max_order = self.cursor.fetchone()[0]
        return (max_order or 0) + 1
    
    def insert_law(self, name: str, category: str = "أخرى") -> int:
        """إدراج قانون جديد وإرجاع ID"""
        order = self.get_next_law_order()
        self.cursor.execute(
            "INSERT INTO laws (name, category, order_num) VALUES (?, ?, ?)",
            (name, category, order)
        )
        return self.cursor.lastrowid
    
    def insert_bab(self, law_id: int, label: str, level: str, 
                   order_num: int, parent_bab_id: Optional[int] = None) -> int:
        """إدراج باب (كتاب/قسم/باب) وإرجاع ID"""
        self.cursor.execute(
            """INSERT INTO abwab (law_id, parent_bab_id, label, level, order_num) 
               VALUES (?, ?, ?, ?, ?)""",
            (law_id, parent_bab_id, label, level, order_num)
        )
        return self.cursor.lastrowid
    
    def insert_fasl(self, law_id: int, bab_id: Optional[int], 
                   label: str, order_num: int) -> int:
        """إدراج فصل وإرجاع ID"""
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
        """إدراج مادة وإرجاع ID"""
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
            print(f"✓ تم استخراج {len(paragraphs)} فقرة من {file_path}")
            return paragraphs
        except Exception as e:
            print(f"✗ خطأ في قراءة {file_path}: {e}")
            return []
    
    def parse_law_structure(self, paragraphs: List[str]) -> Dict:
        """
        تحليل بنية القانون من الفقرات
        الهيكل المتوقع:
        - عناوين الأبواب: "الباب الأول:" أو "الكتاب الثاني:"
        - عناوين الفصول: "الفصل الأول:" أو "الفصل الثاني:"
        - المواد: "المادة 1:" أو "المادة رقم 1:"
        """
        structure = {
            'abwab': [],
            'fusul': [],
            'mawad': []
        }
        
        current_bab = None
        current_fasl = None
        madda_order = 0
        
        for i, paragraph in enumerate(paragraphs):
            # البحث عن عنوان باب
            bab_match = re.match(r'^(الكتاب|الباب|القسم)\s+(\w+)\s*:\s*(.*)', paragraph)
            if bab_match:
                current_bab = {
                    'level': bab_match.group(1),
                    'name': bab_match.group(2),
                    'title': bab_match.group(3) or "",
                    'order': len(structure['abwab'])
                }
                structure['abwab'].append(current_bab)
                current_fasl = None
                madda_order = 0
                continue
            
            # البحث عن عنوان فصل
            fasl_match = re.match(r'^الفصل\s+(\w+)\s*:\s*(.*)', paragraph)
            if fasl_match:
                current_fasl = {
                    'name': fasl_match.group(1),
                    'title': fasl_match.group(2) or "",
                    'parent_bab': current_bab,
                    'order': len(structure['fusul'])
                }
                structure['fusul'].append(current_fasl)
                madda_order = 0
                continue
            
            # البحث عن مادة
            madda_match = re.match(r'^المادة\s+(?:رقم\s+)?(\d+)\s*:\s*(.*)', paragraph)
            if madda_match:
                madda_order += 1
                madda = {
                    'number': madda_match.group(1),
                    'body': madda_match.group(2),
                    'parent_fasl': current_fasl,
                    'parent_bab': current_bab,
                    'order': madda_order
                }
                structure['mawad'].append(madda)
        
        return structure
    
    def import_from_word(self, file_path: str, law_name: str, category: str = "أخرى"):
        """استيراد قانون كامل من ملف Word"""
        print(f"\n📄 جاري معالجة: {law_name}")
        
        # استخراج الفقرات
        paragraphs = self.extract_docx_paragraphs(file_path)
        if not paragraphs:
            print(f"✗ لم يتم استخراج محتوى من {file_path}")
            return
        
        # تحليل البنية
        structure = self.parse_law_structure(paragraphs)
        
        # إدراج القانون
        law_id = self.insert_law(law_name, category)
        print(f"✓ تم إدراج القانون: {law_name} (ID: {law_id})")
        
        # إدراج الأبواب والفصول والمواد
        for bab in structure['abwab']:
            bab_id = self.insert_bab(law_id, bab['title'], bab['level'], bab['order'])
            print(f"  ✓ {bab['level']}: {bab['title']}")
            
            # المواد المباشرة تحت الباب
            for madda in structure['mawad']:
                if madda['parent_bab'] == bab and not madda['parent_fasl']:
                    self.insert_madda(
                        law_id, madda['number'], madda['body'],
                        bab_id=bab_id, order_num=madda['order']
                    )
            
            # الفصول تحت الباب
            for fasl in structure['fusul']:
                if fasl['parent_bab'] == bab:
                    fasl_id = self.insert_fasl(law_id, bab_id, fasl['title'], fasl['order'])
                    print(f"    ✓ فصل: {fasl['title']}")
                    
                    # المواد تحت الفصل
                    for madda in structure['mawad']:
                        if madda['parent_fasl'] == fasl:
                            self.insert_madda(
                                law_id, madda['number'], madda['body'],
                                bab_id=bab_id, fasl_id=fasl_id, 
                                order_num=madda['order']
                            )
        
        # الفصول والمواد الجذرية (بدون باب أب)
        for fasl in structure['fusul']:
            if not fasl['parent_bab']:
                fasl_id = self.insert_fasl(law_id, None, fasl['title'], fasl['order'])
                print(f"  ✓ فصل (جذري): {fasl['title']}")
                
                for madda in structure['mawad']:
                    if madda['parent_fasl'] == fasl:
                        self.insert_madda(
                            law_id, madda['number'], madda['body'],
                            fasl_id=fasl_id, order_num=madda['order']
                        )
        
        # المواد الجذرية (بدون باب ولا فصل)
        for madda in structure['mawad']:
            if not madda['parent_bab'] and not madda['parent_fasl']:
                self.insert_madda(
                    law_id, madda['number'], madda['body'],
                    order_num=madda['order']
                )
        
        print(f"✓ تم إدراج {len(structure['mawad'])} مادة")


def main():
    """البرنامج الرئيسي"""
    db_path = "app_database.db"
    
    importer = LawImporter(db_path)
    importer.connect()
    
    # قائمة الملفات المراد استيرادها
    word_files = [
        ("قانون اراضي وعقارات الدولة.docx", "قانون أراضي وعقارات الدولة", "القانون الإداري"),
        ("قانون التحكيم.docx", "قانون التحكيم", "القانون الإجرائي"),
        ("قانون الجرائم والعقوبات العسكرية.docx", "قانون الجرائم والعقوبات العسكرية", "القانون الجنائي"),
        ("قانون المرور اليمني.docx", "قانون المرور اليمني", "قانون المرور"),
        ("قانون الوقف الشرعي.docx", "قانون الوقف الشرعي", "القانون المدني"),
        ("قانون تنظيم السجون.docx", "قانون تنظيم السجون", "القانون الإجرائي"),
        ("قانون تنظيم مهنة المحاماة.docx", "قانون تنظيم مهنة المحاماة", "قانون الأنشطة المهنية"),
        ("قانون مزاولة المهن الطبية.docx", "قانون مزاولة المهن الطبية", "القانون الطبي"),
    ]
    
    for file_name, law_name, category in word_files:
        if os.path.exists(file_name):
            importer.import_from_word(file_name, law_name, category)
        else:
            print(f"⚠ لم يتم العثور على: {file_name}")
    
    importer.close()
    print("\n✓ اكتمل الاستيراد!")


if __name__ == "__main__":
    main()
