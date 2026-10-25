import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'chat_view.dart';
import 'dialogs.dart';
import 'sidebar.dart';

/// Responsive shell: permanent sidebar on wide screens (desktop/tablet),
/// drawer on phones.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffold = GlobalKey();
  bool _sidebarOpen = true;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    state.hostKeyPrompter = (request) => showHostKeyDialog(context, request);
    state.commandApprover = (call, profile) =>
        showApprovalDialog(context, call, profile);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                if (_sidebarOpen) ...[
                  SizedBox(
                    width: 272,
                    child: Sidebar(
                      onClose: () => setState(() => _sidebarOpen = false),
                    ),
                  ),
                  VerticalDivider(width: 1, color: c.border),
                ],
                Expanded(
                  child: ChatView(
                    onOpenSidebar: _sidebarOpen
                        ? null
                        : () => setState(() => _sidebarOpen = true),
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          key: _scaffold,
          drawer: Drawer(
            backgroundColor: c.sidebar,
            width: 300,
            child: Sidebar(onNavigate: () => Navigator.of(context).maybePop()),
          ),
          body: ChatView(
            onOpenSidebar: () => _scaffold.currentState?.openDrawer(),
          ),
        );
      },
    );
  }
}
