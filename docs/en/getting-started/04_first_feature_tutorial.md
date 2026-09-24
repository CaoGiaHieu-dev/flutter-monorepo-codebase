# 04 · Tutorial: Your First Feature in 30 Minutes

## Goal

You build a small **notes** module, end to end. It has a screen that lists notes. A use case feeds the screen, a repository feeds the use case, and a fake data source feeds the repository. Home gets a button that opens the screen.

Then you run every CI gate, build the app, and remove the module again. You touch each layer once: feature, domain, data and a module API package. Every step says what to run and what you should see.

It takes about 30 minutes. Most of that is the generator and `build_runner` working.

## Prerequisites

- **Setup is done.** [`01_setup.md`](01_setup.md) is finished, or at least `dart tools/workspace_setup/configure.dart --stub-firebase` has run to the end.
- **The tree is clean.** `git status` prints nothing. The last step uses git to undo everything.
- **Commands run from the repository root.** A step that needs another directory says `cd`.
- **Nothing to read first.** Each step links the guide that explains it, if you want the why.

---

## 1. Generate the feature

```bash
dart tools/module_generator/generate.dart 1 notes "" 1 1 --apps mobile
```

The arguments are: `1` a feature, `notes` its name, `""` no package prefix, `1` Provider, `1` a stack route (`IFeatureRouteModule`). `--apps mobile` keeps the module out of `apps/admin`.

It runs for about 90 seconds and ends with:

```text
[V] Module "feature_notes" created.
```

It then prints a "What is left for you to do by hand" list. You can skip it: its routes are already filled in. Its item 3 mentions `core_di`, but this tutorial puts the navigator in the module's own API package instead (step 9, RULE-22).

See what changed:

```bash
git status --short
```

```text
 M apps/mobile/app_manifest.yaml
 M apps/mobile/lib/di/injection.dart
 M apps/mobile/pubspec.yaml
 M pubspec.yaml
?? modules/notes/
```

The generator added `- { id: notes, layers: [feature] }` to the mobile manifest. Then it ran `composer sync`, which rewrote the other three files. Never edit those three by hand (RULE-16).

Run the tests the generator wrote:

```bash
cd modules/notes/feature && flutter test && cd -
```

Expect `All tests passed!`.

## 2. Generate the domain and data packages

```bash
dart tools/module_generator/generate.dart 2 notes --apps mobile
dart tools/module_generator/generate.dart 3 notes --apps mobile
```

Generate the domain first, because the data package depends on it. Each run ends with `[V] Module "domain_notes" created.` (then `data_notes`). The manifest line now reads `- { id: notes, layers: [data, domain, feature] }`.

Each package comes with one stub: `INotesRepository` with a placeholder `ping()`, and `NotesRepositoryImpl`. You replace both next.

## 3. Write the domain: entity, contract, use case

The domain is pure Dart: no Flutter, no Dio, no `core_*` (RULE-03). Create the entity:

```dart
// modules/notes/domain/lib/src/entities/note_entity.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'note_entity.freezed.dart';

/// One note, as the business rules see it. No JSON here: parsing is the
/// data layer's job.
@freezed
abstract class NoteEntity with _$NoteEntity {
  const NoteEntity._();

  const factory NoteEntity({required String id, required String title}) =
      _NoteEntity;
}
```

Replace the generated repository contract. Every method returns a `Result`:

```dart
// modules/notes/domain/lib/src/repositories/i_notes_repository.dart
import 'package:domain_core/domain_core.dart';

import '../entities/note_entity.dart';

/// Implemented by `NotesRepositoryImpl` in `data_notes`.
abstract class INotesRepository {
  Future<Result<List<NoteEntity>>> getNotes();
}
```

Create the use case. It is an `@injectable` factory and does one thing (RULE-49):

```dart
// modules/notes/domain/lib/src/usecases/get_notes_usecase.dart
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../entities/note_entity.dart';
import '../repositories/i_notes_repository.dart';

/// Returns every note.
@injectable
class GetNotesUseCase extends BaseUseCase<List<NoteEntity>, NoParams> {
  GetNotesUseCase(this._repository);

  final INotesRepository _repository;

  @override
  Future<Result<List<NoteEntity>>> call(NoParams params) {
    return _repository.getNotes();
  }
}
```

## 4. Write the data layer: model, fake data source, repository

The model parses JSON and maps itself to the entity:

```dart
// modules/notes/data/lib/src/models/note_model.dart
import 'package:data_core/data_core.dart';
import 'package:domain_notes/domain_notes.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'note_model.freezed.dart';
part 'note_model.g.dart';

@freezed
abstract class NoteModel with _$NoteModel implements BaseModel<NoteEntity> {
  const NoteModel._();

  const factory NoteModel({
    @JsonKey(name: 'id') required String id,
    @JsonKey(name: 'title') required String title,
  }) = _NoteModel;

  factory NoteModel.fromJson(Map<String, dynamic> json) =>
      _$NoteModelFromJson(json);

  @override
  NoteEntity toEntity() => NoteEntity(id: id, title: title);
}
```

The data source is a fake that serves two notes from memory. It returns models, never entities (RULE-41). The folder is `data_sources/`, never `datasources/` (RULE-40):

```dart
// modules/notes/data/lib/src/data_sources/local/notes_local_data_source.dart
import 'package:injectable/injectable.dart';

import '../../models/note_model.dart';

abstract class INotesLocalDataSource {
  Future<List<NoteModel>> getNotes();
}

/// A fake: serves two notes from memory. Swap it for a Retrofit data source
/// (`data_sources/remote/`) or a Drift one later — the repository and
/// everything above it stay the same.
@LazySingleton(as: INotesLocalDataSource)
class NotesLocalDataSource implements INotesLocalDataSource {
  @override
  Future<List<NoteModel>> getNotes() async => const [
    NoteModel(id: '1', title: 'Read the architecture overview'),
    NoteModel(id: '2', title: 'Ship the first feature'),
  ];
}
```

Replace the generated repository. `execute()` turns any thrown error into a `Failure`, and `mapper` turns models into entities (RULE-42):

```dart
// modules/notes/data/lib/src/repositories_impl/notes_repository_impl.dart
import 'package:data_core/data_core.dart';
import 'package:domain_core/domain_core.dart';
import 'package:domain_notes/domain_notes.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/local/notes_local_data_source.dart';
import '../models/note_model.dart';

@LazySingleton(as: INotesRepository)
class NotesRepositoryImpl extends IBaseRepository implements INotesRepository {
  NotesRepositoryImpl(this._local);

  final INotesLocalDataSource _local;

  @override
  Future<Result<List<NoteEntity>>> getNotes() {
    return execute<List<NoteModel>, List<NoteEntity>>(
      _local.getNotes,
      mapper: (models) => [for (final model in models) model.toEntity()],
    );
  }
}
```

## 5. Generate code and barrels

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/notes/domain/lib
dart tools/barrel_generator/generate.dart modules/notes/data/lib
```

`build_runner` writes the Freezed, JSON and DI files. The barrel generator then exports your new files, so `package:domain_notes/domain_notes.dart` now includes `NoteEntity` and `GetNotesUseCase`. Barrels always come after codegen (RULE-75).

Check this slice:

```bash
flutter analyze modules/notes
```

Expect `No issues found!`.

## 6. Inject the use case into the provider

The feature must declare the domain it uses (RULE-06). In `modules/notes/feature/pubspec.yaml`, add `domain_notes` under `dependencies:`, right after `domain_core`:

```yaml
# modules/notes/feature/pubspec.yaml — under dependencies:
  domain_notes:
    path: ../domain
```

Then resolve the workspace:

```bash
flutter pub get
```

Replace the generated provider. The use case arrives through the constructor, never through `getIt` (RULE-11). The provider stays an `@injectable` factory, because it belongs to one screen (RULE-10):

```dart
// modules/notes/feature/lib/src/provider/notes_provider.dart
import 'package:domain_core/domain_core.dart';
import 'package:domain_notes/domain_notes.dart';
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

@injectable
class NotesProvider extends BaseProvider<List<NoteEntity>> {
  NotesProvider(this._getNotes);

  final GetNotesUseCase _getNotes;

  /// Called once, right after construction — `BaseProvider` schedules it.
  @override
  Future<void> initialize() async {
    await super.initialize();
    await executeOperation(
      OperationConfig(operation: () => _getNotes(const NoParams())),
    );
  }
}
```

`executeOperation` shows loading, runs the use case and stores its data. The route still creates the provider with `getIt<NotesProvider>()`. That call now builds the whole chain: provider, use case, repository, data source.

## 7. Show the list on the page

Every visible string comes from the feature's ARB files (RULE-34), with `lowerCamelCase` keys (RULE-35). Replace both files:

```json
// modules/notes/feature/assets/language/en.arb
{
  "@@locale": "en",
  "title": "Notes",
  "emptyNotes": "No notes yet"
}
```

```json
// modules/notes/feature/assets/language/vi.arb
{
  "@@locale": "vi",
  "title": "Ghi chú",
  "emptyNotes": "Chưa có ghi chú nào"
}
```

The `//` line above each block only names the file. ARB is plain JSON, so do not paste it in. Then generate the Dart side:

```bash
cd modules/notes/feature && flutter gen-l10n && cd -
```

Replace the generated page. Every size goes through `context` or a design token (RULE-30, RULE-33):

```dart
// modules/notes/feature/lib/src/pages/notes_page.dart
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:domain_notes/domain_notes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../extensions/extensions.dart';
import '../provider/provider.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10nNotes.title)),
      body: BaseViewWidget<NotesProvider, List<NoteEntity>>(
        emptyWidget: (context, child) => _empty(context),
        builder: (context, notes, child) {
          if (notes.isEmpty) return _empty(context);
          return AdaptiveContent(
            child: ListView.separated(
              padding: EdgeInsets.all(AppSpacing.lg(context)),
              itemCount: notes.length,
              separatorBuilder: (context, index) =>
                  SizedBox(height: AppSpacing.smH(context)),
              itemBuilder: (context, index) => ListTile(
                leading: Icon(Icons.note_outlined, size: context.r(24)),
                title: Text(
                  notes[index].title,
                  style: AppTextStyles.bodyMediumStyle(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: Text(
      context.l10nNotes.emptyNotes,
      style: AppTextStyles.bodyMediumStyle(context),
    ),
  );
}
```

The page does not create its provider. The route already does that, so wrapping it again here would make a second instance (RULE-21).

The provider's constructor changed, so its DI registration must be regenerated:

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/notes/feature/lib
```

## 8. Update the tests and add your own

The generated tests build `NotesProvider()` with no arguments, so they no longer compile. Give them a fake repository. Fakes are hand-written here; the repo uses no mocking library (RULE-61).

```dart
// modules/notes/feature/test/fake_notes_repository.dart
import 'package:domain_core/domain_core.dart';
import 'package:domain_notes/domain_notes.dart';

/// A hand-written fake (the repo uses no mocking library): returns whatever
/// [result] holds.
class FakeNotesRepository implements INotesRepository {
  FakeNotesRepository(this.result);

  Result<List<NoteEntity>> result;

  @override
  Future<Result<List<NoteEntity>>> getNotes() async => result;
}
```

Replace the provider test:

```dart
// modules/notes/feature/test/notes_provider_test.dart
import 'package:domain_core/domain_core.dart';
import 'package:domain_notes/domain_notes.dart';
import 'package:feature_notes/feature_notes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_notes_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the notes on construction', () async {
    final provider = NotesProvider(
      GetNotesUseCase(
        FakeNotesRepository(
          const Result.success([NoteEntity(id: '1', title: 'Hello')]),
        ),
      ),
    );
    addTearDown(provider.dispose);

    // BaseProvider schedules initialize() itself; this waits for it.
    await provider.ensureInitialized();

    expect(provider.isSuccess, isTrue);
    expect(provider.data, [const NoteEntity(id: '1', title: 'Hello')]);
  });
}
```

Replace the page test. The page must sit under `ResponsiveInit`, because every size in it goes through `context` (RULE-62):

```dart
// modules/notes/feature/test/notes_page_test.dart
import 'package:core_responsive/core_responsive.dart';
import 'package:domain_core/domain_core.dart';
import 'package:domain_notes/domain_notes.dart';
import 'package:feature_notes/feature_notes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider_state_management/provider_state_management.dart';

import 'fake_notes_repository.dart';

/// Pumps [NotesPage] the way the route shows it: under `ResponsiveInit`,
/// with this feature's localizations, and its provider created above it.
Future<void> _pumpPage(
  WidgetTester tester, {
  List<NoteEntity> notes = const [NoteEntity(id: '1', title: 'Hello')],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates:
          FeatureNotesLocalizations.localizationsDelegates,
      supportedLocales: FeatureNotesLocalizations.supportedLocales,
      builder: (context, child) => ResponsiveInit(child: child!),
      home: ChangeNotifierProvider(
        create: (_) => NotesProvider(
          GetNotesUseCase(FakeNotesRepository(Result.success(notes))),
        ),
        child: const NotesPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows its localized title and one tile per note', (
    tester,
  ) async {
    await _pumpPage(tester);

    final l10n = FeatureNotesLocalizations.of(
      tester.element(find.byType(NotesPage)),
    )!;
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text(l10n.title)),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, 'Hello'), findsOneWidget);
  });

  testWidgets('says so when there are no notes', (tester) async {
    await _pumpPage(tester, notes: const []);

    final l10n = FeatureNotesLocalizations.of(
      tester.element(find.byType(NotesPage)),
    )!;
    expect(find.text(l10n.emptyNotes), findsOneWidget);
  });

  testWidgets('lays out on a phone and on a tablet', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in const [Size(360, 740), Size(1280, 800)]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await _pumpPage(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(NotesPage), findsOneWidget);
    }
  });
}
```

Now add a test of your own, for the repository. It lives in the data package's own `test/` folder (RULE-60). Create the folder and the file:

```dart
// modules/notes/data/test/notes_repository_impl_test.dart
import 'package:data_notes/data_notes.dart';
import 'package:domain_notes/domain_notes.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingDataSource implements INotesLocalDataSource {
  @override
  Future<List<NoteModel>> getNotes() => throw const FormatException('bad');
}

void main() {
  test('maps every model to an entity', () async {
    final repository = NotesRepositoryImpl(NotesLocalDataSource());

    final result = await repository.getNotes();

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull?.first, isA<NoteEntity>());
    expect(result.dataOrNull, hasLength(2));
  });

  test('turns a thrown error into a Failure instead of throwing', () async {
    final repository = NotesRepositoryImpl(_ThrowingDataSource());

    final result = await repository.getNotes();

    expect(result.isFailure, isTrue);
  });
}
```

Run both suites:

```bash
cd modules/notes/feature && flutter test && cd -
cd modules/notes/data && flutter test && cd -
```

Expect `All tests passed!` twice: four tests in the feature, two in the data package.

## 9. Let Home open the notes screen

`feature_home` may not import `feature_notes` (RULE-04). It reaches the screen through a navigator interface in the notes module's **API package**, `notes_api` (RULE-22). No generator builds one; it is two files.

Create the package's pubspec:

```yaml
# modules/notes/api/pubspec.yaml
name: notes_api
description: "Public API of the notes module — the contracts other features may depend on"
version: 1.0.0
publish_to: none

environment:
  sdk: ">=3.13.3 <4.0.0"
  flutter: ">=3.47.4"

resolution: workspace

dependencies:
  flutter:
    sdk: flutter
```

Create the interface:

```dart
// modules/notes/api/lib/src/navigators/notes_navigator.dart
import 'package:flutter/widgets.dart';

/// Routes owned by the notes module, for other features to reach.
/// Resolve it with `getItOrNull<NotesNavigator>()`.
abstract class NotesNavigator {
  void toNotes(BuildContext context);
}
```

Add the `api` layer to the module's line in `apps/mobile/app_manifest.yaml`:

```yaml
# apps/mobile/app_manifest.yaml — under modules:
  - { id: notes, layers: [api, data, domain, feature] }
```

Compose it, resolve it and export its files:

```bash
dart tools/composer/composer.dart sync
flutter pub get
dart tools/barrel_generator/generate.dart modules/notes/api/lib
```

`sync` prints `✅ 2 app(s) composed, 35 workspace members.`

**Implement the navigator in the feature.** In `modules/notes/feature/pubspec.yaml`, add under `dependencies:`:

```yaml
# modules/notes/feature/pubspec.yaml — under dependencies:
  notes_api:
    path: ../api
```

Then create the implementation in the feature's `routing/`. It pushes the route, so the back arrow returns to Home:

```dart
// modules/notes/feature/lib/src/routing/notes_navigator_impl.dart
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:notes_api/notes_api.dart';

import 'notes_route_module.dart';

@Singleton(as: NotesNavigator)
class NotesNavigatorImpl implements NotesNavigator {
  @override
  void toNotes(BuildContext context) => const NotesRoute().push<void>(context);
}
```

**Call it from Home.** In `modules/home/feature/pubspec.yaml`, add under `dependencies:`:

```yaml
# modules/home/feature/pubspec.yaml — under dependencies:
  notes_api:
    path: ../../notes/api
```

Add an `openNotes` key to Home's two ARB files, `modules/home/feature/assets/language/en.arb` and `vi.arb`:

```json
"openNotes": "Open notes"
```

```json
"openNotes": "Mở ghi chú"
```

Put a comma after the key before it, since ARB is strict JSON. Then add two imports to `modules/home/feature/lib/src/pages/home_page.dart`. Keep the list sorted: `core_common` goes before `core_di`, and `notes_api` after `material_ui`.

```dart
// modules/home/feature/lib/src/pages/home_page.dart — two new imports
import 'package:core_common/core_common.dart';
import 'package:notes_api/notes_api.dart';
```

Then add a button right after the "Refresh profile" `TextButton` in the `Column`:

```dart
// modules/home/feature/lib/src/pages/home_page.dart — after the refresh button
TextButton(
  // getItOrNull: an app composed without the notes
  // module registers no NotesNavigator — the tap then
  // does nothing instead of crashing.
  onPressed: () =>
      getItOrNull<NotesNavigator>()?.toNotes(context),
  child: Text(context.l10nHome.openNotes),
),
```

`getItOrNull` keeps Home working in an app without the notes module (RULE-12). The `context` comes straight from the widget (RULE-23).

Regenerate everything the last edits touched:

```bash
cd modules/home/feature && flutter gen-l10n && cd -
flutter pub get
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/notes/feature/lib
```

## 10. See it on a device (optional)

```bash
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev
```

In the sample app, Home sits behind the auth module's sign-in. The committed `env.dev` leaves `BASE_URL` empty, so sign-in cannot succeed until you point it at a backend. That is fine for this tutorial: the widget tests of step 8 prove the page, and the APK build below proves the app compiles with it.

With a backend: tap **Open notes** on Home. The two notes appear, and the back arrow returns to Home.

---

## Verify

Run the gates CI runs, in its order. Each line shows what a pass prints.

```bash
dart tools/composer/composer.dart verify          # ✅ Generated artifacts are up to date.
dart tools/arch_check/check.dart                  # ✅ All architecture rules hold across 35 packages.
flutter analyze                                   # No issues found!
cd modules/notes/feature && flutter test && cd -  # All tests passed!
cd modules/notes/data && flutter test && cd -     # All tests passed!
cd modules/home/feature && flutter test && cd -   # All tests passed!
cd apps/mobile && flutter test test/di_smoke_test.dart && cd -   # All tests passed!
dart tools/dependency_sync.dart --check           # ✅ Success: All packages ... in perfect sync
dart tools/unused_checker/check_script.dart       # 🎉 FINAL RESULT: All checks passed!
```

The DI smoke test boots the real DI graph of `apps/mobile` for every flavor. It is what proves your new registrations resolve (RULE-63).

Finish with a real build, because a clean analyze is not a build (RULE-77):

```bash
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev && cd -
```

Expect `✓ Built build/app/outputs/flutter-apk/app-dev-debug.apk`. The first build takes several minutes.

## Clean up: remove the module

`notes` is not a sample, so `remove_sample` does not know it. Removing a module you own takes four moves.

1. **Take Home's call out.** Undo the step 9 edits under `modules/home/feature`: the `notes_api` dependency, the `openNotes` key in both ARB files, and the two imports and the button. If you have not committed them, one command does it:

   ```bash
   git restore modules/home/feature
   ```

2. **Drop the module from every manifest that composes it.** Delete the `- { id: notes, … }` line from `apps/mobile/app_manifest.yaml`, then recompose:

   ```bash
   dart tools/composer/composer.dart sync
   ```

   This rewrites the root `workspace:` list, `apps/mobile/pubspec.yaml` and `injection.dart` without the notes packages.

3. **Delete the module's directory**, generated files included:

   ```bash
   rm -rf modules/notes
   ```

4. **Rebuild what referred to it:**

   ```bash
   flutter pub get
   cd modules/home/feature && flutter gen-l10n && cd -
   dart run build_runner build --workspace
   flutter analyze
   ```

`git status` is empty again, and `flutter analyze` prints `No issues found!`.

> [!TIP]
> In a throwaway clone there is a shortcut: `git restore . && git clean -fdx modules/notes`, then `dart tools/workspace_setup/configure.dart --stub-firebase` to rebuild every generated file.

---

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| The generator exits 64: `feature_notes` already exists | An earlier attempt left `modules/notes/` behind | Remove it as in *Clean up*, then start again |
| `Undefined name 'NoteEntity'` (or `GetNotesUseCase`) in another package | The domain barrel does not export the new files yet | Run the barrel generator for `modules/notes/domain/lib` after `build_runner` (step 5) |
| `The class 'NotesProvider' doesn't have an unnamed constructor with 0 arguments`, or tests fail to compile | `module.module.dart` or the generated tests still build `NotesProvider()` | Re-run `build_runner` (end of step 7) and replace the two tests (step 8) |
| `context.l10nNotes.emptyNotes` does not exist | `gen-l10n` has not run since the ARB edit | `cd modules/notes/feature && flutter gen-l10n` |
| `flutter pub get` fails on `notes_api` | The `api` layer is not in the manifest yet, or `composer sync` was skipped | Add `api` to the notes line, then `composer sync` and `flutter pub get` (step 9) |
| `flutter analyze` reports `directives_ordering` in `home_page.dart` | The new imports are out of alphabetical order | `core_common` goes before `core_di`; `notes_api` after `material_ui` |
| `composer verify` fails after you edited `injection.dart` or a pubspec's managed block | Those regions are generated | Revert the hand edit and run `composer sync` (RULE-16) |
| The DI smoke test fails with `… is not registered` | A registration is missing or the codegen is stale | Re-run `build_runner`; check the class carries its annotation ([`05_di.md`](../guides/05_di.md)) |

---

## What you learned, and where to go next

You used every piece a real module needs: the generator and the manifest, a pure-Dart domain, a data layer that never throws, a provider fed by constructor injection, a page sized through `context`, a module API for cross-feature navigation, and the gates.

| To go deeper on… | Read |
|:--|:--|
| The feature package, its routes and l10n | [`../guides/01_new_feature.md`](../guides/01_new_feature.md) |
| Entities, use cases, repositories, real data sources | [`../guides/02_new_domain_data.md`](../guides/02_new_domain_data.md) |
| Provider vs BLoC | [`../guides/03_state_management.md`](../guides/03_state_management.md) |
| Routes and cross-feature navigation | [`../guides/04_routing.md`](../guides/04_routing.md) |
| A real HTTP data source | [`../guides/08_networking.md`](../guides/08_networking.md) |
| Why the layers are split this way | [`../architecture/01_overview.md`](../architecture/01_overview.md) |
| Every rule cited above | [`../reference/01_rules.md`](../reference/01_rules.md) |
