import { GeminiProvider } from "./providers/gemini_provider";

export type AIProviderHistoryMessage = {
  role: "user" | "assistant";
  content: string;
};

export type AIProviderSource = {
  article_id: number;
  law_name: string;
  article_number: string;
  article_text: string;
  chapter?: string | null;
  score?: number;
  reference?: string;
};

export type AIProviderInput = {
  systemInstruction: string;
  language: string;
  question: string;
  history: AIProviderHistoryMessage[];
  sources: AIProviderSource[];
};

export type AIProviderWebSource = {
  title: string;
  url: string;
};

export type AIProviderResult = {
  answer: string;
  webSources: AIProviderWebSource[];
};

export interface AIProvider {
  generateAnswer(input: AIProviderInput): Promise<AIProviderResult>;
}

export class AIProviderError extends Error {
  readonly userMessage: string;

  constructor(userMessage: string, message?: string) {
    super(message ?? userMessage);
    this.name = "AIProviderError";
    this.userMessage = userMessage;
  }
}

export type AIProviderEnv = {
  AI_PROVIDER?: string;
  AI_MODEL?: string;
  GEMINI_API_KEY?: string;
};

export function createAIProvider(env: AIProviderEnv): AIProvider {
  switch ((env.AI_PROVIDER || "gemini").trim().toLowerCase()) {
    case "gemini":
      return new GeminiProvider(env);
    default:
      throw new AIProviderError(
        "خدمة المساعد غير مهيأة بمزود ذكاء اصطناعي مدعوم حاليًا.",
        `Unsupported AI_PROVIDER: ${env.AI_PROVIDER}`,
      );
  }
}
