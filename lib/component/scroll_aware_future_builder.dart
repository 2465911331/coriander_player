import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Starts once per resource and never reschedules after disposal.
class ScrollAwareFutureBuilder<T> extends StatefulWidget {
  const ScrollAwareFutureBuilder(
      {super.key, required this.future, required this.builder, this.identity});
  final Future<T> Function() future;
  final AsyncWidgetBuilder<T> builder;
  final Object? identity;
  @override
  State<ScrollAwareFutureBuilder<T>> createState() =>
      _ScrollAwareFutureBuilderState<T>();
}

class _ScrollAwareFutureBuilderState<T>
    extends State<ScrollAwareFutureBuilder<T>> {
  Future<T>? _future;
  bool _scheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ScrollAwareFutureBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        (widget.identity == null && oldWidget.future != widget.future)) {
      _future = null;
      _load();
    }
  }

  void _load() {
    if (!mounted || _future != null) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      if (_scheduled) return;
      _scheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        _scheduled = false;
        if (!mounted) return;
        _load();
        if (_future != null) setState(() {});
      });
      return;
    }
    _future = Future<T>.sync(widget.future);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
      key: ValueKey(widget.identity), future: _future, builder: widget.builder);
}
