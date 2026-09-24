# Cô lập Module bằng Git Submodule

**File này trả lời:** làm sao để một team chỉ checkout đúng module của mình, build được cả app từ đó, và không bao giờ nhìn thấy source của team khác?

**Đọc xong bạn có thể:** tách một module thành repository riêng, làm việc trên bản checkout từng phần, và biết chính xác CI đang bảo vệ bạn khỏi sai lầm nào.

---

## 1. Điều gì khiến chuyện này khả thi

Không có gì trong repo này mã hoá vị trí của một package.

`composer` phân giải package **theo tên**, tìm bằng cách quét `pubspec.yaml`. `arch_check` suy ra tầng của package từ tên. `MonorepoHelper` duyệt cây thư mục. Nên một module vắng mặt đơn giản là không được tìm thấy — không tool nào giữ một danh sách để rồi lạc hậu.

Đó là toàn bộ cơ chế. `composer sync` viết ra một phép lắp ráp từ *những gì có trên đĩa*, và một bản build gồm năm module cũng hợp lệ như bản gồm sáu.

Bố cục thư mục lo phần còn lại: `modules/<name>/` chứa mọi tầng của một bounded context, nên ranh giới submodule và ranh giới sở hữu là cùng một đường kẻ. (Xem [bảng quyền sở hữu](../architecture/01_overview.md#4-ai-sở-hữu-cái-gì).)

---

## 2. Tách một module thành repository riêng

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

Không có gì khác phải đổi. `app_manifest.yaml` vẫn ghi `- { id: auth, layers: [domain, data, feature] }`, vì manifest gọi tên module chứ không gọi tên thư mục.

> [!IMPORTANT]
> Chỉ làm điều này **sau khi** module đã ổn định. Di chuyển một file giữa hai module sẽ thôi là một thao tác rename và trở thành xoá-rồi-thêm trên hai repository, với phần review bị chẻ đôi.

---

## 3. Làm việc trên bản checkout từng phần

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

**Vì sao cần bước `bootstrap`.** `composer.dart` import `package:path` và `package:yaml`, nên chỉ chạy được trong một workspace đã resolve — mà một bản checkout từng phần vừa clone thì không resolve được: danh sách `workspace:` ở root và path dependency của từng app (đều đã commit) vẫn nêu mọi module, một submodule chưa init là thư mục rỗng không có `pubspec.yaml`, và `flutter pub get` từ chối cả workspace vì nó (*"No workspace packages matching `modules/home/feature`"*). `tools/composer/bootstrap.dart` phá vòng lặp đó. Nó không import package nào, nên chạy được khi chưa hề có `.dart_tool/`, và nó chỉ **xoá bớt** — trong các vùng `composer:managed` của `pubspec.yaml` ở root và của từng `apps/<id>/pubspec.yaml` — mọi mục mà thư mục không có `pubspec.yaml`. Sau đó `sync` viết lại đúng các vùng đó, cùng `injection.dart` của từng app, từ manifest. Trên bản checkout đầy đủ, `bootstrap` không có gì để bỏ và không ghi gì, nên chạy lúc nào cũng an toàn. `--dry-run` cho xem nó sẽ bỏ những gì.

`bootstrap` từ chối — không ghi gì, exit 1 — khi một module **đang có** khai path dependency viết tay tới một module không có (ví dụ `modules/auth/data` mà thiếu `modules/auth/domain`): không vùng managed nào bỏ được dòng đó, nên pub vẫn sẽ lỗi. Hãy init thêm submodule còn thiếu.

Hãy chạy `sync` cho **mọi app** — đừng thu hẹp bằng `--app mobile`. Danh sách `workspace:` ở root luôn được dựng lại từ tất cả app và bỏ đi những gì không có trên đĩa, nhưng `--app mobile` để nguyên `apps/admin/pubspec.yaml`, vẫn khai path dependency tới các module đang thiếu (chẳng hạn `settings`) — và khi đó `flutter pub get` không resolve được workspace.

App chạy. Nó không có màn hình home, không settings, không dashboard — và vẫn boot được, vì mọi lần shell tra cứu một hợp đồng do module sở hữu đều là `getItOrNull` hoặc `getAllOrEmpty` (`arch_check` R8), và không file nào của shell import một module (`arch_check` R10 trong app, R1 trong `platform_app_shell`).

`dart tools/composer/composer.dart verify` **fail** trên bản checkout từng phần, và đúng là phải thế: nó ngầm bật `--strict`, nên một module được khai trong manifest mà không có trên đĩa là lỗi (*"N declared package(s) missing from disk"*). Đó là kiểm tra mà CI Gate 0 chạy, trên runner có đủ mọi submodule. Ở máy local, `flutter analyze` mới là kiểm tra có ý nghĩa.

Code của team khác không chỉ là "không được build" — nó **không nằm trên đĩa**, và `modules/home` chỉ là một thư mục rỗng chứ không phải source: `.gitmodules` chỉ ghi path và URL của nó, còn commit được chốt là một mục gitlink trong cây của superproject.

---

## 4. Một cạm bẫy duy nhất, và thứ bắt được nó

`composer sync` — và `bootstrap` chạy trước nó — sửa những file **đã được commit**:

- danh sách `workspace:` trong `pubspec.yaml` gốc
- path dependency trong `apps/<id>/pubspec.yaml`, cho mỗi app được sync
- `apps/<id>/lib/di/injection.dart`, cũng vậy

Không truyền `--app` thì là mọi app — năm file khi có `mobile` và `admin`.

Trên bản checkout từng phần, nó ghi vào đó một phép lắp ráp thiếu module. Điều đó đúng ở local và sai khi commit: nó sẽ xoá các module khác khỏi app của tất cả mọi người.

`sync` nói thẳng điều đó, gọi tên các file, và in ra lệnh khôi phục:

```
⚠️ PARTIAL COMPOSITION — 7 declared package(s) are not on disk.
  What was just written composes only what is present, which is exactly right
  for working on one module. It is wrong to commit: it would drop the other
  modules from the app for everyone.

  Files changed:
    apps/mobile/pubspec.yaml
    apps/mobile/lib/di/injection.dart
    apps/admin/pubspec.yaml
    apps/admin/lib/di/injection.dart
    pubspec.yaml

  Restore them before you commit:
    git checkout -- apps/mobile/pubspec.yaml apps/mobile/lib/di/injection.dart apps/admin/pubspec.yaml apps/admin/lib/di/injection.dart pubspec.yaml
```

Sau `bootstrap`, hai pubspec của app và `pubspec.yaml` ở root đã chứa sẵn các vùng đã được cắt bớt, nên `sync` không thấy gì cần đổi ở đó và chỉ gọi tên hai file `injection.dart`. `bootstrap` đã in dòng khôi phục riêng cho các pubspec; `git status` cho thấy đủ cả năm file. Trước khi commit, hãy khôi phục toàn bộ:

```bash
git checkout -- pubspec.yaml apps/mobile/pubspec.yaml apps/admin/pubspec.yaml \
  apps/mobile/lib/di/injection.dart apps/admin/lib/di/injection.dart
```

`pubspec.lock` không nằm trong số đó: các member của workspace không được ghi vào nó, và bỏ một member chỉ làm nó đổi khi member đó là nơi cuối cùng dùng một package bên ngoài nào đó — hãy xem cả nó trong `git status`.

Và nếu vẫn lỡ commit, **CI Gate 0 sẽ fail**. `composer verify` sinh lại từ manifest trên một runner có đầy đủ submodule, rồi so với các file đã commit. Một phép lắp ráp thiếu module thì không thể khớp, nên sai lầm dừng lại ở pull request thay vì đi vào bản phát hành.

Đó là tấm lưới an toàn đáng hiểu rõ: trạng thái local được phép thiếu, trạng thái đã commit thì không, và một cái máy — không phải người review — giữ ranh giới đó.

---

## 5. Vì sao không dùng private pub registry

Private registry (`dart pub publish` lên server tự dựng) là cách còn lại để giấu source của team này khỏi team kia, và nó là câu trả lời đúng cho một package có **nhiều nơi tiêu thụ và nhịp phát hành chậm** — một design system, một SDK analytics.

Nó là câu trả lời sai ở đây:

| | Submodule | Private registry |
|:--|:--|:--|
| Thay đổi xuyên module | mỗi repository một PR, review bình thường | publish, chờ, bump version, publish lại |
| Lặp nhanh ở local | sửa thẳng source đang có sẵn | `dependency_overrides` ở từng nơi tiêu thụ |
| Lệch version | một commit hash, đã chốt | hai app dùng hai version của cùng một module |
| Chi phí dựng | một lệnh `git submodule add` | một server, auth, credential cho CI |

Các module sản phẩm thay đổi cùng nhau và ship cùng nhau. Submodule giữ cho điều đó rẻ.

---

## 6. Cô lập **không** mua cho bạn những gì

- **Không phải ranh giới bảo mật.** Quyền truy cập submodule là quyền trên repository. Ai đã có bản checkout thì có source; cơ chế này chặn việc vô tình phụ thuộc lẫn nhau và việc đọc lướt qua, không chặn được người cố tình.
- **Không miễn cho bạn khỏi hợp đồng.** Một module vẫn chỉ nói chuyện với module khác qua `core_di`. Cái thay đổi là: phá vỡ một hợp đồng giờ hiện ra thành một PR xuyên repository thay vì một chỉnh sửa âm thầm.
- **Không phải kỷ luật tuỳ chọn.** Mọi rào chắn khiến checkout từng phần khả thi — lookup tuỳ chọn của R8, lệnh cấm import của R10, phân giải theo tên — đều ngừng hoạt động ngay khi ai đó thêm một import trực tiếp. Chính vì thế mỗi rào chắn đều đánh hỏng build chứ không chỉ nằm trong một buổi review.

---

## Liên quan

- [Tổng quan kiến trúc — ai sở hữu cái gì](../architecture/01_overview.md)
- [Tham chiếu tooling — `composer`](../reference/03_tooling.md)
- [Luật — khả năng gỡ bỏ feature](../reference/01_rules.md)
