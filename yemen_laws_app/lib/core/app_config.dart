class AppConfig {
  AppConfig._();

  static const geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static const geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );

  static const legalAiBaseUrl = String.fromEnvironment(
    'LEGAL_AI_BASE_URL',
    defaultValue: 'https://odd-mouse-c1e0.ghgfcrcgrf57566.workers.dev',
  );

  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
}
