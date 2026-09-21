import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

extension AssetPathEntityL10n on AssetPathEntity {
  String nameL10n(BuildContext context) {
    final subType = albumTypeEx?.darwin?.subtype;
    if (subType == null)
      return name.isNotEmpty ? name : context.l10n.selectAlbum;

    switch (subType) {
      case PMDarwinAssetCollectionSubtype.albumRegular:
        return context.l10n.albumRegular;
      case PMDarwinAssetCollectionSubtype.albumSyncedEvent:
        return context.l10n.albumSyncedEvent;
      case PMDarwinAssetCollectionSubtype.albumSyncedFaces:
        return context.l10n.albumSyncedFaces;
      case PMDarwinAssetCollectionSubtype.albumSyncedAlbum:
        return context.l10n.albumSyncedAlbum;
      case PMDarwinAssetCollectionSubtype.albumImported:
        return context.l10n.albumImported;
      case PMDarwinAssetCollectionSubtype.smartAlbumGeneric:
        return context.l10n.smartAlbumGeneric;
      case PMDarwinAssetCollectionSubtype.smartAlbumPanoramas:
        return context.l10n.smartAlbumPanoramas;
      case PMDarwinAssetCollectionSubtype.smartAlbumVideos:
        return context.l10n.smartAlbumVideos;
      case PMDarwinAssetCollectionSubtype.smartAlbumFavorites:
        return context.l10n.smartAlbumFavorites;
      case PMDarwinAssetCollectionSubtype.smartAlbumTimelapses:
        return context.l10n.smartAlbumTimelapses;
      case PMDarwinAssetCollectionSubtype.smartAlbumAllHidden:
        return context.l10n.smartAlbumAllHidden;
      case PMDarwinAssetCollectionSubtype.smartAlbumRecentlyAdded:
        return context.l10n.smartAlbumRecentlyAdded;
      case PMDarwinAssetCollectionSubtype.smartAlbumBursts:
        return context.l10n.smartAlbumBursts;
      case PMDarwinAssetCollectionSubtype.smartAlbumSlomoVideos:
        return context.l10n.smartAlbumSlomoVideos;
      case PMDarwinAssetCollectionSubtype.smartAlbumUserLibrary:
        return context.l10n.smartAlbumUserLibrary;
      case PMDarwinAssetCollectionSubtype.smartAlbumSelfPortraits:
        return context.l10n.smartAlbumSelfPortraits;
      case PMDarwinAssetCollectionSubtype.smartAlbumScreenshots:
        return context.l10n.smartAlbumScreenshots;
      case PMDarwinAssetCollectionSubtype.smartAlbumDepthEffect:
        return context.l10n.smartAlbumDepthEffect;
      case PMDarwinAssetCollectionSubtype.smartAlbumLivePhotos:
        return context.l10n.smartAlbumLivePhotos;
      case PMDarwinAssetCollectionSubtype.smartAlbumAnimated:
        return context.l10n.smartAlbumAnimated;
      case PMDarwinAssetCollectionSubtype.smartAlbumLongExposures:
        return context.l10n.smartAlbumLongExposures;
      case PMDarwinAssetCollectionSubtype.smartAlbumUnableToUpload:
        return context.l10n.smartAlbumUnableToUpload;
      case PMDarwinAssetCollectionSubtype.smartAlbumRAW:
        return context.l10n.smartAlbumRAW;
      case PMDarwinAssetCollectionSubtype.smartAlbumCinematic:
        return context.l10n.smartAlbumCinematic;
      default:
        return name;
    }
  }
}
