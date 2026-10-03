import 'package:path/path.dart' as p;

import '../../shared/contract_scan.dart';
import 'catalog.dart';

/// What the workspace's source registers with dependency injection, read once
/// by the static scan in `tools/shared/contract_scan.dart`.
///
/// It answers "which package registers this type?" for V3 (an app's
/// `capabilities:` against the code), V10 (the app's own registrations) and the
/// report's "implemented by" column. The scan reads source, not the graph: a
/// hand-written `getIt.register…` is invisible to it, and `checkAppContract`
/// (the smoke test, and boot in a debug build) is the authority that re-derives
/// the truth from the graph the app really builds.

/// One registration, and the package that holds it.
class Provision {
  const Provision({
    required this.package,
    required this.file,
    required this.registration,
  });

  /// The workspace package name (`feature_auth`, `mobile_app`).
  final String package;

  /// Repo-relative path of the file.
  final String file;

  final Registration registration;

  int get line => registration.line;

  String get type => registration.type;
}

/// Every registration of every workspace package, by package.
class ProvisionIndex {
  const ProvisionIndex(this._byPackage);

  /// An index that knows nothing — what a view built without a scan carries.
  const ProvisionIndex.empty() : _byPackage = const {};

  final Map<String, List<Provision>> _byPackage;

  /// Scans the hand-written `lib/` of every package in [packages] (name ->
  /// directory). The catalog's own source is skipped: it names every contract
  /// and registers none.
  factory ProvisionIndex.scan(String root, Map<String, String> packages) {
    final out = <String, List<Provision>>{};
    for (final entry in packages.entries) {
      final files = [
        for (final f in handWrittenDartUnderLib(entry.value))
          if (!f.endsWith(kCatalogFile)) f,
      ];
      if (files.isEmpty) continue;
      final provisions = <Provision>[];
      for (final r in scanRegistrations(files)) {
        provisions.add(
          Provision(
            package: entry.key,
            file: p.posix.relative(r.file, from: root),
            registration: r,
          ),
        );
      }
      if (provisions.isNotEmpty) out[entry.key] = provisions;
    }
    return ProvisionIndex(out);
  }

  /// The registrations of [type] in [packages], in package then file order.
  List<Provision> of(String type, Iterable<String> packages) {
    final out = <Provision>[];
    for (final name in packages.toList()..sort()) {
      for (final provision in _byPackage[name] ?? const <Provision>[]) {
        if (provision.type == type) out.add(provision);
      }
    }
    return out;
  }

  /// The registrations of [type] anywhere in the workspace.
  List<Provision> anywhere(String type) => of(type, _byPackage.keys);
}
