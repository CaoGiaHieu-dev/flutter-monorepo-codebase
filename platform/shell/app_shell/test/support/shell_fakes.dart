import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

/// In-memory stand-ins for what the shell's DI module registers, so a test
/// can build `AppMaterialWrapper` / `RootApp` without storage or plugins.
class FakeThemeStorage implements IThemeStorage {
  @override
  ThemeMode getThemeMode() => ThemeMode.light;

  @override
  void saveThemeMode(ThemeMode mode) {}
}

class FakeLanguageStorage implements ILanguageStorage {
  @override
  Locale getLanguage() => const Locale('en');

  @override
  void saveLanguage(Locale locale) {}
}

/// Records instead of subscribing to the `app_links` platform stream.
class FakeDeeplinkProvider extends DeeplinkProvider {
  FakeDeeplinkProvider(super._router);

  int initCalls = 0;

  @override
  void initAppLink() => initCalls++;
}

/// A key-value backend held in memory.
class MemoryStorage extends StorageInterface {
  final _values = <String, Object?>{};

  @override
  Future<void> init() async {}

  @override
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)? reviver,
  }) async {
    final value = _values[key];
    return reviver != null ? reviver(key, value) : value as T?;
  }

  @override
  Future<void> write<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// The shell's real [AppBootStorage] over [MemoryStorage].
AppBootStorage memoryBootStorage({bool viewedOnboard = false}) {
  final storage = MemoryStorage();
  final boot = AppBootStorage(StorageManager(storage, storage));
  if (viewedOnboard) boot.viewedOnboard.value = true;
  return boot;
}

class FakeEntryLocation implements IAppEntryLocation {
  FakeEntryLocation(this.path);

  @override
  final String path;
}

class FakeFeatureRoutes implements IFeatureRouteModule {
  FakeFeatureRoutes(this.routes);

  @override
  final List<RouteBase> routes;
}

class FakeDestination extends INavDestinationModule {
  FakeDestination({required this.path, required this.routes, this.order = 0});

  @override
  final int order;

  @override
  final String path;

  @override
  final List<RouteBase> routes;

  @override
  NavDestination destination(BuildContext context) =>
      const NavDestination(label: 'tab', icon: Icons.home);
}

/// Where the shell sends a signed-out user — a session owner's contribution.
class FakeSignInLocation implements ISignInLocation {
  FakeSignInLocation(this.path);

  @override
  final String path;
}

/// Where the shell sends a signed-in user. A test that must stay on the
/// location it set up registers that location here, so the boot redirect
/// lands where the test already is.
class FakePostSignInLocation implements IPostSignInLocation {
  FakePostSignInLocation(this.path);

  @override
  final String path;
}

/// A page that records the [RouteAware] callbacks the shell's
/// `AppRouter.routeObserver` delivers to it.
class RouteAwareProbe extends StatefulWidget {
  const RouteAwareProbe(this.name, this.log, {super.key});

  final String name;
  final List<String> log;

  @override
  State<RouteAwareProbe> createState() => _RouteAwareProbeState();
}

class _RouteAwareProbeState extends State<RouteAwareProbe> with RouteAware {
  RouteObserver<ModalRoute<void>>? _observer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && _observer == null) {
      _observer = getIt<AppRouter>().routeObserver..subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() => widget.log.add('${widget.name}.didPush');

  @override
  void didPushNext() => widget.log.add('${widget.name}.didPushNext');

  @override
  void didPopNext() => widget.log.add('${widget.name}.didPopNext');

  @override
  void didPop() => widget.log.add('${widget.name}.didPop');

  @override
  Widget build(BuildContext context) => Text(widget.name);
}
