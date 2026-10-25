/// Core of SSH Agent: read-only SSH tools, local LLM clients and the agent
/// loop. Pure Dart (dart:io) - shared by the Flutter app on Windows, Android
/// and iOS and by the command line client.
library;

export 'src/agent/agent.dart';
export 'src/agent/agent_event.dart';
export 'src/agent/conversation.dart';
export 'src/agent/system_prompt.dart';
export 'src/llm/chat_message.dart';
export 'src/llm/llm_client.dart';
export 'src/llm/llm_config.dart';
export 'src/llm/ollama_client.dart';
export 'src/llm/openai_client.dart';
export 'src/llm/text_tool_calls.dart';
export 'src/remote/connection_profile.dart';
export 'src/remote/remote_executor.dart';
export 'src/remote/remote_session.dart';
export 'src/remote/ssh_executor.dart';
export 'src/tools/tool.dart';
export 'src/tools/tool_registry.dart';
export 'src/util/shell.dart';
