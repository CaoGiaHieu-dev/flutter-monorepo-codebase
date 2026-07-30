# Shared UI Components (`feature_shared`)

Reusable presentation widgets shared across feature packages. Import via `package:feature_shared/...`.

> **Do not** import `package:app/presentation/shared/...` — that path does not exist. Widgets live in this package only.

`core_base_ui` holds theme tokens, assets, and global l10n — **not** widgets.

## Directory Structure

```
lib/
├── buttons/           # CustomButton and variants
├── inputs/            # CustomInputField
├── feedback/          # LoadingWidget, EmptyWidget, LoadingMoreWidget
├── navigation/        # AppBarCustom, DotDivider
├── media/             # Network image + assets picker helpers
├── layout/            # KeepAlive, refresh, text scale helpers
├── dialogs/           # AppDialog, overlays, toast, bottom sheets
├── di/                # Micro-package DI module
└── feature_shared.dart
```

## Usage

```dart
import 'package:feature_shared/buttons/custom_button.dart';
import 'package:feature_shared/inputs/custom_input_field.dart';
import 'package:feature_shared/feedback/loading_widget.dart';
import 'package:feature_shared/dialogs/app_overlay.dart';

CustomButton.rectangle(
  onPressed: () => handleSubmit(),
  child: Text('Submit'),
);

CustomInputField(
  controller: emailController,
  hintText: 'Enter your email',
);

AppOverlay.showToast(content: 'Saved');
```

## Rules

- Callers apply `flutter_screenutil` (`.w` / `.h` / `.sp` / `.r`) **before** passing sizes into shared widgets.
- Shared atomic widgets must stay UI-agnostic — do not scale constructor params internally.
- Prefer `context.colorScheme` / `AppTextStyles` from `core_base_ui` for theming.
- Feature-specific copy must use the owning feature's l10n; shared widgets that need strings should take them as parameters or use `core_base_ui` global l10n.
