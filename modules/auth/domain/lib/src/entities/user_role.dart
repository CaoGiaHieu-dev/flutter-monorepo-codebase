/// What a signed-in user may do, as the auth module models it.
///
/// Plain Dart: how a backend spells a role on the wire is a transport
/// concern, mapped in `data_auth`'s `UserModel` — this package names no
/// JSON value.
enum UserRole { customer, owner, none, unknown }
