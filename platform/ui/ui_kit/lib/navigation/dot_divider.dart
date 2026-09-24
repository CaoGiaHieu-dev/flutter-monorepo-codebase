import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/shared_ui_constants.dart';

class DotDivider extends StatelessWidget {
  const DotDivider({super.key});

  @override
  Widget build(BuildContext context) {
    // Horizontal line: dash and gap are widths, so they scale with `w`.
    final dash = context.w(SharedUiConstants.DOT_DIVIDER_DASH_LENGTH);
    return DottedLine(
      direction: Axis.horizontal,
      dashColor: context.colors.surfaceVariant,
      dashGapColor: Colors.transparent,
      dashGapLength: dash,
      dashLength: dash,
    );
  }
}
