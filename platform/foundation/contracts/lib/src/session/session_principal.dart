/// The identity of whoever holds the current session, reduced to what a
/// *consumer* needs.
///
/// ## Why this exists instead of re-exporting a user entity
///
/// [ISessionStatusStream] used to carry `UserEntity` from `domain_auth`. That
/// made the DI Hub — and therefore every consumer of it — depend on one
/// module's domain package for a *type*. `getItOrNull` cannot soften that: an
/// unresolved import fails at compile time, not at lookup time, so the
/// dependency was real and the auth module was not actually removable.
///
/// It also over-shares by construction. An entity grows whatever fields its
/// owning module needs — a payout account, a device token, an internal flag —
/// and a contract that re-exports it hands every consumer each of those the
/// moment it is added, without anyone deciding to share it. The contract being
/// smaller than the entity is the feature, not a limitation.
///
/// The module that owns the session (the `auth` sample) maps its entity to a
/// [SessionPrincipal] at its boundary, and is free to reshape the entity
/// afterwards without anyone rebuilding. Nothing here names that module: the
/// platform knows *that* there is a session, never *who* runs it.
///
/// Add a field here only when a *second* module genuinely needs it. A field one
/// module needs belongs in that module's own API package (`modules/<id>/api`).
final class SessionPrincipal {
  const SessionPrincipal({
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
      other is SessionPrincipal &&
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
  String toString() => 'SessionPrincipal(id: $id, displayName: $displayName)';
}
