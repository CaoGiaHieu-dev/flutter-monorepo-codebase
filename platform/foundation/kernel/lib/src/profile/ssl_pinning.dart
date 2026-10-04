import '../flavor.dart';

/// The certificate-pinning decision for one flavor.
///
/// There is no "unset": an app either pins ([SslPinning.pinned]) or says why
/// it does not ([SslPinning.disabled]). A flavor with no decision on a
/// platform that can pin is a boot problem (`P04`) and a composer error.
sealed class SslPinning {
  /// Pin the certificates whose SPKI SHA-256 hashes (base64) are [leaf] and
  /// [backup], and any [more].
  ///
  /// Two are required — the leaf and a backup — so rotating the leaf never
  /// bricks the app. The count is a property of the signature rather than a
  /// check on a list: Dart's constant evaluator cannot read `List.length`, so
  /// a list-taking constructor could not state it at compile time.
  const factory SslPinning.pinned(
    String leaf,
    String backup, [
    List<String> more,
  ]) = PinnedSsl;

  /// Do not pin, for the stated [reason]. The reason is logged at boot and
  /// listed under "decisions to revisit before shipping" in the app report.
  const factory SslPinning.disabled(String reason) = DisabledSsl;
}

/// Pin the given certificates. See [SslPinning.pinned].
final class PinnedSsl implements SslPinning {
  const PinnedSsl(this.leaf, this.backup, [this.more = const <String>[]])
    : assert(leaf != '' && backup != '', 'A pin cannot be empty.'),
      assert(leaf != backup, 'The backup pin must differ from the leaf pin.');

  /// The leaf certificate's base64 SPKI SHA-256 hash.
  final String leaf;

  /// The backup certificate's hash, kept so a leaf rotation does not break
  /// the app.
  final String backup;

  /// Any further hashes to accept.
  final List<String> more;

  /// Every hash to pin, leaf first.
  List<String> get hashes => [leaf, backup, ...more];
}

/// Do not pin. See [SslPinning.disabled].
final class DisabledSsl implements SslPinning {
  const DisabledSsl(this.reason)
    : assert(reason != '', 'A disabled pinning decision needs a reason.');

  /// Why this flavor does not pin.
  final String reason;
}

/// The pinning decision of every flavor an app declares.
final class SslPinningPolicy {
  const SslPinningPolicy(this.byFlavor);

  /// A policy that decides nothing: no flavor pins and none is flagged. What a
  /// hand-built object gets in a test: an empty hash list per flavor.
  const SslPinningPolicy.none() : byFlavor = const {};

  final Map<Flavor, SslPinning> byFlavor;

  /// The decision for [flavor], or `null` when the app made none.
  SslPinning? decisionFor(Flavor flavor) => byFlavor[flavor];

  /// The hashes to pin for [flavor]: the decision's when it is
  /// [SslPinning.pinned], empty otherwise (disabled, or no decision).
  List<String> hashesFor(Flavor flavor) {
    final decision = decisionFor(flavor);
    return decision is PinnedSsl ? decision.hashes : const <String>[];
  }
}
