import 'package:flutter/material.dart';
import 'package:ssh_agent_core/ssh_agent_core.dart';

/// User settings of the app (stored as JSON; the API key separately in the
/// secure store).
class AppSettings {
  AppSettings({
    this.llm = const LlmConfig(),
    this.maxSteps = 20,
    this.maxToolOutputChars = 12000,
    this.historyChars = 60000,
    this.confirmCommands = false,
    this.expandToolOutput = true,
    this.answerLanguage = 'Czech',
    this.extraInstructions = '',
    Set<ToolCategory>? enabledCategories,
    this.themeMode = ThemeMode.system,
    this.serifAnswers = true,
  }) : enabledCategories = enabledCategories ?? ToolCategory.values.toSet();

  LlmConfig llm;

  /// Maximum number of model calls per answer.
  int maxSteps;

  /// Tool output is shortened to this many characters for the model.
  int maxToolOutputChars;

  /// Approximate size of the conversation history sent to the model.
  int historyChars;

  /// Ask before every command.
  bool confirmCommands;

  /// Tool output cards start expanded.
  bool expandToolOutput;
  String answerLanguage;
  String extraInstructions;
  Set<ToolCategory> enabledCategories;
  ThemeMode themeMode;

  /// Assistant answers in a serif font (like Claude).
  bool serifAnswers;

  Map<String, Object?> toJson() => {
    'llm': llm.toJson(),
    'maxSteps': maxSteps,
    'maxToolOutputChars': maxToolOutputChars,
    'historyChars': historyChars,
    'confirmCommands': confirmCommands,
    'expandToolOutput': expandToolOutput,
    'answerLanguage': answerLanguage,
    'extraInstructions': extraInstructions,
    'enabledCategories': [for (final c in enabledCategories) c.name],
    'themeMode': themeMode.name,
    'serifAnswers': serifAnswers,
  };

  factory AppSettings.fromJson(Map<String, Object?> json, {String? apiKey}) {
    final d = AppSettings();
    final categories = json['enabledCategories'];
    return AppSettings(
      llm: json['llm'] is Map
          ? LlmConfig.fromJson(
              Map<String, Object?>.from(json['llm'] as Map),
              apiKey: apiKey,
            )
          : d.llm,
      maxSteps: (json['maxSteps'] as num?)?.toInt() ?? d.maxSteps,
      maxToolOutputChars:
          (json['maxToolOutputChars'] as num?)?.toInt() ?? d.maxToolOutputChars,
      historyChars: (json['historyChars'] as num?)?.toInt() ?? d.historyChars,
      confirmCommands: json['confirmCommands'] as bool? ?? d.confirmCommands,
      expandToolOutput: json['expandToolOutput'] as bool? ?? d.expandToolOutput,
      answerLanguage: json['answerLanguage'] as String? ?? d.answerLanguage,
      extraInstructions:
          json['extraInstructions'] as String? ?? d.extraInstructions,
      enabledCategories: categories is List
          ? {
              for (final c in ToolCategory.values)
                if (categories.contains(c.name)) c,
            }
          : null,
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == json['themeMode'],
        orElse: () => d.themeMode,
      ),
      serifAnswers: json['serifAnswers'] as bool? ?? d.serifAnswers,
    );
  }
}
