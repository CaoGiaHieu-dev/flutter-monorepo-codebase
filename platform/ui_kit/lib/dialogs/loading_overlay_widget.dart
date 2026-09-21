import 'package:material_ui/material_ui.dart';

import '../feedback/loading_widget.dart';

class LoadingOverlayWidget extends StatelessWidget {
  const LoadingOverlayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      // `Colors.black38` on purpose, and the one hardcoded colour left in this
      // package. A scrim is not a surface: it dims whatever is behind it, and
      // Flutter's own `ModalBarrier` is a fixed black in both themes for the
      // same reason. Swapping it for `context.colors.*` would make it
      // *lighten* the screen in dark mode.
      backgroundColor: Colors.black38,
      body: LoadingWidget(),
    );
  }
}
