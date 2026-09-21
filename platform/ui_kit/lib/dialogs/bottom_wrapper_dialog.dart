import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

class BottomWrapperDialog extends StatelessWidget {
  const BottomWrapperDialog({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Dialog(
        alignment: Alignment.bottomCenter,
        insetPadding: context.edgeInsets(horizontal: 16),
        // Not `Colors.white`: the sheet's children use theme colours, so a
        // hardcoded background stayed white in dark mode and rendered light
        // text on it.
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: context.borderRadius(all: 16),
        ),
        child: child,
      ),
    );
  }
}
