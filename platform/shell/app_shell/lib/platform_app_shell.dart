/// The app shell every app under `apps/` composes.
///
/// Before this package existed, a second app meant copying 1,369 lines out of
/// `apps/mobile/lib/` — a fork, not an app. What remains in an app is what
/// genuinely differs between apps: its `app_manifest.yaml`, the
/// `injection.dart` generated from that manifest, a one-line `main.dart`
/// calling [runShellApp], and anything that identifies the app itself, such
/// as its Firebase options.
///
/// This package imports no module. `arch_check` R1 holds that, because it is
/// a `platform/` package: core may not import `feature_*`, `data_*` or a
/// product `domain_*`. Every module-owned thing the shell needs arrives
/// through a `core_di` contract resolved with `getItOrNull` /
/// `getAllOrEmpty`.
///
/// An app can also tell the shell what it is: [runShellApp] takes an
/// `AppProfile` (its declared platforms, flavors and capabilities) and
/// [ShellHooks] (its code at fixed points). The shell holds the declaration to
/// what the app actually registers — [SHELL_CONTRACTS] is the one table of
/// what the shell resolves, [checkAppContract] the one check of it — and a
/// boot that cannot start shows [BootErrorApp] instead of a blank window.
library;

// Auto-generated exports, do not edit manually.
export 'di/module.dart';
export 'di/module.module.dart';
export 'src/app_material_wrapper.dart';
export 'src/boot/boot_error_app.dart';
export 'src/bootstrap.dart';
export 'src/composition/composition_check.dart';
export 'src/composition/shell_contracts.dart';
export 'src/main_scope.dart';
export 'src/navigation/app_router.dart';
export 'src/provider/deeplink_provider.dart';
export 'src/root_app.dart';
export 'src/shell_hooks.dart';
export 'src/utils/shell_contract_constants.dart';
export 'src/widgets/navigator_wrapper_widget.dart';
export 'src/widgets/undefined_route_widget.dart';
