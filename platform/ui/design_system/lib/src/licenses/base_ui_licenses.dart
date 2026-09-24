import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../gen/assets.gen.dart';

/// Adds the licences of what `core_base_ui` bundles to [LicenseRegistry],
/// so `showLicensePage` lists them next to the Dart packages'.
///
/// The Plus Jakarta Sans files ship inside the app, and the SIL Open Font
/// License they carry requires the licence to travel with them. Loaded
/// lazily — only when a licence page asks — so it costs nothing at boot.
/// Call once, before `runApp`; `runShellApp` does.
void registerBaseUiLicenses() {
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString(Assets.fonts.plusJakartaSans.ofl);
    yield LicenseEntryWithLineBreaks(const ['Plus Jakarta Sans'], ofl);
  });
}
