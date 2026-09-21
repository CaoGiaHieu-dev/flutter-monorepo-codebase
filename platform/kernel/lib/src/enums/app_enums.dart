import 'package:json_annotation/json_annotation.dart';

part 'app_enums.g.dart';

/// Application update status for version checking
enum UpdateStatus {
  /// App needs to be updated
  needsUpdate,

  /// App is up to date
  upToDate,

  /// Invalid version detected
  invalidVersion,
}

/// WebSocket connection state
enum SocketState {
  /// Socket is connected
  connected,

  /// Socket is disconnected
  disconnected,
}

/// Application build flavors/environments
@JsonEnum(alwaysCreate: true)
enum Flavor {
  /// Development environment
  @JsonValue('dev')
  dev,

  /// Staging environment
  @JsonValue('staging')
  staging,

  /// Production environment
  @JsonValue('prod')
  prod;

  const Flavor();

  /// Convert enum to string value
  String toValue() => _$FlavorEnumMap[this]!;
}

/// Sort order for data queries
@JsonEnum(alwaysCreate: true)
enum SortOrder {
  /// Ascending order
  @JsonValue('ASC')
  asc,

  /// Descending order
  @JsonValue('DESC')
  desc,
}

/// Sort field options for data queries
@JsonEnum(alwaysCreate: true)
enum SortBy {
  /// Sort by creation date
  @JsonValue('createdAt')
  createdAt,

  /// Sort by last update date
  @JsonValue('updatedAt')
  updatedAt,
}
