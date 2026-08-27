import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:photo_manager/photo_manager.dart';

import 'assets_picker_l10n_extension.dart';

class AlbumSelection extends StatelessWidget {
  final List<AssetPathEntity> albums;
  final ValueChanged<AssetPathEntity> onAlbumSelected;

  const AlbumSelection({required this.albums, required this.onAlbumSelected});

  @override
  Widget build(BuildContext context) {
    return CupertinoActionSheet(
      title: Text(context.l10n.selectAlbum),
      actions: albums.map((album) {
        return CupertinoActionSheetAction(
          child: Text(album.nameL10n(context)),
          onPressed: () => onAlbumSelected(album),
        );
      }).toList(),
      cancelButton: CupertinoActionSheetAction(
        child: Text(context.l10n.cancel),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}
