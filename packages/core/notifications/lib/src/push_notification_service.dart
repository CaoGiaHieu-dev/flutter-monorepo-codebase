import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core_common/core_common.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';

import 'utils/notification_constants.dart';

/// Enum to define the type of operation for blocked types.
enum _BlockedTypeOperationType { add, remove }

/// Class to represent a blocked type operation.
class _BlockedTypeOperation {
  final String type;
  final _BlockedTypeOperationType operationType;

  _BlockedTypeOperation(this.type, this.operationType);
}

/// Android notification channel for app messages.
const _initializationSettingsAndroid = AndroidInitializationSettings(
  NotificationConstants.androidDefaultIcon,
);

/// The notification channel for app messages.
const _channel = AndroidNotificationChannel(
  NotificationConstants.channelId,
  NotificationConstants.channelName,
  description: NotificationConstants.channelDescription,
  importance: Importance.max,
);

/// The notification channel group for app messages.
const _channelGroup = AndroidNotificationChannelGroup(
  NotificationConstants.channelGroupId,
  NotificationConstants.channelGroupName,
  description: NotificationConstants.channelGroupDescription,
);

/// Handles background messages received when the app is in the background.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: getItOrNull<FirebaseOptions>());
  } catch (_) {
    // If Firebase is already initialized, or fails because of lack of options, ignore.
  }
  DynamicLogger.log(
    message,
    tag: 'PushNotificationService.firebaseMessagingBackgroundHandler',
  );
}

/// Service class for managing push notifications.
///
/// Registered as a `@singleton` in DI. The [init] method is called
/// automatically when the DI container starts up thanks to
/// `@PostConstruct(preResolve: true)`.
@singleton
class PushNotificationService {
  /// Flutter local notifications plugin instance.
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  /// Instance of FirebaseMessaging.
  late final FirebaseMessaging _firebaseMessaging;

  /// Stream controller for broadcasting data received from notifications.
  final _dataStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream controller for broadcasting notification titles.
  final _titleStreamController = StreamController<String>.broadcast();

  /// Stream controller for broadcasting notification bodies.
  final _bodyStreamController = StreamController<String>.broadcast();

  /// Stream controller for broadcasting FCM tokens.
  final _tokenStreamController = StreamController<String>.broadcast();

  /// Stream controller for broadcasting foreground messages.
  final _foregroundMessageStreamController =
      StreamController<RemoteMessage>.broadcast();

  /// List of blocked notification types.
  final _blockedNotificationTypes = <String>[];

  /// FCM token of the device.
  String? _fcmToken;

  /// Firebase Options for initialization.
  final FirebaseOptions _firebaseOptions;

  /// The initial message received when the app is launched.
  RemoteMessage? _initialMessage;

  /// Constructor. Receives optional [FirebaseOptions] via DI.
  /// The initialization logic is handled automatically in [init].
  PushNotificationService(this._firebaseOptions) {
    // Set the processing function for the message queue.
    _blockedTypeQueue.setProcessingFunction(_processBlockedTypeOperation);
  }

  /// Stream getter for the data stream.
  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;

  /// Stream getter for the title stream.
  Stream<String> get titleStream => _titleStreamController.stream;

  /// Stream getter for the body stream.
  Stream<String> get bodyStream => _bodyStreamController.stream;

  /// Stream getter for the token stream.
  Stream<String> get tokenStream => _tokenStreamController.stream;

  /// Stream getter for the foreground message stream.
  Stream<RemoteMessage> get foregroundMessageStream =>
      _foregroundMessageStreamController.stream;

  /// Getter for the FCM token.
  String? get fcmToken => _fcmToken;

  /// Getter for the initial message.
  RemoteMessage? get initialMessage => _initialMessage;

  /// Message queue for handling blocked types.
  final MessageQueue<_BlockedTypeOperation> _blockedTypeQueue = MessageQueue();

  /// Initializes the notification service.
  ///
  /// This method initializes Firebase, sets up Flutter notifications, requests permissions,
  /// sets notification listeners, gets the initial message, and initializes Flutter local notifications.
  /// Automatically called during DI setup.
  @PostConstruct(preResolve: true)
  Future<void> init() async {
    await _initializeFirebase();
    await _setupFlutterNotifications();

    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    DynamicLogger.log(
      'User granted permission: ${settings.authorizationStatus}',
      tag: 'PushNotificationService.init',
    );

    if (Platform.isAndroid) {
      await _requestNotificationPermissionAndroid();
    } else if (Platform.isIOS) {
      await _requestNotificationPermissionIOS();
    }

    await _setNotificationListeners();
    await _initializeFlutterLocalNotifications();

    // Determines the initial message that opened the app, prioritizing local notifications.
    // This is crucial for handling app launches from terminated state via a notification tap.
    await _getInitialMessage();
  }

  /// Fetches the initial [RemoteMessage] that caused the application to open.
  Future<void> _getInitialMessage() async {
    // Holder for the initial message.
    RemoteMessage? initialMessage;

    // 1. Attempt to get the message from local notification plugin.
    final notificationAppLaunchDetails = await flutterLocalNotificationsPlugin
        .getNotificationAppLaunchDetails();

    // Check if the app was launched by a local notification and the payload is present.
    if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
      final payload =
          notificationAppLaunchDetails!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        DynamicLogger.log(
          'App launched from local notification with payload.',
          tag: 'PushNotificationService._getInitialMessage',
        );
        try {
          // The payload is a JSON string containing the message data, so we decode it.
          final data = Map<String, dynamic>.from(jsonDecode(payload));
          // Construct a RemoteMessage from the data payload.
          initialMessage = RemoteMessage(data: data);
        } catch (e, s) {
          DynamicLogger.log(
            'Error decoding local notification payload: $e',
            tag: 'PushNotificationService._getInitialMessage',
            level: LogLevel.ERROR,
            stackTrace: s,
          );
        }
      }
    }

    // 2. Fallback to FirebaseMessaging.getInitialMessage().
    if (initialMessage == null) {
      DynamicLogger.log(
        'No local notification launch detected, checking Firebase for initial message.',
        tag: 'PushNotificationService._getInitialMessage',
      );
      initialMessage = await _firebaseMessaging.getInitialMessage();
    }

    // Assign the final determined initial message.
    _initialMessage = initialMessage;
  }

  /// Initializes Firebase.
  Future<void> _initializeFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _firebaseOptions);
    }
    _firebaseMessaging = FirebaseMessaging.instance;
  }

  /// Sets up Flutter notifications.
  Future<void> _setupFlutterNotifications() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannelGroup(_channelGroup);
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
  }

  /// Requests notification permission for Android devices.
  Future<void> _requestNotificationPermissionAndroid() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  /// Requests notification permission for iOS devices.
  Future<void> _requestNotificationPermissionIOS() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Sets notification listeners.
  Future<void> _setNotificationListeners() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedAppMessage);

    await registerToken();

    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      if (_fcmToken == newToken) return;
      _fcmToken = newToken;
      _tokenStreamController.sink.add(newToken);
      DynamicLogger.log(
        newToken,
        tag: 'PushNotificationService.Fcm onTokenRefresh',
      );
    });

    DynamicLogger.log(fcmToken, tag: 'PushNotificationService.Fcm token');
  }

  /// Initializes Flutter local notifications.
  Future<void> _initializeFlutterLocalNotifications() async {
    final initializationSettingsDarwin = const DarwinInitializationSettings();
    final initializationSettings = InitializationSettings(
      android: _initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );
  }

  /// Handles notification response.
  void _onDidReceiveNotificationResponse(
    NotificationResponse notificationResponse,
  ) {
    final payload = notificationResponse.payload;
    // A tap can arrive with no payload at all (e.g. a notification posted
    // without one). Decoding an empty string always throws, so bail out early
    // instead of logging a bogus FormatException on every such tap.
    if (payload == null || payload.isEmpty) return;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        DynamicLogger.log(
          'Notification payload is not a JSON object: $decoded',
          tag: 'PushNotificationService.onDidReceiveNotificationResponse',
          level: LogLevel.ERROR,
        );
        return;
      }
      _dataStreamController.sink.add(Map<String, dynamic>.from(decoded));
    } catch (e, s) {
      DynamicLogger.log(
        e,
        tag: 'PushNotificationService.onDidReceiveNotificationResponse',
        level: LogLevel.ERROR,
        stackTrace: s,
      );
    }
  }

  /// Handles foreground messages received when the app is in the foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    _foregroundMessageStreamController.sink.add(message);
    showFlutterNotification(message);
  }

  /// Handles opened app messages.
  void _handleOpenedAppMessage(RemoteMessage message) {
    _handleMessageData(message);
  }

  /// Handles message data.
  void _handleMessageData(RemoteMessage message) {
    _dataStreamController.sink.add(message.data);

    if (message.notification?.title != null) {
      _titleStreamController.sink.add(message.notification!.title!);
    }
    if (message.notification?.body != null) {
      _bodyStreamController.sink.add(message.notification!.body!);
    }
  }

  /// Shows a Flutter notification.
  Future<void> showFlutterNotification(
    RemoteMessage message, {
    bool force = false,
  }) async {
    RemoteNotification? notification = message.notification;
    if (notification == null) return;

    // Check if the notification type is blocked, unless forced.
    if (!force &&
        _blockedNotificationTypes
            .map((e) => e.toLowerCase())
            .contains(message.data['type'])) {
      return;
    }

    // Get the active notifications and use them to create an inbox style if more than one active notification.
    final activeNotifications = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.getActiveNotifications();

    InboxStyleInformation? inboxStyleInformation;
    if (activeNotifications?.isNotEmpty ?? false) {
      // Match on `groupKey`, not `channelId`: every notification posted below
      // carries `groupKey: _channelGroup.id`, whereas its `channelId` is
      // `_channel.id`. Comparing `channelId` against the *group* id never
      // matches, which left the inbox style permanently empty.
      final lines =
          activeNotifications
              ?.where((element) => element.groupKey == _channelGroup.id)
              .map((element) => element.body ?? '')
              .toList() ??
          [];
      inboxStyleInformation = InboxStyleInformation(
        lines.take(min(3, lines.length)).toList(),
        contentTitle: NotificationConstants.channelName,
        summaryText: 'You have ${activeNotifications?.length} messages',
      );
    }

    // Create Android notification details.
    final androidNotifyDetail = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      styleInformation: inboxStyleInformation,
      setAsGroupSummary: true,
      groupKey: _channelGroup.id,
      onlyAlertOnce: true,
      priority: Priority.high,
      importance: Importance.max,
      icon: NotificationConstants.androidDefaultIcon,
    );

    // Create iOS notification details.
    const iOSNotifyDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    // Show the notification.
    await _showMessage(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      android: androidNotifyDetail,
      iOS: iOSNotifyDetails,
      payload: jsonEncode(message.data),
    );
  }

  /// Shows a notification.
  ///
  /// [android] and [iOS] are bundled into a [NotificationDetails] and handed to
  /// the plugin, which selects the entry matching the current platform. Passing
  /// them is what preserves the channel, group, inbox style, icon and priority
  /// configured by [showFlutterNotification] — omitting them makes the OS fall
  /// back to its defaults.
  Future<void> _showMessage({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? android,
    DarwinNotificationDetails? iOS,
    String? payload,
  }) async {
    await flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: android, iOS: iOS),
      payload: payload,
    );
  }

  /// Subscribes to a topic.
  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
    DynamicLogger.log(
      'Subscribed to topic: $topic',
      tag: 'PushNotificationService.subscribeToTopic',
    );
  }

  /// Unsubscribes from a topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
    DynamicLogger.log(
      'Unsubscribed from topic: $topic',
      tag: 'PushNotificationService.unsubscribeFromTopic',
    );
  }

  /// Processing function for blocked type operations.
  Future<void> _processBlockedTypeOperation(
    _BlockedTypeOperation operation,
  ) async {
    if (operation.operationType == _BlockedTypeOperationType.add) {
      if (!_blockedNotificationTypes.contains(operation.type)) {
        _blockedNotificationTypes.add(operation.type);
      }
    } else if (operation.operationType == _BlockedTypeOperationType.remove) {
      _blockedNotificationTypes.remove(operation.type);
    }
  }

  /// Adds notification types to the blocked list.
  Future<void> addBlockedTypes(List<String> types) async {
    for (var type in types) {
      await _blockedTypeQueue.enqueue(
        _BlockedTypeOperation(type, _BlockedTypeOperationType.add),
      );
    }
  }

  /// Removes notification types from the blocked list.
  Future<void> removeBlockedTypes(List<String> types) async {
    for (var type in types) {
      await _blockedTypeQueue.enqueue(
        _BlockedTypeOperation(type, _BlockedTypeOperationType.remove),
      );
    }
  }

  /// Revokes the FCM token.
  Future<void> revokeToken() async {
    await _firebaseMessaging.deleteToken();
    DynamicLogger.log(
      'FCM token revoked',
      tag: 'PushNotificationService.revokeToken',
    );
  }

  /// Registers the FCM token.
  Future<void> registerToken() async {
    _fcmToken = await _firebaseMessaging.getToken().catchError((e, s) {
      DynamicLogger.log(
        e,
        tag: 'PushNotificationService.registerToken',
        level: LogLevel.ERROR,
      );
      debugPrintStack(stackTrace: s);
      return null;
    });
    if (_fcmToken != null) {
      _tokenStreamController.sink.add(_fcmToken!);
    }
  }

  /// Closes every broadcast controller owned by this service.
  ///
  /// Not called in production: this service is registered as a `@singleton`,
  /// so the DI container holds it for the whole application lifetime and the
  /// process exits before teardown would matter. It exists for tests and for
  /// callers that tear the container down explicitly (e.g. `getIt.reset()`
  /// between integration tests) — without it those tests leak stream
  /// controllers across cases.
  ///
  /// After calling this the instance is unusable; resolve a fresh one from DI.
  void dispose() {
    _dataStreamController.close();
    _bodyStreamController.close();
    _titleStreamController.close();
    _tokenStreamController.close();
    _foregroundMessageStreamController.close();
  }
}
