/// Convenience re-export — [AppFailure] is declared in `domain_core`.
///
/// Failures are part of the `Result` contract, so they belong at the centre of
/// the architecture alongside it, not in an infrastructure package. Declaring
/// them there is what allows `domain_core` to depend on nothing — not on
/// `core_common`, and so not on Flutter either — which is the Clean
/// Architecture direction: Domain depends on nothing, every other layer may
/// depend on Domain.
///
/// This file lets a `package:core_common/core_common.dart` import resolve
/// `AppFailure` without also importing `domain_core`. Prefer importing
/// `package:domain_core/domain_core.dart` directly in new code.
library;

export 'package:domain_core/domain_core.dart'
    show
        AppFailure,
        AuthFailure,
        CacheFailure,
        NetworkFailure,
        ParseFailure,
        ServerFailure,
        ServiceFailure,
        StorageFailure,
        ValidationFailure;
