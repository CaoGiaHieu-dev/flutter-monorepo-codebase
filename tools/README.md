# 🛠️ Development Tools

Thư mục này chứa các công cụ CLI dành cho lập trình viên, hỗ trợ tự động hóa quy trình phát triển và duy trì chất lượng mã nguồn cho Flutter Clean Architecture Monorepo.

> **Quy tắc**: Tất cả CLI Tools trong thư mục này **CẤM** sử dụng `print()`. Bắt buộc dùng `stdout.writeln()` và `stderr.writeln()`.

---

## 📁 Directory Structure

```text
tools/
├── module_generator/               # 🏗️ CLI tạo module mới (Feature/Domain/Data/Core)
│   ├── generate.dart               # Entry point chính
│   └── src/
│       ├── input_actions.dart       # Xử lý tham số CLI & interactive input
│       ├── module_type.dart         # Enum ModuleType, StateManagementType, ModuleConfig
│       ├── pubspec_generator.dart   # Sinh pubspec.yaml với dependencies đúng tầng
│       └── common_helpers.dart      # Tạo thư mục, đăng ký workspace/DI, chạy CLI
├── barrel_generator/               # 📦 Sinh barrel files (export *.dart)
│   └── generate.dart               # Quét lib/ và tạo file barrel tự động
├── code_review/                    # 🤖 AI-powered code review (Gemini)
│   ├── code_review.dart            # Script review chính
│   ├── review_prompt.md            # Prompt AI chi tiết
│   ├── code_review_config.json     # Cấu hình (API key, scope, etc.)
│   ├── CODE_REVIEW_README.md       # Tài liệu chi tiết
│   └── QUICK_START.md              # Hướng dẫn nhanh
├── unused_checker/                 # 🧹 Phân tích & dọn dẹp tài nguyên dư thừa
│   ├── check_script.dart           # Chạy tất cả kiểm tra cùng lúc
│   ├── check_unused_assets.dart    # Phát hiện assets không sử dụng
│   ├── check_unused_file.dart      # Phát hiện files mồ côi
│   ├── check_unused_packages.dart  # Phát hiện packages không sử dụng
│   └── check_unused_translate.dart # Phát hiện translation keys dư thừa
├── workspace_setup/                # ⚙️ Thiết lập workspace tổng
│   └── configure.dart              # Script đa nền tảng (Windows/macOS/Linux)
├── firebase/                       # 🔥 Cấu hình Firebase đa môi trường
│   └── firebase_config.dart
├── theme_generator/                # 🎨 Sinh Splash Screen & App Icons
│   └── theme_setting.dart
├── android_compliance/             # 📱 Kiểm tra Android 15+ 16KB Page Size
├── dependency_sync.dart            # 📦 Đồng bộ version thư viện từ catalog
└── check_outdated.dart             # 🔄 Kiểm tra thư viện lỗi thời trên pub.dev
```

---

## 🚀 Quick Usage

### 🏗️ Module Generator (Tạo Module Mới)
```bash
# Cú pháp: dart tools/module_generator/generate.dart <loại> <tên> [<thư_mục>] [<SM>] [<route>]
# <loại>: 1=Feature, 2=Domain, 3=Data, 4=Core, 5=Custom
# <SM> (chỉ Feature): 1=Provider, 2=BLoC, 3=None
# <route> (chỉ Feature): 1=IFeatureRouteModule, 2=IDashboardTabModule (tab Bottom Nav), 3=none
# Chon 2 chi khi feature la tab chinh sau login - xem docs/{en,vi}/guides/04_routing.md.

# Feature 'profile' + Provider + stack routes (IFeatureRouteModule):
dart tools/module_generator/generate.dart 1 profile "" 1 1

# Feature 'chat' + BLoC + tab Bottom Nav (IDashboardTabModule):
dart tools/module_generator/generate.dart 1 chat "" 2 2

# Domain micro-package 'payment':
dart tools/module_generator/generate.dart 2 payment

# Data micro-package 'payment':
dart tools/module_generator/generate.dart 3 payment

# Core package 'logging':
dart tools/module_generator/generate.dart 4 logging

# Interactive (không tham số):
dart tools/module_generator/generate.dart
```

CLI đăng ký workspace + `app` pubspec + `injection.dart` và scaffold stub DI route.
**Không** cần (và **không** nên) sửa list `$…Route` trong `app_router.dart` — host thu thập bằng DI.

### 📦 Barrel Files Generator
```bash
# Sinh cho 1 package cụ thể:
dart tools/barrel_generator/generate.dart packages/features/profile/lib

# Sinh cho domain micro-package:
dart tools/barrel_generator/generate.dart packages/domain/auth/lib
```

### 📦 Dependency Sync (Version Catalog)
```bash
# Đồng bộ version từ pubspec_dependencies.yaml xuống tất cả packages:
dart tools/dependency_sync.dart

# Chỉ kiểm tra xung đột (không ghi đè) — phù hợp CI/pre-commit:
dart tools/dependency_sync.dart --check
```

### 🔄 Outdated Dependencies Checker
```bash
# Kiểm tra phiên bản thư viện đã lỗi thời trên pub.dev:
dart tools/check_outdated.dart
```

### 🤖 Code Review (AI-Powered)
```bash
# Review toàn bộ files:
dart tools/code_review/code_review.dart --all

# Review file cụ thể:
dart tools/code_review/code_review.dart --file lib/main.dart

# Review files đã thay đổi:
dart tools/code_review/code_review.dart --changed

# Focus vào architecture + security:
dart tools/code_review/code_review.dart --all --focus architecture,security
```

### 🧹 Unused Checker (Dọn Dẹp)
```bash
# Chạy tất cả kiểm tra (khuyên dùng):
dart tools/unused_checker/check_script.dart

# Hoặc chạy riêng từng loại:
dart tools/unused_checker/check_unused_assets.dart
dart tools/unused_checker/check_unused_packages.dart
dart tools/unused_checker/check_unused_translate.dart
dart tools/unused_checker/check_unused_file.dart
```

### ⚙️ Workspace Setup & Config
```bash
# Thiết lập workspace:
dart tools/workspace_setup/configure.dart   # đa nền tảng

# Firebase config:
dart tools/firebase/firebase_config.dart

# Theme (splash + icons):
dart tools/theme_generator/theme_setting.dart
```

---

## 🔑 Prerequisites

- **Dart SDK**: >= 3.13.1
- **Flutter SDK**: >= 3.47.1
- **Ruby**: >= 3.0 (cho Fastlane, chỉ cần khi build CI/CD)
- **Gemini API Key**: Chỉ cần cho Code Review Tool

---

## 💡 Best Practices

### Workflow Tạo Module Mới:
```bash
# 1. Tạo domain + data micro-packages:
dart tools/module_generator/generate.dart 2 payment
dart tools/module_generator/generate.dart 3 payment

# 2. Triển khai code (Entities → Repository Interfaces → UseCases → Models → DataSources → RepositoryImpl)

# 3. Sinh barrel files:
dart tools/barrel_generator/generate.dart packages/domain/payment/lib
dart tools/barrel_generator/generate.dart packages/data/payment/lib

# 4. Sinh mã DI:
dart run build_runner build -d --workspace
```

### Workflow Dọn Dẹp Định Kỳ:
```bash
# 1. Kiểm tra tài nguyên dư thừa:
dart tools/unused_checker/check_script.dart

# 2. Kiểm tra thư viện lỗi thời:
dart tools/check_outdated.dart

# 3. Đồng bộ version:
dart tools/dependency_sync.dart
```

---

**Built with ❤️ for Flutter Clean Architecture Development**