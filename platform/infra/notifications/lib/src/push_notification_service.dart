import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_kernel/platform_kernel.dart';

import 'utils/notification_constants.dart';

/// Enum to define the type of operation for blocked types.
enum _BlockedTypeOperationType { add, remove }

/// Class to represent a blocked type operation.
class _BlockedTypeOperation {
  final String type;
  final _BlockedTypeOperationType operationType;

  _BlockedTypeOperation(this.type, this.operationType);
}

/// Builds a piece of text for the grouped (inbox-style) Android notification
/// that summarises the [activeCount] notifications already on screen.
///
/// Returning `null` leaves that piece of text out.
typedef NotificationInboxTextBuilder = String? Function(int activeCount);

/// Android notification channel for app messages.
const _initializationSettingsAndroid = AndroidInitializationSettings(
  NotificationConstants.ANDROID_DEFAULT_ICON,
);

/// The notification channel for app messages.
const _channel = AndroidNotificationChannel(
  NotificationConstants.CHANNEL_ID,
  NotificationConstants.CHANNEL_NAME,
  description: NotificationConstants.CHANNEL_DESCRIPTION,
  importance: Importance.max,
);

/// The notification channel group for app messages.
const _channelGroup = AndroidNotificationChannelGroup(
  NotificationConstants.CHANNEL_GROUP_ID,
  NotificationConstants.CHANNEL_GROUP_NAME,
  description: NotificationConstants.CHANNEL_GROUP_DESCRIPTION,
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
/// `@PostConstruct(preResolve: true)` — so everything it awaits delays
/// `configureDependencies()`, and with it the first frame. It therefore awaits
/// only what must exist by then (Firebase, the channels, the message handlers,
/// the initial message); the permission prompt and the FCM token fetch run in
/// the background. Read the token from [tokenStream], not [fcmToken], right
/// after boot.
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

  /// Builds the summary line of the grouped (inbox-style) Android
  /// notification, e.g. "3 new messages".
  ///
  /// `null` by default: this package owns no translations, and a hardcoded
  /// sentence would be English on every device. Set it from the app — which
  /// has its localizations — to show a summary.
  NotificationInboxTextBuilder? inboxSummaryBuilder;

  /// Builds the title of the grouped (inbox-style) Android notification.
  ///
  /// `null` by default, in which case the notification keeps its own title.
  NotificationInboxTextBuilder? inboxTitleBuilder;

  /// Message queue for handling blocked types.
  final MessageQueue<_BlockedTypeOperation> _blockedTypeQueue = MessageQueue();

  /// Initializes the notification service.
  ///
  /// Awaits only what must be ready when DI finishes: Firebase, the Android
  /// channels, the message handlers, the local notifications plugin and the
  /// message that launched the app. The permission prompt and the FCM token
  /// fetch are started but **not** awaited — awaiting them held the whole boot
  /// on a system dialog (until the user answered it) or on the network (the
  /// token fetch, offline). Their failures are logged, never thrown.
  /// Automatically called during DI setup.
  @PostConstruct(preResolve: true)
  Future<void> init() async {
    await _initializeFirebase();
    await _setupFlutterNotifications();
    _setNotificationListeners();
    await _initializeFlutterLocalNotifications();

    // Determines the initial message that opened the app, prioritizing local notifications.
    // This is crucial for handling app launches from terminated state via a notification tap.
    await _getInitialMessage();

    unawaited(_requestPermissionsAndRegisterToken());
  }

  /// Requests notification permission, then registers the FCM token.
  ///
  /// Runs in the background from [init]; never throws.
  Future<void> _requestPermissionsAndRegisterToken() async {
    try {
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
    } catch (e, s) {
      DynamicLogger.log(
        'Requesting notification permission failed: $e',
        tag: 'PushNotificationService.init',
        level: LogLevel.ERROR,
        stackTrace: s,
      );
    }

    try {
      await registerToken();
      DynamicLogger.log(fcmToken, tag: 'PushNotificationService.Fcm token');
    } catch (e, s) {
      DynamicLogger.log(
        'Registering the FCM token failed: $e',
        tag: 'PushNotificationService.init',
        level: LogLevel.ERROR,
        stackTrace: s,
      );
    }
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
          final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
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
  ///
  /// The token itself is fetched by [registerToken], in the background.
  void _setNotificationListeners() {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedAppMessage);

    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      if (_fcmToken == newToken) return;
      _fcmToken = newToken;
      _tokenStreamController.sink.add(newToken);
      DynamicLogger.log(
        newToken,
        tag: 'PushNotificationService.Fcm onTokenRefresh',
      );
    });
  }

  /// Initializes Flutter local notifications.
  Future<void> _initializeFlutterLocalNotifications() async {
    // No permission request here: on iOS it would make this awaited call wait
    // for the user to answer the prompt. [_requestPermissionsAndRegisterToken]
    // asks, in the background.
    final initializationSettingsDarwin = const DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
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
    if (!force && isTypeBlocked(message.data['type']?.toString())) {
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
      final activeCount = activeNotifications?.length ?? 0;
      inboxStyleInformation = InboxStyleInformation(
        lines.take(min(3, lines.length)).toList(),
        contentTitle: inboxTitleBuilder?.call(activeCount),
        summaryText: inboxSummaryBuilder?.call(activeCount),
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
      icon: NotificationConstants.ANDROID_DEFAULT_ICON,
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

  /// Normalizes a notification type for comparison: blocking is
  /// case-insensitive and ignores surrounding whitespace.
  static String _normalizeType(String type) => type.trim().toLowerCase();

  /// Whether notifications of [type] are currently blocked.
  ///
  /// Case-insensitive: blocking `Promo` also blocks `promo` and `PROMO`.
  bool isTypeBlocked(String? type) =>
      type != null && _blockedNotificationTypes.contains(_normalizeType(type));

  /// Processing function for blocked type operations.
  Future<void> _processBlockedTypeOperation(
    _BlockedTypeOperation operation,
  ) async {
    // Stored normalized, so add/remove/lookup all agree on one spelling.
    final type = _normalizeType(operation.type);
    if (operation.operationType == _BlockedTypeOperationType.add) {
      if (!_blockedNotificationTypes.contains(type)) {
        _blockedNotificationTypes.add(type);
      }
    } else if (operation.operationType == _BlockedTypeOperationType.remove) {
      _blockedNotificationTypes.remove(type);
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
    _fcmToken = await _firebaseMessaging.getToken().catchError((
      Object e,
      StackTrace s,
    ) {
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
