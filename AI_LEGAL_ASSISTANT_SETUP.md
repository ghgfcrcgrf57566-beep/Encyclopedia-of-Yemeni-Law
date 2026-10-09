# ربط المساعد القانوني بـ Cloudflare

## التدفق المعتمد

1. يبحث التطبيق أولاً في SQLite المحلية.
2. إذا وجد مادة مطابقة أو مواد ذات صلة، يرسل هذه المواد فقط إلى Cloudflare Worker لشرحها، وتُرفق أسماء القوانين وأرقام المواد في النتيجة.
3. إذا لم يجد مواد محلية ذات صلة، يرسل السؤال والنطاق إلى Worker، الذي يبحث في D1/Vectorize ثم يستخدم Gemini كخدمة خلفية.
4. لا يُضمّن مفتاح Gemini داخل APK؛ يُحفظ في Cloudflare Worker Secret باسم `GEMINI_API_KEY`.
5. تبقى الإجابة القانونية المحلية متاحة إذا تعذر الاتصال بالخدمة في مسار المادة المطابقة تماماً.

## إعداد التطبيق

ضع عنوان Worker في متغير المستودع GitHub باسم `LEGAL_AI_BASE_URL`، مثل عنوان Worker الحالي:
`https://odd-mouse-c1e0.ghgfcrcgrf57566.workers.dev`

عند البناء المحلي:

```bash
cd yemen_laws_app
flutter pub get
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build apk --release \
  --dart-define=LEGAL_AI_BASE_URL=https://odd-mouse-c1e0.ghgfcrcgrf57566.workers.dev \
  --dart-define=APP_VERSION=1.0.0
```

## إعداد Cloudflare

ملفات الخادم في `backend/legal-ai`. قاعدة D1 اسمها `yemen_laws_db` والفهرس الدلالي `yemen-laws-articles`.

يجب أن تتوفر أسرار Worker التالية قبل تشغيل الإجابات:
- `GEMINI_API_KEY`: مفتاح Google Gemini، يُضاف من إعدادات Worker > Settings > Variables and Secrets.
- `REINDEX_TOKEN`: رمز عشوائي قوي لحماية نقطة إعادة الفهرسة.

ملفات إعداد المخطط والتصدير موجودة في:
- `backend/legal-ai/schema.sql`
- `yemen_laws_app/tools/export_rag_data.py`
- `backend/legal-ai/setup-cloudflare.sh`

## فحوص ما قبل الإطلاق

- تأكد من وجود سجلات القوانين والمواد في D1؛ إنشاء الجداول وحده لا يملأ قاعدة البيانات.
- شغّل تصدير SQLite إلى SQL ثم حمّل البيانات إلى D1.
- أعد فهرسة المواد في Vectorize.
- اختبر `/health` و`/api/chat` مع سؤال طلاق، وسؤال مدني، وسؤال لا توجد له مادة محلية.
- لا تعتبر وجود كلمة مشتركة دليلاً على الصلة القانونية، ولا تعرض مواد غير مرتبطة بالسؤال.
