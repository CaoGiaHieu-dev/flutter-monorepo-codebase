# Shared UI Kit (`core_ui_kit`)

Reusable, feature-agnostic presentation widgets. Import via `package:core_ui_kit/...`.

Lives under `platform/` rather than `modules/*/feature/` on purpose: it is a shared library every feature may depend on, not a removable feature. It depends only on other core packages and never on a feature.

> **Do not** import a shared widget from an app package (`package:mobile_app/...`) — apps hold no widgets. Widgets live in this package only.

`core_base_ui` holds theme tokens, assets, and global l10n — **not** widgets.

## Directory Structure

```
lib/
├── buttons/           # CustomButton and variants
├── inputs/            # CustomInputField
├── feedback/          # LoadingWidget, EmptyWidget, LoadingMoreWidget
├── navigation/        # AppBarCustom, DotDivider
├── media/             # Cached network image
├── layout/            # KeepAlive, refresh, text scale helpers
├── dialogs/           # AppDialog, overlays, toast, bottom sheets
├── utils/             # SharedUiConstants — the kit's own constants
├── di/                # Micro-package DI module
└── core_ui_kit.dart
```

## Usage

```dart
import 'package:core_ui_kit/buttons/custom_button.dart';
import 'package:core_ui_kit/inputs/custom_input_field.dart';
import 'package:core_ui_kit/feedback/loading_widget.dart';
import 'package:core_ui_kit/dialogs/app_overlay.dart';

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

- Callers apply `core_responsive` (`context.w` / `context.h` / `context.sp` / `context.r`) **before** passing sizes into shared widgets.
- Shared atomic widgets must stay UI-agnostic — do not scale constructor params internally.
- Take brand colours from `context.colors.*` (the `ThemeSystemExtension` palette) and text styles from `AppTextStyles`, both from `core_base_ui`. Avoid `context.colorScheme`: `ThemeProvider` wires only `primary` and `surface` of Material's `ColorScheme` to the palette — see `docs/en/guides/11_design_system.md` §2.
- Feature-specific copy must use the owning feature's l10n; shared widgets that need strings should take them as parameters or use `core_base_ui` global l10n.
