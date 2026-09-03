import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/di/module.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/extensions.dart';

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
    return Scaffold(
      appBar: AppBar(title: Text(context.l10nSettings.settings)),
      body: ListView(
        padding: EdgeInsets.all(context.r(16)),
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
          ListTile(
            title: Text(context.l10nSettings.logout),
            trailing: const Icon(Icons.logout),
            onTap: () {
              getIt<IAuthActionHandler>().logout(context);
            },
          ),
        ],
      ),
    );
  }
}
