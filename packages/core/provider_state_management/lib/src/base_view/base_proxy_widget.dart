import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BaseProxyWidget<T, R extends ChangeNotifier> extends StatelessWidget {
  final R Function(BuildContext context, T parent) create;
  final Widget child;
  final bool Function(T parent, R previous) updateWhen;
  final Widget Function(BuildContext context, Widget? child)? builder;

  const BaseProxyWidget({
    super.key,
    required this.create,
    required this.child,
    this.builder,
    required this.updateWhen,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProxyProvider<T, R>(
      create: (context) => create(context, context.read<T>()),
      update: (context, value, previous) {
        if (previous == null || updateWhen(value, previous)) {
          return create(context, value);
        }
        return previous;
      },
      builder: builder,
      child: child,
    );
  }
}

class BaseProxyWidget2<T1, T2, R extends ChangeNotifier>
    extends StatelessWidget {
  final R Function(BuildContext context, T1 t1, T2 t2) create;
  final Widget child;
  final bool Function(T1 t1, T2 t2, R previous) updateWhen;
  final Widget Function(BuildContext context, Widget? child)? builder;

  const BaseProxyWidget2({
    super.key,
    required this.create,
    required this.child,
    this.builder,
    required this.updateWhen,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProxyProvider2<T1, T2, R>(
          create: (context) =>
              create(context, context.read<T1>(), context.read<T2>()),
          update: (context, t1, t2, previous) {
            if (previous == null || updateWhen(t1, t2, previous)) {
              return create(context, t1, t2);
            }
            return previous;
          },
        ),
      ],
      child: child,
    );
  }
}

class BaseProxyWidget3<T1, T2, T3, R extends ChangeNotifier>
    extends StatelessWidget {
  final R Function(BuildContext context, T1 t1, T2 t2, T3 t3) create;
  final Widget child;
  final bool Function(T1 t1, T2 t2, T3 t3, R previous) updateWhen;
  final Widget Function(BuildContext context, Widget? child)? builder;

  const BaseProxyWidget3({
    super.key,
    required this.create,
    required this.child,
    this.builder,
    required this.updateWhen,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProxyProvider3<T1, T2, T3, R>(
          create: (context) => create(
            context,
            context.read<T1>(),
            context.read<T2>(),
            context.read<T3>(),
          ),
          update: (context, t1, t2, t3, previous) {
            if (previous == null || updateWhen(t1, t2, t3, previous)) {
              return create(context, t1, t2, t3);
            }
            return previous;
          },
        ),
      ],
      child: child,
    );
  }
}

class BaseProxyWidget4<T1, T2, T3, T4, R extends ChangeNotifier>
    extends StatelessWidget {
  final R Function(BuildContext context, T1 t1, T2 t2, T3 t3, T4 t4) create;
  final Widget child;
  final bool Function(T1 t1, T2 t2, T3 t3, T4 t4, R previous) updateWhen;
  final Widget Function(BuildContext context, Widget? child)? builder;

  const BaseProxyWidget4({
    super.key,
    required this.create,
    required this.child,
    this.builder,
    required this.updateWhen,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProxyProvider4<T1, T2, T3, T4, R>(
          create: (context) => create(
            context,
            context.read<T1>(),
            context.read<T2>(),
            context.read<T3>(),
            context.read<T4>(),
          ),
          update: (context, t1, t2, t3, t4, previous) {
            if (previous == null || updateWhen(t1, t2, t3, t4, previous)) {
              return create(context, t1, t2, t3, t4);
            }
            return previous;
          },
        ),
      ],
      child: child,
    );
  }
}
