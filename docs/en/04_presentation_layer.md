# 04. Presentation & UI Layer (Features Hub)

The Presentation layer is responsible for managing the display lifecycle, receiving user interactions, and painting the UI. In the new architecture, this layer is no longer contained within a single main directory but is divided into **independent Feature Packages** located under `packages/features/` to maximize encapsulation and independence.

---

## 🏛️ 1. Feature Package Organizational Grid (Feature Monorepo Grid)

```text
packages/features/
├── splash/       # Splash Module: Initial launch greeting screen
├── onboarding/   # Onboarding Module: App introduction & initial guide
├── auth/         # Auth Module: Login, Register, Forgot Password
├── dashboard/    # Dashboard Module: Bottom Bar shell only (composes other features' routes)
├── home/         # Home Module: Home tab content (sample)
├── settings/     # Settings Module: Settings tab content (sample) — separate from Home
└── shared/       # Shared Module: Contains shared display widgets across features
```

> **Clean Architecture note:** Dashboard owns **shell chrome only** (`DashboardRouteModule`). Tab screens register `IDashboardTabModule` in their own packages; `AppRouter` assembles branches. See `docs/en/08_routing.md` § Dashboard.

### Internal Structure of a Feature Package (e.g., `feature_auth`)
```text
feature_auth/
├── lib/
│   ├── auth.dart         # Barrel file exposing the Feature's public APIs and Routes
│   ├── src/
│   │   ├── pages/        # Large screens associated with routing (e.g., LoginPage)
│   │   ├── widgets/      # Small specialized widgets used solely for this module
│   │   ├── provider/     # Interface logic controllers (ViewModels)
│   │   └── routing/      # Declares the Feature's specific GoRouter configuration
│   └── di/
│       └── module.dart   # Local DI initialization for the Auth package
```

---

## 🧬 2. The Heart of the UI: MVVM / MVI Mechanism (Agnostic State Management)

The system provides an agnostic State Management mechanism supporting multiple platforms (Provider, BLoC, Riverpod). Feature modules are free to choose the tool that best fits the team:
- **View (Pages/Widgets)**: Only paints the UI based on the current immutable state, listening to changes via the corresponding library's mechanism (e.g., `Consumer`, `BlocBuilder`).
- **ViewModel/Bloc**: Encouraged to inherit from the corresponding Bases (**`BaseProvider<T>`** for Provider, or **`BaseBloc`** for BLoC — use **`BaseCubit` only when events are unnecessary**), responsible for intercepting user interactions, calling Domain UseCases, and updating the UI state.

### Standardized UI State (`ViewState<T>` / `ViewStateModel<T>`)
For **Provider**, UI state is wrapped via `ViewStateModel<T>` inside `BaseProvider`.

For **BLoC**, `ViewState<T>` is the **shared optional helper** (`initial` / `loading` / `success` / `error`) — useful for simple screens and for living alongside Provider modules. **It is not mandatory**: complex BLoC features may define their own Freezed UI state (`BaseBloc<Event, CustomState>`).
- `initial`: Screen just launched.
- `loading`: System is processing data loading/executing tasks.
- `success(T data)`: Processing successful, emits clean data.
- `error(String message)`: An error occurred, emits a visual error message.

### 📚 Implementation Details (Library-Specific Guidelines)

Due to the Agnostic nature of the system, specific documentation (such as how to call APIs, automate Loading, paint paginated lists, or listen to side-effects) is not hardcoded here.

Instead, you **MUST read the documentation (README)** attached inside each State Management package to grasp all the powerful features the system has pre-built for the library you are choosing:

- 👉 **[Provider Core Documentation (`provider_state_management`)](file:///c:/Users/PC/Desktop/codebase/packages/core/provider_state_management/README.md)**: For teams using Provider. Read this to know how to use `executeOperation`, `BaseViewWidget`, `ProviderStateListener`, `BaseProxyWidget`, etc.
- 👉 **[BLoC Core Documentation (`bloc_state_management`)](file:///c:/Users/PC/Desktop/codebase/packages/core/bloc_state_management/README.md)**: For teams using BLoC. Covers `BaseBloc`, optional `ViewState`, custom Freezed state, `BlocBuilder` / Pattern Matching, and route-level providers.

---

## ⚡ 3. UI Controller Lifecycle Management Strategy (Agnostic Lifecycle)

Developers MUST clearly classify the scope of the UI Controller (ViewModel / Bloc) to apply the correct registration mechanism:

| Classification trait | Feature Controller (ViewModel/Bloc tied to 1 screen) | Global Controller (App Service/Theme/Auth) |
| :--- | :--- | :--- |
| **Operating scope** | Only tied to a specific Page / flow | Entire application (App-wide) |
| **Lifespan** | Automatically destroyed when screen is closed (Auto-dispose) | Lives throughout the app's lifetime (Singleton) |
| **DI Registration Mechanism** | Use `@injectable` (creates a new instance every `getIt` call) | Use `@lazySingleton` (initialized exactly once) |

#### UI Controller Initialization Location (Route-Level Instantiation)
For Feature Controllers, **it is mandatory to initialize them at the Routing layer** (in the `route_module.dart` file) instead of initializing them inside the screen's Widget. By combining `@injectable` and `ChangeNotifierProvider` (or `BlocProvider`), GetIt will automatically handle initializing dependent classes (UseCases), and the Provider Framework will be responsible for automatically calling the `dispose()` or `close()` function to free up RAM when the user leaves that screen.

*(For details on how to wrap Routes and link cross-State dependencies (Proxy State), please see the SM package's documentation or section 6 of [08. Routing & Navigation](08_routing.md))*

---

## 🚦 4. Decoupled Routing Communication via Scoped Navigator (Decentralized Routing)

In a Feature's View or ViewModel, **it is absolutely forbidden to directly import another Feature's routing file** to self-invoke page navigation commands. This breaks encapsulation and causes circular dependency errors.

All coordination actions outside the Feature must go through a **separate Navigator Interface** (defined in `core_di` and implemented locally within that Feature itself, e.g., `AuthNavigator` is implemented in `feature_auth`):

```dart
// Defined at packages/core/di/lib/src/navigators/auth_navigator.dart
import 'package:core_di/core_di.dart';

abstract class AuthNavigator {
  void toRegister(BuildContext context);
}

// ViewModel usage:
class MyViewModel extends BaseController {
  // Communication Navigator injected automatically via GetIt
  final AuthNavigator _navigator;

  MyViewModel(this._navigator);

  void onUserClickRegister(BuildContext context) {
    // Navigation: ViewModel calls local navigator, doesn't need to care where the Register page is
    _navigator.toRegister(context);
  }
}
```

### 🤝 Sharing Pages / Widgets Between Features In Decoupled Model

In the decentralized Monorepo architecture (Decoupled), Features are not allowed to import each other directly to avoid causing **Circular Dependency** errors. When Feature A wants to display a Page or a child Widget owned by Feature B, we apply the following strategies:

#### 1. Page Sharing (As an intact screen)

*   **Independent page transition**: Use routing via **Navigator Interface** (presented above). The implementation class at the local Feature package will instruct `GoRouter` to navigate to Feature B's destination screen.
*   **Grafting pages as children (e.g., Tabs in DashboardPage)**:
    *   The Dashboard Feature must **not** import `HomePage` / `ChatPage` / `ProfilePage` packages.
    *   Each tab feature registers `IDashboardTabModule` (order, path, routes, nav item).
    *   `feature_dashboard` implements `DashboardRouteModule` (chrome) and builds the bottom bar from `getAllOrEmpty<IDashboardTabModule>()`.
    *   `AppRouter` builds `StatefulShellBranch`es from the same modules — **do not** hardcode tab routes in `app_router.dart`.
    *   Full rules / anti-patterns: `docs/en/08_routing.md` § Dashboard.

#### 2. Child Widget Sharing (Embedding Feature B's Widget into Feature A's UI)

*   **Case of pure UI Widgets (No business logic / provider)**:
    *   If the widget is a commonly reusable UI component (like a button, general info card, progress bar...), place them in the **`feature_shared`** package (`packages/features/shared`). All feature packages can import this package.
*   **Case of Widgets tied to Feature B's Logic / Provider**:
    *   *Example:* Chat Feature needs to display a quick user info card (`UserProfileCardWidget`) from the Profile package.
    *   *Solution:* Use the **Widget Builder Interface via Dependency Injection (GetIt)** mechanism:
        
        1. Declare a Builder Interface at the shared communication layer (e.g., `core_di` or `core_common`):
           ```dart
           abstract class ProfileWidgetBuilder {
             Widget buildProfileCard({required String userId});
           }
           ```
        2. Implement that Interface at the `feature_profile` package and register it with GetIt as `@Singleton` or `@LazySingleton`:
           ```dart
           import 'package:core_di/core_di.dart';
           
           @Singleton(as: ProfileWidgetBuilder)
           class ProfileWidgetBuilderImpl implements ProfileWidgetBuilder {
             @override
             Widget buildProfileCard({required String userId}) {
               // Can initialize local Provider/Proxy and wrap around the child Widget if needed
               return UserProfileCardWidget(userId: userId);
             }
           }
           ```
        3. At `feature_chat`, simply inject the `ProfileWidgetBuilder` interface via GetIt to render the UI without knowing the implementation details or importing `feature_profile`'s source code:
           ```dart
           class ChatItemWidget extends StatelessWidget {
             final String senderId;
             const ChatItemWidget({required this.senderId});
           
             @override
             Widget build(BuildContext context) {
               return Row(
                 children: [
                   // Embed the Profile Card widget completely decoupled
                   getIt<ProfileWidgetBuilder>().buildProfileCard(userId: senderId),
                   const Text('Message content...'),
                 ],
               );
             }
           }
           ```

*   **Dialog / BottomSheet Case**:
    *   If a Widget needs to be opened as a conversation dialog or a bottom sliding sheet, we declare a display method in that feature's Navigator Interface:
       ```dart
       abstract class ChatNavigator {
         void showProfileDialog(BuildContext context, {required String userId});
       }
       ```
    *   The local Navigator implementation class at the App Shell layer (`app/`) will be responsible for importing `feature_profile`'s `UserProfileDialog` widget and calling the corresponding `showDialog(context, builder: ...)` function.

---

## 🤝 5. Sharing Services & Business Logic Between Features (Cross-Feature Communication)

In a multi-module architecture (Multi-package Monorepo), the core principle is to **ensure independent encapsulation and eliminate mutual dependencies (Loose Coupling)**. Feature packages are not allowed to directly import each other's code to avoid Circular Dependency errors.

To share data, business, or state between Features, the system mandates the following 4 standardized design models:

---

### 🏛️ Model 1: Sharing Business Logic via Domain Layer (Domain UseCase Sharing)

This is the **most highly recommended** model for most business sharing problems. Instead of Feature A directly calling Feature B, both Features communicate through the shared **Domain** layer (`packages/domain/* (Micro-packages)`).

*   **How it works**: 
    - The `domain` package contains all the application's Entities, interfaces (Repository contracts), and UseCases.
    - Every Feature package can depend on the `domain` package.
    - When Feature A (e.g., `feature_booking`) needs info or to perform an action related to Feature B (e.g., `feature_auth`), it will inject the corresponding UseCase from `domain` (e.g., `GetProfileUseCase`) via `GetIt`.
*   **Flow diagram**:
    ```mermaid
    graph LR
        feature_booking["feature_booking"] -->|"Import & Inject Usecase"| domain_usecase["GetProfileUseCase"]
        feature_auth["feature_auth"] -->|"Implementation & Provision"| domain_usecase
    ```

*   **Example**:
    ```dart
    // In feature_booking/lib/src/provider/booking_controller.dart
    import 'package:domain_*/domain_*.dart'; // Only depends on Domain
    
    class BookingController {
      final CreateBookingUseCase _createBookingUseCase;
      // Uses Auth's UseCase via the Domain layer
      final GetProfileUseCase _getProfileUseCase;
    
      BookingController(
        this._createBookingUseCase,
        this._getProfileUseCase,
      );
    
      Future<void> makeReservation() async {
        // Get current user info from UseCase without importing feature_auth
        final userResult = await _getProfileUseCase();
        // ... proceed with logic
      }
    }
    ```

---

### ⚙️ Model 2: Sharing Core Services & Infrastructure Utilities (Core Infrastructure Services)

Infrastructure services intended for app-wide sharing (running in the background, containing no UI) are independently packaged in `packages/core/` directories.

*   **How it works**:
    - Setup core libraries like: `core_storage` (manages local database, cache), `core_network` (HTTP connections/API calls), `core_notifications` (Push Notification manager).
    - Feature packages simply import these core libraries to store or send/receive data.
*   **Example**:
    ```dart
    // In feature_chat/lib/src/controller/chat_controller.dart
    import 'package:core_storage/core_storage.dart'; // Import core package
    
    class ChatController {
      final LocalStorage _localStorage; // Declare using interface from core_storage
      
      ChatController(this._localStorage);
      
      Future<void> saveDraftMessage(String draft) async {
        // Save directly down to Local Storage
        await _localStorage.write(StoragePresets.chatDraftKey, draft);
      }
    }
    ```

---

### 🌐 Model 3: Sharing Global State & Cross-System Communication (Agnostic Streams)

**Extremely important note:** When working in a multi State Management environment, if Feature A (using BLoC) wants to listen to Feature B (using Provider) or get global state, it will face a library barrier. To resolve this, the entire system applies **Neutral Streams on the DI Hub**:

*   **Global State Rule**: Global state belonging to no specific feature (e.g., Theme, Deeplink) must use **1 single standard** (Provider or pure Dart `Stream`/`ValueNotifier`) so as not to force Features to cross-depend on libraries.
*   **Cross-feature communication (Cross-feature SM)**:
    1. Feature A creates an Interface wrapping a pure Dart `Stream` or `ValueListenable` and registers it on GetIt.
    2. Feature A never directly exposes the BLoC or Provider instance to the outside.
    3. Feature B simply injects this Interface and listens to neutral information without needing to know which UI tool Feature A was coded with.
*   **Flow diagram**:
    ```mermaid
    graph TD
        Hub["DI Hub (core_di)<br/>&lt;I_NeutralStreamInterface&gt;"]
        
        FeatA["Feature A<br/>(Using Provider)"]
        FeatB["Feature B<br/>(Using BLoC)"]

        FeatA -->|"Push Data"| Hub
        Hub -->|"Listen to Stream"| FeatB
    ```

*   **Dual Registration Rule**: To avoid ugly type casting (`as`) in the owner feature, register the implementation as a concrete `@singleton` and use a `@module` to bind it to the Interface. This allows the owner feature to inject the concrete implementation directly via constructor, while other features only listen to the Interface.

*   **Practical Example (`IAuthStatusStream`)**:

    **Step 1: Define the neutral stream interface in `packages/core/di/lib/src/agnostic_streams/i_auth_status_stream.dart`**
    *(Note: The DI Hub is allowed to import domain micro-packages to strongly type the data payload).*
    ```dart
    import 'package:domain_auth/domain_auth.dart';
    
    /// Agnostic Stream Interface for Authentication Status.
    /// Features can listen to [authStatusStream] to react to login/logout events
    /// without depending directly on `feature_auth`.
    abstract class IAuthStatusStream {
      Stream<UserEntity?> get authStatusStream;
      UserEntity? get currentUser;
    }
    ```

    **Step 2: Implement and register in the Owner Feature (`packages/features/auth/lib/src/services/auth_status_stream_impl.dart`)**
    ```dart
    import 'dart:async';
    import 'package:core_di/core_di.dart';
    import 'package:domain_auth/domain_auth.dart';
    import 'package:injectable/injectable.dart';

    @singleton
    class AuthStatusStreamImpl implements IAuthStatusStream {
      final _controller = StreamController<UserEntity?>.broadcast();
      UserEntity? _currentUser;

      @override
      Stream<UserEntity?> get authStatusStream => _controller.stream;

      @override
      UserEntity? get currentUser => _currentUser;

      /// Internal method for feature_auth to push state updates
      void updateAuthStatus(UserEntity? user) {
        _currentUser = user;
        _controller.add(user);
      }
    }
    ```

    **Step 3: Trigger the update from the Owner Feature (`packages/features/auth/lib/src/provider/auth_provider.dart`)**
    ```dart
    // Inject the concrete implementation `AuthStatusStreamImpl _authStream` via constructor
    Future<void> login(String email, String password) async {
      await executeOperation(
        OperationConfig(
          operation: () => _loginUseCase(LoginParams(email: email, password: password)),
          onSuccess: (user) async {
            // Push data to the stream directly
            _authStream.updateAuthStatus(user);
          },
        ),
      );
    }
    ```

    **Step 4: Listen neutrally from another feature (`packages/features/home/lib/src/pages/home_page.dart`)**
    ```dart
    import 'package:core_di/core_di.dart';
    import 'package:domain_auth/domain_auth.dart';

    // ...
    // feature_home listens to IAuthStatusStream without importing feature_auth
    StreamBuilder<UserEntity?>(
      stream: getIt<IAuthStatusStream>().authStatusStream,
      builder: (context, snapshot) {
        final isLoggedIn = snapshot.data != null;
        return Text(isLoggedIn ? 'Logged In' : 'Logged Out');
      },
    )
    ```

---

### 🎨 Model 4: Managing Pure UI State (Bypassing the Domain Layer)

**ThemeMode** and **Locale** are pure UI preferences. They cannot pass through the Domain layer because Domain is **Pure Dart** and must not import `package:flutter/material.dart`.

*   **How it works**:
    - UI Providers in `core_base_ui` (`ThemeProvider`, `LanguageProvider`) manage in-memory state.
    - Persistence goes through agnostic interfaces on the DI Hub (`IThemeStorage`, `ILanguageStorage`).
    - Concrete implementations live in the **App Shell** (`app/lib/di/`) and read/write `StorageValuePresets` from `core_storage`.
*   **Flow diagram**:
    ```mermaid
    graph LR
        ThemeUI["ThemeProvider<br/>(core_base_ui)"] -->|"Direct Save"| ITheme["IThemeStorage<br/>(core_di)"]
        ITheme -->|"Implements"| ThemeImpl["ThemeStorageImpl<br/>(app/di)"]
        ThemeImpl --> Presets["StorageValuePresets<br/>(core_storage)"]

        LangUI["LanguageProvider<br/>(core_base_ui)"] -->|"Direct Save"| ILang["ILanguageStorage<br/>(core_di)"]
        ILang -->|"Implements"| LangImpl["LanguageStorageImpl<br/>(app/di)"]
        LangImpl --> Presets
    ```
*   **Current workflows**:
    - **Theme**: `ThemeProvider` ➔ `IThemeStorage` ➔ `StorageValuePresets.themeMode`
    - **Language**: `LanguageProvider` ➔ `ILanguageStorage` ➔ `StorageValuePresets.locale`

---

### 🤝 Model 5: Communication via Builder Interface & Service Locator (Decoupled Service Interfaces)

In the case where Feature A wants to interact with specific logic or trigger a state in Feature B (e.g., `feature_payment` needs to trigger a card info update popup in `feature_profile`), but this business doesn't belong to the Domain layer and cannot be resolved by a simple UI Route.

*   **How it works**:
    1. Define a communication Interface (Contract) in the shared library `core_di` or `core_common`.
    2. Feature B implements this interface and registers with GetIt as a `@Singleton`.
    3. Feature A just calls GetIt to fetch this interface for use without knowing any implementation details or importing Feature B's library.

*   **Practical Example**:
    
    **Step 1: Declare shared interface in `packages/core/di/lib/src/services/payment_service_delegate.dart`**
    ```dart
    abstract class PaymentServiceDelegate {
      Future<bool> verifyUserProfile(BuildContext context, {required String userId});
    }
    ```
    
    **Step 2: Implement and register in `packages/features/profile`**
    ```dart
    import 'package:core_di/core_di.dart';
    
    @Singleton(as: PaymentServiceDelegate)
    class ProfilePaymentServiceDelegateImpl implements PaymentServiceDelegate {
      @override
      Future<bool> verifyUserProfile(BuildContext context, {required String userId}) async {
        // Perform UI logic or call info verification dialog in Profile
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => const UserProfileVerificationDialog(),
        );
        return result ?? false;
      }
    }
    ```
    
    **Step 3: Use in `packages/features/payment`**
    ```dart
    import 'package:core_di/core_di.dart';
    
    class PaymentController {
      final PaymentServiceDelegate _profileDelegate;
      
      // Inject interface into constructor
      PaymentController(this._profileDelegate);
      
      Future<void> executeCheckout(BuildContext context) async {
        // Trigger info verification via loose delegate
        final isVerified = await _profileDelegate.verifyUserProfile(context, userId: 'user123');
        
        if (!isVerified) {
          // Stop checkout...
          return;
        }
        
        // Proceed with checkout...
      }
    }
    ```

---

### 🎛️ Model 6: Cross-Feature UI Actions via Action Handlers

When Feature A needs to **trigger a UI-bound action owned by Feature B** (e.g., Settings in `feature_settings` calls logout owned by `feature_auth`) without importing Feature B, use an **Action Handler** contract on the DI Hub.

*   **When to use**: The action requires Feature B's Provider / UI context (`BuildContext`, `context.read<AuthProvider>()`, dialogs) and is **not** a simple route navigation (use Navigator) and **not** a Domain UseCase-only call.
*   **How it works**:
    1. Declare `I*ActionHandler` in `packages/core/di/lib/src/actions/`.
    2. Implement `*ActionHandlerImpl` inside the **owning feature** (or App Shell when the owner is global app state) and register with `@Injectable(as: I*ActionHandler)` / `@LazySingleton(as: ...)`.
    3. Consuming features call `getIt<I*ActionHandler>().method(context)` without importing the owning feature package.
*   **Practical Example (`IAuthActionHandler`)**:

    **Step 1: Interface in `packages/core/di/lib/src/actions/i_auth_action_handler.dart`**
    ```dart
    import 'package:flutter/widgets.dart';

    abstract class IAuthActionHandler {
      void logout(BuildContext context);
    }
    ```

    **Step 2: Implementation in `packages/features/auth/lib/src/handlers/auth_action_handler_impl.dart`**
    ```dart
    @Injectable(as: IAuthActionHandler)
    class AuthActionHandlerImpl implements IAuthActionHandler {
      @override
      void logout(BuildContext context) {
        context.read<AuthProvider>().logout();
      }
    }
    ```

    **Step 3: Consumer in `feature_settings`**
    ```dart
    getIt<IAuthActionHandler>().logout(context);
    ```

*   **Naming**:
    - Interface file: `i_<feature>_action_handler.dart` / class `I*ActionHandler`
    - Implementation file: `<feature>_action_handler_impl.dart` / class `*ActionHandlerImpl`
    - **ABSOLUTELY FORBIDDEN** to name an implementation class with the `I` prefix (that prefix is reserved for interfaces).

---

### 📊 Summary Table of Solution Choices

| Problem to solve | Suitable Solution | How to implement |
| :--- | :--- | :--- |
| Call API, handle Database, Business logic without UI | **Model 1: Domain UseCase** | Define UseCase in `domain`, inject into ViewModel via constructor. |
| Save app config, check network connection, analytic logs | **Model 2: Core Service** | Directly import `core_storage`, `core_network`, `core_notifications` libraries. |
| Track login state across features without SM coupling | **Model 3: Agnostic Streams** | Neutral `Stream` / `ValueListenable` interface on `core_di`; dual-register owner impl. |
| Persist ThemeMode / pure UI prefs (no Domain) | **Model 4: Pure UI State** | `ThemeProvider` → `IThemeStorage` → Storage. |
| Trigger popup, embed complex child widgets across features | **Model 5: Service / Builder Interface** | Declare Interface in `core_di`, implement in source feature, use via GetIt. |
| Trigger Feature B UI action (logout, etc.) from Feature A | **Model 6: Action Handler** | `I*ActionHandler` in `core_di`, `*ActionHandlerImpl` in owning feature. |

---

Specific configuration for this conflict-avoiding decentralized routing is detailed in [08. Comprehensive Decentralized Routing & Navigation](08_routing.md).

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
