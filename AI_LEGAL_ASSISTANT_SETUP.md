# المساعد القانوني الذكي

1. يبحث المساعد أولاً في قاعدة SQLite المحلية.
2. إذا وجد مواد مناسبة، يعرضها مباشرة ولا يرسل السؤال إلى خدمة خارجية.
3. إذا لم يجد مواد محلية مناسبة، يستخدم Gemini API مباشرة من Flutter كحل احتياطي.
4. التطبيق لا يعتمد على Cloudflare Worker أو LEGAL_AI_BASE_URL.

## إعداد مفتاح Gemini

محلياً:
```bash
flutter build apk --release --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```

وفي GitHub Actions أضف Secret باسم `GEMINI_API_KEY`.

يمكن تغيير النموذج عبر:
```bash
--dart-define=GEMINI_MODEL=gemini-3.8-flash
```

ملاحظة أمنية: `--dart-define` يمنع وضع المفتاح في المستودع، لكنه لا يجعله سراً داخل APK؛ يمكن استخراج مفتاح العميل تقنياً، لذلك يجب تقييد المفتاح في Google AI Studio.
