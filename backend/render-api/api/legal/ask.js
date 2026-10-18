import { handleChat } from "../../lib/handler.js";

export default async function handler(req, res) {
  return handleChat(req, res);
}
