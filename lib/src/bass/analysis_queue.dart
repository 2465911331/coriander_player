/// All offline workers share BASS's no-output device (0). Serialize their
/// lifetimes so freeing one worker's device cannot invalidate another's stream.
class AudioAnalysisQueue {
  static final instance = AudioAnalysisQueue();
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
