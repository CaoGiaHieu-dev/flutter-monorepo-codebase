/// The identity of the signed-in user, reduced to what a *consumer* needs.
///
/// ## Why this exists instead of re-exporting `UserEntity`
///
/// [IAuthStatusStream] used to carry `UserEntity` from `domain_auth`. That made
/// the DI Hub — and therefore every consumer of it — depend on one feature's
/// domain package for a *type*. `getItOrNull` cannot soften that: an unresolved
/// import fails at compile time, not at lookup time, so the dependency was real
/// and the auth feature was not actually removable.
///
/// It also over-shared. `UserEntity` carries `bankName`, `bankAccount` and
/// `fcmToken`; a module that only wants to know whether someone is signed in
/// had read access to all three. The contract is smaller than the entity on
/// purpose — that is the feature, not a limitation.
///
/// The owning feature maps `UserEntity → AuthPrincipal` at its boundary, and is
/// free to reshape its entity afterwards without anyone rebuilding.
///
/// Add a field here only when a *second* module genuinely needs it. A field one
/// module needs belongs in that module's own contract.
final class AuthPrincipal {
  const AuthPrincipal({
    required this.id,
    this.displayName,
    this.email,
    this.roles = const <String>{},
  });

  /// Stable identifier for the signed-in user.
  final String id;

  /// Name fit to show in a UI, when the backend supplies one.
  final String? displayName;

  final String? email;

  /// Coarse authorisation tags, as plain strings.
  ///
  /// Deliberately not an enum: an enum would have to live somewhere, and
  /// wherever it lived would become a second place every module must agree on.
  /// A module that cares about a specific role compares against its own
  /// constant.
  final Set<String> roles;

  bool hasRole(String role) => roles.contains(role);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthPrincipal &&
          other.id == id &&
          other.displayName == displayName &&
          other.email == email &&
          _sameRoles(other.roles);

  bool _sameRoles(Set<String> other) =>
      other.length == roles.length && other.containsAll(roles);

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    email,
    Object.hashAllUnordered(roles),
  );

  @override
  String toString() => 'AuthPrincipal(id: $id, displayName: $displayName)';
}
