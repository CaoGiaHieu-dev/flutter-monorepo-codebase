import '../flavor.dart';
import 'app_platform.dart';
import 'app_profile.dart';

/// What a shell hook is told about the app it runs in.
final class AppRuntime {
  const AppRuntime({
    required this.profile,
    required this.flavor,
    required this.platform,
    required this.isDebug,
  });

  /// The app's profile — its declared facts and tuning.
  final AppProfile profile;

  /// The flavor this run is built for.
  final Flavor flavor;

  /// The platform this run is on.
  final AppPlatform platform;

  /// Whether this is a debug build.
  final bool isDebug;
}
