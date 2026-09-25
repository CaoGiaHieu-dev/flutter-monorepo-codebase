/// SAMPLE CODE — safe to delete.
///
/// This package is a reference implementation shipped with the template,
/// not product code. It demonstrates:
/// Pure-Dart entities, params, repository contract and use cases.
///
/// To remove it and everything that travels with it:
///
/// ```sh
/// dart tools/sample_cleanup/remove_sample.dart auth            # preview
/// dart tools/sample_cleanup/remove_sample.dart auth --apply    # do it
/// ```
///
/// Classification and the full removal bundle live in
/// `tools/sample_manifest.yaml`.
library;

// Auto-generated exports, do not edit manually.
export 'di/module.dart';
export 'di/module.module.dart';
export 'src/entities/user_entity.dart';
export 'src/entities/user_role.dart';
export 'src/params/login_params.dart';
export 'src/repositories/i_auth_repository.dart';
export 'src/usecases/login_usecase.dart';
export 'src/usecases/logout_usecase.dart';
export 'src/usecases/refresh_token_usecase.dart';
