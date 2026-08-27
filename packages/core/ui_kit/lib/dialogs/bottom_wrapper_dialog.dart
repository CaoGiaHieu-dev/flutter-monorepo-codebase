import 'package:flutter/material.dart';
import 'package:flutter_screenutil_plus/flutter_screenutil_plus.dart';

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
