import 'package:test/test.dart';

import '../shared/contract_scan.dart';
import 'support/tool_harness.dart';

/// `tools/shared/contract_scan.dart` — the scanner `arch_check` (R8, R16) and
/// `composer` (V3, V10, the report) share.
///
/// Two halves, tested apart:
///
/// - **implementers** (`ownersImplementing`): extracted unchanged from
///   `arch_check`'s R8, so its output equals what R8 produced before the move
///   (`arch_check_test.dart`, untouched, is the other half of that proof);
/// - **registrations** (`registrationsIn`): the precise rule — GetIt resolves
///   the exact type, so a class is registered as itself, or as what `as:`
///   binds it to, and a member of an `@module` class as its declared type.
void main() {
  /// The `(type, kind, environments)` of every registration in [source].
  List<String> scan(String source) => [
    for (final r in registrationsIn(source))
      '${r.type} ${r.kind.name}'
          '${r.environments.isEmpty ? '' : ' ${(r.environments.toList()..sort()).join(',')}'}',
  ];

  group('registrations: annotated classes', () {
    test('a registering annotation registers the class itself', () {
      expect(
        scan(
          '@injectable\nclass A {}\n'
          '@Injectable()\nclass B {}\n'
          '@singleton\nclass C {}\n'
          '@Singleton()\nclass D {}\n'
          '@lazySingleton\nclass E {}\n'
          '@LazySingleton()\nclass F {}\n',
        ),
        [
          'A annotatedClass',
          'B annotatedClass',
          'C annotatedClass',
          'D annotatedClass',
          'E annotatedClass',
          'F annotatedClass',
        ],
      );
    });

    test('as: registers what it binds, and only that', () {
      // `NetworkConfigImpl` is not in the graph under its own name.
      expect(
        scan('@LazySingleton(as: NetworkConfig)\nclass NetworkConfigImpl {}\n'),
        ['NetworkConfig boundAs'],
      );
    });

    test('a generic binding target keeps the type name', () {
      expect(
        scan(
          '@LazySingleton(as: IDatabaseMigration<CacheDatabase>)\n'
          'class Step1 {}\n',
        ),
        ['IDatabaseMigration boundAs'],
      );
    });

    test('modifiers, extra annotations and wrapped arguments are read', () {
      expect(
        scan(
          '@Singleton(\n'
          '  as: ISessionState,\n'
          '  dispose: (i) => i.dispose(),\n'
          ')\n'
          '@Deprecated("old")\n'
          'final class Auth implements ISessionState {}\n',
        ),
        ['ISessionState boundAs'],
      );
    });

    test('implements, extends and with register nothing', () {
      expect(
        scan(
          'class A implements IFoo {}\n'
          'class B extends IFoo {}\n'
          'class C with IFoo {}\n',
        ),
        isEmpty,
      );
    });

    test('an annotation on a member or a constructor is not a class', () {
      expect(
        scan(
          'class A {\n'
          '  @factoryMethod\n'
          '  A.make();\n'
          '  @singleton\n'
          '  void setup() {}\n'
          '}\n',
        ),
        isEmpty,
      );
    });

    test('environments: @Environment, @dev, @prod and env:', () {
      expect(
        scan(
          "@Environment('dev')\n@injectable\nclass A {}\n"
          '@injectable\n@Environment(Environment.prod)\nclass B {}\n'
          '@dev\n@lazySingleton\nclass C {}\n'
          "@LazySingleton(env: ['staging', Environment.prod])\nclass D {}\n",
        ),
        [
          'A annotatedClass dev',
          'B annotatedClass prod',
          'C annotatedClass dev',
          'D annotatedClass prod,staging',
        ],
      );
    });
  });

  group('registrations: @module members', () {
    test('a getter or method registers its declared type', () {
      expect(
        scan(
          '@module\n'
          'abstract class AuthModule {\n'
          '  @lazySingleton\n'
          '  ISessionState bindState(AuthProvider provider) => provider;\n'
          '  @singleton\n'
          '  ISessionStatusStream get stream;\n'
          '}\n',
        ),
        ['ISessionState moduleMember', 'ISessionStatusStream moduleMember'],
      );
    });

    test('Future<X> registers X; static and unannotated members count', () {
      expect(
        scan(
          '@module\n'
          'abstract class M {\n'
          '  @preResolve\n'
          '  Future<Database> open() async => Database();\n'
          '  static Dio get dio => Dio();\n'
          '  StorageManager get storage;\n'
          '}\n',
        ),
        [
          'Database moduleMember',
          'Dio moduleMember',
          'StorageManager moduleMember',
        ],
      );
    });

    test('private members, void and constructors are skipped', () {
      expect(
        scan(
          '@module\n'
          'abstract class M {\n'
          '  M();\n'
          '  void helper() {}\n'
          '  Foo get _hidden => Foo();\n'
          '}\n',
        ),
        isEmpty,
      );
    });

    test('a member carries its own environment', () {
      expect(
        scan(
          '@module\n'
          'abstract class FirebaseModule {\n'
          "  @lazySingleton\n  @Environment('dev')\n"
          '  FirebaseOptions get dev => throw 0;\n'
          '  @lazySingleton\n  @prod\n'
          '  FirebaseOptions get prod => throw 0;\n'
          '}\n',
        ),
        [
          'FirebaseOptions moduleMember dev',
          'FirebaseOptions moduleMember prod',
        ],
      );
    });

    test('members of a class that is not a module are not registrations', () {
      expect(scan('abstract class M {\n  Foo get foo;\n}\n'), isEmpty);
    });

    test('a nested block does not leak members', () {
      expect(
        scan(
          '@module\n'
          'abstract class M {\n'
          '  Foo build() {\n'
          '    final Bar bar = Bar();\n'
          '    return Foo(bar);\n'
          '  }\n'
          '}\n',
        ),
        ['Foo moduleMember'],
      );
    });
  });

  group('registrations: what is not code', () {
    test('a doc comment example registers nothing', () {
      expect(
        scan(
          '/// Register it with:\n'
          '/// @LazySingleton(as: IAnalytics)\n'
          '/// class MyAnalytics implements IAnalytics {}\n'
          'abstract class IAnalytics {}\n',
        ),
        isEmpty,
      );
    });

    test('a string literal registers nothing', () {
      expect(
        scan(
          "const t = '@injectable\\nclass A {}';\nconst u = '''\n@singleton\nclass B {}\n''';\n",
        ),
        isEmpty,
      );
    });

    test('a block comment registers nothing', () {
      expect(scan('/*\n@injectable\nclass A {}\n*/\nclass B {}\n'), isEmpty);
    });

    test('the line is the annotation, one-based', () {
      final r = registrationsIn('\n\n@injectable\nclass A {}\n').single;
      expect(r.line, 3);
    });
  });

  group('registrations: environments', () {
    test('no environment covers every flavor', () {
      final r = registrationsIn('@injectable\nclass A {}\n').single;
      expect(r.coversEnvironment('dev'), isTrue);
      expect(r.coversEnvironment('prod'), isTrue);
    });

    test('a named environment covers only itself', () {
      final r = registrationsIn(
        "@Environment('dev')\n@injectable\nclass A {}\n",
      ).single;
      expect(r.coversEnvironment('dev'), isTrue);
      expect(r.coversEnvironment('prod'), isFalse);
    });
  });

  group('implementers: what R8 asks, unchanged by the move', () {
    TempWorkspace workspace() => TempWorkspace.create({
      'modules/a/feature/lib/a.dart':
          'class A implements IFoo, IBar {}\n'
          '@LazySingleton(as: IBaz)\nclass B {}\n'
          'class C extends IQux {}\n'
          'class D with IMixin {}\n'
          'class E implements INotAContract {}\n',
      'modules/a/feature/lib/a.g.dart':
          '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
          'class G implements IGenerated {}\n',
      'platform/shell/lib/s.dart': 'class S implements IFoo {}\n',
    });

    test('every supertype mention and as: counts, per owner', () {
      final ws = workspace();
      final owners = ownersImplementing(
        [
          ScanUnit('a', '${ws.root}/modules/a/feature'),
          ScanUnit(null, '${ws.root}/platform/shell'),
        ],
        {'IFoo', 'IBar', 'IBaz', 'IQux', 'IMixin', 'IGenerated'},
      );
      expect(owners, {
        'IFoo': {'a'},
        'IBar': {'a'},
        'IBaz': {'a'},
        'IQux': {'a'},
        'IMixin': {'a'},
      });
    });

    test('a package with no owner is not an owner', () {
      final ws = workspace();
      expect(
        ownersImplementing(
          [
            ScanUnit(null, '${ws.root}/platform/shell'),
          ],
          {'IFoo'},
        ),
        isEmpty,
      );
    });

    test('unlike registrations, a bare implements counts here', () {
      final ws = workspace();
      expect(
        ownersImplementing(
          [
            ScanUnit('a', '${ws.root}/modules/a/feature'),
          ],
          {'IFoo'},
        ),
        {
          'IFoo': {'a'},
        },
      );
      expect(scan('class A implements IFoo {}\n'), isEmpty);
    });
  });

  group('declared types, generated files and lookups', () {
    test('typesDeclaredIn reads the hand-written classes and mixins', () {
      final ws = TempWorkspace.create({
        'p/lib/a.dart':
            'abstract class IA {}\n'
            'sealed class B {}\n'
            'abstract interface class C {}\n'
            'mixin M {}\n'
            'class _Private {}\n'
            'typedef T = int;\n',
        'p/lib/a.g.dart':
            '// GENERATED CODE - DO NOT MODIFY BY HAND\nclass Generated {}\n',
      });
      expect(typesDeclaredIn('${ws.root}/p'), {'IA', 'B', 'C', 'M'});
    });

    group('isGeneratedSource', () {
      const gen = '// GENERATED CODE - DO NOT MODIFY BY HAND\n';

      test('a conventional name or a gen/ folder, with the header, is '
          'generated', () {
        final ws = TempWorkspace.create({
          'p/pubspec.yaml': 'name: p\n',
          for (final name in [
            'a.g.dart',
            'a.freezed.dart',
            'a.config.dart',
            'a.module.dart',
            'a.gr.dart',
            'src/gen/gen.dart',
            'generated/x.dart',
          ])
            'p/lib/$name': '${gen}class X {}\n',
          'p/lib/a.mocks.dart': '// Mocks generated by Mockito 5.4.4\n',
          'p/lib/generated_plugin_registrant.dart':
              '//\n// Generated file. Do not edit.\n//\n',
          'p/lib/module.dart': 'class X {}\n',
        });
        final root = '${ws.root}/p';
        for (final name in [
          'a.g.dart',
          'a.freezed.dart',
          'a.config.dart',
          'a.module.dart',
          'a.gr.dart',
          'a.mocks.dart',
          'generated_plugin_registrant.dart',
          'src/gen/gen.dart',
          'generated/x.dart',
        ]) {
          expect(
            isGeneratedSource('$root/lib/$name', packageRoot: root),
            isTrue,
            reason: name,
          );
        }
        expect(
          isGeneratedSource('$root/lib/module.dart', packageRoot: root),
          isFalse,
        );
      });

      test('a name or folder without the generator header is hand-written', () {
        final ws = TempWorkspace.create({
          'p/pubspec.yaml': 'name: p\n',
          'p/lib/size_ext.g.dart': 'final a = 16.w;\n',
          'p/lib/src/gen/hand.dart': 'final a = 16.w;\n',
          'p/lib/late.g.dart': 'class A {}\n$gen',
        });
        final root = '${ws.root}/p';
        for (final name in [
          'size_ext.g.dart',
          'src/gen/hand.dart',
          'late.g.dart',
        ]) {
          expect(
            isGeneratedSource('$root/lib/$name', packageRoot: root),
            isFalse,
            reason: name,
          );
        }
      });

      test('firebase_options_* and gen-l10n output (named by l10n.yaml) need '
          'no header', () {
        final ws = TempWorkspace.create({
          'p/pubspec.yaml': 'name: p\n',
          'p/l10n.yaml': 'output-dir: lib/src/gen/language\n',
          'p/lib/firebase_options_dev.dart': '// CI-only stub\n',
          'p/lib/src/gen/language/app_localizations.dart': "import 'x';\n",
          'p/lib/src/gen/other/app_localizations.dart': "import 'x';\n",
        });
        final root = '${ws.root}/p';
        expect(
          isGeneratedSource(
            '$root/lib/firebase_options_dev.dart',
            packageRoot: root,
          ),
          isTrue,
        );
        expect(
          isGeneratedSource(
            '$root/lib/src/gen/language/app_localizations.dart',
            packageRoot: root,
          ),
          isTrue,
        );
        expect(
          isGeneratedSource(
            '$root/lib/src/gen/other/app_localizations.dart',
            packageRoot: root,
          ),
          isFalse,
        );
      });

      test('the checkout path never decides: a root under gen/ or generated/ '
          'does not turn the whole package generated', () {
        final ws = TempWorkspace.create({
          'gen/repo/p/pubspec.yaml': 'name: p\n',
          'gen/repo/p/lib/a.dart': 'class A {}\n',
          'generated/repo/p/pubspec.yaml': 'name: p\n',
          'generated/repo/p/lib/a.dart': 'class A {}\n',
        });
        for (final dir in ['gen', 'generated']) {
          final root = '${ws.root}/$dir/repo/p';
          expect(
            isGeneratedSource('$root/lib/a.dart', packageRoot: root),
            isFalse,
            reason: dir,
          );
        }
      });
    });

    test('supertype scan reads code, not comments, and strips import '
        'prefixes', () {
      final ws = TempWorkspace.create({
        'p/pubspec.yaml': 'name: p\n',
        'p/lib/a.dart':
            '/// Mirrors ThemeStorageImpl: implements IProse\n'
            '// class Old implements IComment {}\n'
            "const s = 'implements IString';\n"
            'class A implements c.IPrefixed, IPlain<int> {}\n'
            'class B extends Base with c.IMixin, IOther {}\n'
            '@LazySingleton(as: c.IBound)\nclass C {}\n',
      });
      final owners = ownersImplementing(
        [ScanUnit('m', '${ws.root}/p')],
        {
          'IProse',
          'IComment',
          'IString',
          'IPrefixed',
          'IPlain',
          'IMixin',
          'IOther',
          'IBound',
        },
      );
      expect(owners.keys.toSet(), {
        'IPrefixed',
        'IPlain',
        'IMixin',
        'IOther',
        'IBound',
      });
    });

    test('typesDeclaredIn ignores a commented-out or templated class', () {
      final ws = TempWorkspace.create({
        'p/pubspec.yaml': 'name: p\n',
        'p/lib/a.dart':
            '// class IOld {}\n'
            "const t = '''\nclass IGen {}\n''';\n"
            '/*\nabstract class IBlock {}\n*/\n'
            'abstract class IReal {}\n',
      });
      expect(typesDeclaredIn('${ws.root}/p'), {'IReal'});
    });

    test('optionalLookupsIn finds getItOrNull and getAllOrEmpty only', () {
      final lookups = optionalLookupsIn(
        'final a = getItOrNull<IA>();\n'
        'final b = getAllOrEmpty<IB>();\n'
        'final c = getIt<IC>();\n'
        '// getItOrNull<ID>()\n'
        "final s = 'getItOrNull<IE>()';\n",
      );
      expect(
        [for (final l in lookups) '${l.type}@${l.line}'],
        [
          'IA@1',
          'IB@2',
        ],
      );
    });
  });
}
