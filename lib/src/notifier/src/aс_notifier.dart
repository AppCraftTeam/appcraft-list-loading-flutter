import 'dart:async';

abstract class ACNotifier<T> {
  ACNotifier({
    this.resendLastEvent = false
  });

  /// Если `true`,
  /// то при попытке отправить событие и при отстуствии подсписчиков, событие будет сохраненою.
  /// А при подписке будет отправлено последнее сохранённое событие.
  final bool resendLastEvent;
  T? _lastEvent;

  final _streamController = StreamController<T>.broadcast();

  ACNotifierSub<T> listen(void onData(T event)?) {
    final subscription = _streamController
      .stream
      .listen(onData);
    _trySendLastEvent();
    return subscription;
  }

  ACNotifierSub<T> listenAny(void onData()?) {
    final subscription = _streamController
      .stream
      .listen((_) {
        onData?.call();
      });
    _trySendLastEvent();
    return subscription;
  }

  void send(T event) {
    if (_streamController.hasListener) {
      _streamController.add(event);
    } else if (resendLastEvent) {
      _lastEvent = event;
    }
  }

  void _trySendLastEvent() {
    if (!resendLastEvent) return;

    final lastEvent = _lastEvent;
    if (lastEvent == null) return;
    _streamController.add(lastEvent);
    _lastEvent = null;
  }

  Future<void> dispose() async =>
    _streamController.close();

}

typedef ACNotifierSub<T> = StreamSubscription<T>;