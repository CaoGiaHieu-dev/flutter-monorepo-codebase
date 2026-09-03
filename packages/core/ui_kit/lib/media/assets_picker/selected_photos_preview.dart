import 'dart:typed_data';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class SelectedPhotosPreview extends StatefulWidget {
  final List<AssetEntity> selectedPhotos;
  final Map<AssetEntity, Uint8List?> thumbnailCache;
  final ValueChanged<AssetEntity> onRemovePhoto;
  final int maxSelection;

  const SelectedPhotosPreview({
    required this.selectedPhotos,
    required this.thumbnailCache,
    required this.onRemovePhoto,
    required this.maxSelection,
  });

  @override
  State<SelectedPhotosPreview> createState() => _SelectedPhotosPreviewState();
}

class _SelectedPhotosPreviewState extends State<SelectedPhotosPreview> {
  late ValueNotifier<Map<AssetEntity, Uint8List?>> _thumbnailNotifier;

  @override
  void initState() {
    super.initState();
    _thumbnailNotifier = ValueNotifier(widget.thumbnailCache);
  }

  @override
  void dispose() {
    _thumbnailNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: context.h(200),
      color: CupertinoColors.systemGrey.withAlpha(0.1.toOpacity),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: context.edgeInsets(horizontal: 12, vertical: 12),
              child: DefaultTextStyle(
                style: TextStyle(
                  color: CupertinoColors.black,
                  fontSize: context.sp(18),
                  fontWeight: FontWeight.bold,
                ),
                child: Text(
                  '${l10n.selected} ${widget.selectedPhotos.length}/${widget.maxSelection}',
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<Map<AssetEntity, Uint8List?>>(
                valueListenable: _thumbnailNotifier,
                builder: (context, thumbnailCache, child) {
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.selectedPhotos.length,
                    itemBuilder: (context, index) {
                      final photo = widget.selectedPhotos[index];
                      final thumbnail = thumbnailCache[photo];

                      if (thumbnail == null) {
                        photo.thumbnailData.then((data) {
                          thumbnailCache[photo] = data;
                          _thumbnailNotifier.value = Map.from(thumbnailCache);
                        });
                      }

                      return Container(
                        width: context.w(110),
                        height: context.h(110),
                        margin: context.edgeInsets(horizontal: 6),
                        child: PhotoItemPreview(
                          photo: photo,
                          thumbnail: thumbnail,
                          onRemovePhoto: widget.onRemovePhoto,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PhotoItemPreview extends StatelessWidget {
  final AssetEntity photo;
  final Uint8List? thumbnail;
  final ValueChanged<AssetEntity> onRemovePhoto;

  const PhotoItemPreview({
    required this.photo,
    required this.thumbnail,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: context.borderRadius(all: 12),
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha((0.2 * 255).round()),
                  spreadRadius: context.r(2),
                  blurRadius: context.r(5),
                  offset: Offset(0, context.h(3)),
                ),
              ],
            ),
            child: thumbnail != null
                ? ExtendedImage.memory(
                    thumbnail!,
                    fit: BoxFit.cover,
                    width: context.w(110),
                    height: context.h(110),
                  )
                : const Center(child: CupertinoActivityIndicator()),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => onRemovePhoto(photo),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CupertinoColors.white.withAlpha((0.8 * 255).round()),
              ),
              child: Icon(
                CupertinoIcons.clear_circled_solid,
                color: CupertinoColors.destructiveRed,
                size: context.r(24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
