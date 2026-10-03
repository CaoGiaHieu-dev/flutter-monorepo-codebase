/// One thing wrong with how an app declares or composes itself, in a shape a
/// person can act on.
///
/// The same type is produced at boot (`AppProfile.validate`), in the smoke
/// test (`checkAppContract`) and by composer, so a problem reads the same
/// wherever it is found.
final class ProfileProblem {
  const ProfileProblem({
    required this.code,
    required this.description,
    required this.action,
  });

  /// A stable id: `P01`–`P05` from `AppProfile.validate`, `C01`–`C09` from
  /// `checkAppContract`.
  final String code;

  /// What is wrong, naming the file and key when there is one.
  final String description;

  /// What to do about it — paste-ready where it is a line of YAML or a command.
  final String action;

  @override
  String toString() => 'Description:\n$description\nAction:\n$action';
}
