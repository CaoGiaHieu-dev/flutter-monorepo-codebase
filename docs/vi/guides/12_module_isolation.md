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
dart tools/composer/composer.dart sync --app mobile   # lắp ráp những gì đang có
dart tools/workspace_setup/configure.dart     # pub get + codegen + l10n
cd apps/mobile && flutter run --flavor dev
```

App chạy. Nó không có màn hình home, không settings, không dashboard — và vẫn boot được, vì mọi lần shell tra cứu một hợp đồng do module sở hữu đều là `getItOrNull` hoặc `getAllOrEmpty` (`arch_check` R8), và không file nào của shell import một module (`arch_check` R10).

Code của team khác không chỉ là "không được build" — nó **không nằm trên đĩa**, và `modules/home` chỉ là một commit hash trong `.gitmodules` chứ không phải source.

---

## 4. Một cạm bẫy duy nhất, và thứ bắt được nó

`composer sync` sửa những file **đã được commit**:

- danh sách `workspace:` trong `pubspec.yaml` gốc
- path dependency trong `apps/<id>/pubspec.yaml`, cho mỗi app được sync
- `apps/<id>/lib/di/injection.dart`, cũng vậy

Không truyền `--app` thì là mọi app — năm file khi có `mobile` và `admin`.

Trên bản checkout từng phần, nó ghi vào đó một phép lắp ráp thiếu module. Điều đó đúng ở local và sai khi commit: nó sẽ xoá các module khác khỏi app của tất cả mọi người.

`sync` nói thẳng điều đó, gọi tên các file, và in ra lệnh khôi phục:

```
⚠ PARTIAL COMPOSITION — 12 declared package(s) are not on disk.
  Files changed:
    pubspec.yaml
    apps/mobile/pubspec.yaml
    apps/mobile/lib/di/injection.dart

  Restore them before you commit:
    git checkout -- pubspec.yaml apps/mobile/pubspec.yaml apps/mobile/lib/di/injection.dart
```

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
