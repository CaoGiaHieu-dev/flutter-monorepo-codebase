import 'package:material_ui/material_ui.dart';

import '../feedback/loading_widget.dart';

/// The full-screen loading layer `AppOverlay.showLoading` inserts: a
/// [LoadingWidget] over the theme's scrim.
class LoadingOverlayWidget extends StatelessWidget {
  const LoadingOverlayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The palette's `scrim` token (through the colour scheme): a scrim
      // dims whatever is behind it, in both themes.
      backgroundColor: Theme.of(context).colorScheme.scrim,
      body: const LoadingWidget(),
    );
  }
}
