import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class CustomCacheNetworkImage extends StatelessWidget {
  const CustomCacheNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const Center(child: Icon(Icons.error));
    }
    return CachedNetworkImage(
      imageUrl: url,
      placeholder: (context, url) => Center(
        child: CircularProgressIndicator.adaptive(
          strokeWidth: 2.0,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).primaryColor,
          ),
        ),
      ),
      errorBuilder: (context, url, error) =>
          const Center(child: Icon(Icons.error)),
      width: width,
      height: height,
      fit: fit,
    );
  }
}

// ==========================================
// 🛠️ Interactive Previews (Flutter 3.44+)
// ==========================================

@Preview(name: 'Cached Network Image', group: 'Media')
Widget customCacheNetworkImagePreview() {
  return const Scaffold(
    body: Center(
      child: CustomCacheNetworkImage(
        'https://flutter.github.io/assets-for-api-docs/assets/widgets/owl.jpg',
        width: 150,
        height: 150,
        fit: BoxFit.cover,
      ),
    ),
  );
}

@Preview(name: 'Empty/Error Image State', group: 'Media')
Widget customCacheNetworkImageErrorPreview() {
  return const Scaffold(
    body: Center(
      child: CustomCacheNetworkImage(
        '', // Empty URL to trigger error widget
        width: 100,
        height: 100,
      ),
    ),
  );
}
