import { health } from "../lib/handler.js";

export default function handler(req, res) {
  if (req.method === "OPTIONS") {
    res.setHeader("access-control-allow-origin", "*");
    res.setHeader("access-control-allow-methods", "GET, OPTIONS");
    res.setHeader("access-control-allow-headers", "content-type, x-app-version, authorization");
    return res.status(204).end();
  }
  if (req.method !== "GET") return res.status(405).json({ error: "طريقة الطلب غير مدعومة." });
  return health(res);
}
