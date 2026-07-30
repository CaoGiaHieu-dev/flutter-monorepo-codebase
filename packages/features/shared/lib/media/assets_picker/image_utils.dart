import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:core_base_ui/core_base_ui.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../dialogs/app_overlay.dart';
import 'assets_picker.dart';

/// Provides utilities for image handling, such as picking from the camera or gallery.
class ImageUtils {
  ImageUtils._();

  static var _isPickingImage = false;

  /// Picks images from the device's camera or gallery.
  ///
  /// This method acts as a dispatcher, calling the appropriate private handler
  /// based on the specified [source] and the current operating system.
  /// It ensures that only one image picking operation can happen at a time.
  static Future<List<Uint8List>> pickImages(
    BuildContext context, {
    AssetsPickType source = AssetsPickType.gallery,
    int limit = 10,
  }) async {
    if (limit == 0) return [];
    if (_isPickingImage) return [];

    _isPickingImage = true;
    List<Uint8List> pickedImages = [];

    try {
      if (source == AssetsPickType.camera) {
        pickedImages = await _pickFromCamera(context);
      } else {
        if (Platform.isAndroid) {
          pickedImages = await _pickFromGalleryAndroid(context, limit: limit);
        } else {
          pickedImages = await _pickFromGalleryIos(context, limit: limit);
        }
      }
    } catch (e, s) {
      if (context.mounted) {
        AppOverlay.showToast(
          content: e.toString(),
          duration: const Duration(seconds: 2),
        );
      }
      DynamicLogger.log(e, level: LogLevel.ERROR, stackTrace: s);
    } finally {
      _isPickingImage = false;
    }

    return pickedImages;
  }

  /// Handles picking a single image from the camera.
  static Future<List<Uint8List>> _pickFromCamera(BuildContext context) async {
    final imagePicker = ImagePicker();
    final pickedImage = await imagePicker.pickImage(
      source: ImageSource.camera,
      requestFullMetadata: false,
      imageQuality: 95,
      maxHeight: 720,
      maxWidth: 480,
    );

    if (pickedImage == null) return [];

    final totalFileSize = getFileSizeInMb(await pickedImage.length());
    if (totalFileSize > 20) {
      if (context.mounted) {
        AppOverlay.showToast(
          content: context.l10n.file_size_exceeded,
          duration: const Duration(seconds: 2),
        );
      }
      return [];
    }

    final imageBytes = await pickedImage.readAsBytes();
    return [imageBytes];
  }

  /// Handles picking multiple images from the gallery on Android using the Photo Picker.
  static Future<List<Uint8List>> _pickFromGalleryAndroid(
    BuildContext context, {
    required int limit,
  }) async {
    final imagePicker = ImagePicker();
    List<XFile> selectedAssets = [];
    if (limit < 2) {
      final selected = await imagePicker.pickImage(
        requestFullMetadata: false,
        imageQuality: 100,
        source: ImageSource.gallery,
      );
      selectedAssets = selected != null ? [selected] : [];
    } else {
      selectedAssets = await imagePicker.pickMultiImage(
        requestFullMetadata: false,
        imageQuality: 100,
        limit: limit,
      );
    }

    if (selectedAssets.isEmpty) return [];

    final limitedAssets = selectedAssets.take(limit).toList();
    final pickedImages = <Uint8List>[];

    if (limitedAssets.isNotEmpty) {
      var totalFileSize = 0;
      for (final asset in limitedAssets) {
        totalFileSize += await asset.length();
      }

      if (getFileSizeInMb(totalFileSize) > 20) {
        if (context.mounted) {
          AppOverlay.showToast(
            content: context.l10n.file_size_exceeded,
            duration: const Duration(seconds: 2),
          );
        }
        return [];
      }

      for (final asset in limitedAssets) {
        final imageBytes = await asset.readAsBytes();
        if (imageBytes.isNotEmpty) {
          pickedImages.add(imageBytes);
        }
      }
    }
    return pickedImages;
  }

  /// Handles picking multiple images from the gallery on iOS using a custom asset picker.
  static Future<List<Uint8List>> _pickFromGalleryIos(
    BuildContext context, {
    required int limit,
  }) async {
    final permission = await getPhotoPermission();
    final permissionStatus = await [permission].request();
    final isGranted =
        permissionStatus[permission] == PermissionStatus.granted ||
        permissionStatus[permission] == PermissionStatus.limited;
    if (!context.mounted) throw Exception('Context is not mounted');
    if (!isGranted)
      throw Exception(context.l10n.permission_denied(permission.toString()));

    final selectedAssets = await AssetsPicker.pickAssets(
      context,
      maxSelection: limit,
    );

    final pickedImages = <Uint8List>[];
    if (selectedAssets?.isNotEmpty ?? false) {
      for (var asset in selectedAssets!) {
        final imageBytes = await asset.thumbnailDataWithSize(
          const ThumbnailSize(480, 680),
        );
        if (imageBytes != null) {
          pickedImages.add(imageBytes);
        }
      }
    }
    return pickedImages;
  }

  /// Determines the appropriate photo-related permission based on the OS and SDK version.
  static Future<Permission> getPhotoPermission() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final androidSdkVersion = androidInfo.version.sdkInt;
      return androidSdkVersion >= 33 ? Permission.photos : Permission.storage;
    } else {
      return Permission.photos;
    }
  }

  /// Gets the formatted file size string (e.g., "1.2 MB").
  static String getFormattedFileSize(String filepath, int decimals) {
    final file = File(filepath);
    final bytes = file.lengthSync();
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// Converts a size in bytes to megabytes.
  static double getFileSizeInMb(int sizeInBytes) {
    return sizeInBytes / (1024 * 1024);
  }

  /// Converts an [ImageProvider] to a [Uint8List].
  static Future<Uint8List> convertImageProviderToUint8List(
    ImageProvider imageProvider,
  ) async {
    final stream = imageProvider.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();
    late ImageStreamListener listener;

    listener = ImageStreamListener(
      (ImageInfo image, bool synchronousCall) {
        completer.complete(image.image);
        stream.removeListener(listener);
      },
      onError: (dynamic exception, StackTrace? stackTrace) {
        completer.completeError(exception, stackTrace);
        stream.removeListener(listener);
      },
    );

    stream.addListener(listener);
    final image = await completer.future;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
