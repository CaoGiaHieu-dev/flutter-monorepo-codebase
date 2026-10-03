<!-- translated-from: docs/en/guides/12_module_isolation.md@a5b62df -->
# Cô lập Module bằng Git Submodule

## Mục tiêu

Một team chỉ checkout đúng module của mình, build được cả app từ đó, và không bao giờ nhìn thấy source của team khác. Bạn tách một module thành repository riêng, làm việc trên bản checkout từng phần, khôi phục phần lắp ráp trước khi commit, và cho một module một package API để feature khác phụ thuộc vào.

## Điều kiện cần

- Một bản checkout đầy đủ build được — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).
- **Vì sao chuyện này khả thi**, vì sao ở đây submodule tốt hơn private pub registry, và cô lập **không** mua cho bạn những gì — [`../architecture/01_overview.md` § 6](../architecture/01_overview.md#6-cô-lập-module--vì-sao-nó-hoạt-động-và-giới-hạn-của-nó).
- Ai sở hữu cái gì, theo từng module — [`../architecture/01_overview.md` § 4](../architecture/01_overview.md#4-ai-sở-hữu-cái-gì).

---

## 1. Tách một module thành repository riêng

Làm một lần cho mỗi module, bởi người quản lý monorepo. Ví dụ với `auth`.

```bash
# 1. Cắt module ra kèm nguyên lịch sử.
#    git-filter-repo là tool đang được bảo trì; git-subtree cũng dùng được.
git clone <monorepo-url> /tmp/auth-extract
cd /tmp/auth-extract
git filter-repo --path modules/auth/ --path-rename modules/auth/:

# 2. Đẩy lên repository của chính nó.
git remote add origin <auth-repo-url>
git push -u origin main

# 3. Quay lại monorepo, thay thư mục bằng một submodule.
cd <monorepo>
git rm -r --cached modules/auth
rm -rf modules/auth
git submodule add <auth-repo-url> modules/auth
git commit -m "chore: auth becomes a submodule"
```

Không có gì khác phải đổi. `app_manifest.yaml` vẫn ghi `- { id: auth, layers: [api, domain, data, feature] }`, vì manifest gọi tên module chứ không gọi tên thư mục.

> [!IMPORTANT]
> Chỉ làm điều này **sau khi** module đã ổn định. Di chuyển một file giữa hai module sẽ thôi là một thao tác rename và trở thành xoá-rồi-thêm trên hai repository, với phần review bị chẻ đôi.

## 2. Làm việc trên bản checkout từng phần

Một dev thuộc team auth clone monorepo mà không lấy source của team khác:

```bash
git clone <monorepo-url> && cd <monorepo>
git submodule update --init modules/auth      # chỉ của họ
dart tools/composer/bootstrap.dart            # bỏ những gì không có trên đĩa để pub resolve được
flutter pub get                               # composer cần workspace đã resolve
dart tools/composer/composer.dart sync        # lắp ráp những gì đang có (mọi app)
dart tools/workspace_setup/configure.dart     # pub get + l10n + codegen + barrels
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev
```

**Vì sao cần bước `bootstrap`.** `composer.dart` import `package:path` và `package:yaml`, nên chỉ chạy được trong một workspace đã resolve. Mà một bản checkout từng phần vừa clone thì không resolve được:

- danh sách `workspace:` ở root và path dependency của từng app (đều đã commit) vẫn nêu mọi module;
- một submodule chưa init là thư mục rỗng không có `pubspec.yaml`;
- nên `flutter pub get` từ chối cả workspace (*"No workspace packages matching `modules/home/feature`"*).

`tools/composer/bootstrap.dart` phá vòng lặp đó. Nó không import package nào, nên chạy được khi chưa hề có `.dart_tool/`. Nó chỉ **xoá bớt** mục, và chỉ trong các vùng `composer:managed` của `pubspec.yaml` ở root và của từng `apps/<id>/pubspec.yaml`: mọi mục mà thư mục không có `pubspec.yaml`. Sau đó `sync` viết lại đúng các vùng đó, cùng `injection.dart` của từng app, từ manifest. Trên bản checkout đầy đủ, `bootstrap` không có gì để bỏ và không ghi gì, nên chạy lúc nào cũng an toàn. `--dry-run` cho xem nó sẽ bỏ những gì.

`bootstrap` từ chối — không ghi gì, exit 1 — khi một module **đang có** khai path dependency viết tay tới một module không có (ví dụ `modules/auth/data` mà thiếu `modules/auth/domain`): không vùng managed nào bỏ được dòng đó, nên pub vẫn sẽ lỗi. Hãy init thêm submodule còn thiếu.

Hãy chạy `sync` cho **mọi app** — đừng thu hẹp bằng `--app mobile`. Danh sách `workspace:` ở root luôn được dựng lại từ tất cả app và bỏ đi những gì không có trên đĩa, nhưng `--app mobile` để nguyên `apps/admin/pubspec.yaml`, vẫn khai path dependency tới các module đang thiếu (chẳng hạn `settings`) — và khi đó `flutter pub get` không resolve được workspace.

`sync` in một cảnh báo cho mỗi package được khai mà không có trên đĩa, và — vì các manifest vẫn khai `tabs`, `dashboard`, `entry` v.v. là `provided` trong khi các module đăng ký chúng đang vắng mặt — một cảnh báo cho mỗi capability mà không package nào đang compose còn đăng ký (V3), kết thúc bằng *"`composer verify` fails until each is fixed"*. Trên bản checkout từng phần, điều đó là bình thường: `sync` vẫn ghi. Đừng sửa manifest để làm im cảnh báo.

App chạy. Trên bản checkout chỉ có auth, nó không có màn hình home, không settings, không dashboard — và vẫn boot được, vì mọi lần shell tra cứu một hợp đồng do module sở hữu đều là `getItOrNull` hoặc `getAllOrEmpty` (`arch_check` R8), và không file nào của shell import một module (`arch_check` R10 trong app, R1 trong `platform_app_shell`).

`dart tools/composer/composer.dart verify` **fail** trên bản checkout từng phần, và đúng là phải thế: nó ngầm bật `--strict`, nên một module được khai trong manifest mà không có trên đĩa là lỗi (*"N declared package(s) missing from disk"*, exit 1). Đó là kiểm tra mà CI Gate 0 chạy, trên runner có đủ mọi submodule. DI smoke test của app cũng fail theo cùng cách, do thiết kế — nó giữ graph khớp với `capabilities:` của manifest (RULE-81), mà một capability khai `provided` lại không có bên implement. Ở máy local, `flutter analyze` mới là kiểm tra có ý nghĩa.

Code của team khác không chỉ là "không được build" — nó **không nằm trên đĩa**, và `modules/home` chỉ là một thư mục rỗng chứ không phải source: `.gitmodules` chỉ ghi path và URL của nó, còn commit được chốt là một mục gitlink trong cây của superproject.

## 3. Khôi phục phần lắp ráp trước khi commit

`composer sync` — và `bootstrap` chạy trước nó — sửa những file **đã được commit**:

- danh sách `workspace:` trong `pubspec.yaml` gốc
- path dependency trong `apps/<id>/pubspec.yaml`, cho mỗi app được sync
- `apps/<id>/lib/di/injection.dart`, cũng vậy
- vùng `report` của `apps/<id>/README.md` — nó liệt kê app ghép những gì — và, khi một giá trị mặc định suy ra thay đổi, vùng `facts` của `apps/<id>/lib/app/app_profile.dart`

Không truyền `--app` thì là mọi app — tối đa chín file khi có `mobile` và `admin`.

Trên bản checkout từng phần, nó ghi vào đó một phép lắp ráp thiếu module. Điều đó đúng ở local và sai khi commit: nó sẽ xoá các module khác khỏi app của tất cả mọi người.

`sync` nói thẳng điều đó, gọi tên các file nó vừa ghi lại, và in ra lệnh khôi phục. Sau khi `bootstrap` đã cắt bớt `pubspec.yaml` ở root và hai pubspec của app, một bản checkout chỉ có auth in ra:

```
⚠️ PARTIAL COMPOSITION — 8 declared package(s) are not on disk.
  What was just written composes only what is present, which is exactly right
  for working on one module. It is wrong to commit: it would drop the other
  modules from the app for everyone.

  Files changed:
    apps/admin/lib/di/injection.dart
    apps/admin/README.md
    apps/mobile/lib/di/injection.dart
    apps/mobile/README.md

  Restore them before you commit:
    git checkout -- apps/admin/lib/di/injection.dart apps/admin/README.md apps/mobile/lib/di/injection.dart apps/mobile/README.md
```

`sync` chỉ gọi tên những gì *nó* đã đổi; `bootstrap` đã in dòng khôi phục riêng cho các pubspec, và `git status` cho thấy đủ từng file. Trước khi commit, hãy khôi phục từng file:

```bash
git checkout -- pubspec.yaml apps/mobile/pubspec.yaml apps/admin/pubspec.yaml \
  apps/mobile/lib/di/injection.dart apps/admin/lib/di/injection.dart \
  apps/mobile/README.md apps/admin/README.md \
  apps/mobile/lib/app/app_profile.dart apps/admin/lib/app/app_profile.dart
```

`pubspec.lock` không nằm trong số đó: các member của workspace không được ghi vào nó, và bỏ một member chỉ làm nó đổi khi member đó là nơi cuối cùng dùng một package bên ngoài nào đó — hãy xem cả nó trong `git status`.

Và nếu vẫn lỡ commit, **CI Gate 0 sẽ fail**. `composer verify` sinh lại từ manifest trên một runner có đầy đủ submodule, rồi so với các file đã commit. Một phép lắp ráp thiếu module thì không thể khớp, nên sai lầm dừng lại ở pull request thay vì đi vào bản phát hành.

Đó là tấm lưới an toàn đáng hiểu rõ: trạng thái local được phép thiếu, trạng thái đã commit thì không, và một cái máy — không phải người review — giữ ranh giới đó.

## 4. Tạo package API cho module

`core_di` chỉ giữ những hợp đồng mà chính platform cần, đặt tên theo thứ nó cần — một phiên đăng nhập (`ISessionState`), một vị trí (`ISignInLocation`, `IPostSignInLocation`). Một hợp đồng tồn tại để *một feature chạm tới module khác* thuộc về module đó: package API của nó, `modules/<id>/api`, tên `<id>_api`. Các sample có hai — `auth_api` (`AuthNavigator`, `IAuthActionHandler`) và `home_api` (`HomeNavigator`).

Module generator tạo được nó (loại 6):

```bash
# payment_api tại modules/payment/api: một stub PaymentNavigator, không có DI module.
# Thêm `layers: [api, …]` vào mọi app_manifest.yaml (hoặc chỉ các id trong --apps), chạy
# composer sync, pub get và barrel generator. Nếu feature_payment tồn tại cùng route
# của nó, nó cũng được thêm payment_api vào dependencies: và một PaymentNavigatorImpl
# trong routing/.
dart tools/module_generator/generate.dart 6 payment
```

Thêm `payment_api` vào `dependencies:` của từng nơi dùng, và implement các hợp đồng khác (action handler, builder) trong feature sở hữu, với `payment_api` trong `dependencies:` của nó. Nơi dùng resolve mọi hợp đồng đó bằng `getItOrNull`. File mới trong package API chỉ đến được nơi dùng qua barrel của package — hãy sinh lại nó bằng `dart tools/barrel_generator/generate.dart modules/payment/api/lib` (RULE-75).

Những gì `arch_check` giữ bạn tuân theo:

- **R3** — package API chỉ phụ thuộc `platform/foundation/*` và package Flutter/pub: không phụ thuộc domain/data/feature của chính module nó, không phụ thuộc module khác hay API của module khác, không phụ thuộc group platform khác. Một feature được import API của module khác, không bao giờ import package feature, data hay domain của nó; một package data không import API của module nào khác.
- **R8** — một type khai báo trong package API và chỉ được implement dưới `modules/` phải resolve bằng `getItOrNull` bên ngoài module của nó.
- **R1 / R10** — không package platform nào và không file app nào (trừ `injection.dart`) import nó.

Layer `api` không cần mục `di_groups`: `composer` biến nó thành workspace member, không bao giờ thành dependency của app hay một dòng trong `injection.dart`. Trong bản checkout từng phần (§2), module mà bạn import API của nó cũng phải được checkout — package API nằm bên trong nó. `remove_sample <id>` giữ lại package API mà package khác vẫn import, báo ai đang import, và để mục manifest thành `{ id: <id>, layers: [api] }`; chạy lại khi không còn ai import package đó.

---

## Kiểm tra

```bash
# Trên bản checkout từng phần
flutter analyze                             # No issues found! — kiểm tra có ý nghĩa ở máy local
cd apps/mobile && flutter run --flavor dev --dart-define-from-file=env.dev   # boot được dù thiếu các module vắng mặt
git status                                  # trước khi commit: không có file lắp ráp nào trong danh sách

# Trên bản checkout đầy đủ (thứ CI chạy)
dart tools/composer/composer.dart verify    # ✅ Generated artifacts are up to date.
dart tools/arch_check/check.dart            # R1, R3, R8, R10 đều đạt
```

`composer verify` **fail** trên bản checkout từng phần là do thiết kế (*"N declared package(s) missing from disk"*, exit 1). Hãy chạy nó trên bản checkout đầy đủ, hoặc để CI Gate 0 lo.

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `flutter pub get`: *No workspace packages matching `modules/home/feature`* | Phần lắp ráp đã commit nêu một module không có trên đĩa | `dart tools/composer/bootstrap.dart`, rồi `pub get` và `composer sync` (§2) |
| `bootstrap` thoát với mã 1 và không ghi gì | Một module đang có khai path dependency viết tay tới một module vắng mặt | Init thêm submodule đó (§2) |
| `pub get` vẫn lỗi sau `sync` | `sync` chạy với `--app mobile`, để `apps/admin/pubspec.yaml` vẫn trỏ tới các module thiếu | Chạy `sync` cho mọi app (§2) |
| CI Gate 0 fail trên PR của bạn | Một phần lắp ráp từng phần đã bị commit | Khôi phục các file composition rồi push lại (§3) |
| `composer verify` fail ở máy local | Bạn đang ở bản checkout từng phần | Đúng như dự kiến; hãy chạy nó trên bản checkout đầy đủ (*Kiểm tra*) |
| Bên tiêu thụ không thấy một kiểu từ `<id>_api` | Barrel của package API chưa export nó, hoặc module chưa được checkout | Chạy barrel generator; init module đó (§4) |

## Liên quan

- Luật: RULE-04 (chỉ chạm tới module qua `<id>_api`), RULE-05 (mọi module đều gỡ được), RULE-12 (tra cứu tuỳ chọn), RULE-16 (lắp ráp qua manifest) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/01_overview.md` § 6](../architecture/01_overview.md#6-cô-lập-module--vì-sao-nó-hoạt-động-và-giới-hạn-của-nó) — vì sao cô lập hoạt động, và giới hạn của nó
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — `composer` và `bootstrap`
