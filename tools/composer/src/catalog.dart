import 'dart:io';

import 'package:path/path.dart' as p;

/// What the shell resolves from dependency injection, read from
/// `platform_app_shell`'s `kShellContracts` (the one table of what an app must
/// and may provide).
///
/// composer cannot import the package — it runs before code generation, and the
/// kernel's barrel pulls generated output — so it reads the Dart source with a
/// strict parser. `app_sync_test.dart` fails when the number of rows parsed
/// differs from the number of `ShellContract<` constructors in the file, so a
/// row this parser cannot read is a red test, not a silently missing id.

/// Repo-relative path of the catalog source, from the package directory.
const String kCatalogFile = 'lib/src/composition/shell_contracts.dart';

/// One row of `kShellContracts`.
class CatalogEntry {
  const CatalogEntry({
    required this.type,
    required this.id,
    required this.required,
    required this.many,
    required this.consumer,
    required this.whenAbsent,
    this.bundle,
  });

  /// The contract's Dart type (`ISessionState`).
  final String type;

  /// The id an app's `capabilities:` uses.
  final String id;

  /// The bundle that declares this row together with its siblings, or null.
  final String? bundle;

  /// `need: ShellNeed.required` — the shell's own packages register it.
  final bool required;

  /// `cardinality: ContractCardinality.many`.
  final bool many;

  /// `path:line` of each lookup, as the source writes them.
  final String consumer;

  /// What the shell does when nothing is registered.
  final String whenAbsent;

  /// The manifest key that declares it: its bundle, else its id.
  String get manifestKey => bundle ?? id;
}

/// The parsed catalog.
class ShellCatalog {
  const ShellCatalog(this.entries);

  final List<CatalogEntry> entries;

  /// The rows an app declares (everything the shell can run without).
  List<CatalogEntry> get optional => [
    for (final e in entries)
      if (!e.required) e,
  ];

  /// The rows the shell's own packages register.
  List<CatalogEntry> get requiredRows => [
    for (final e in entries)
      if (e.required) e,
  ];

  /// The ids a `capabilities:` key may use: every optional id, and every
  /// bundle.
  Set<String> get declarableKeys => {
    for (final e in optional) ...[e.id, e.manifestKey],
  };

  /// The optional rows a manifest key declares: a bundle expands to its
  /// members, a contract id to itself.
  List<CatalogEntry> membersOf(String key) => [
    for (final e in optional)
      if (e.manifestKey == key || e.id == key) e,
  ];

  /// Manifest keys in catalog order, a bundle once.
  List<String> get optionalKeys {
    final keys = <String>[];
    for (final e in optional) {
      if (!keys.contains(e.manifestKey)) keys.add(e.manifestKey);
    }
    return keys;
  }
}

/// Reads `kShellContracts` from [source], the text of `shell_contracts.dart`.
///
/// Throws a [FormatException] naming the row when one cannot be read.
ShellCatalog parseCatalogSource(String source) {
  final start = source.indexOf('kShellContracts');
  if (start == -1) {
    throw const FormatException('no `kShellContracts` list in the source');
  }
  final body = source.substring(start);
  final starts = RegExp(r'ShellContract<(\w+)>\(').allMatches(body).toList();
  final entries = <CatalogEntry>[];
  for (var i = 0; i < starts.length; i++) {
    final end = i + 1 < starts.length ? starts[i + 1].start : body.length;
    final text = body.substring(starts[i].end, end);
    final type = starts[i].group(1)!;

    String field(String name) {
      final m = RegExp("\\b$name:\\s*'(\\w+)'").firstMatch(text);
      if (m == null) {
        throw FormatException('`ShellContract<$type>` has no `$name: \'...\'`');
      }
      return m.group(1)!;
    }

    String enumField(String name, String enumType) {
      final m = RegExp('\\b$name:\\s*$enumType\\.(\\w+)').firstMatch(text);
      if (m == null) {
        throw FormatException(
          '`ShellContract<$type>` has no `$name: $enumType.x`',
        );
      }
      return m.group(1)!;
    }

    final bundle = RegExp(r"\bbundle:\s*'(\w+)'").firstMatch(text)?.group(1);
    entries.add(
      CatalogEntry(
        type: type,
        id: field('id'),
        bundle: bundle,
        required: enumField('need', 'ShellNeed') == 'required',
        many: enumField('cardinality', 'ContractCardinality') == 'many',
        consumer: _stringField(text, 'consumer', type),
        whenAbsent: _stringField(text, 'whenAbsent', type),
      ),
    );
  }
  return ShellCatalog(entries);
}

/// The value of [name]: one Dart string literal or several adjacent ones,
/// concatenated, up to the `,` that ends the argument.
String _stringField(String text, String name, String type) {
  final m = RegExp('\\b$name:\\s*').firstMatch(text);
  if (m == null)
    throw FormatException('`ShellContract<$type>` has no `$name:`');
  final out = StringBuffer();
  var i = m.end;
  while (i < text.length) {
    final c = text[i];
    if (c == "'" || c == '"') {
      i++;
      while (i < text.length && text[i] != c) {
        if (text[i] == r'\' && i + 1 < text.length) {
          out.write(text[i + 1]);
          i += 2;
        } else {
          out.write(text[i]);
          i++;
        }
      }
      i++; // closing quote
    } else if (c == ',') {
      break;
    } else if (c.trim().isEmpty) {
      i++;
    } else {
      throw FormatException(
        '`ShellContract<$type>` `$name` is not a string literal',
      );
    }
  }
  return out.toString();
}

/// Reads the catalog from the `platform_app_shell` package at [shellDir].
///
/// Returns null when the package or the file is missing, with [why] naming it.
ShellCatalog? readCatalog(
  Map<String, String> packages, {
  void Function(String why)? why,
}) {
  final dir = packages['platform_app_shell'];
  if (dir == null) {
    why?.call(
      'cannot read the shell contract catalog: no package named '
      '`platform_app_shell` in this workspace',
    );
    return null;
  }
  final file = File(p.posix.join(dir, kCatalogFile));
  if (!file.existsSync()) {
    why?.call(
      'cannot read the shell contract catalog: '
      '${p.posix.join(dir, kCatalogFile)} does not exist',
    );
    return null;
  }
  try {
    return parseCatalogSource(file.readAsStringSync());
  } on FormatException catch (e) {
    why?.call(
      'cannot read the shell contract catalog '
      '(${p.posix.join(dir, kCatalogFile)}): ${e.message}',
    );
    return null;
  }
}
