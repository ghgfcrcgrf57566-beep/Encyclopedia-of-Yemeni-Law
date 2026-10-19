class AppConfig {
  AppConfig._();

  // Vercel Preview API; override with --dart-define=LEGAL_AI_BASE_URL=... when needed.
  static const legalAiBaseUrl = String.fromEnvironment(
    'LEGAL_AI_BASE_URL',
    defaultValue: 'https://yemen-law-gemini-3kow7qasa-li-4e33.vercel.app',
  );

  static const geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static const geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.8-flash',
  );

  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
}
