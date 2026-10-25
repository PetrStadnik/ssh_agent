enum LlmProvider {
  /// Ollama native API (`/api/chat`) - recommended.
  ollama('Ollama'),

  /// Any OpenAI compatible server: LM Studio, llama.cpp `llama-server`,
  /// vLLM, LocalAI, Jan... (`/v1/chat/completions`).
  openAiCompatible('OpenAI-kompatibilní (LM Studio, llama.cpp, vLLM)');

  const LlmProvider(this.label);

  final String label;
}

/// Reasoning ("thinking") of the model.
enum ThinkingMode {
  /// Do not send any setting - model default.
  auto('Výchozí podle modelu'),
  off('Vypnuto'),
  on('Zapnuto'),
  low('Nízké úsilí'),
  medium('Střední úsilí'),
  high('Vysoké úsilí');

  const ThinkingMode(this.label);

  final String label;

  /// Value of the Ollama `think` field (null = do not send).
  Object? get ollamaValue => switch (this) {
    ThinkingMode.auto => null,
    ThinkingMode.off => false,
    ThinkingMode.on => true,
    ThinkingMode.low => 'low',
    ThinkingMode.medium => 'medium',
    ThinkingMode.high => 'high',
  };

  /// OpenAI `reasoning_effort` (null = do not send).
  String? get reasoningEffort => switch (this) {
    ThinkingMode.low => 'low',
    ThinkingMode.medium => 'medium',
    ThinkingMode.high => 'high',
    _ => null,
  };
}

/// Settings of the local model server.
class LlmConfig {
  const LlmConfig({
    this.provider = LlmProvider.ollama,
    this.baseUrl = 'http://127.0.0.1:11434',
    this.model = 'qwen3.5:9b',
    this.apiKey,
    this.temperature = 0.2,
    this.contextLength = 32768,
    this.thinking = ThinkingMode.auto,
    this.keepAlive = '30m',
    this.idleTimeout = const Duration(minutes: 5),
  });

  final LlmProvider provider;
  final String baseUrl;
  final String model;

  /// Only for OpenAI compatible servers that require it.
  final String? apiKey;
  final double temperature;

  /// Context window (Ollama `num_ctx`). Tool outputs are long - 16k is the
  /// practical minimum, 32k recommended.
  final int contextLength;
  final ThinkingMode thinking;

  /// How long Ollama keeps the model loaded after a request.
  final String keepAlive;

  /// Maximum silence while waiting for the next streamed token (loading a
  /// model on a slow PC can take minutes).
  final Duration idleTimeout;

  LlmConfig copyWith({
    LlmProvider? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
    double? temperature,
    int? contextLength,
    ThinkingMode? thinking,
    String? keepAlive,
    Duration? idleTimeout,
  }) => LlmConfig(
    provider: provider ?? this.provider,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    temperature: temperature ?? this.temperature,
    contextLength: contextLength ?? this.contextLength,
    thinking: thinking ?? this.thinking,
    keepAlive: keepAlive ?? this.keepAlive,
    idleTimeout: idleTimeout ?? this.idleTimeout,
  );

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'baseUrl': baseUrl,
    'model': model,
    'temperature': temperature,
    'contextLength': contextLength,
    'thinking': thinking.name,
    'keepAlive': keepAlive,
    'idleTimeoutSeconds': idleTimeout.inSeconds,
  };

  /// [apiKey] is a secret and is stored separately by the app.
  factory LlmConfig.fromJson(Map<String, Object?> json, {String? apiKey}) {
    const d = LlmConfig();
    return LlmConfig(
      provider: LlmProvider.values.firstWhere(
        (p) => p.name == json['provider'],
        orElse: () => d.provider,
      ),
      baseUrl: json['baseUrl'] as String? ?? d.baseUrl,
      model: json['model'] as String? ?? d.model,
      apiKey: apiKey,
      temperature: (json['temperature'] as num?)?.toDouble() ?? d.temperature,
      contextLength:
          (json['contextLength'] as num?)?.toInt() ?? d.contextLength,
      thinking: ThinkingMode.values.firstWhere(
        (t) => t.name == json['thinking'],
        orElse: () => d.thinking,
      ),
      keepAlive: json['keepAlive'] as String? ?? d.keepAlive,
      idleTimeout: Duration(
        seconds:
            (json['idleTimeoutSeconds'] as num?)?.toInt() ??
            d.idleTimeout.inSeconds,
      ),
    );
  }
}
