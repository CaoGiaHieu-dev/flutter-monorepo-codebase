import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class AppBarCustom extends AppBar {
  AppBarCustom({
    super.key,
    super.leading,
    super.automaticallyImplyLeading = true,
    super.title,
    super.actions,
    super.flexibleSpace,
    super.bottom,
    super.elevation,
    super.scrolledUnderElevation,
    super.notificationPredicate = defaultScrollNotificationPredicate,
    super.shadowColor,
    super.surfaceTintColor,
    super.shape,
    super.backgroundColor,
    super.foregroundColor,
    super.iconTheme,
    super.actionsIconTheme,
    super.primary = true,
    super.centerTitle,
    super.excludeHeaderSemantics = false,
    super.titleSpacing,
    super.toolbarOpacity = 1.0,
    super.bottomOpacity = 1.0,
    super.toolbarHeight,
    super.leadingWidth,
    super.toolbarTextStyle,
    super.titleTextStyle,
    super.systemOverlayStyle,
    super.forceMaterialTransparency = false,
    super.clipBehavior,
  }) : assert(elevation == null || elevation >= 0.0);
}

// ==========================================
// 🛠️ Interactive Previews (Flutter 3.44+)
// ==========================================

@Preview(name: 'Custom AppBar with Title', group: 'Navigation')
Widget appBarCustomPreview() {
  return Scaffold(
    appBar: AppBarCustom(
      title: const Text('Dashboard'),
      centerTitle: true,
      leading: IconButton(icon: const Icon(Icons.menu), onPressed: () {}),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () {},
        ),
      ],
    ),
    body: const Center(child: Text('Main Content Area')),
  );
}
