/// What an app declares about one optional contract the shell resolves
/// (`capabilities:` in `apps/<id>/app_manifest.yaml`).
///
/// Absence is a decision, not an accident: the app either provides the
/// contract ([CapabilityExpectation.provided]) or states why it does not
/// ([CapabilityExpectation.absent]). The shell's `checkAppContract` holds the
/// declaration to what is actually registered.
sealed class CapabilityExpectation {
  /// The app registers an implementation.
  const factory CapabilityExpectation.provided() = ProvidedCapability;

  /// The app deliberately registers none, for [reason].
  const factory CapabilityExpectation.absent(String reason) = AbsentCapability;
}

/// See [CapabilityExpectation.provided].
final class ProvidedCapability implements CapabilityExpectation {
  const ProvidedCapability();
}

/// See [CapabilityExpectation.absent].
final class AbsentCapability implements CapabilityExpectation {
  const AbsentCapability(this.reason)
    : assert(reason != '', 'An absent capability needs a reason.');

  /// Why the app has no implementation.
  final String reason;
}
