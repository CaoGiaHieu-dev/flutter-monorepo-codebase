import 'package:serverpod/serverpod.dart';

/// Authentication endpoint handling user registration, login, and session validation.
class AuthEndpoint extends Endpoint {
  Future<Map<String, dynamic>> login(
    Session session,
    String email,
    String password,
  ) async {
    session.log('User attempting login with email: $email');

    // In a production serverpod setup, verify credentials against database:
    // final user = await UserInfo.db.findFirstRow(session, where: (t) => t.email.equals(email));
    return {
      'success': true,
      'token': 'srv_jwt_${DateTime.now().millisecondsSinceEpoch}',
      'user': {
        'id': 'usr_${email.hashCode.abs()}',
        'email': email,
        'name': email.split('@').first,
        'role': 'customer',
      },
    };
  }

  Future<Map<String, dynamic>> register(
    Session session,
    String email,
    String password,
    String name,
  ) async {
    session.log('Registering new user: $email');
    return {
      'success': true,
      'token': 'srv_jwt_${DateTime.now().millisecondsSinceEpoch}',
      'user': {
        'id': 'usr_${email.hashCode.abs()}',
        'email': email,
        'name': name,
        'role': 'customer',
      },
    };
  }
}
