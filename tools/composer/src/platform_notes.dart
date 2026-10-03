/// Native notes: what a person standing up a platform's runner should know
/// that no manifest key can express and no gate checks.
///
/// Printed under the platforms table of the app report for every platform
/// declared `runner: scaffold`. Native files stay hand-written and unverified
/// — a manifest vocabulary for every Gradle / Xcode setting would duplicate
/// those tools — so each note says how it is known: **measured** (built or run
/// in this repository), or **from the plugin docs** (not built here).
const Map<String, List<String>> kPlatformNotes = {
  'android': [
    'push needs google-services.json per Android flavor (gitignored) when '
        'core_notifications is composed. From the plugin docs.',
  ],
  'ios': [
    'push needs the aps-environment entitlement and the '
        'GoogleService-Info.plist copy phase. From the plugin docs.',
  ],
  'web': [
    '`flutter build web` has no --flavor option: pass '
        '--dart-define=FLUTTER_APP_FLAVOR=<flavor>, and a release without it '
        'runs as prod. Measured.',
    'The browser owns TLS, so SSL pinning does not apply; secure storage '
        'needs a secure context (https or localhost). Measured.',
  ],
  'windows': [
    'flutter_secure_storage_windows needs the Visual Studio ATL component. '
        'From the plugin docs, not built here.',
    'No URL protocol is registered, so deep links never arrive. From the '
        'plugin docs, not built here.',
  ],
  'macos': [
    'The scaffolded entitlements enable the sandbox but not '
        'com.apple.security.network.client; add it for any network access. '
        'Derived from the scaffold, not built here.',
    'flutter_secure_storage needs the keychain access group, or '
        'MacOsOptions(usesDataProtectionKeychain: false). From the plugin '
        'docs, not built here.',
  ],
  'linux': [
    'flutter_secure_storage needs libsecret and a running, unlocked Secret '
        'Service; on a clean session the app blocks behind the keyring '
        'dialog. Measured.',
  ],
};
