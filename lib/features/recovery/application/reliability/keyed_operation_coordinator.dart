enum CoordinatedOperationState { executed, replayed, conflict }

class CoordinatedOperationResult<T> {
  const CoordinatedOperationResult._({required this.state, this.value});

  const CoordinatedOperationResult.executed(T result)
    : this._(state: CoordinatedOperationState.executed, value: result);

  const CoordinatedOperationResult.replayed(T result)
    : this._(state: CoordinatedOperationState.replayed, value: result);

  const CoordinatedOperationResult.conflict()
    : this._(state: CoordinatedOperationState.conflict);

  final CoordinatedOperationState state;
  final T? value;
}

class KeyedOperationCoordinator {
  final Set<String> _activeKeys = {};
  final Map<String, Object> _completedValues = {};

  Future<CoordinatedOperationResult<T>> run<T>({
    required String key,
    required Future<T> Function() operation,
    required bool Function(T result) rememberResult,
  }) async {
    final completed = _completedValues[key];
    if (completed is T) {
      return CoordinatedOperationResult.replayed(completed);
    }
    if (!_activeKeys.add(key)) {
      return const CoordinatedOperationResult.conflict();
    }
    try {
      final value = await operation();
      if (rememberResult(value)) _completedValues[key] = value as Object;
      return CoordinatedOperationResult.executed(value);
    } finally {
      _activeKeys.remove(key);
    }
  }

  bool isActive(String key) => _activeKeys.contains(key);
}
