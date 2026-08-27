import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class BottomWrapperDialog extends StatelessWidget {
  const BottomWrapperDialog({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Dialog(
        alignment: Alignment.bottomCenter,
        insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: child,
      ),
    );
  }
}
