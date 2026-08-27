import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil_plus/flutter_screenutil_plus.dart';
import 'package:photo_manager/photo_manager.dart';

class PhotoGridItem extends StatefulWidget {
  final AssetEntity photo;
  final Map<AssetEntity, Uint8List?> thumbnailCache;
  final ValueNotifier<List<AssetEntity>> selectedPhotos;
  final ValueChanged<AssetEntity> onPhotoTap;
  final int max;

  const PhotoGridItem({
    required this.photo,
    required this.thumbnailCache,
    required this.selectedPhotos,
    required this.onPhotoTap,
    required this.max,
  });

  @override
  State<PhotoGridItem> createState() => _PhotoGridItemState();
}

class _PhotoGridItemState extends State<PhotoGridItem>
    with AutomaticKeepAliveClientMixin {
  final _thumbnailNotifier = ValueNotifier<Uint8List?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.endOfFrame.whenComplete(_loadThumbnail);
  }

  Future<void> _loadThumbnail() async {
    if (widget.thumbnailCache.containsKey(widget.photo)) {
      _thumbnailNotifier.value = widget.thumbnailCache[widget.photo];
    } else {
      // Preload resized thumbnails and cache them
      // Kept as `.w` on purpose: this runs inside an async method with no
      // BuildContext, and reaching for one across an await is unsafe. The
      // value is a decode hint for the thumbnail cache, not a layout
      // dimension, so it never needs to rebuild on a metrics change.
      final bytes = await widget.photo.thumbnailDataWithSize(
        ThumbnailSize.square(200.w.toInt()),
        quality: 80,
      );

      _thumbnailNotifier.value = bytes;
      widget.thumbnailCache[widget.photo] = bytes;
    }
  }

  @override
  void dispose() {
    _thumbnailNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<List<AssetEntity>>(
      valueListenable: widget.selectedPhotos,
      builder: (context, selectedPhotos, child) {
        final isSelected = selectedPhotos.contains(widget.photo);
        final isDisabled = selectedPhotos.length >= widget.max && !isSelected;
        return GestureDetector(
          onTap: () => widget.onPhotoTap(widget.photo),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: context.borderRadius(all: 8),
                child: ColorFiltered(
                  colorFilter: isDisabled
                      ? ColorFilter.mode(
                          Colors.black.withAlpha((0.6 * 255).round()),
                          BlendMode.multiply,
                        )
                      : const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.multiply,
                        ),
                  child: child,
                ),
              ),
              if (isSelected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: CupertinoColors.white,
                    ),
                    child: const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      child: ValueListenableBuilder<Uint8List?>(
        valueListenable: _thumbnailNotifier,
        builder: (context, bytes, child) {
          return bytes != null
              ? ExtendedImage.memory(
                  bytes,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                )
              : const Center(child: CupertinoActivityIndicator());
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
