/// Compatibility re-export — [AppFailure] now lives in `domain_core`.
///
/// Failures are part of the `Result` contract, so they belong at the centre of
/// the architecture alongside it, not in an infrastructure package. Moving the
/// declaration is what lets `domain_core` drop its dependency on
/// `core_common` (and on Flutter with it), restoring the Clean Architecture
/// direction: Domain depends on nothing, every other layer may depend on
/// Domain.
///
/// This file stays so the many existing `package:core_common/core_common.dart`
/// imports keep resolving `AppFailure` unchanged. Prefer importing
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
