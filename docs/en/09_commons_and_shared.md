# 09. Using Shared Components (Commons & Reusable UI)

To ensure a high degree of consistency in User Experience and to adhere to the **DRY (Don't Repeat Yourself)** principle, the codebase clearly demarcates reusable components into two specialized module packages: **`core_base_ui`** (Design System) and **`feature_shared`** (Shared Widgets).

---

## 🏛️ 1. Reusable Components Demarcation Map

Developers must clearly grasp architectural boundaries to place shared resources and Widgets in the correct locations:

```text
                        [ REUSABLE RESOURCES & WIDGETS ]
                                        │
             ┌──────────────────────────┴──────────────────────────┐
             ▼ (Contains raw Tokens/Resources only - No Widgets)    ▼ (Contains all shared Widgets)
    [ core_base_ui (Design Tokens) ]                    [ feature_shared (Common Widget Library) ]
    - Fonts, Colors (Color Palette, Themes)             - Raw, atomic Widgets (CustomButton, CustomInputField)
    - Static Assets (Images, SVG Icons)                 - Business Widgets containing logic (JobCardWidget, UserAvatar)
    - Language translation files (L10n ARB)             - Shared Dialog frame (AppDialog)
    - UI Extensions (context.themeExtension)            - Feedback states (LoadingWidget, EmptyWidget)
```

---

## 🎨 2. Core Design System: `packages/core/base_ui`

This package acts as the physical **Design System** (containing only constant values, styles, and assets) of the application.

> [!IMPORTANT]
> **The `core_base_ui` package contains 0 Flutter Widgets**. It is strictly forbidden to manually create a `widgets/` directory or place UI Widget classes in this package to avoid complicating the dependency lifecycle.

- **Typography & Extensions (Dart Power)**:
  Use Extensions to write extremely short UI source code that auto-scales according to the device screen size:
  - Get primary color: `context.themeExtension.primary` instead of the verbose `Theme.of(context).primaryColor`.
  - Quick spacing: `16.verticalSpace` or `8.horizontalSpace` (Supported via integrated ScreenUtil).
  - Quick typography: `context.textTheme.titleMedium`.
  - Quick language translation: `context.l10n.keyName`.
- **Generated Assets**: Manage images/icons via auto-generated `Assets.gen.dart`.

---

## 🧬 3. Shared Widget Library: `packages/features/shared`

This package was created to contain **all reusable UI Widgets** of the application, divided into two main categories:

### A. Raw UI Widgets (Atomic Widgets)
UI components that do not carry business logic but are customized according to the brand's design:
- `CustomButton`: Brand-standard button (rectangle, circle, outlined, dropdown), with built-in Haptic Feedback and loading effects.
- `CustomInputField`: Data input field with built-in validation, character counter, and error states.
- `LoadingWidget`, `EmptyWidget`: System status indicators.

### B. Business Widgets (Domain-Aware Widgets)
Widgets displayed commonly across multiple screens but **have direct references to data entity models (`Entities`)** or need to call UseCases:
- `JobCardWidget`: Receives a `JobEntity` parameter and displays job card details.
- `UserAvatar`: Receives a `UserEntity` parameter to load an avatar and a border based on user role.

### Dependency Rules:
Widgets in `feature_shared` can depend on `domain_*`, `core_common`, and `core_base_ui` packages.

---

## 🛠️ 4. The 3-Step Process Before Writing A New Component

To avoid creating dozens of duplicate Widgets that bloat the application size:

1. **Step 1: Search for raw widgets** in `packages/features/shared/lib/` to see if a similar button or input field already exists.
2. **Step 2: Search for business widgets** in `packages/features/shared/lib/` to see if a colleague has previously written a display card for this object.
3. **Step 3: Consult Extensions** to see if date/currency formatting utilities have already been defined in `core_common`.

*If not present, proceed to write anew in the correct subdirectory within `feature_shared` and export it via the main barrel file (`feature_shared.dart`) to share resources across the entire system.*

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
