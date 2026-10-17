import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/profile_fakes.dart';

/// The repository root: the directory above `platform/` that holds the
/// version catalog. Tests run from the package directory.
Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/pubspec_dependencies.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('repository root not found');
    dir = parent;
  }
  return dir;
}

/// The files of a contract's `consumer`.
Iterable<String> _consumerFiles(ShellContract<Object> contract) =>
    contract.consumer.split(',').map((entry) => entry.trim());

/// Whether [source] looks [type] up — `getIt<T>`, `getItOrNull<T>` or
/// `getAllOrEmpty<T>` — or has it injected as a field (`final T _x;`).
bool _looksUp(String source, String type) {
  final t = RegExp.escape(type);
  return RegExp('\\b(?:getIt|getItOrNull|getAllOrEmpty)\\s*<\\s*$t\\s*>')
          .hasMatch(
            source,
          ) ||
      RegExp('\\bfinal\\s+$t\\??\\s+_?\\w+\\s*;').hasMatch(source);
}

/// What the shell resolves from DI, as one table.
void main() {
  group('SHELL_CONTRACTS', () {
    test('has 7 required and 14 optional rows', () {
      expect(SHELL_CONTRACTS, hasLength(21));
      expect(
        SHELL_CONTRACTS.where((c) => c.need == ShellNeed.required),
        hasLength(7),
      );
      expect(
        SHELL_CONTRACTS.where((c) => c.need == ShellNeed.optional),
        hasLength(14),
      );
    });

    test('ids and types are unique', () {
      expect(SHELL_CONTRACTS.map((c) => c.id).toSet(), hasLength(21));
      expect(SHELL_CONTRACTS.map((c) => c.type).toSet(), hasLength(21));
    });

    test('ids are snake_case', () {
      for (final contract in SHELL_CONTRACTS) {
        expect(contract.id, matches(RegExp(r'^[a-z]+(_[a-z]+)*$')));
      }
    });

    test('every row says what the shell does without it', () {
      for (final contract in SHELL_CONTRACTS) {
        expect(contract.whenAbsent.trim(), isNotEmpty, reason: contract.id);
        expect(contract.consumer.trim(), isNotEmpty, reason: contract.id);
      }
    });

    test('only optional rows are bundled, and the session bundle has four', () {
      for (final contract in SHELL_CONTRACTS) {
        if (contract.bundle != null) {
          expect(contract.need, ShellNeed.optional, reason: contract.id);
        }
      }
      expect(
        SHELL_CONTRACTS.where((c) => c.bundle == 'session').map((c) => c.id),
        ['session_state', 'session_gateway', 'session_refresh', 'sign_in'],
      );
    });

    test('the manifest key is the bundle, else the id', () {
      final byId = {for (final c in SHELL_CONTRACTS) c.id: c};

      expect(byId['sign_in']!.manifestKey, 'session');
      expect(byId['splash']!.manifestKey, 'splash');
    });

    test('collected contracts are the ones several modules contribute', () {
      expect(
        SHELL_CONTRACTS
            .where((c) => c.cardinality == ContractCardinality.many)
            .map((c) => c.id),
        ['routes', 'tabs', 'tree_wrappers', 'localization'],
      );
    });

    test('every consumer file looks the contract up', () {
      final root = _repoRoot();

      for (final contract in SHELL_CONTRACTS) {
        final files = _consumerFiles(contract).toList();
        expect(files, isNotEmpty, reason: contract.id);
        expect(files.toSet(), hasLength(files.length), reason: contract.id);
        for (final path in files) {
          final file = File('${root.path}/$path');
          expect(file.existsSync(), isTrue, reason: '${contract.id}: $path');
          final type = contract.type.toString();
          expect(
            _looksUp(file.readAsStringSync(), type),
            isTrue,
            reason:
                '${contract.id}: $path no longer looks up $type — the catalog '
                'has drifted from the code. Update this row\'s `consumer` in '
                'utils/shell_contract_constants.dart in the same change.',
          );
        }
      }
    });
  });

  group('ShellContract.registered', () {
    setUp(getIt.enableRegisteringMultipleInstancesOfOneType);
    tearDown(getIt.reset);

    ShellContract<Object> row(String id) =>
        SHELL_CONTRACTS.singleWhere((c) => c.id == id);

    test('nothing registered is an empty list, never a throw', () {
      for (final contract in SHELL_CONTRACTS) {
        expect(contract.registered(), isEmpty, reason: contract.id);
      }
    });

    test('a single contract lists its one registration', () {
      final splash = FakeSplash();
      getIt.registerSingleton<IAppSplashScreen>(splash);

      expect(row('splash').registered(), [same(splash)]);
    });

    test('a collected contract lists every registration', () {
      final a = aRoute('/a');
      final b = aRoute('/b');
      getIt
        ..registerSingleton<IFeatureRouteModule>(a)
        ..registerSingleton<IFeatureRouteModule>(b);

      expect(row('routes').registered(), [same(a), same(b)]);
    });

    test('is resolved by the exact contract type', () {
      getIt.registerSingleton<IErrorReporter>(FakeReporter());

      expect(row('error_reporter').registered(), hasLength(1));
      expect(row('analytics').registered(), isEmpty);
    });
  });
}
