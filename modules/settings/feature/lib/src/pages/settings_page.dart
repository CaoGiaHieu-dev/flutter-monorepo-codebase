import 'package:auth_api/auth_api.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../extensions/l10n_settings_extension.dart';

/// SAMPLE: a nav destination that switches theme and language through the
/// shell's global providers, and reaches another module's action
/// (`IAuthActionHandler`) without importing that module.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _languageKey = GlobalKey();

  Future<void> _pickLanguage() async {
    // The shell mounts `LanguageProvider` and `ThemeProvider` above the router
    // (RULE-11). Read before the `await`, while `context` is mounted.
    final languages = context.read<LanguageProvider>();
    final picked = await _languageKey.showDropDown<Locale>(
      context,
      options: languages.languageSet.supported,
      builder: (context, locale) => Text(locale.languageName(context)),
    );
    if (picked != null) languages.setLocale(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10nSettings;
    final themeMode = context.select<ThemeProvider, ThemeMode>(
      (theme) => theme.themeMode,
    );
    // `getItOrNull`, not `getIt`: the handler is declared in `auth_api` but
    // implemented by the removable `feature_auth`. With no auth module there is
    // no session to end, so the row is not offered (arch_check R8).
    final authActions = getItOrNull<IAuthActionHandler>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          ListTile(
            key: _languageKey,
            title: Text(l10n.changeLanguage),
            onTap: _pickLanguage,
          ),
          ListTile(
            title: Text(l10n.changeTheme),
            subtitle: Text(switch (themeMode) {
              ThemeMode.system => l10n.themeSystem,
              ThemeMode.light => l10n.themeLight,
              ThemeMode.dark => l10n.themeDark,
            }),
            onTap: () => context.read<ThemeProvider>().toggleTheme(),
          ),
          if (authActions != null)
            ListTile(
              title: Text(l10n.logout),
              onTap: () => authActions.logout(context),
            ),
        ],
      ),
    );
  }
}
