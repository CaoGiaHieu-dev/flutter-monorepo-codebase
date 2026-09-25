# Shared UI Kit (`core_ui_kit`)

Reusable, feature-agnostic presentation widgets and the app's one overlay system. Import the package barrel only:

```dart
import 'package:core_ui_kit/core_ui_kit.dart';
```

Lives under `platform/` rather than `modules/*/feature/` on purpose: it is a shared library every feature may depend on, not a removable feature. It depends only on other platform packages and never on a feature.

> **Do not** import a shared widget from an app package (`package:mobile_app/...`) — apps hold no widgets. Widgets live in this package only.

`core_base_ui` holds theme tokens, assets, and global l10n — **not** widgets.

## Directory Structure

```
lib/
├── core_ui_kit.dart   # the public API (generated barrel)
├── di/                # Micro-package DI module
└── src/
    ├── buttons/       # CustomButton.rectangle
    ├── dialogs/       # AppOverlay (dialogs, toast, loading), OverlayDialogWidget, RetryDialog
    ├── feedback/      # LoadingWidget, EmptyWidget (LoadMoreListView lives in provider_state_management)
    ├── inputs/        # CustomInputField
    ├── layout/        # TextScaleDown
    ├── media/         # CustomCacheNetworkImage
    ├── navigation/    # BottomTransitionPage
    └── utils/         # SharedUiConstants — the kit's own defaults
```

## Usage

```dart
CustomButton.rectangle(
  onPressed: handleSubmit,
  child: Text(submitLabel),
);

CustomInputField(
  controller: emailController,
  hintText: context.l10nAuth.enterYourEmail,
);

AppOverlay.showToast(content: context.l10n.somethingWentWrong);
```

## Overlays

`AppOverlay` is the only overlay system. The app shell mounts `AppOverlayInitializer` in `MaterialApp.builder`; from then on anything — a network callback, a session listener — can raise an overlay without a `BuildContext`. Stacking, bottom to top: loading < dialog < toast.

| Call | What it does |
|:--|:--|
| `AppOverlay.showDialog<T>(builder: …)` | Queues a dialog; one is visible at a time. Returns the result it is closed with (`null` when dismissed). `identity` de-duplicates. |
| `OverlayDialogState.closeDialog([result])` | Closes *this* dialog — a late call never closes the next one. |
| `AppOverlay.dismissDialog(result: …)` / `clearDialogs()` | Closes the visible dialog / it and every queued one. |
| `AppOverlay.showToast(content: …)` / `removeToastOverlay()` | A toast that removes itself after `SharedUiConstants.TOAST_DURATION`. |
| `AppOverlay.showLoading()` / `removeLoadingOverlay()` | The full-screen loading layer. |

A system back while a dialog is visible dismisses a `barrierDismissible` dialog and is swallowed by any other, so the page behind is never popped. The barrier and the loading layer use the palette's `scrim` token (`colorScheme.scrim`). Each dialog is its own `OverlayDialogWidget` subclass in a `*_dialog.dart` file (RULE-36).

## Rules

- Callers apply `core_responsive` (`context.w` / `context.h` / `context.sp` / `context.r`) **before** passing sizes into shared widgets; a widget scales only its own defaults (RULE-31).
- Sizes, radii and spacing come from `AppSpacing` / `AppRadius`, or from `SharedUiConstants` for a widget's own geometry — never a bare number in a widget (RULE-33).
- Take colours from `context.colors.*` (the `ThemeSystemExtension` palette) and text styles from `AppTextStyles`, both from `core_base_ui`. `context.colorScheme` carries the same palette in Material's slots.
- The kit has no ARB (RULE-34): a widget that needs text takes it as a parameter or uses `core_base_ui`'s global l10n.
