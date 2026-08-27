import 'package:dio/dio.dart';

import '../handlers/refresh_token_handler.dart';
import '../utils/network_constants.dart';

/// Bridges a `401 Unauthorized` response to [RefreshTokenHandler].
///
/// Placed **before** `RetryInterceptor` in the chain so an expired session is
/// renewed and the original request replayed, instead of being retried with
/// the same stale token.
///
/// Three guards keep the flow from looping:
/// 1. Requests that opted out of auth
///    ([NetworkConstants.EXTRA_NEED_AUTHENTICATION] `= false`) are ignored, so
///    the refresh call itself never triggers a refresh.
/// 2. A request already replayed after a refresh is marked with
///    [NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] and is not refreshed a
///    second time.
/// 3. [RefreshTokenHandler] serialises concurrent `401`s behind a single
///    `Completer`, so N failing requests cause exactly one refresh.
class RefreshTokenInterceptor extends Interceptor {
  RefreshTokenInterceptor(this._handler);

  final RefreshTokenHandler _handler;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!_shouldRefresh(err)) {
      super.onError(err, handler);
      return;
    }

    // Mark the options *before* handing over: `RefreshTokenHandler` replays
    // this same RequestOptions through `dio.fetch`, which re-enters this
    // interceptor. The flag makes that second pass fall through to `super`.
    err.requestOptions.extra[NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] =
        true;

    _handler.handleRefresh(err, handler);
  }

  bool _shouldRefresh(DioException err) {
    if (err.response?.statusCode != NetworkConstants.STATUS_UNAUTHORIZED) {
      return false;
    }

    final extra = err.requestOptions.extra;

    final needAuthentication =
        extra[NetworkConstants.EXTRA_NEED_AUTHENTICATION] as bool? ?? true;
    if (!needAuthentication) return false;

    final alreadyAttempted =
        extra[NetworkConstants.EXTRA_TOKEN_REFRESH_ATTEMPTED] as bool? ?? false;
    return !alreadyAttempted;
  }
}
