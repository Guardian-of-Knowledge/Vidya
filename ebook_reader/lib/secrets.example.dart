class Secrets {
  // Read at build-time or leave empty. Do NOT commit real keys.
  static const String openAiApiKey =
      String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
}
