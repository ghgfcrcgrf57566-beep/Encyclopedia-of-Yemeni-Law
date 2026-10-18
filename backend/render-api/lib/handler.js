const MODEL = (process.env.AI_MODEL || "gemini-3.8-flash").trim().replace(/^models\//, "");
const MAX_QUESTION_CHARS = Math.max(100, Number(process.env.MAX_QUESTION_CHARS || 1200));
const MAX_BODY_BYTES = 64 * 1024;

const HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, x-app-version, authorization",
};

function send(res, status, body) {
  for (const [name, value] of Object.entries(HEADERS)) res.setHeader(name, value);
  res.statusCode = status;
  res.end(JSON.stringify(body));
}

function readBody(req) {
  let body = req.body;
  if (typeof body === "string") {
    if (Buffer.byteLength(body, "utf8") > MAX_BODY_BYTES) {
      const error = new Error("Request body too large");
      error.statusCode = 413;
      throw error;
    }
    try { body = JSON.parse(body || "{}"); }
    catch {
      const error = new Error("Invalid JSON");
      error.statusCode = 400;
      throw error;
    }
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) return {};
  if (Buffer.byteLength(JSON.stringify(body), "utf8") > MAX_BODY_BYTES) {
    const error = new Error("Request body too large");
    error.statusCode = 413;
    throw error;
  }
  return body;
}

const SYSTEM_INSTRUCTION = `أنت المساعد القانوني الذكي لموسوعة القوانين اليمنية. قدّم شرحًا قانونيًا واضحًا بالعربية، ولا تختلق مواد أو أرقام قوانين أو أحكامًا قضائية. لا تدّع أن إجابتك حكم قضائي أو فتوى رسمية أو رأيًا ملزمًا. إذا لم تتوفر لديك مصادر قانونية موثوقة، فصرّح بحدود الإجابة واطلب التحقق من النص الرسمي. افصل بين الوقائع التي يذكرها المستخدم وبين القاعدة القانونية والتحليل، ولا تجزم عند نقص المعطيات.`;

export function sendJson(res, status, body) {
  send(res, status, body);
}

export function health(res) {
  send(res, 200, {
    ok: true,
    service: "yemen-laws-vercel-api",
    gemini_configured: Boolean(process.env.GEMINI_API_KEY?.trim()),
    model: MODEL,
    legal_database_connected: false,
    status: "staged-migration",
  });
}

export async function handleChat(req, res) {
  if (req.method === "OPTIONS") {
    for (const [name, value] of Object.entries(HEADERS)) res.setHeader(name, value);
    res.statusCode = 204;
    return res.end();
  }
  if (req.method !== "POST") return send(res, 405, { error: "طريقة الطلب غير مدعومة." });

  let body;
  try { body = readBody(req); }
  catch (error) {
    const status = error?.statusCode || 400;
    return send(res, status, {
      error: status === 413 ? "حجم الطلب أكبر من المسموح." : "صيغة الطلب غير صحيحة.",
    });
  }

  const apiKey = process.env.GEMINI_API_KEY?.trim();
  if (!apiKey) {
    return send(res, 503, { error: "خدمة المساعد غير مهيأة. أضف GEMINI_API_KEY إلى متغيرات البيئة في Vercel." });
  }

  const question = String(body.message ?? body.question ?? "").trim();
  if (!question) return send(res, 400, { error: "يرجى إدخال السؤال." });
  if (question.length > MAX_QUESTION_CHARS) {
    return send(res, 413, { error: `السؤال أطول من الحد المسموح (${MAX_QUESTION_CHARS} حرفًا).` });
  }

  const history = Array.isArray(body.history) ? body.history.slice(-12).map((item) => ({
    role: item?.role === "assistant" || item?.role === "model" ? "model" : "user",
    parts: [{ text: String(item?.content ?? item?.text ?? "").slice(0, 4000) }],
  })).filter((item) => item.parts[0].text.trim()) : [];

  let response;
  try {
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODEL)}:generateContent`,
      {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
          contents: [...history, { role: "user", parts: [{ text: question }] }],
          generationConfig: { maxOutputTokens: 900 },
        }),
        signal: AbortSignal.timeout(45000),
      },
    );
  } catch (error) {
    console.error("Gemini network error:", error?.name || "unknown");
    return send(res, 502, { error: "تعذر الاتصال بخدمة المساعد حاليًا. حاول مرة أخرى." });
  }

  const raw = await response.text();
  let payload = {};
  try { payload = JSON.parse(raw); } catch {}
  if (!response.ok) {
    console.error("Gemini HTTP error:", response.status);
    return send(res, 502, { error: "تعذر توليد الإجابة حاليًا.", upstream_status: response.status });
  }

  const answer = (payload.candidates?.[0]?.content?.parts || [])
    .map((part) => typeof part.text === "string" ? part.text : "")
    .join("").trim();
  if (!answer) return send(res, 502, { error: "لم تُرجع خدمة المساعد إجابة نصية." });

  return send(res, 200, {
    answer,
    response: answer,
    sources: [],
    webSources: [],
    response_source: "gemini_fallback_no_law_database",
    warning: "هذه النسخة الأولية لا تسترجع مواد قاعدة القوانين المحلية بعد.",
  });
}
