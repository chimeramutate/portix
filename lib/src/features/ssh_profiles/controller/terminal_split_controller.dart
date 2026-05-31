import 'package:flutter/material.dart';

enum SplitDirection {
  left,
  right,
  top,
  bottom;

  Axis get axis {
    return switch (this) {
      SplitDirection.left || SplitDirection.right => Axis.horizontal,
      SplitDirection.top || SplitDirection.bottom => Axis.vertical,
    };
  }
}

sealed class SplitNode {
  const SplitNode();
  List<String> get sessionIds;

  bool contains(String sessionId) => sessionIds.contains(sessionId);
}

class SplitLeaf extends SplitNode {
  const SplitLeaf(this.sessionId);

  final String sessionId;

  @override
  List<String> get sessionIds => [sessionId];
}

class SplitBranch extends SplitNode {
  const SplitBranch(this.axis, this.children);

  final Axis axis;
  final List<SplitNode> children;

  @override
  List<String> get sessionIds => [
    for (final child in children) ...child.sessionIds,
  ];
}

class TerminalWorkspaceGroup {
  TerminalWorkspaceGroup({
    required this.id,
    required this.label,
    required this.root,
  });

  final String id;
  final String label;
  SplitNode root;
}

class TerminalSplitController {
  const TerminalSplitController();

  SplitNode? removeSession(SplitNode? node, String sessionId) {
    if (node == null) return null;
    if (node is SplitLeaf) {
      return node.sessionId == sessionId ? null : node;
    }
    final branch = node as SplitBranch;
    final children = branch.children
        .map((child) => removeSession(child, sessionId))
        .nonNulls
        .toList();
    if (children.isEmpty) return null;
    if (children.length == 1) return children.first;
    return SplitBranch(branch.axis, children);
  }

  SplitNode insertSplit(
    SplitNode node,
    String targetSessionId,
    String newSessionId,
    SplitDirection direction,
  ) {
    if (node is SplitLeaf) {
      if (node.sessionId != targetSessionId) return node;
      final newLeaf = SplitLeaf(newSessionId);
      final targetLeaf = SplitLeaf(targetSessionId);
      final axis = direction.axis;
      final children = switch (direction) {
        SplitDirection.left || SplitDirection.top => [newLeaf, targetLeaf],
        SplitDirection.right || SplitDirection.bottom => [targetLeaf, newLeaf],
      };
      return SplitBranch(axis, children);
    }
    final branch = node as SplitBranch;
    return SplitBranch(branch.axis, [
      for (final child in branch.children)
        insertSplit(child, targetSessionId, newSessionId, direction),
    ]);
  }

  SplitNode replaceSessionIds(
    SplitNode node,
    Map<String, String> replacements,
  ) {
    if (node is SplitLeaf) {
      return SplitLeaf(replacements[node.sessionId] ?? node.sessionId);
    }
    final branch = node as SplitBranch;
    return SplitBranch(branch.axis, [
      for (final child in branch.children)
        replaceSessionIds(child, replacements),
    ]);
  }
}
