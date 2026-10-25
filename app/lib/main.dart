import 'package:flutter/material.dart';

import 'app.dart';
import 'state/app_state.dart';
import 'state/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(await FileAppStorage.open());
  await state.load();
  runApp(SshAgentApp(state: state));
}
