import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/extensions.dart';

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

  void _onLanguageChanged() {
    languageButtonKey.showDropDown(
      context,
      options: AppLocalizations.supportedLocales,
      onTap: (value) {
        if (value != null) {
          getIt<LanguageProvider>().setLocale(value);
        }
      },
      builder: (context, item) {
        return Text(item.languageName(context));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // `getItOrNull`, not `getIt`: [IAuthActionHandler] is declared in `core_di`
    // but implemented by `feature_auth`, which is removable. A throwing lookup
    // here compiles fine — this package depends on `core_di`, not on the auth
    // feature — and then crashes at runtime in a build without it. With no auth
    // feature there is no session to end, so the row is simply not offered.
    //
    // Enforced by `dart tools/arch_check/check.dart` rule R8.
    final authActions = getItOrNull<IAuthActionHandler>();

    return Scaffold(
      appBar: AppBar(title: Text(context.l10nSettings.settings)),
      body: ListView(
        padding: context.edgeInsets(all: 16),
        children: [
          ListTile(
            key: languageButtonKey,
            title: Text(context.l10nSettings.changeLanguage),
            trailing: const Icon(Icons.language),
            onTap: _onLanguageChanged,
          ),
          ListTile(
            title: Text(context.l10nSettings.changeTheme),
            trailing: const Icon(Icons.color_lens),
            onTap: () {
              getIt<ThemeProvider>().toggleTheme();
            },
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
