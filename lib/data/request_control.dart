import 'dart:async';
import 'dart:collection';

/// Shares pending work only; completed values are never a second cache.
class SingleFlight<T> {
  final _pending = <String, Future<T>>{};

  Future<T> run(String key, Future<T> Function() action) {
    final pending = _pending[key];
    if (pending != null) return pending;
    late final Future<T> future;
    future = Future<T>.sync(action).whenComplete(() {
      if (identical(_pending[key], future)) _pending.remove(key);
    });
    _pending[key] = future;
    return future;
  }
}

/// FIFO permits, shared by interactive and background requests to a provider.
class RequestGate {
  final int limit;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();
  RequestGate(int limit) : limit = limit.clamp(1, 4);

  Future<T> run<T>(Future<T> Function() action) async {
    if (_active >= limit) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await action();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
