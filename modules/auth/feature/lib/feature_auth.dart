/// SAMPLE CODE — safe to delete.
///
/// This package is a reference implementation shipped with the template,
/// not product code. It demonstrates:
/// Provider state management, a global `@lazySingleton` controller, auth
/// through the domain and data layers, the platform's session contracts
/// (`ISessionState`, `ISessionStatusStream`, `ISignInLocation`) and the
/// module's own public API (`auth_api`: `AuthNavigator`, `IAuthActionHandler`)
/// other samples consume.
///
/// To remove it and everything that travels with it:
///
/// ```sh
/// dart tools/sample_cleanup/remove_sample.dart auth            # preview
/// dart tools/sample_cleanup/remove_sample.dart auth --apply    # do it
/// ```
///
/// Classification and the full removal bundle live in
/// `tools/sample_manifest.yaml`.
library;

// Auto-generated exports, do not edit manually.
export 'di/auth_tree_wrapper.dart';
export 'di/localization.dart';
export 'di/module.dart';
export 'di/module.module.dart';
export 'src/extensions/l10n_auth_extension.dart';
export 'src/gen/language/app_localizations.dart';
export 'src/gen/language/app_localizations_en.dart';
export 'src/gen/language/app_localizations_vi.dart';
export 'src/handlers/auth_action_handler_impl.dart';
export 'src/pages/login_page.dart';
export 'src/provider/auth_error_state.dart';
export 'src/provider/auth_provider.dart';
export 'src/routing/auth_feature_route_module.dart';
export 'src/routing/auth_navigator_impl.dart';
export 'src/routing/auth_route_module.dart';
export 'src/routing/auth_sign_in_location.dart';
export 'src/services/auth_status_stream_impl.dart';
export 'src/utils/auth_path.dart';
export 'src/widgets/auth_form_widget.dart';
export 'src/widgets/auth_header_widget.dart';
