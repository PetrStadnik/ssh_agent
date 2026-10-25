import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme.dart';
import 'ui/home_screen.dart';

class SshAgentApp extends StatelessWidget {
  const SshAgentApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: state,
    child: Selector<AppState, ThemeMode>(
      selector: (_, s) => s.settings.themeMode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'SSH Agent',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: themeMode,
        home: const HomeScreen(),
      ),
    ),
  );
}
