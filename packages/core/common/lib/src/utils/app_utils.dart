import 'dart:io';
import 'dart:math' as math;

import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../enums/app_enums.dart';

/// The `AppUtils` class provides various utility functions for the application.
/// It includes methods for checking internet connection, handling permissions, and more.
class AppUtils {
  AppUtils._();

  /// The current update status of the application.
  static UpdateStatus forceUpdateStatus = UpdateStatus.upToDate;

  /// The internet connection checker instance.
  static final internetConnection = InternetConnection();

  /// Unfocuses the keyboard if it is currently focused.
  static void unfocusKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Gets the formatted file size for the specified file path.
  /// [filepath] - The path of the file.
  /// [decimals] - The number of decimal places to include in the formatted size.
  /// Returns the formatted file size as a string.
  static String getFormattedFileSize(String filepath, int decimals) {
    final file = File(filepath);
    final bytes = file.lengthSync();
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// Gets the file size in megabytes for the specified size in bytes.
  /// [sizeInBytes] - The size in bytes.
  /// Returns the size in megabytes as a double.
  static double getFileSizeInMb(int sizeInBytes) {
    final sizeInMb = sizeInBytes / (1024 * 1024);
    return sizeInMb;
  }

  /// Requests the specified permissions.
  /// [permissions] - The list of permissions to request.
  /// Returns a boolean indicating whether all permissions were granted.
  static Future<bool> requestPermission(List<Permission> permissions) async {
    final statuses = await permissions.request();

    final responseStatus = <Permission, PermissionStatus>{};

    for (var item in statuses.entries) {
      if (item.value != PermissionStatus.granted &&
          item.value != PermissionStatus.limited) {
        responseStatus[item.key] = await item.key.request();
      } else {
        responseStatus[item.key] = item.value;
      }
    }

    for (var item in responseStatus.entries) {
      if (item.value != PermissionStatus.granted &&
          item.value != PermissionStatus.limited) {
        return false;
      }
    }

    return true;
  }
}
