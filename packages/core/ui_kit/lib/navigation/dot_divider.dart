import 'package:core_base_ui/core_base_ui.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:material_ui/material_ui.dart';

class DotDivider extends StatelessWidget {
  const DotDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return DottedLine(
      direction: Axis.horizontal,
      dashColor: context.colors.surfaceVariant,
      dashGapColor: Colors.transparent,
      dashGapLength: 2,
      dashLength: 2,
    );
  }
}
