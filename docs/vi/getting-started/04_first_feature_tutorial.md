<!-- translated-from: docs/en/getting-started/04_first_feature_tutorial.md@b65f8b3 -->
# 04 · Tutorial: Feature đầu tiên của bạn trong 30 phút

## Mục tiêu

Bạn dựng một module **notes** nhỏ, từ đầu tới cuối. Nó có một màn hình liệt kê ghi chú. Một use case cấp dữ liệu cho màn hình, một repository cấp cho use case, và một data source giả cấp cho repository. Home có thêm một nút mở màn hình đó.

Sau đó bạn chạy mọi CI gate, build app, rồi gỡ module ra. Bạn chạm vào mỗi tầng một lần: feature, domain, data và một package API của module. Mỗi bước đều nói rõ chạy lệnh gì và bạn sẽ thấy gì.

Mất khoảng 30 phút. Phần lớn thời gian là chờ generator và `build_runner` chạy.

## Điều kiện cần

- **Đã cài đặt xong.** [`01_setup.md`](01_setup.md) đã hoàn tất, hoặc ít nhất `dart tools/workspace_setup/configure.dart --stub-firebase` đã chạy xong.
- **Cây thư mục sạch.** `git status` không in gì. Bước cuối dùng git để hoàn tác mọi thứ.
- **Chạy lệnh từ thư mục gốc repo.** Bước nào cần thư mục khác sẽ ghi rõ `cd`.
- **Không cần đọc gì trước.** Mỗi bước có link tới hướng dẫn giải thích nó, nếu bạn muốn biết vì sao.

---

## 1. Sinh feature

```bash
dart tools/module_generator/generate.dart 1 notes "" 1 1 --apps mobile
```

Các tham số là: `1` một feature, `notes` tên của nó, `""` không có tiền tố package, `1` Provider, `1` một route dạng stack (`IFeatureRouteModule`). `--apps mobile` giữ module ngoài `apps/admin`.

Lệnh chạy khoảng 90 giây và kết thúc bằng:

```text
[V] Module "feature_notes" created.
```

Sau đó nó in danh sách "What is left for you to do by hand". Bạn có thể bỏ qua: route đã được điền sẵn. Mục 3 của danh sách nhắc tới `core_di`, nhưng tutorial này đặt navigator trong package API riêng của module (bước 9, RULE-22).

Xem những gì đã thay đổi:

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

Generator đã thêm `- { id: notes, layers: [feature] }` vào manifest của mobile. Rồi nó chạy `composer sync`, lệnh này viết lại ba file còn lại. Đừng bao giờ sửa tay ba file đó (RULE-16).

Chạy các test mà generator đã viết:

```bash
cd modules/notes/feature && flutter test && cd -
```

Kết quả mong đợi: `All tests passed!`.

## 2. Sinh package domain và data

```bash
dart tools/module_generator/generate.dart 2 notes --apps mobile
dart tools/module_generator/generate.dart 3 notes --apps mobile
```

Sinh domain trước, vì package data phụ thuộc vào nó. Mỗi lần chạy kết thúc bằng `[V] Module "domain_notes" created.` (rồi tới `data_notes`). Dòng trong manifest giờ là `- { id: notes, layers: [data, domain, feature] }`.

Mỗi package có sẵn một stub: `INotesRepository` với phương thức giữ chỗ `ping()`, và `NotesRepositoryImpl`. Bạn sẽ thay cả hai ngay sau đây.

## 3. Viết domain: entity, hợp đồng, use case

Domain là Dart thuần: không Flutter, không Dio, không `core_*` (RULE-03). Tạo entity:

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

Thay hợp đồng repository được sinh sẵn. Mọi method đều trả về một `Result`:

```dart
// modules/notes/domain/lib/src/repositories/i_notes_repository.dart
import 'package:domain_core/domain_core.dart';

import '../entities/note_entity.dart';

/// Implemented by `NotesRepositoryImpl` in `data_notes`.
abstract class INotesRepository {
  Future<Result<List<NoteEntity>>> getNotes();
}
```

Tạo use case. Nó là factory `@injectable` và chỉ làm một việc (RULE-49):

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

## 4. Viết tầng data: model, data source giả, repository

Model đọc JSON và tự map sang entity:

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

Data source là bản giả, trả về hai ghi chú từ bộ nhớ. Nó trả về model, không bao giờ trả entity (RULE-41). Thư mục là `data_sources/`, không bao giờ là `datasources/` (RULE-40):

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

Thay repository được sinh sẵn. `execute()` biến mọi lỗi bị ném thành `Failure`, còn `mapper` biến model thành entity (RULE-42):

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

## 5. Sinh code và barrel

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/notes/domain/lib
dart tools/barrel_generator/generate.dart modules/notes/data/lib
```

`build_runner` viết các file Freezed, JSON và DI. Sau đó barrel generator export các file mới của bạn, nên `package:domain_notes/domain_notes.dart` giờ đã có `NoteEntity` và `GetNotesUseCase`. Barrel luôn chạy sau codegen (RULE-75).

Kiểm tra lát cắt này:

```bash
flutter analyze modules/notes
```

Kết quả mong đợi: `No issues found!`.

## 6. Inject use case vào provider

Feature phải khai báo domain mà nó dùng (RULE-06). Trong `modules/notes/feature/pubspec.yaml`, thêm `domain_notes` dưới `dependencies:`, ngay sau `domain_core`:

```yaml
# modules/notes/feature/pubspec.yaml — under dependencies:
  domain_notes:
    path: ../domain
```

Rồi resolve workspace:

```bash
flutter pub get
```

Thay provider được sinh sẵn. Use case đi vào qua constructor, không bao giờ qua `getIt` (RULE-11). Provider vẫn là factory `@injectable`, vì nó thuộc về một màn hình (RULE-10):

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

`executeOperation` hiện loading, chạy use case và lưu dữ liệu của nó. Route vẫn tạo provider bằng `getIt<NotesProvider>()`. Giờ lời gọi đó dựng cả chuỗi: provider, use case, repository, data source.

## 7. Hiện danh sách trên page

Mọi chuỗi hiển thị đều lấy từ các file ARB của feature (RULE-34), với key dạng `lowerCamelCase` (RULE-35). Thay cả hai file:

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

Dòng `//` phía trên mỗi khối chỉ để nêu tên file. ARB là JSON thuần, nên đừng dán dòng đó vào. Rồi sinh phần Dart:

```bash
cd modules/notes/feature && flutter gen-l10n && cd -
```

Thay page được sinh sẵn. Mọi kích thước đều đi qua `context` hoặc một design token (RULE-30, RULE-33):

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

Page không tự tạo provider. Route đã làm việc đó, nên bọc thêm lần nữa ở đây sẽ tạo instance thứ hai (RULE-21).

Constructor của provider đã đổi, nên phần đăng ký DI của nó phải được sinh lại:

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/notes/feature/lib
```

## 8. Cập nhật test và thêm test của riêng bạn

Test được sinh sẵn dựng `NotesProvider()` không tham số, nên giờ chúng không compile được nữa. Hãy đưa cho chúng một repository giả. Ở repo này fake được viết tay; không dùng thư viện mock nào (RULE-61).

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

Thay test của provider:

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

Thay test của page. Page phải nằm dưới `ResponsiveInit`, vì mọi kích thước trong nó đều đi qua `context` (RULE-62):

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

Giờ hãy thêm một test của riêng bạn, cho repository. Nó nằm trong thư mục `test/` của chính package data (RULE-60). Tạo thư mục và file:

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

Chạy cả hai bộ test:

```bash
cd modules/notes/feature && flutter test && cd -
cd modules/notes/data && flutter test && cd -
```

Kết quả mong đợi: `All tests passed!` hai lần — bốn test trong feature, hai test trong package data.

## 9. Cho Home mở màn hình notes

`feature_home` không được import `feature_notes` (RULE-04). Nó tới màn hình qua một navigator interface nằm trong **package API** của module notes, `notes_api` (RULE-22). Không generator nào dựng package này; nó chỉ gồm hai file.

Tạo pubspec của package:

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

Tạo interface:

```dart
// modules/notes/api/lib/src/navigators/notes_navigator.dart
import 'package:flutter/widgets.dart';

/// Routes owned by the notes module, for other features to reach.
/// Resolve it with `getItOrNull<NotesNavigator>()`.
abstract class NotesNavigator {
  void toNotes(BuildContext context);
}
```

Thêm layer `api` vào dòng của module trong `apps/mobile/app_manifest.yaml`:

```yaml
# apps/mobile/app_manifest.yaml — under modules:
  - { id: notes, layers: [api, data, domain, feature] }
```

Ghép nó vào app, resolve, và export các file của nó:

```bash
dart tools/composer/composer.dart sync
flutter pub get
dart tools/barrel_generator/generate.dart modules/notes/api/lib
```

`sync` in ra `✅ 2 app(s) composed, 35 workspace members.`

**Implement navigator trong feature.** Trong `modules/notes/feature/pubspec.yaml`, thêm dưới `dependencies:`:

```yaml
# modules/notes/feature/pubspec.yaml — under dependencies:
  notes_api:
    path: ../api
```

Rồi tạo phần implement trong `routing/` của feature. Nó push route, nên nút quay lại đưa bạn về Home:

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

**Gọi nó từ Home.** Trong `modules/home/feature/pubspec.yaml`, thêm dưới `dependencies:`:

```yaml
# modules/home/feature/pubspec.yaml — under dependencies:
  notes_api:
    path: ../../notes/api
```

Thêm key `openNotes` vào hai file ARB của Home, `modules/home/feature/assets/language/en.arb` và `vi.arb`:

```json
"openNotes": "Open notes"
```

```json
"openNotes": "Mở ghi chú"
```

Nhớ thêm dấu phẩy sau key đứng trước, vì ARB là JSON chặt. Rồi thêm hai import vào `modules/home/feature/lib/src/pages/home_page.dart`. Giữ danh sách theo thứ tự chữ cái: `core_common` đứng trước `core_di`, còn `notes_api` đứng sau `material_ui`.

```dart
// modules/home/feature/lib/src/pages/home_page.dart — two new imports
import 'package:core_common/core_common.dart';
import 'package:notes_api/notes_api.dart';
```

Rồi thêm một nút ngay sau `TextButton` "Refresh profile" trong `Column`:

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

`getItOrNull` giữ cho Home chạy được trong một app không có module notes (RULE-12). `context` lấy thẳng từ widget (RULE-23).

Sinh lại mọi thứ mà các chỉnh sửa vừa rồi chạm tới:

```bash
cd modules/home/feature && flutter gen-l10n && cd -
flutter pub get
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/notes/feature/lib
```

## 10. Xem trên thiết bị (tuỳ chọn)

```bash
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev
```

Trong app mẫu, Home nằm sau màn đăng nhập của module auth. File `env.dev` đã commit để trống `BASE_URL`, nên đăng nhập không thể thành công cho tới khi bạn trỏ nó vào một backend. Với tutorial này thì không sao: widget test ở bước 8 chứng minh page chạy đúng, và lần build APK bên dưới chứng minh app compile được cùng nó.

Nếu có backend: bấm **Mở ghi chú** trên Home. Hai ghi chú hiện ra, và nút quay lại đưa bạn về Home.

---

## Kiểm tra

Chạy các gate mà CI chạy, theo đúng thứ tự. Mỗi dòng ghi kèm thứ mà một lần chạy đạt sẽ in ra.

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

Smoke test DI boot đồ thị DI thật của `apps/mobile` cho mọi flavor. Đó là bằng chứng các đăng ký mới của bạn resolve được (RULE-63).

Kết thúc bằng một lần build thật, vì analyze sạch chưa phải là build được (RULE-77):

```bash
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev && cd -
```

Kết quả mong đợi: `✓ Built build/app/outputs/flutter-apk/app-dev-debug.apk`. Lần build đầu tiên mất vài phút.

## Dọn dẹp: gỡ module

`notes` không phải module mẫu, nên `remove_sample` không biết tới nó. Gỡ một module của chính bạn gồm bốn thao tác.

1. **Bỏ lời gọi ở Home.** Hoàn tác các chỉnh sửa của bước 9 trong `modules/home/feature`: dependency `notes_api`, key `openNotes` trong hai file ARB, hai import và cái nút. Nếu bạn chưa commit chúng, một lệnh là đủ:

   ```bash
   git restore modules/home/feature
   ```

2. **Bỏ module khỏi mọi manifest đang ghép nó.** Xoá dòng `- { id: notes, … }` khỏi `apps/mobile/app_manifest.yaml`, rồi ghép lại:

   ```bash
   dart tools/composer/composer.dart sync
   ```

   Lệnh này viết lại danh sách `workspace:` ở root, `apps/mobile/pubspec.yaml` và `injection.dart` mà không còn các package notes.

3. **Xoá thư mục của module**, kể cả các file được sinh:

   ```bash
   rm -rf modules/notes
   ```

4. **Dựng lại những gì từng tham chiếu tới nó:**

   ```bash
   flutter pub get
   cd modules/home/feature && flutter gen-l10n && cd -
   dart run build_runner build --workspace
   flutter analyze
   ```

`git status` lại trống trơn, và `flutter analyze` in ra `No issues found!`.

> [!TIP]
> Trên một bản clone dùng xong bỏ thì có lối tắt: `git restore . && git clean -fdx modules/notes`, rồi `dart tools/workspace_setup/configure.dart --stub-firebase` để dựng lại mọi file được sinh.

---

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| Generator thoát với mã 64: `feature_notes` đã tồn tại | Một lần thử trước để lại `modules/notes/` | Gỡ nó như ở phần *Dọn dẹp*, rồi làm lại từ đầu |
| `Undefined name 'NoteEntity'` (hoặc `GetNotesUseCase`) ở một package khác | Barrel của domain chưa export các file mới | Chạy barrel generator cho `modules/notes/domain/lib` sau `build_runner` (bước 5) |
| `The class 'NotesProvider' doesn't have an unnamed constructor with 0 arguments`, hoặc test không compile | `module.module.dart` hoặc các test được sinh vẫn dựng `NotesProvider()` | Chạy lại `build_runner` (cuối bước 7) và thay hai test (bước 8) |
| `context.l10nNotes.emptyNotes` không tồn tại | Chưa chạy `gen-l10n` sau khi sửa ARB | `cd modules/notes/feature && flutter gen-l10n` |
| `flutter pub get` lỗi ở `notes_api` | Layer `api` chưa có trong manifest, hoặc đã bỏ qua `composer sync` | Thêm `api` vào dòng notes, rồi `composer sync` và `flutter pub get` (bước 9) |
| `flutter analyze` báo `directives_ordering` trong `home_page.dart` | Các import mới sai thứ tự chữ cái | `core_common` đứng trước `core_di`; `notes_api` đứng sau `material_ui` |
| `composer verify` fail sau khi bạn sửa `injection.dart` hay khối managed của một pubspec | Các vùng đó là code được sinh | Hoàn tác phần sửa tay và chạy `composer sync` (RULE-16) |
| Smoke test DI fail với `… is not registered` | Thiếu một đăng ký, hoặc code sinh ra đã cũ | Chạy lại `build_runner`; kiểm tra class có mang annotation của nó ([`05_di.md`](../guides/05_di.md)) |

---

## Bạn đã học được gì, và đi tiếp từ đâu

Bạn đã dùng mọi mảnh ghép mà một module thật cần: generator và manifest, một domain Dart thuần, một tầng data không bao giờ ném lỗi, một provider nhận dependency qua constructor, một page định kích thước qua `context`, một package API cho điều hướng xuyên feature, và các gate.

| Muốn hiểu sâu hơn về… | Đọc |
|:--|:--|
| Feature package, route và đa ngôn ngữ của nó | [`../guides/01_new_feature.md`](../guides/01_new_feature.md) |
| Entity, use case, repository, data source thật | [`../guides/02_new_domain_data.md`](../guides/02_new_domain_data.md) |
| Provider hay BLoC | [`../guides/03_state_management.md`](../guides/03_state_management.md) |
| Route và điều hướng xuyên feature | [`../guides/04_routing.md`](../guides/04_routing.md) |
| Một data source HTTP thật | [`../guides/08_networking.md`](../guides/08_networking.md) |
| Vì sao các tầng được tách như vậy | [`../architecture/01_overview.md`](../architecture/01_overview.md) |
| Mọi luật được nhắc tới ở trên | [`../reference/01_rules.md`](../reference/01_rules.md) |
