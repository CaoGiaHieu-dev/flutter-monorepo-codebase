import 'package:freezed_annotation/freezed_annotation.dart';

enum UserRole {
  @JsonValue('customer')
  customer,
  @JsonValue('owner')
  owner,
  @JsonValue('none')
  none,
  unknown,
}
