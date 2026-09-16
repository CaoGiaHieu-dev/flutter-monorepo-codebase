import 'package:serverpod_client/serverpod_client.dart';

/// Serverpod client communication protocol.
class Protocol extends SerializationManager {
  static final Protocol instance = Protocol();

  @override
  T deserialize<T>(dynamic data, [Type? t]) {
    t ??= T;
    if (t == UserInfoModel) {
      return UserInfoModel.fromJson(data as Map<String, dynamic>) as T;
    }
    if (t == AuthResponseModel) {
      return AuthResponseModel.fromJson(data as Map<String, dynamic>) as T;
    }
    return super.deserialize<T>(data, t);
  }

  @override
  String? getClassNameForObject(Object? data) {
    if (data is UserInfoModel) return 'UserInfoModel';
    if (data is AuthResponseModel) return 'AuthResponseModel';
    return super.getClassNameForObject(data);
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    final className = data['className'];
    if (className == 'UserInfoModel') {
      return UserInfoModel.fromJson(data['data'] as Map<String, dynamic>);
    }
    if (className == 'AuthResponseModel') {
      return AuthResponseModel.fromJson(data['data'] as Map<String, dynamic>);
    }
    return super.deserializeByClassName(data);
  }
}

/// User info model sent from Serverpod server.
class UserInfoModel implements SerializableModel {
  UserInfoModel({
    required this.id,
    required this.email,
    required this.name,
    this.role = 'customer',
  });

  final String id;
  final String email;
  final String name;
  final String role;

  factory UserInfoModel.fromJson(Map<String, dynamic> json) {
    return UserInfoModel(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      role: (json['role'] as String?) ?? 'customer',
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
    };
  }
}

/// Auth response model from Serverpod server.
class AuthResponseModel implements SerializableModel {
  AuthResponseModel({
    required this.success,
    this.token,
    this.user,
    this.error,
  });

  final bool success;
  final String? token;
  final UserInfoModel? user;
  final String? error;

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    return AuthResponseModel(
      success: json['success'] as bool,
      token: json['token'] as String?,
      user: json['user'] != null
          ? UserInfoModel.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      error: json['error'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      if (token != null) 'token': token,
      if (user != null) 'user': user!.toJson(),
      if (error != null) 'error': error,
    };
  }
}

/// Caller for authentication endpoint on Serverpod.
class EndpointAuth extends EndpointRef {
  EndpointAuth(super.caller);

  @override
  String get name => 'auth';

  Future<AuthResponseModel> login(String email, String password) async {
    return caller.callServerEndpoint<AuthResponseModel>(
      'auth',
      'login',
      {'email': email, 'password': password},
    );
  }

  Future<AuthResponseModel> register(String email, String password, String name) async {
    return caller.callServerEndpoint<AuthResponseModel>(
      'auth',
      'register',
      {'email': email, 'password': password, 'name': name},
    );
  }

  Future<UserInfoModel?> getCurrentUser() async {
    return caller.callServerEndpoint<UserInfoModel?>(
      'auth',
      'getCurrentUser',
      {},
    );
  }
}

/// Main Serverpod Client
class AppServerClient extends ServerpodClientShared {
  AppServerClient(
    String host, {
    super.securityContext,
    super.streamingConnectionTimeout = const Duration(seconds: 5),
    super.connectionTimeout = const Duration(seconds: 20),
    super.onFailedCall,
    super.onSucceededCall,
    super.disconnectStreamsOnLostInternetConnection,
  }) : super(
          host,
          Protocol.instance,
        ) {
    auth = EndpointAuth(this);
  }

  late final EndpointAuth auth;

  @override
  Map<String, EndpointRef> get endpointRefLookup => {
    'auth': auth,
  };

  @override
  Map<String, ModuleEndpointCaller> get moduleLookup => {};
}
