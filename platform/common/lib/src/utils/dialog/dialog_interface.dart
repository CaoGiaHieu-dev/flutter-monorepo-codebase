part of 'app_dialog_controller.dart';

abstract class OverlayDialogWidget extends StatefulWidget {
  const OverlayDialogWidget({super.key});

  @override
  OverlayDialogState<OverlayDialogWidget> createState();
}

abstract class OverlayDialogState<T extends OverlayDialogWidget>
    extends State<T> {
  void closeDialog([dynamic result]) {
    AppDialogController.dismiss(
      identity: OverlayInheritedWidget.maybeOf(context)?.identity,
      result: result,
    );
  }

  @override
  Widget build(BuildContext context);
}

class OverlayInheritedWidget extends InheritedWidget {
  const OverlayInheritedWidget(this.identity, {required super.child});
  final String identity;

  static OverlayInheritedWidget? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<OverlayInheritedWidget>();
  }

  @override
  bool updateShouldNotify(covariant OverlayInheritedWidget oldWidget) {
    return oldWidget.identity != identity;
  }
}
