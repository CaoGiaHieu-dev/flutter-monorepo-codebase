/// Pure-Dart foundation shared by every package.
///
/// It declares **no** `flutter` dependency, and no UI, Firebase, plugin or
/// routing package. That is the whole point: this is the one package everything
/// else depends on, so its dependency list becomes everyone's. `arch_check`
/// rule R9 keeps it that way.
library;

export 'src/src.dart';
