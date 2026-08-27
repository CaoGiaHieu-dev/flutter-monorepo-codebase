import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider_state_management/provider_state_management.dart';

class LoadingMoreWidget<P extends LoadMoreMixin> extends StatelessWidget {
  const LoadingMoreWidget({this.builder});

  final WidgetBuilder? builder;

  @override
  Widget build(BuildContext context) {
    return Selector<P, bool>(
      selector: (_, provider) => provider.isLoadingMore,
      builder: (_, isLoadingMore, child) {
        if (isLoadingMore) return child!;
        return const SizedBox();
      },
      child:
          builder?.call(context) ??
          SafeArea(
            minimum: EdgeInsets.symmetric(vertical: 10.h),
            child: const Center(child: CircularProgressIndicator.adaptive()),
          ),
    );
  }
}

class LoadMoreListView<P extends LoadMoreMixin> extends BoxScrollView {
  const LoadMoreListView({
    super.key,
    required this.itemBuilder,
    this.findChildIndexCallback,
    this.separatorBuilder,
    required this.itemCount,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    super.scrollCacheExtent,
    super.dragStartBehavior,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    super.hitTestBehavior,
  }) : assert(itemCount >= 0),
       itemExtent = null,
       itemExtentBuilder = null,
       prototypeItem = null,
       super(semanticChildCount: itemCount);

  final double? itemExtent;

  final ItemExtentBuilder? itemExtentBuilder;

  final Widget? prototypeItem;

  final NullableIndexedWidgetBuilder itemBuilder;
  final ChildIndexGetter? findChildIndexCallback;
  final IndexedWidgetBuilder? separatorBuilder;
  final int itemCount;

  @override
  Widget buildChildLayout(BuildContext context) {
    final SliverChildDelegate childrenDelegate;

    final isLoadMore = context.select<P, bool>((value) => value.isLoadingMore);

    childrenDelegate = SliverChildBuilderDelegate(
      (BuildContext context, int index) {
        if (index == _computeActualChildCount(itemCount) - 1 && isLoadMore) {
          return SafeArea(
            minimum: EdgeInsets.symmetric(vertical: 10.h),
            child: const Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final int itemIndex = index ~/ 2;
        if (index.isEven) {
          return itemBuilder(context, itemIndex);
        }
        return separatorBuilder?.call(context, itemIndex) ?? const SizedBox();
      },
      findChildIndexCallback: findChildIndexCallback,
      childCount: _computeActualChildCount(itemCount) + (isLoadMore ? 1 : 0),
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      addSemanticIndexes: true,
      semanticIndexCallback: (Widget widget, int index) {
        return index.isEven ? index ~/ 2 : null;
      },
    );
    if (itemExtent != null) {
      return SliverFixedExtentList(
        delegate: childrenDelegate,
        itemExtent: itemExtent!,
      );
    } else if (itemExtentBuilder != null) {
      return SliverVariedExtentList(
        delegate: childrenDelegate,
        itemExtentBuilder: itemExtentBuilder!,
      );
    } else if (prototypeItem != null) {
      return SliverPrototypeExtentList(
        delegate: childrenDelegate,
        prototypeItem: prototypeItem!,
      );
    }
    return SliverList(delegate: childrenDelegate);
  }

  Widget loadMoreWrapper(Widget child) {
    return Selector<P, bool>(
      selector: (context, p) => p.isLoadingMore,
      builder: (context, value, child) {
        return SliverList(
          delegate: SliverChildListDelegate([
            child!,
            if (value)
              const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
          ]),
        );
      },
      child: child,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DoubleProperty('itemExtent', itemExtent, defaultValue: null),
    );
  }

  static int _computeActualChildCount(int itemCount) {
    return math.max(0, itemCount * 2 - 1);
  }
}
