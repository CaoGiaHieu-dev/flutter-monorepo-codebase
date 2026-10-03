/// What to remove right after `flutter create` has written a runner into an
/// app — the shell lines of the report's create block and of `composer new`'s
/// next steps. `flutter create` writes files this repository does not want:
/// a sample widget test that does not compile (`MyApp` is not a class here, so
/// Gate 2 fails), an `analysis_options.yaml` that would replace the root's
/// strict options for the whole app (RULE-70), and IDE project files.
const List<String> kFlutterCreateCleanup = [
  '# flutter create also writes files this repo does not want: a sample test',
  '# that does not compile, an analysis_options.yaml that would replace the',
  "# root's strict options for this whole app (RULE-70), and IDE files.",
  'rm -f test/widget_test.dart analysis_options.yaml',
  'rm -rf .idea *.iml',
];

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
    '`flutter build web` has no --flavor option, and the Flutter tool refuses '
        '--dart-define=FLUTTER_APP_FLAVOR (the name is the framework\'s own). '
        'Name the flavor with --dart-define=APP_FLAVOR=<flavor>, which the '
        'shell reads on the web only; without it a release runs as prod and a '
        'debug run as dev. The tool\'s refusal is measured; the APP_FLAVOR '
        'define is covered by a unit test, not by a web build.',
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
