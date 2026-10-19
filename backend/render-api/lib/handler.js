import { fileURLToPath } from "node:url";

const MODEL = (process.env.AI_MODEL || "gemini-3.8-flash").trim().replace(/^models\//, "");
const FREE_FALLBACK_MODEL = "nvidia/nemotron-3.5-lightning-free";
const MAX_QUESTION_CHARS = Math.max(100, Number(process.env.MAX_QUESTION_CHARS || 1200));
const MAX_BODY_BYTES = 64 * 1024;
const DEFAULT_LEGAL_DB_URL = "https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/yemen_laws_app/assets/db/app_database.db";
const LEGAL_DB_URL = (process.env.LEGAL_DB_URL || DEFAULT_LEGAL_DB_URL).trim();
const MAX_DB_BYTES = 15 * 1024 * 1024;

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

let legalDbPromise;

function normalizeArabic(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .replace(/[\u064B-\u065F\u0670\u0640]/g, "")
    .replace(/[أإآٱ]/g, "ا")
    .replace(/ى/g, "ي")
    .replace(/ؤ/g, "و")
    .replace(/ئ/g, "ي")
    .replace(/ة/g, "ه")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const STOP_WORDS = new Set([
  "ما", "ماذا", "كيف", "هل", "هو", "هي", "هم", "في", "من", "عن", "على", "الى",
  "إلى", "مع", "هذا", "هذه", "ذلك", "تلك", "ثم", "او", "أو", "و", "يا", "اي",
  "أي", "كان", "تكون", "يكون", "التي", "الذي", "الذين", "اللواتي", "اللاتي",
  "بموجب", "وفق", "حسب", "قانون", "القانون", "الماده", "ماده", "المواد", "مادة",
  "اليمني", "اليمنيه", "اليمنية", "هل يجوز", "اريد", "أريد", "اعرف", "معرفه",
]);

function queryTerms(question) {
  return [...new Set(normalizeArabic(question).split(" ").filter((word) =>
    word.length > 1 && !STOP_WORDS.has(word)
  ))].slice(0, 18);
}

async function loadLegalDb() {
  if (!legalDbPromise) {
    legalDbPromise = (async () => {
      const response = await fetch(LEGAL_DB_URL, { signal: AbortSignal.timeout(15000) });
      if (!response.ok) throw new Error(`Legal DB download failed: ${response.status}`);
      const declaredLength = Number(response.headers.get("content-length") || 0);
      if (declaredLength > MAX_DB_BYTES) throw new Error("Legal DB file exceeds configured size limit");
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (!bytes.length || bytes.length > MAX_DB_BYTES) throw new Error("Legal DB file is empty or too large");

      const sqlModule = await import("fts5-sql-bundle");
      const initSqlJs = typeof sqlModule.default === "function"
        ? sqlModule.default
        : (typeof sqlModule.default?.default === "function" ? sqlModule.default.default : sqlModule.initSqlJs);
      if (typeof initSqlJs !== "function") throw new Error("Could not resolve SQL.js initializer from fts5-sql-bundle");
      const wasmPath = fileURLToPath(new URL("../node_modules/fts5-sql-bundle/dist/sql-wasm.wasm", import.meta.url));
      const SQL = await initSqlJs({ locateFile: (file) => file === "sql-wasm.wasm" ? wasmPath : file });
      const db = new SQL.Database(bytes);
      const tableNames = db.exec("SELECT name FROM sqlite_master WHERE type='table'");
      const tables = new Set((tableNames[0]?.values || []).map((row) => String(row[0])));
      if (!tables.has("laws") || !tables.has("mawad")) {
        db.close();
        throw new Error("Legal DB is missing required laws/mawad tables");
      }
      return db;
    })().catch((error) => {
      legalDbPromise = undefined;
      throw error;
    });
  }
  return legalDbPromise;
}

function searchLegalArticles(db, question, history) {
  const contextQuestion = [question, ...history.filter((item) => item.role === "user").slice(-2).map((item) => item.text)].join(" ");
  const terms = queryTerms(contextQuestion);
  if (!terms.length) return [];

  const result = db.exec(`
    SELECT m.id AS article_id, m.number AS article_number, m.body AS article_body,
           l.id AS law_id, l.name AS law_name, l.short_name AS law_short_name,
           l.category AS law_category
    FROM mawad m
    JOIN laws l ON l.id = m.law_id
    WHERE m.body IS NOT NULL AND trim(m.body) <> ''
  `);
  const rows = result[0]?.values || [];
  const scored = [];
  const normalizedTerms = terms.map((term) => [term, new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g")]);

  for (const row of rows) {
    const [articleId, number, body, lawId, lawName, shortName, category] = row;
    const normBody = normalizeArabic(body);
    const normLaw = normalizeArabic(`${lawName || ""} ${shortName || ""}`);
    const normNumber = normalizeArabic(number);
    let score = 0;
    let matchedTerms = 0;
    for (const [term, regex] of normalizedTerms) {
      const bodyMatches = normBody.match(regex);
      const bodyCount = bodyMatches ? bodyMatches.length : 0;
      const lawMatch = normLaw.includes(term);
      const numberMatch = normNumber.includes(term);
      if (bodyCount || lawMatch || numberMatch) matchedTerms++;
      score += Math.min(bodyCount, 3) * 1.5;
      if (lawMatch) score += 4;
      if (numberMatch) score += 7;
    }
    if (matchedTerms >= Math.min(2, terms.length) && score >= 3) {
      scored.push({
        article_id: articleId,
        article_number: String(number ?? ""),
        article_body: String(body ?? ""),
        law_id: lawId,
        law_name: String(lawName ?? "قانون غير محدد"),
        law_category: String(category ?? ""),
        score: score + (matchedTerms / terms.length),
        matched_terms: matchedTerms,
      });
    }
  }
  scored.sort((a, b) => b.score - a.score || b.matched_terms - a.matched_terms);
  const seen = new Set();
  return scored.filter((item) => {
    const key = `${item.law_id}:${item.article_number}:${item.article_id}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, 5);
}

function localAnswer(articles, question) {
  const lines = [
    "وجدت في قاعدة القوانين المحلية مواد ذات صلة بسؤالك. النصوص التالية من قاعدة بيانات الموسوعة، ويُستحسن مطابقتها مع النسخة الرسمية النافذة قبل الاستناد إليها في إجراء قضائي.",
    "",
  ];
  for (const [index, article] of articles.entries()) {
    lines.push(`${index + 1}. ${article.law_name} — المادة (${article.article_number || "دون رقم"}):`);
    lines.push(article.article_body.slice(0, 2400));
    lines.push("");
  }
  lines.push("هذه نتيجة استرجاع للنصوص ذات الصلة وليست فتوى أو رأيًا قانونيًا نهائيًا. إذا أوضحت الوقائع ونوع الدعوى والطلب، يمكن تضييق البحث إلى المواد الأقرب.");
  return lines.join("\n").trim();
}

export function sendJson(res, status, body) {
  send(res, status, body);
}

export async function health(res) {
  let legalDatabaseConnected = false;
  let legalDatabaseError;
  try {
    const db = await loadLegalDb();
    legalDatabaseConnected = Boolean(db);
  } catch (error) {
    legalDatabaseError = error?.message || "database unavailable";
    console.error("Legal database health check failed:", legalDatabaseError);
  }
  send(res, 200, {
    ok: true,
    service: "yemen-laws-vercel-api",
    gemini_configured: Boolean(process.env.GEMINI_API_KEY?.trim()),
    ai_gateway_configured: Boolean((process.env.AI_GATEWAY_API_KEY || process.env.VERCEL_OIDC_TOKEN || "").trim()),
    model: MODEL,
    free_fallback_model: FREE_FALLBACK_MODEL,
    legal_database_connected: legalDatabaseConnected,
    legal_database_error: legalDatabaseConnected ? undefined : (legalDatabaseError || "تعذر تحميل قاعدة البيانات القانونية من المصدر المحدد."),
    status: legalDatabaseConnected ? "legal-database-ready" : "database-unavailable",
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

  const question = String(body.message ?? body.question ?? "").trim();
  if (!question) return send(res, 400, { error: "يرجى إدخال السؤال." });
  if (question.length > MAX_QUESTION_CHARS) {
    return send(res, 413, { error: `السؤال أطول من الحد المسموح (${MAX_QUESTION_CHARS} حرفًا).` });
  }

  const history = Array.isArray(body.history) ? body.history.slice(-12).map((item) => ({
    role: item?.role === "assistant" || item?.role === "model" ? "model" : "user",
    text: String(item?.content ?? item?.text ?? "").slice(0, 4000),
  })).filter((item) => item.text.trim()) : [];

  // Handle unambiguous greetings locally so they never depend on the legal DB or an external model.
  const normalizedQuestion = normalizeArabic(question);
  const greetingReplies = new Map([
    ["السلام عليكم", "وعليكم السلام ورحمة الله وبركاته، أهلًا بك. كيف يمكنني مساعدتك؟"],
    ["السلام عليكم ورحمة الله وبركاته", "وعليكم السلام ورحمة الله وبركاته، أهلًا بك. كيف يمكنني مساعدتك؟"],
    ["مرحبا", "مرحبًا بك! كيف يمكنني مساعدتك؟"],
    ["اهلا", "أهلًا وسهلًا بك. كيف يمكنني مساعدتك؟"],
    ["اهلا وسهلا", "أهلًا وسهلًا بك. كيف يمكنني مساعدتك؟"],
    ["صباح الخير", "صباح النور والسرور! كيف يمكنني مساعدتك؟"],
    ["مساء الخير", "مساء النور! كيف يمكنني مساعدتك؟"],
    ["شكرا", "على الرحب والسعة، يسعدني مساعدتك."]
  ]);
  const greetingReply = [...greetingReplies.entries()].find(([phrase]) => normalizeArabic(phrase) === normalizedQuestion)?.[1];
  if (greetingReply) {
    return send(res, 200, {
      answer: greetingReply,
      response: greetingReply,
      sources: [],
      webSources: [],
      response_source: "local_greeting",
      model: "local-rule",
      fallback_used: false
    });
  }

  let db;
  try {
    db = await loadLegalDb();
  } catch (error) {
    console.error("Legal database load failed:", error?.message || "unknown");
    return send(res, 503, {
      error: "تعذر الوصول إلى قاعدة القوانين المحلية؛ أوقفنا الإجابة القانونية حتى لا نعطيك جوابًا غير مستند إلى مصدر محلي.",
      response_source: "legal_database_unavailable",
    });
  }

  let articles;
  try {
    articles = searchLegalArticles(db, question, history);
  } catch (error) {
    console.error("Legal database search failed:", error?.message || "unknown");
    return send(res, 503, { error: "تعذر البحث في قاعدة القوانين المحلية حاليًا." });
  }

  if (articles.length) {
    const answer = localAnswer(articles, question);
    const sources = articles.map((article) => ({
      law_id: article.law_id,
      law_name: article.law_name,
      category: article.law_category,
      article_id: article.article_id,
      article_number: article.article_number,
      excerpt: article.article_body.slice(0, 700),
      source: "local_legal_database",
    }));
    return send(res, 200, {
      answer,
      response: answer,
      sources,
      webSources: [],
      response_source: "local_legal_database",
      model: MODEL,
      fallback_used: false,
    });
  }

  const apiKey = process.env.GEMINI_API_KEY?.trim();
  const gatewayKey = (process.env.AI_GATEWAY_API_KEY || process.env.VERCEL_OIDC_TOKEN || "").trim();

  async function tryFreeGatewayFallback(reason) {
    if (!gatewayKey) {
      console.error("AI Gateway fallback unavailable: missing gateway authentication", reason || "");
      return null;
    }
    try {
      const gatewayResponse = await fetch("https://ai-gateway.vercel.sh/v1/chat/completions", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${gatewayKey}`,
        },
        body: JSON.stringify({
          model: FREE_FALLBACK_MODEL,
          messages: [
            { role: "system", content: SYSTEM_INSTRUCTION + " أجب بالعربية الواضحة. إذا كان السؤال قانونيًا، لا تختلق نصوصًا أو أرقام مواد يمنية، واذكر حدود معرفتك. إذا كانت الرسالة تحية أو مجاملة، فأجب بصورة طبيعية ومختصرة." },
            ...history.map((item) => ({ role: item.role === "model" ? "assistant" : "user", content: item.text })),
            { role: "user", content: question },
          ],
          stream: false,
          max_tokens: 900,
        }),
        signal: AbortSignal.timeout(15000),
      });
      const rawGateway = await gatewayResponse.text();
      let gatewayPayload = {};
      try { gatewayPayload = JSON.parse(rawGateway); } catch {}
      if (!gatewayResponse.ok) {
        console.error("AI Gateway fallback HTTP error:", gatewayResponse.status);
        return null;
      }
      const gatewayAnswer = gatewayPayload.choices?.[0]?.message?.content;
      if (typeof gatewayAnswer !== "string" || !gatewayAnswer.trim()) {
        console.error("AI Gateway fallback returned no text");
        return null;
      }
      return gatewayAnswer.trim();
    } catch (error) {
      console.error("AI Gateway fallback network error:", error?.name || "unknown");
      return null;
    }
  }

  async function sendGatewayFallback(reason) {
    const fallbackAnswer = await tryFreeGatewayFallback(reason);
    if (!fallbackAnswer) {
      return send(res, 502, {
        error: "تعذر توليد الإجابة حاليًا. تحقق من اتصال خدمة المساعد وإعداد مصادقة Vercel AI Gateway.",
        response_source: "all_ai_providers_failed",
      });
    }
    const warning = "تنبيه: لم يُعثر على مادة محلية مناسبة في قاعدة الموسوعة لهذا السؤال؛ تحقّق من النصوص الرسمية قبل الاعتماد على الإجابة.";
    return send(res, 200, {
      answer: fallbackAnswer + "\n\n" + warning,
      response: fallbackAnswer,
      sources: [],
      webSources: [],
      response_source: "vercel_ai_gateway_free_fallback",
      model: FREE_FALLBACK_MODEL,
      fallback_used: true,
      warning,
    });
  }

  if (!apiKey) {
    return sendGatewayFallback("gemini_key_missing");
  }

  let response;
  try {
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODEL)}:generateContent`,
      {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION + " لم يُعثر على مادة قانونية محلية مناسبة في قاعدة الموسوعة لهذا السؤال. لا تنسب أي مادة أو حكم إلى قانون يمني دون مصدر موثوق، وصرّح بأن الإجابة عامة وتحتاج إلى مراجعة النص الرسمي." }] },
          contents: [...history.map((item) => ({
            role: item.role,
            parts: [{ text: item.text }],
          })), { role: "user", parts: [{ text: question }] }],
          generationConfig: { maxOutputTokens: 900 },
        }),
        signal: AbortSignal.timeout(12000),
      },
    );
  } catch (error) {
    console.error("Gemini network error:", error?.name || "unknown");
    return sendGatewayFallback("gemini_network_error");
  }

  const raw = await response.text();
  let payload = {};
  try { payload = JSON.parse(raw); } catch {}
  if (!response.ok) {
    console.error("Gemini HTTP error:", response.status);
    return sendGatewayFallback(`gemini_http_${response.status}`);
  }

  const answer = (payload.candidates?.[0]?.content?.parts || [])
    .map((part) => typeof part.text === "string" ? part.text : "")
    .join("").trim();
  if (!answer) return sendGatewayFallback("gemini_empty_answer");

  return send(res, 200, {
    answer: answer + "\n\nتنبيه: لم يُعثر على مادة محلية مناسبة في قاعدة الموسوعة لهذا السؤال؛ تحقّق من النصوص الرسمية قبل الاعتماد على الإجابة.",
    response: answer,
    sources: [],
    webSources: [],
    response_source: "gemini_fallback_no_local_match",
    model: MODEL,
    fallback_used: true,
    warning: "لم يُعثر على مادة محلية مناسبة؛ الإجابة العامة ليست بديلًا عن مراجعة النص الرسمي.",
  });
}
