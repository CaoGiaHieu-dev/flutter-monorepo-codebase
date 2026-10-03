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

/// `path:line` entries of a contract's `consumer`.
Iterable<({String path, int line})> _lookups(ShellContract<Object> contract) =>
    contract.consumer.split(',').map((entry) {
      final trimmed = entry.trim();
      final colon = trimmed.lastIndexOf(':');
      return (
        path: trimmed.substring(0, colon),
        line: int.parse(trimmed.substring(colon + 1)),
      );
    });

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

    test('every consumer line is a lookup of the contract it names', () {
      final root = _repoRoot();

      for (final contract in SHELL_CONTRACTS) {
        for (final (:path, :line) in _lookups(contract)) {
          final file = File('${root.path}/$path');
          expect(file.existsSync(), isTrue, reason: '${contract.id}: $path');
          final lines = file.readAsLinesSync();
          expect(
            line,
            inInclusiveRange(1, lines.length),
            reason: '${contract.id}: $path:$line',
          );
          final type = contract.type.toString();
          final namedAt = [
            for (final (index, text) in lines.indexed)
              if (text.contains(type)) index + 1,
          ];
          expect(
            lines[line - 1],
            contains(type),
            reason:
                '${contract.id}: $path:$line is not a lookup of $type — the '
                'catalog has drifted from the code. The file names $type at '
                '${namedAt.isEmpty ? 'no line' : 'line ${namedAt.join(', ')}'}'
                '; update this row\'s `consumer` in utils/shell_contract_constants.dart '
                'in the same change that moved it.',
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
