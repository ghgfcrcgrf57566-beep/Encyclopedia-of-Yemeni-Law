import http from "node:http";

const PORT = Number(process.env.PORT || 10000);
const HOST = "0.0.0.0";
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
  res.writeHead(status, HEADERS);
  res.end(JSON.stringify(body));
}

async function readJson(req) {
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (Buffer.byteLength(raw, "utf8") > MAX_BODY_BYTES) {
      const error = new Error("Request body too large");
      error.statusCode = 413;
      throw error;
    }
  }
  try {
    return JSON.parse(raw || "{}");
  } catch {
    const error = new Error("Invalid JSON");
    error.statusCode = 400;
    throw error;
  }
}

const SYSTEM_INSTRUCTION = `أنت المساعد القانوني الذكي لموسوعة القوانين اليمنية. قدّم شرحًا قانونيًا واضحًا بالعربية، ولا تختلق مواد أو أرقام قوانين أو أحكامًا قضائية. لا تدّع أن إجابتك حكم قضائي أو فتوى رسمية أو رأيًا ملزمًا. إذا لم تتوفر لديك مصادر قانونية موثوقة، فصرّح بحدود الإجابة واطلب التحقق من النص الرسمي. افصل بين الوقائع التي يذكرها المستخدم وبين القاعدة القانونية والتحليل، ولا تجزم عند نقص المعطيات.`;

async function chat(body) {
  const apiKey = process.env.GEMINI_API_KEY?.trim();
  if (!apiKey) {
    return {
      status: 503,
      body: { error: "خدمة المساعد غير مهيأة. أضف GEMINI_API_KEY في إعدادات Render." },
    };
  }

  const question = String(body.message ?? body.question ?? "").trim();
  if (!question) return { status: 400, body: { error: "يرجى إدخال السؤال." } };
  if (question.length > MAX_QUESTION_CHARS) {
    return { status: 413, body: { error: `السؤال أطول من الحد المسموح (${MAX_QUESTION_CHARS} حرفًا).` } };
  }

  const history = Array.isArray(body.history) ? body.history.slice(-12).map((item) => ({
    role: item?.role === "assistant" || item?.role === "model" ? "model" : "user",
    parts: [{ text: String(item?.content ?? item?.text ?? "").slice(0, 4000) }],
  })).filter((item) => item.parts[0].text.trim()) : [];

  const contents = [...history, { role: "user", parts: [{ text: question }] }];
  let response;
  try {
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODEL)}:generateContent`,
      {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
          contents,
          generationConfig: { maxOutputTokens: 900 },
        }),
        signal: AbortSignal.timeout(45000),
      },
    );
  } catch (error) {
    console.error("Gemini network error:", error?.name || "unknown");
    return { status: 502, body: { error: "تعذر الاتصال بخدمة المساعد حاليًا. حاول مرة أخرى." } };
  }

  const raw = await response.text();
  let payload = {};
  try { payload = JSON.parse(raw); } catch {}
  if (!response.ok) {
    console.error("Gemini HTTP error:", response.status);
    return { status: 502, body: { error: "تعذر توليد الإجابة حاليًا.", upstream_status: response.status } };
  }

  const answer = (payload.candidates?.[0]?.content?.parts || [])
    .map((part) => typeof part.text === "string" ? part.text : "")
    .join("").trim();
  if (!answer) return { status: 502, body: { error: "لم تُرجع خدمة المساعد إجابة نصية." } };

  return {
    status: 200,
    body: {
      answer,
      response: answer,
      sources: [],
      webSources: [],
      response_source: "gemini_fallback_no_law_database",
      warning: "هذه النسخة الأولية لا تسترجع مواد قاعدة القوانين المحلية بعد.",
    },
  };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  if (req.method === "OPTIONS") {
    res.writeHead(204, HEADERS);
    return res.end();
  }

  if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/health")) {
    return send(res, 200, {
      ok: true,
      service: "yemen-laws-render-api",
      gemini_configured: Boolean(process.env.GEMINI_API_KEY?.trim()),
      model_configured: Boolean(MODEL),
      legal_database_connected: false,
      status: "staged-migration",
    });
  }

  if ((url.pathname === "/api/chat" || url.pathname === "/api/legal/ask") && req.method === "POST") {
    try {
      const body = await readJson(req);
      const result = await chat(body);
      return send(res, result.status, result.body);
    } catch (error) {
      return send(res, error?.statusCode || 500, {
        error: error?.statusCode === 413 ? "حجم الطلب أكبر من المسموح." :
          error?.statusCode === 400 ? "صيغة الطلب غير صحيحة." : "حدث خطأ داخلي في الخدمة.",
      });
    }
  }

  return send(res, 404, { error: "المسار غير موجود." });
});

server.listen(PORT, HOST, () => {
  console.log(`Render API listening on ${HOST}:${PORT}`);
});
