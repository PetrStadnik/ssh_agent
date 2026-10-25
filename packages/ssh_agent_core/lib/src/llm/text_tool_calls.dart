import 'dart:convert';

import 'chat_message.dart';

/// Result of [extractTextToolCalls].
class TextToolCalls {
  const TextToolCalls(this.calls, this.remainingText);

  final List<ToolCall> calls;

  /// The answer text without the parsed calls.
  final String remainingText;
}

final RegExp _taggedCall = RegExp(
  r'<(tool_call|function_call|tools)>\s*([\s\S]*?)\s*</\1>',
  caseSensitive: false,
);
final RegExp _mistralCalls = RegExp(r'\[TOOL_CALLS\]\s*');
final RegExp _emptyFence = RegExp(r'```[a-zA-Z]*\s*```');

/// Fallback for models that write a tool call as text instead of using the
/// native function calling (happens with small models or broken chat
/// templates). Recognises:
///
/// * `<tool_call>{"name": ..., "arguments": {...}}</tool_call>` (Hermes/Qwen)
/// * `[TOOL_CALLS][{"name": ..., "arguments": {...}}]` (Mistral)
/// * a JSON object `{"name": ..., "arguments"|"parameters": {...}}`, also
///   inside a ```json code block.
///
/// Only names from [toolNames] are accepted, so normal answers that merely
/// contain JSON are left alone.
TextToolCalls extractTextToolCalls(
  String content,
  Set<String> toolNames, {
  String idPrefix = 'text_call',
}) {
  final calls = <ToolCall>[];
  final removals = <(int, int)>[];
  var counter = 0;

  void addFrom(Object? decoded) {
    if (decoded is List) {
      for (final item in decoded) {
        addFrom(item);
      }
      return;
    }
    final call = _toCall(decoded, toolNames, () => '${idPrefix}_${++counter}');
    if (call != null) calls.add(call);
  }

  for (final match in _taggedCall.allMatches(content)) {
    final before = calls.length;
    for (final span in _jsonValues(match.group(2)!)) {
      addFrom(span.$3);
    }
    if (calls.length > before) removals.add((match.start, match.end));
  }

  if (calls.isEmpty) {
    final mistral = _mistralCalls.firstMatch(content);
    if (mistral != null) {
      final rest = content.substring(mistral.end);
      final values = _jsonValues(rest);
      if (values.isNotEmpty) {
        addFrom(values.first.$3);
        if (calls.isNotEmpty) {
          removals.add((mistral.start, mistral.end + values.first.$2));
        }
      }
    }
  }

  if (calls.isEmpty) {
    for (final span in _jsonValues(content)) {
      final before = calls.length;
      addFrom(span.$3);
      if (calls.length > before) removals.add((span.$1, span.$2));
    }
  }

  if (calls.isEmpty) return TextToolCalls(const [], content);
  final text = StringBuffer();
  var position = 0;
  removals.sort((a, b) => a.$1.compareTo(b.$1));
  for (final (start, end) in removals) {
    if (start < position) continue;
    text.write(content.substring(position, start));
    position = end;
  }
  text.write(content.substring(position));
  final remaining = text.toString().replaceAll(_emptyFence, '').trim();
  return TextToolCalls(calls, remaining);
}

ToolCall? _toCall(
  Object? value,
  Set<String> toolNames,
  String Function() newId,
) {
  if (value is! Map) return null;
  var map = value;
  if (map['function'] is Map) map = map['function'] as Map;
  final name = map['name'] ?? map['tool'] ?? map['tool_name'];
  if (name is! String || !toolNames.contains(name)) return null;
  var args = map['arguments'] ?? map['parameters'] ?? map['args'] ?? const {};
  if (args is String) {
    try {
      args = jsonDecode(args);
    } on FormatException {
      return ToolCall(
        id: newId(),
        name: name,
        arguments: const {},
        argumentsError: 'Arguments are not valid JSON: $args',
      );
    }
  }
  if (args is! Map) return null;
  return ToolCall(
    id: newId(),
    name: name,
    arguments: Map<String, Object?>.from(args),
  );
}

/// Finds top level JSON objects/arrays in [text]: (start, end, value).
List<(int, int, Object?)> _jsonValues(String text) {
  final result = <(int, int, Object?)>[];
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (ch != '{' && ch != '[') {
      i++;
      continue;
    }
    final end = _matchingBracket(text, i);
    if (end == -1) {
      i++;
      continue;
    }
    try {
      final value = jsonDecode(text.substring(i, end + 1));
      result.add((i, end + 1, value));
      i = end + 1;
    } on FormatException {
      i++;
    }
  }
  return result;
}

int _matchingBracket(String text, int start) {
  final stack = <String>[];
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    switch (ch) {
      case '"':
        inString = true;
      case '{':
        stack.add('}');
      case '[':
        stack.add(']');
      case '}':
      case ']':
        if (stack.isEmpty || stack.removeLast() != ch) return -1;
        if (stack.isEmpty) return i;
    }
  }
  return -1;
}
