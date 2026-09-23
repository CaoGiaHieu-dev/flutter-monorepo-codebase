// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'exceptions.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppException {

 String get message; int? get code;
/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppExceptionCopyWith<AppException> get copyWith => _$AppExceptionCopyWithImpl<AppException>(this as AppException, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AppException;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppException&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.code, _this.code) || other.code == _this.code));
}


@override
int get hashCode {
  final _this = this as AppException;
  return Object.hash(runtimeType,_this.message,_this.code);
}



}

/// @nodoc
abstract mixin class $AppExceptionCopyWith<$Res>  {
  factory $AppExceptionCopyWith(AppException value, $Res Function(AppException) _then) = _$AppExceptionCopyWithImpl;
@useResult
$Res call({
 String message, int? code
});




}
/// @nodoc
class _$AppExceptionCopyWithImpl<$Res>
    implements $AppExceptionCopyWith<$Res> {
  _$AppExceptionCopyWithImpl(this._self, this._then);

  final AppException _self;
  final $Res Function(AppException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? message = null,Object? code = freezed,}) {
  return _then(_self.copyWith(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [AppException].
extension AppExceptionPatterns on AppException {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NetworkException value)?  network,TResult Function( ServerException value)?  server,TResult Function( AuthException value)?  auth,TResult Function( StorageException value)?  storage,TResult Function( ValidationException value)?  validation,TResult Function( ParseException value)?  parse,TResult Function( CacheException value)?  cache,TResult Function( ServiceException value)?  service,TResult Function( UnknownException value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NetworkException() when network != null:
return network(_that);case ServerException() when server != null:
return server(_that);case AuthException() when auth != null:
return auth(_that);case StorageException() when storage != null:
return storage(_that);case ValidationException() when validation != null:
return validation(_that);case ParseException() when parse != null:
return parse(_that);case CacheException() when cache != null:
return cache(_that);case ServiceException() when service != null:
return service(_that);case UnknownException() when unknown != null:
return unknown(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NetworkException value)  network,required TResult Function( ServerException value)  server,required TResult Function( AuthException value)  auth,required TResult Function( StorageException value)  storage,required TResult Function( ValidationException value)  validation,required TResult Function( ParseException value)  parse,required TResult Function( CacheException value)  cache,required TResult Function( ServiceException value)  service,required TResult Function( UnknownException value)  unknown,}){
final _that = this;
switch (_that) {
case NetworkException():
return network(_that);case ServerException():
return server(_that);case AuthException():
return auth(_that);case StorageException():
return storage(_that);case ValidationException():
return validation(_that);case ParseException():
return parse(_that);case CacheException():
return cache(_that);case ServiceException():
return service(_that);case UnknownException():
return unknown(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NetworkException value)?  network,TResult? Function( ServerException value)?  server,TResult? Function( AuthException value)?  auth,TResult? Function( StorageException value)?  storage,TResult? Function( ValidationException value)?  validation,TResult? Function( ParseException value)?  parse,TResult? Function( CacheException value)?  cache,TResult? Function( ServiceException value)?  service,TResult? Function( UnknownException value)?  unknown,}){
final _that = this;
switch (_that) {
case NetworkException() when network != null:
return network(_that);case ServerException() when server != null:
return server(_that);case AuthException() when auth != null:
return auth(_that);case StorageException() when storage != null:
return storage(_that);case ValidationException() when validation != null:
return validation(_that);case ParseException() when parse != null:
return parse(_that);case CacheException() when cache != null:
return cache(_that);case ServiceException() when service != null:
return service(_that);case UnknownException() when unknown != null:
return unknown(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message,  int? code)?  network,TResult Function( String message,  int? code)?  server,TResult Function( String message,  int? code)?  auth,TResult Function( String message,  int? code)?  storage,TResult Function( String message,  int? code,  String? field)?  validation,TResult Function( String message,  int? code)?  parse,TResult Function( String message,  int? code)?  cache,TResult Function( String message,  int? code)?  service,TResult Function( String message,  int? code)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NetworkException() when network != null:
return network(_that.message,_that.code);case ServerException() when server != null:
return server(_that.message,_that.code);case AuthException() when auth != null:
return auth(_that.message,_that.code);case StorageException() when storage != null:
return storage(_that.message,_that.code);case ValidationException() when validation != null:
return validation(_that.message,_that.code,_that.field);case ParseException() when parse != null:
return parse(_that.message,_that.code);case CacheException() when cache != null:
return cache(_that.message,_that.code);case ServiceException() when service != null:
return service(_that.message,_that.code);case UnknownException() when unknown != null:
return unknown(_that.message,_that.code);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message,  int? code)  network,required TResult Function( String message,  int? code)  server,required TResult Function( String message,  int? code)  auth,required TResult Function( String message,  int? code)  storage,required TResult Function( String message,  int? code,  String? field)  validation,required TResult Function( String message,  int? code)  parse,required TResult Function( String message,  int? code)  cache,required TResult Function( String message,  int? code)  service,required TResult Function( String message,  int? code)  unknown,}) {final _that = this;
switch (_that) {
case NetworkException():
return network(_that.message,_that.code);case ServerException():
return server(_that.message,_that.code);case AuthException():
return auth(_that.message,_that.code);case StorageException():
return storage(_that.message,_that.code);case ValidationException():
return validation(_that.message,_that.code,_that.field);case ParseException():
return parse(_that.message,_that.code);case CacheException():
return cache(_that.message,_that.code);case ServiceException():
return service(_that.message,_that.code);case UnknownException():
return unknown(_that.message,_that.code);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message,  int? code)?  network,TResult? Function( String message,  int? code)?  server,TResult? Function( String message,  int? code)?  auth,TResult? Function( String message,  int? code)?  storage,TResult? Function( String message,  int? code,  String? field)?  validation,TResult? Function( String message,  int? code)?  parse,TResult? Function( String message,  int? code)?  cache,TResult? Function( String message,  int? code)?  service,TResult? Function( String message,  int? code)?  unknown,}) {final _that = this;
switch (_that) {
case NetworkException() when network != null:
return network(_that.message,_that.code);case ServerException() when server != null:
return server(_that.message,_that.code);case AuthException() when auth != null:
return auth(_that.message,_that.code);case StorageException() when storage != null:
return storage(_that.message,_that.code);case ValidationException() when validation != null:
return validation(_that.message,_that.code,_that.field);case ParseException() when parse != null:
return parse(_that.message,_that.code);case CacheException() when cache != null:
return cache(_that.message,_that.code);case ServiceException() when service != null:
return service(_that.message,_that.code);case UnknownException() when unknown != null:
return unknown(_that.message,_that.code);case _:
  return null;

}
}

}

/// @nodoc


class NetworkException extends AppException {
  const NetworkException(this.message, {this.code}): super._();
  

@override final  String message;
@override final  int? code;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NetworkExceptionCopyWith<NetworkException> get copyWith => _$NetworkExceptionCopyWithImpl<NetworkException>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NetworkException&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code);
}



}

/// @nodoc
abstract mixin class $NetworkExceptionCopyWith<$Res> implements $AppExceptionCopyWith<$Res> {
  factory $NetworkExceptionCopyWith(NetworkException value, $Res Function(NetworkException) _then) = _$NetworkExceptionCopyWithImpl;
@override @useResult
$Res call({
 String message, int? code
});




}
/// @nodoc
class _$NetworkExceptionCopyWithImpl<$Res>
    implements $NetworkExceptionCopyWith<$Res> {
  _$NetworkExceptionCopyWithImpl(this._self, this._then);

  final NetworkException _self;
  final $Res Function(NetworkException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,}) {
  return _then(NetworkException(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class ServerException extends AppException {
  const ServerException(this.message, {this.code}): super._();
  

@override final  String message;
@override final  int? code;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ServerExceptionCopyWith<ServerException> get copyWith => _$ServerExceptionCopyWithImpl<ServerException>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ServerException&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code);
}



}

/// @nodoc
abstract mixin class $ServerExceptionCopyWith<$Res> implements $AppExceptionCopyWith<$Res> {
  factory $ServerExceptionCopyWith(ServerException value, $Res Function(ServerException) _then) = _$ServerExceptionCopyWithImpl;
@override @useResult
$Res call({
 String message, int? code
});




}
/// @nodoc
class _$ServerExceptionCopyWithImpl<$Res>
    implements $ServerExceptionCopyWith<$Res> {
  _$ServerExceptionCopyWithImpl(this._self, this._then);

  final ServerException _self;
  final $Res Function(ServerException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,}) {
  return _then(ServerException(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class AuthException extends AppException {
  const AuthException(this.message, {this.code}): super._();
  

@override final  String message;
@override final  int? code;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthExceptionCopyWith<AuthException> get copyWith => _$AuthExceptionCopyWithImpl<AuthException>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthException&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code);
}



}

/// @nodoc
abstract mixin class $AuthExceptionCopyWith<$Res> implements $AppExceptionCopyWith<$Res> {
  factory $AuthExceptionCopyWith(AuthException value, $Res Function(AuthException) _then) = _$AuthExceptionCopyWithImpl;
@override @useResult
$Res call({
 String message, int? code
});




}
/// @nodoc
class _$AuthExceptionCopyWithImpl<$Res>
    implements $AuthExceptionCopyWith<$Res> {
  _$AuthExceptionCopyWithImpl(this._self, this._then);

  final AuthException _self;
  final $Res Function(AuthException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,}) {
  return _then(AuthException(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class StorageException extends AppException {
  const StorageException(this.message, {this.code}): super._();
  

@override final  String message;
@override final  int? code;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StorageExceptionCopyWith<StorageException> get copyWith => _$StorageExceptionCopyWithImpl<StorageException>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StorageException&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code);
}



}

/// @nodoc
abstract mixin class $StorageExceptionCopyWith<$Res> implements $AppExceptionCopyWith<$Res> {
  factory $StorageExceptionCopyWith(StorageException value, $Res Function(StorageException) _then) = _$StorageExceptionCopyWithImpl;
@override @useResult
$Res call({
 String message, int? code
});




}
/// @nodoc
class _$StorageExceptionCopyWithImpl<$Res>
    implements $StorageExceptionCopyWith<$Res> {
  _$StorageExceptionCopyWithImpl(this._self, this._then);

  final StorageException _self;
  final $Res Function(StorageException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,}) {
  return _then(StorageException(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class ValidationException extends AppException {
  const ValidationException(this.message, {this.code, this.field}): super._();
  

@override final  String message;
@override final  int? code;
 final  String? field;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ValidationExceptionCopyWith<ValidationException> get copyWith => _$ValidationExceptionCopyWithImpl<ValidationException>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ValidationException&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code)&&(identical(other.field, field) || other.field == field));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code,field);
}



}

/// @nodoc
abstract mixin class $ValidationExceptionCopyWith<$Res> implements $AppExceptionCopyWith<$Res> {
  factory $ValidationExceptionCopyWith(ValidationException value, $Res Function(ValidationException) _then) = _$ValidationExceptionCopyWithImpl;
@override @useResult
$Res call({
 String message, int? code, String? field
});




}
/// @nodoc
class _$ValidationExceptionCopyWithImpl<$Res>
    implements $ValidationExceptionCopyWith<$Res> {
  _$ValidationExceptionCopyWithImpl(this._self, this._then);

  final ValidationException _self;
  final $Res Function(ValidationException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,Object? field = freezed,}) {
  return _then(ValidationException(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,field: freezed == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class ParseException extends AppException {
  const ParseException(this.message, {this.code}): super._();
  

@override final  String message;
@override final  int? code;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParseExceptionCopyWith<ParseException> get copyWith => _$ParseExceptionCopyWithImpl<ParseException>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ParseException&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code);
}



}

/// @nodoc
abstract mixin class $ParseExceptionCopyWith<$Res> implements $AppExceptionCopyWith<$Res> {
  factory $ParseExceptionCopyWith(ParseException value, $Res Function(ParseException) _then) = _$ParseExceptionCopyWithImpl;
@override @useResult
$Res call({
 String message, int? code
});




}
/// @nodoc
class _$ParseExceptionCopyWithImpl<$Res>
    implements $ParseExceptionCopyWith<$Res> {
  _$ParseExceptionCopyWithImpl(this._self, this._then);

  final ParseException _self;
  final $Res Function(ParseException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,}) {
  return _then(ParseException(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class CacheException extends AppException {
  const CacheException(this.message, {this.code}): super._();
  

@override final  String message;
@override final  int? code;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CacheExceptionCopyWith<CacheException> get copyWith => _$CacheExceptionCopyWithImpl<CacheException>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CacheException&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code);
}



}

/// @nodoc
abstract mixin class $CacheExceptionCopyWith<$Res> implements $AppExceptionCopyWith<$Res> {
  factory $CacheExceptionCopyWith(CacheException value, $Res Function(CacheException) _then) = _$CacheExceptionCopyWithImpl;
@override @useResult
$Res call({
 String message, int? code
});




}
/// @nodoc
class _$CacheExceptionCopyWithImpl<$Res>
    implements $CacheExceptionCopyWith<$Res> {
  _$CacheExceptionCopyWithImpl(this._self, this._then);

  final CacheException _self;
  final $Res Function(CacheException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,}) {
  return _then(CacheException(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class ServiceException extends AppException {
  const ServiceException(this.message, {this.code}): super._();
  

@override final  String message;
@override final  int? code;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ServiceExceptionCopyWith<ServiceException> get copyWith => _$ServiceExceptionCopyWithImpl<ServiceException>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ServiceException&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code);
}



}

/// @nodoc
abstract mixin class $ServiceExceptionCopyWith<$Res> implements $AppExceptionCopyWith<$Res> {
  factory $ServiceExceptionCopyWith(ServiceException value, $Res Function(ServiceException) _then) = _$ServiceExceptionCopyWithImpl;
@override @useResult
$Res call({
 String message, int? code
});




}
/// @nodoc
class _$ServiceExceptionCopyWithImpl<$Res>
    implements $ServiceExceptionCopyWith<$Res> {
  _$ServiceExceptionCopyWithImpl(this._self, this._then);

  final ServiceException _self;
  final $Res Function(ServiceException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,}) {
  return _then(ServiceException(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class UnknownException extends AppException {
  const UnknownException(this.message, {this.code}): super._();
  

@override final  String message;
@override final  int? code;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnknownExceptionCopyWith<UnknownException> get copyWith => _$UnknownExceptionCopyWithImpl<UnknownException>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnknownException&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code);
}



}

/// @nodoc
abstract mixin class $UnknownExceptionCopyWith<$Res> implements $AppExceptionCopyWith<$Res> {
  factory $UnknownExceptionCopyWith(UnknownException value, $Res Function(UnknownException) _then) = _$UnknownExceptionCopyWithImpl;
@override @useResult
$Res call({
 String message, int? code
});




}
/// @nodoc
class _$UnknownExceptionCopyWithImpl<$Res>
    implements $UnknownExceptionCopyWith<$Res> {
  _$UnknownExceptionCopyWithImpl(this._self, this._then);

  final UnknownException _self;
  final $Res Function(UnknownException) _then;

/// Create a copy of AppException
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,}) {
  return _then(UnknownException(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
