// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'dart:async' as _i687;

import 'package:core_di/core_di.dart' as _i472;
import 'package:feature_payment/src/routing/payment_navigator_impl.dart'
    as _i405;
import 'package:feature_payment/src/routing/payment_route_module.dart' as _i770;
import 'package:injectable/injectable.dart' as _i526;

class FeaturePaymentPackageModule extends _i526.MicroPackageModule {
// initializes the registration of main-scope dependencies inside of GetIt
  @override
  _i687.FutureOr<void> init(_i526.GetItHelper gh) {
    gh.lazySingleton<_i472.PaymentNavigator>(
        () => _i405.PaymentNavigatorImpl());
    gh.lazySingleton<_i472.IFeatureRouteModule>(
        () => _i770.PaymentRouteModule());
  }
}
