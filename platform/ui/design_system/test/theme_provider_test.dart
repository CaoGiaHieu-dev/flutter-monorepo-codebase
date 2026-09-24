import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The system bars must follow the brightness the app actually renders in —
/// for [ThemeMode.system] that is the OS brightness, not the light palette.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
  final light = ThemeProvider.overlayStyleFor(Brightness.light);
  final dark = ThemeProvider.overlayStyleFor(Brightness.dark);

  tearDown(dispatcher.clearPlatformBrightnessTestValue);

  Future<ThemeProvider> providerWith(ThemeMode mode) async {
    final provider = ThemeProvider(_MemoryThemeStorage(mode));
    await provider.initialize();
    addTearDown(provider.dispose);
    return provider;
  }

  test('light and dark styles contrast icons with their bar', () {
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);
    expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    expect(light.statusBarIconBrightness, Brightness.dark);
    expect(dark.statusBarIconBrightness, Brightness.light);
    // Each bar is painted in its own palette's background.
    expect(
      light.systemNavigationBarColor,
      isNot(equals(dark.systemNavigationBarColor)),
    );
  });

  test('system mode on a dark OS uses the dark palette', () async {
    dispatcher.platformBrightnessTestValue = Brightness.dark;

    final provider = await providerWith(ThemeMode.system);

    expect(provider.effectiveBrightness, Brightness.dark);
    expect(provider.systemUiOverlayStyle, dark);
  });

  test('system mode on a light OS uses the light palette', () async {
    dispatcher.platformBrightnessTestValue = Brightness.light;

    final provider = await providerWith(ThemeMode.system);

    expect(provider.systemUiOverlayStyle, light);
  });

  test('system mode follows a platform brightness change', () async {
    dispatcher.platformBrightnessTestValue = Brightness.light;
    final provider = await providerWith(ThemeMode.system);
    var notified = 0;
    provider.addListener(() => notified++);

    dispatcher.platformBrightnessTestValue = Brightness.dark;
    provider.didChangePlatformBrightness();

    expect(provider.systemUiOverlayStyle, dark);
    expect(notified, greaterThan(0));
  });

  test('an explicit mode ignores the OS brightness', () async {
    dispatcher.platformBrightnessTestValue = Brightness.dark;

    final provider = await providerWith(ThemeMode.light);

    expect(provider.systemUiOverlayStyle, light);
  });
}

class _MemoryThemeStorage implements IThemeStorage {
  _MemoryThemeStorage(this._mode);

  ThemeMode _mode;

  @override
  ThemeMode getThemeMode() => _mode;

  @override
  void saveThemeMode(ThemeMode mode) => _mode = mode;
}
