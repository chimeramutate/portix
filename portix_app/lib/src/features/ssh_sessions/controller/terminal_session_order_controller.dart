class TerminalSessionOrderController {
  final List<String> _order = [];

  int get length => _order.length;

  int indexOf(String sessionId) => _order.indexOf(sessionId);

  void remove(String sessionId) {
    _order.remove(sessionId);
  }

  void restoreAtOrPlaceLast(String sessionId, int index) {
    _order.remove(sessionId);
    if (index >= 0 && index <= _order.length) {
      _order.insert(index, sessionId);
      return;
    }
    _order.add(sessionId);
  }

  List<T> ordered<T>(List<T> sessions, String Function(T session) idOf) {
    final activeIds = sessions.map(idOf).toSet();
    _order.removeWhere((sessionId) => !activeIds.contains(sessionId));
    for (final session in sessions) {
      final sessionId = idOf(session);
      if (!_order.contains(sessionId)) {
        _order.add(sessionId);
      }
    }
    final byId = {for (final session in sessions) idOf(session): session};
    return [
      for (final sessionId in _order)
        if (byId[sessionId] != null) byId[sessionId]!,
    ];
  }

  void place(
    String draggedSessionId, {
    String? targetSessionId,
    bool afterTarget = true,
  }) {
    _order.remove(draggedSessionId);
    if (targetSessionId == null) {
      _order.add(draggedSessionId);
      return;
    }
    final targetIndex = _order.indexOf(targetSessionId);
    if (targetIndex < 0) {
      _order.add(draggedSessionId);
      return;
    }
    final insertIndex = afterTarget ? targetIndex + 1 : targetIndex;
    _order.insert(insertIndex.clamp(0, _order.length), draggedSessionId);
  }
}
