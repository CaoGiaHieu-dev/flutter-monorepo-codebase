import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/cupertino.dart';
import 'package:photo_manager/photo_manager.dart';

import 'album_selection.dart';
import 'assets_picker_l10n_extension.dart';
import 'photo_grid_item.dart';
import 'selected_photos_preview.dart';

// Auto-generated exports, do not edit manually.
export 'album_selection.dart';
export 'assets_picker_l10n_extension.dart';
export 'image_utils.dart';
export 'photo_grid_item.dart';
export 'selected_photos_preview.dart';

enum AssetsPickType { gallery, camera }

class AssetsPicker extends StatefulWidget {
  final int maxSelection;
  final RequestType type;

  const AssetsPicker({this.maxSelection = 5, required this.type});

  @override
  State<AssetsPicker> createState() => _AssetsPickerState();

  static Future<bool> checkPermission() async {
    final permitted = await PhotoManager.requestPermissionExtend();
    return permitted.hasAccess;
  }

  // Static function to navigate to the AssetsPicker page and return the selected assets
  static Future<List<AssetEntity>?> pickAssets(
    BuildContext context, {
    int maxSelection = 5,
  }) async {
    final permitted = await PhotoManager.requestPermissionExtend();
    if (!permitted.hasAccess) return [];
    if (!context.mounted) return [];

    final result = await Navigator.push<List<AssetEntity>>(
      context,
      CupertinoPageRoute(
        builder: (context) =>
            AssetsPicker(maxSelection: maxSelection, type: RequestType.image),
      ),
    );
    return result;
  }
}

class _AssetsPickerState extends State<AssetsPicker> {
  final ValueNotifier<List<AssetEntity>> _photos = ValueNotifier([]);
  final ValueNotifier<List<AssetPathEntity>> _albums = ValueNotifier([]);
  final ValueNotifier<List<AssetEntity>> _selectedPhotos = ValueNotifier([]);
  final ValueNotifier<AssetPathEntity?> _selectedAlbum = ValueNotifier(null);
  final ValueNotifier<bool> _isLoadMore = ValueNotifier(false);
  final Map<AssetEntity, Uint8List?> _thumbnailCache = {};
  final Queue<Function> _scrollEventQueue = Queue();
  final _scrollController = ScrollController();
  var _isEndPage = false;
  var currentPage = 0;
  var _isProcessingScrollEvent = false;

  @override
  void initState() {
    super.initState();
    _fetchAlbums();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchAlbums() async {
    List<PMDarwinAssetCollectionSubtype> subTypes = switch (widget.type) {
      RequestType.image => [
        PMDarwinAssetCollectionSubtype.albumRegular,
        PMDarwinAssetCollectionSubtype.albumSyncedEvent,
        PMDarwinAssetCollectionSubtype.albumSyncedFaces,
        PMDarwinAssetCollectionSubtype.albumSyncedAlbum,
        PMDarwinAssetCollectionSubtype.albumImported,
        PMDarwinAssetCollectionSubtype.smartAlbumGeneric,
        PMDarwinAssetCollectionSubtype.smartAlbumFavorites,
        PMDarwinAssetCollectionSubtype.smartAlbumUserLibrary,
        PMDarwinAssetCollectionSubtype.smartAlbumScreenshots,
        PMDarwinAssetCollectionSubtype.smartAlbumLivePhotos,
      ],
      RequestType.video => [
        PMDarwinAssetCollectionSubtype.albumRegular,
        PMDarwinAssetCollectionSubtype.albumImported,
        PMDarwinAssetCollectionSubtype.smartAlbumGeneric,
        PMDarwinAssetCollectionSubtype.smartAlbumFavorites,
        PMDarwinAssetCollectionSubtype.smartAlbumUserLibrary,
        PMDarwinAssetCollectionSubtype.smartAlbumVideos,
      ],
      _ => [
        PMDarwinAssetCollectionSubtype.albumRegular,
        PMDarwinAssetCollectionSubtype.albumImported,
        PMDarwinAssetCollectionSubtype.smartAlbumGeneric,
        PMDarwinAssetCollectionSubtype.smartAlbumFavorites,
        PMDarwinAssetCollectionSubtype.smartAlbumUserLibrary,
      ],
    };

    final albums = await PhotoManager.getAssetPathList(
      type: widget.type,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        audioOption: const FilterOption(
          needTitle: false,
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        createTimeCond: DateTimeCond.def().copyWith(ignore: true),
        updateTimeCond: DateTimeCond.def().copyWith(ignore: true),
      ),
      pathFilterOption: PMPathFilter(
        darwin: PMDarwinPathFilter(
          type: [PMDarwinAssetCollectionType.smartAlbum],
          subType: subTypes,
        ),
      ),
    );

    _albums.value = albums;
    if (albums.isNotEmpty) {
      _selectedAlbum.value = albums.first;
      _fetchPhotos();
    }
  }

  Future<void> _fetchPhotos() async {
    if (_selectedAlbum.value == null || _isEndPage) return;

    final recentPhotos = await _selectedAlbum.value!.getAssetListPaged(
      page: currentPage,
      size: 20,
    );

    if (recentPhotos.isEmpty) {
      _isEndPage = true;
      return;
    }

    _photos.value = [..._photos.value, ...recentPhotos];

    currentPage++;

    // Check if the GridView is full and load more if necessary
    WidgetsBinding.instance.endOfFrame.whenComplete(() {
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent <=
              _scrollController.position.viewportDimension) {
        _fetchPhotos();
      }
    });
  }

  Future<void> _onScroll() async {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _scrollEventQueue.add(() async {
        _isLoadMore.value = true;
        await _fetchPhotos();
        _isLoadMore.value = false;
      });

      if (!_isProcessingScrollEvent) {
        _processScrollEvents();
      }
    }
  }

  Future<void> _processScrollEvents() async {
    if (_isProcessingScrollEvent || _scrollEventQueue.isEmpty) return;

    _isProcessingScrollEvent = true;

    while (_scrollEventQueue.isNotEmpty) {
      final event = _scrollEventQueue.removeFirst();
      await event();
    }

    _isProcessingScrollEvent = false;
  }

  void _onPhotoTap(AssetEntity photo) {
    final currentSelected = _selectedPhotos.value;
    if (currentSelected.contains(photo)) {
      currentSelected.remove(photo);
    } else {
      if (currentSelected.length < widget.maxSelection) {
        currentSelected.add(photo);
      }
    }
    _selectedPhotos.value = List.from(currentSelected);
  }

  void _showAlbumSelection() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => AlbumSelection(
        albums: _albums.value,
        onAlbumSelected: (album) {
          if (_selectedAlbum.value != album) {
            _selectedAlbum.value = album;
            currentPage = 0;
            _photos.value = [];
            _isEndPage = false;
            _isLoadMore.value = false;
            _resetScrollController();
            _fetchPhotos();
          }

          Navigator.pop(context);
        },
      ),
    );
  }

  void _resetScrollController() {
    _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: _buildNavigationBar(context),
      child: Column(
        children: [
          Expanded(child: _buildPhotoGrid(context)),
          _buildSelectedPhotosPreview(),
        ],
      ),
    );
  }

  /// Builds the navigation bar with album selector and done button.
  CupertinoNavigationBar _buildNavigationBar(BuildContext context) {
    return CupertinoNavigationBar(
      middle: _buildAlbumSelector(context),
      trailing: _buildDoneButton(context),
    );
  }

  /// Builds the album selector widget.
  Widget _buildAlbumSelector(BuildContext context) {
    return GestureDetector(
      onTap: _showAlbumSelection,
      child: ValueListenableBuilder<AssetPathEntity?>(
        valueListenable: _selectedAlbum,
        builder: (context, selectedAlbum, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selectedAlbum?.nameL10n(context) ?? context.l10n.selectAlbum,
              ),
              Icon(CupertinoIcons.chevron_down, size: context.sp(16)),
            ],
          );
        },
      ),
    );
  }

  /// Builds the done button.
  Widget _buildDoneButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, _selectedPhotos.value),
      child: Text(
        context.l10n.done,
        style: const TextStyle(color: CupertinoColors.activeBlue),
      ),
    );
  }

  /// Builds the photo grid with loading indicator.
  Widget _buildPhotoGrid(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.all(context.w(4)),
            sliver: ValueListenableBuilder<List<AssetEntity>>(
              valueListenable: _photos,
              builder: (context, photos, child) {
                return photos.isEmpty
                    ? _buildEmptyState(context)
                    : _buildPhotoGridSliver(context, photos);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the empty state when no photos are available.
  Widget _buildEmptyState(BuildContext context) {
    return SliverFillRemaining(
      child: Center(
        child: DefaultTextStyle(
          style: TextStyle(
            color: CupertinoColors.systemGrey,
            fontSize: context.sp(18),
          ),
          child: Text(context.l10n.noPhotosAvailable),
        ),
      ),
    );
  }

  /// Builds the photo grid sliver.
  Widget _buildPhotoGridSliver(BuildContext context, List<AssetEntity> photos) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: context.w(4),
        mainAxisSpacing: context.h(4),
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildGridItem(photos, index),
        childCount: photos.length + 1,
      ),
    );
  }

  /// Builds individual grid items (photos or loading indicator).
  Widget _buildGridItem(List<AssetEntity> photos, int index) {
    if (index == photos.length) {
      return ValueListenableBuilder<bool>(
        valueListenable: _isLoadMore,
        builder: (context, isLoading, child) {
          return isLoading
              ? const Center(child: CupertinoActivityIndicator())
              : const SizedBox.shrink();
        },
      );
    }

    final photo = photos[index];
    return PhotoGridItem(
      photo: photo,
      thumbnailCache: _thumbnailCache,
      selectedPhotos: _selectedPhotos,
      onPhotoTap: _onPhotoTap,
      max: widget.maxSelection,
    );
  }

  /// Builds the selected photos preview at the bottom.
  Widget _buildSelectedPhotosPreview() {
    return ValueListenableBuilder<List<AssetEntity>>(
      valueListenable: _selectedPhotos,
      builder: (context, selectedPhotos, child) {
        if (selectedPhotos.isEmpty) return const SizedBox.shrink();
        return SelectedPhotosPreview(
          selectedPhotos: selectedPhotos,
          thumbnailCache: _thumbnailCache,
          onRemovePhoto: (photo) {
            final currentSelected = _selectedPhotos.value;
            currentSelected.remove(photo);
            _selectedPhotos.value = List.from(currentSelected);
          },
          maxSelection: widget.maxSelection,
        );
      },
    );
  }
}
