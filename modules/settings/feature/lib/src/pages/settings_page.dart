import 'package:auth_api/auth_api.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../extensions/l10n_settings_extension.dart';

/// SAMPLE — a second nav destination, and the one screen that *consumes*
/// another module's contract without depending on that module.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final languageButtonKey = GlobalKey(
    debugLabel: 'languageButtonKey',
  );

  /// The app shell mounts `LanguageProvider` and `ThemeProvider` above the
  /// router, so this page reads them from the tree (RULE-11) — before the
  /// `await`, while `context` is certainly mounted.
  Future<void> _onLanguageChanged() async {
    final languages = context.read<LanguageProvider>();
    final picked = await languageButtonKey.showDropDown<Locale>(
      context,
      options: languages.languageSet.supported,
      builder: (context, item) => Text(item.languageName(context)),
    );
    if (picked != null) languages.setLocale(picked);
  }

  String _themeModeName(BuildContext context, ThemeMode mode) {
    final l10n = context.l10nSettings;
    return switch (mode) {
      ThemeMode.system => l10n.themeSystem,
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
    };
  }

  @override
  Widget build(BuildContext context) {
    // `getItOrNull`, not `getIt`: [IAuthActionHandler] is declared in
    // `auth_api` but implemented by `feature_auth`, which is removable. A
    // throwing lookup here compiles fine — this package depends on the auth
    // module's API package, not on its feature — and then crashes at runtime
    // in a build without it. With no auth
    // feature there is no session to end, so the row is simply not offered.
    //
    // Enforced by `dart tools/arch_check/check.dart` rule R8.
    final authActions = getItOrNull<IAuthActionHandler>();
    // Rebuilds this row when the mode changes (a tap here, or a restore).
    final themeMode = context.select<ThemeProvider, ThemeMode>(
      (theme) => theme.themeMode,
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.l10nSettings.settings)),
      body: ListView(
        padding: EdgeInsets.all(AppSpacing.lg(context)),
        children: [
          ListTile(
            key: languageButtonKey,
            title: Text(context.l10nSettings.changeLanguage),
            trailing: const Icon(Icons.language),
            onTap: _onLanguageChanged,
          ),
          ListTile(
            title: Text(context.l10nSettings.changeTheme),
            // The row cycles through three modes; saying which one is
            // active also tells a screen reader what a tap changes.
            subtitle: Text(_themeModeName(context, themeMode)),
            trailing: const Icon(Icons.color_lens),
            onTap: () => context.read<ThemeProvider>().toggleTheme(),
          ),
          if (authActions != null)
            ListTile(
              title: Text(context.l10nSettings.logout),
              trailing: const Icon(Icons.logout),
              onTap: () => authActions.logout(context),
            ),
        ],
      ),
    );
  }
}
