import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../constants/api_status_constants.dart';

/// Utility class for downloading images from URLs.
class DownloadImage {
  /// Downloads an image from the given [url] and returns it as a [Uint8List].
  ///
  /// Returns the image data if the download is successful, otherwise returns null.
  static Future<Uint8List?> downloadImage(String? url) async {
    if (url == null || url.isEmpty) {
      return null;
    }

    try {
      // Perform the download request
      final response = await Dio().get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: false,
          validateStatus: (status) {
            return status != null && status < 500;
          },
        ),
      );

      // Check if the response status code indicates success
      if (response.statusCode == ApiStatusConstants.SUCCESS &&
          response.data != null) {
        return Uint8List.fromList(response.data!);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Downloads a list of images from the given [urls] and returns them as a list of [Uint8List].
  ///
  /// Returns a list of image data if the downloads are successful, otherwise returns empty.
  static Future<List<Uint8List>> downloadImages(List<String?> urls) async {
    try {
      final List<Uint8List> images = [];
      for (final String? url in urls) {
        if (url == null) continue;
        final Uint8List? imageData = await downloadImage(url);
        if (imageData != null) {
          images.add(imageData);
        }
      }
      return images;
    } catch (e) {
      return [];
    }
  }
}
