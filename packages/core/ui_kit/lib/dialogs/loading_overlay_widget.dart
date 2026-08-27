import 'package:flutter/material.dart';

import '../feedback/loading_widget.dart';

class LoadingOverlayWidget extends StatelessWidget {
  const LoadingOverlayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black38,
      body: LoadingWidget(),
    );
  }
}
