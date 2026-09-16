import 'package:serverpod/serverpod.dart';
import 'package:serverpod_database/serverpod_database.dart';

/// Server initialization and lifecycle hooks.
void run(List<String> args) async {
  final pod = Serverpod(
    args,
    Protocol(),
    Endpoints(),
  );

  await pod.start();
}

/// Fallback Protocol stub until serverpod generate is run
class Protocol extends DatabaseSerializationManager {
  @override
  Table? getTableForType(Type t) => null;

  @override
  List<TableDefinition> getTargetTableDefinitions() => [];
}

/// Fallback Endpoints stub until serverpod generate is run
class Endpoints extends EndpointDispatch {
  @override
  void initializeEndpoints(Server server) {}
}
