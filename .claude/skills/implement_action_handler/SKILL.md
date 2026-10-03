---
name: implement_action_handler
description: Use when feature A must trigger a UI-bound action owned by feature B without importing it — e.g. "call logout from settings", "add an action handler", "trigger another feature's dialog, bottom sheet or provider method". Declares I*ActionHandler in the owner's <id>_api package, implements it in the owning feature's handlers/ (a dialog or sheet is its own widget class), and resolves it with getItOrNull.
---

# Skill: Implement a cross-feature action handler

Use this skill when feature A must trigger a one-shot, UI-bound action that feature B owns, without importing B:
"call logout from settings", "open another feature's bottom sheet", "trigger its provider method".

**Guide:** [`docs/en/guides/10_cross_feature.md`](../../../docs/en/guides/10_cross_feature.md) § 7.
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-04, RULE-12, RULE-23, RULE-25, RULE-36,
RULE-78. Cite them; do not restate them.

## When to use

| Need | Prefer |
| :--- | :--- |
| Navigate to another feature's screen | a **navigator** (`AuthNavigator` in `auth_api`, `HomeNavigator` in `home_api`) — [`implement_navigation_route`](../implement_navigation_route/SKILL.md) |
| Shared business logic without UI | a **domain use case** |
| Observe the session | an **agnostic stream** (`ISessionStatusStream`, `ISessionState` in `core_di`) |
| Inject a widget or scope from another feature | `IAppTreeWrapper` (`core_di`) or a widget-builder interface in the owner's `<id>_api` |
| Trigger feature B's Provider method, dialog or sheet from feature A | **action handler** (`I*ActionHandler`) |

The sample: `feature_settings` depends on `auth_api` and offers its logout row only when
`getItOrNull<IAuthActionHandler>()` is non-null (`modules/settings/feature/lib/src/pages/settings_page.dart`);
with no auth feature composed the row is not offered. `remove_sample auth` keeps `auth_api` while Settings imports it.

## Steps

### Step 1: Declare the interface in the owner's API package

`modules/<owner>/api/lib/src/actions/i_<name>_action_handler.dart`, package `<owner>_api` (foundation and Flutter
dependencies only — `arch_check` R3). If the module has no API package yet,
`dart tools/module_generator/generate.dart 6 <owner>` creates it (navigator stub included) —
[`create_api_package`](../create_api_package/SKILL.md). `core_di` is for product-neutral contracts only. Real code,
`modules/auth/api/lib/src/actions/i_auth_action_handler.dart`:

```dart
import 'package:flutter/widgets.dart';

abstract class IAuthActionHandler {
  /// Signs the user out; completes once the stored session is cleared.
  Future<void> logout(BuildContext context);
}
```

A new file reaches consumers only through the generated package barrel: [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator) says when to regenerate it.

### Step 2: Implement it in the owning feature

The owning feature declares `<owner>_api` under `dependencies:` (`feature_auth` lists `auth_api`) and implements
the interface in `modules/<owner>/feature/lib/src/handlers/<name>_action_handler_impl.dart`
(`modules/auth/feature/lib/src/handlers/auth_action_handler_impl.dart`):

```dart
import 'package:auth_api/auth_api.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';

@Injectable(as: IAuthActionHandler)
class AuthActionHandlerImpl implements IAuthActionHandler {
  @override
  Future<void> logout(BuildContext context) =>
      context.read<AuthProvider>().logout();
}
```

A handler that opens a dialog or a bottom sheet **names a widget class** — never an inline tree in the builder
(RULE-36): the class lives in its own `*_dialog.dart` / `*_bottom_sheet.dart` file in the owning feature.

```dart
@Injectable(as: INoteActionHandler)
class NoteActionHandlerImpl implements INoteActionHandler {
  @override
  Future<void> newNote(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const NewNoteBottomSheet(), // widgets/new_note_bottom_sheet.dart
  );
}
```

Its strings come from the owning feature's ARB ([`localize_feature`](../localize_feature/SKILL.md)). Handler
classes are `*ActionHandlerImpl`; the `I` prefix belongs to the interface only (RULE-78, `arch_check` R15).

### Step 3: Call it from the consuming feature

```dart
final authActions = getItOrNull<IAuthActionHandler>();
// …
if (authActions != null) ListTile(onTap: () => authActions.logout(context))
```

The consumer lists `<owner>_api` under `dependencies:` and must **not** import the owning feature. Resolve with
`getItOrNull` (RULE-12 — `arch_check` R8 blocks a throwing `getIt` here); when the action must visibly do
something without the owner, branch on the null and show a fallback or hide the control rather than letting the
widget throw. Pass `BuildContext` straight from the widget (RULE-23).

### Step 4: Codegen

```bash
dart run build_runner build --workspace
```

Then fully restart the app: hot reload does not pick up new DI registrations. If the feature's annotated
handler imports an interface you just added to `<owner>_api`, regenerate that package's barrel **before**
`build_runner`, as [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator) says.

## Naming

| Kind | File | Class |
| :--- | :--- | :--- |
| Interface | `i_<name>_action_handler.dart` | `I*ActionHandler` |
| Implementation | `<name>_action_handler_impl.dart` | `*ActionHandlerImpl` |

## Related

- [`docs/en/guides/10_cross_feature.md`](../../../docs/en/guides/10_cross_feature.md) — all six cross-feature communication models
- [`implement_dependency_injection`](../implement_dependency_injection/SKILL.md) — `getIt` vs `getItOrNull` vs `getAllOrEmpty`

## Verify

```bash
dart run build_runner build --workspace
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart                         # R3 consumer imports the API not the feature, R8 getItOrNull, R15 I prefix
dart tools/composer/composer.dart verify                 # the api layer is in the manifest
cd modules/<consumer>/feature && flutter test            # test with and without a fake handler registered
cd apps/mobile && flutter test test/di_smoke_test.dart   # the handler factory builds from the real graph
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77, after a DI or dependency change
```
