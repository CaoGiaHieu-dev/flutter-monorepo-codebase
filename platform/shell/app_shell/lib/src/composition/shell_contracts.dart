import 'package:core_common/core_common.dart';

/// Whether the shell can run without a contract.
enum ShellNeed {
  /// The shell registers it itself, from its own packages. Without it the
  /// shell does not work.
  required,

  /// An app or a module contributes it. Without it the shell degrades as the
  /// row's `whenAbsent` says — and the app declares which it chose.
  optional,
}

/// How many implementations the shell collects of a contract.
enum ContractCardinality {
  /// One, resolved with `getItOrNull`.
  one,

  /// Any number, collected with `getAllOrEmpty`.
  many,
}

/// One thing the shell resolves from dependency injection: what it is, what
/// the shell does without it, and where it is looked up.
///
/// The catalog (`SHELL_CONTRACTS`, in `utils/shell_contract_constants.dart`) is the one table of what an app must and
/// may provide. `checkAppContract` holds every app to it, and each lookup
/// stays `getItOrNull` / `getAllOrEmpty` with a fallback (RULE-12), so an app
/// composed without a contributing module still boots.
final class ShellContract<T extends Object> {
  const ShellContract({
    required this.id,
    required this.need,
    required this.cardinality,
    required this.consumer,
    required this.whenAbsent,
    this.bundle,
  });

  /// The stable id an app's `capabilities:` declaration uses (`splash`,
  /// `session_state`).
  final String id;

  /// Whether the shell needs it, or an app may go without.
  final ShellNeed need;

  /// How many implementations the shell collects.
  final ContractCardinality cardinality;

  /// The manifest key that declares this contract together with its
  /// siblings — a bundle declares all its members at once (`session`) — or
  /// `null` when the contract is declared under its own [id].
  final String? bundle;

  /// Where the shell looks it up: `path:line`, comma-separated when there are
  /// several. Shown in the app report; a test holds each line to the contract
  /// it names.
  final String consumer;

  /// What the shell does when nothing is registered, in a sentence — shown
  /// verbatim in the app report and in the problems that name this contract.
  final String whenAbsent;

  /// The contract's type.
  Type get type => T;

  /// The manifest key that declares this contract: its [bundle], else its
  /// [id].
  String get manifestKey => bundle ?? id;

  /// What the graph has registered for [T] right now, resolved the way the
  /// shell resolves it — never `getIt` / `getAll`, so an absent registration
  /// is an empty list.
  List<Object> registered() => cardinality == ContractCardinality.many
      ? [...getAllOrEmpty<T>()]
      : [?getItOrNull<T>()];
}
