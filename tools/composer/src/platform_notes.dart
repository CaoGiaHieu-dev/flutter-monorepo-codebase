/// Native notes: what a person running an app on a generated runner should
/// know that no manifest key can express and no gate checks.
///
/// Printed under the platforms table of the app report for every platform
/// declared `runner: scaffold` — a runner `composer runners` writes and git
/// never tracks. Each note says how it is known: **measured** (built and
/// booted in this repository), or **unverified** (not runnable here; the
/// full-matrix CI run is the proof).
const Map<String, List<String>> kPlatformNotes = {
  'web': [
    'The flavor comes from --dart-define=APP_FLAVOR=<flavor> (the web has no '
        '--flavor). Secure storage needs a secure context (https or '
        'localhost); the browser owns TLS, so nothing is pinned. Without a '
        'splash module the page stays empty until boot ends. URLs are hash '
        'URLs; for path URLs call `usePathUrlStrategy()` in '
        '`ShellHooks.beforeDependencies` and have the server rewrite every '
        'path to index.html. An app that links core_database needs '
        'sqlite3.wasm and drift_worker.js in its web runner, which '
        '`composer runners` writes. Measured.',
  ],
  'linux': [
    'With no Secret Service, secure values are kept in memory for the run '
        '(`secure_storage: memory_fallback`, derived), and preferences '
        'sealed with a key it cannot read stay on disk while the run uses '
        'defaults. A fresh session with '
        'a locked or new keyring blocks the app behind the keyring prompt '
        'until it is answered; no code can avoid it. Dev and prod share one '
        'application id, so one support directory and one keyring '
        'namespace. libdartjni.so is bundled. Measured.',
  ],
  'macos': [
    '`composer runners` adds the network-client entitlement to both '
        'entitlements files. Secure storage uses the login keychain (no '
        'keychain sharing, no signing team needed). `--flavor` needs Xcode '
        'schemes, so a generated runner names the flavor with APP_FLAVOR. '
        'Plugins resolve through Swift Package Manager, not CocoaPods. '
        'Unverified.',
  ],
  'windows': [
    'flutter_secure_storage needs Visual Studio 2022 "Desktop development '
        'with C++" with the ATL component. Linking core_notifications '
        'downloads the Firebase C++ SDK (FlutterFire). The window title is '
        'the package name until the runner is ejected. Unverified.',
  ],
};

/// Printed once under the notes, whenever any platform is generated.
const String kAllGeneratedRunnersNote =
    'no native flavors (APP_FLAVOR), no push, no deep links — eject '
    '(`runner: committed`) to own them';
