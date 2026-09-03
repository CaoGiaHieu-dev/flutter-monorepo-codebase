import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/material.dart';

class BottomWrapperDialog extends StatelessWidget {
  const BottomWrapperDialog({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Dialog(
        alignment: Alignment.bottomCenter,
        insetPadding: context.edgeInsets(horizontal: 16),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: context.borderRadius(all: 16),
        ),
        child: child,
      ),
    );
  }
}
