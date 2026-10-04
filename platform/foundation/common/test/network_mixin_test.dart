import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class _Recorder with NetworkMixin {
  _Recorder(this.source);

  final StreamController<InternetStatus> source;
  final calls = <String>[];

  @override
  Stream<InternetStatus> get internetStatusStream => source.stream;

  @override
  void onNetworkConnected() => calls.add('connected');

  @override
  void onNetworkDisconnected() => calls.add('disconnected');
}

/// `NetworkMixin` turns the connectivity stream into `onNetworkConnected` /
/// `onNetworkDisconnected`, with at most one live subscription.
void main() {
  late StreamController<InternetStatus> source;
  late _Recorder recorder;

  setUp(() {
    source = StreamController<InternetStatus>.broadcast();
    recorder = _Recorder(source);
  });

  tearDown(() async {
    await recorder.stopListenOnNetworkConnect();
    await source.close();
  });

  test('a status change reaches the matching callback', () async {
    await recorder.startListenOnNetworkConnect();

    source
      ..add(InternetStatus.disconnected)
      ..add(InternetStatus.connected);
    await pumpEventQueue();

    expect(recorder.calls, ['disconnected', 'connected']);
  });

  test('nothing is delivered before start', () async {
    source.add(InternetStatus.connected);
    await pumpEventQueue();

    expect(recorder.calls, isEmpty);
  });

  test('starting twice keeps a single subscription', () async {
    await recorder.startListenOnNetworkConnect();
    await recorder.startListenOnNetworkConnect();

    source.add(InternetStatus.connected);
    await pumpEventQueue();

    expect(recorder.calls, ['connected']);
    expect(source.hasListener, isTrue);
  });

  test('overlapping starts keep a single subscription', () async {
    await Future.wait([
      recorder.startListenOnNetworkConnect(),
      recorder.startListenOnNetworkConnect(),
    ]);

    source.add(InternetStatus.disconnected);
    await pumpEventQueue();

    expect(recorder.calls, ['disconnected']);
  });

  test('stop ends delivery, and a later start resumes it', () async {
    await recorder.startListenOnNetworkConnect();
    await recorder.stopListenOnNetworkConnect();

    source.add(InternetStatus.connected);
    await pumpEventQueue();
    expect(recorder.calls, isEmpty);
    expect(source.hasListener, isFalse);

    await recorder.startListenOnNetworkConnect();
    source.add(InternetStatus.connected);
    await pumpEventQueue();
    expect(recorder.calls, ['connected']);
  });

  test('stop without start is harmless', () async {
    await recorder.stopListenOnNetworkConnect();
  });
}
