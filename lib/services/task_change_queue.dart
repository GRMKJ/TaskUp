import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/pending_change.dart';
import '../models/task_model.dart';

class TaskChangeQueue {
  TaskChangeQueue._();

  static final TaskChangeQueue instance = TaskChangeQueue._();

  static const _storageKey = 'taskup.pendingChanges';
  final Uuid _uuid = const Uuid();

  Future<List<PendingTaskChange>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? <String>[];
    return PendingTaskChange.decodeList(raw);
  }

  Future<void> _write(List<PendingTaskChange> changes) async {
    changes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, PendingTaskChange.encodeList(changes));
  }

  Future<List<PendingTaskChange>> all() => _read();

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<void> enqueueCreate(TaskModel task) async {
    final changes = await _read();
    changes.removeWhere((change) =>
        change.type == PendingChangeType.create && change.tempId == task.id);
    changes.add(PendingTaskChange(
      id: _uuid.v4(),
      type: PendingChangeType.create,
      tempId: task.id,
      task: task.copyWith(pendingSync: true).toJson(),
      createdAt: DateTime.now(),
    ));
    await _write(changes);
  }

  Future<void> updateDraft(TaskModel task) async {
    final changes = await _read();
    final index = changes.indexWhere((change) =>
        change.type == PendingChangeType.create && change.tempId == task.id);
    if (index == -1) return;
    changes[index] = changes[index].copyWith(task: task.toJson());
    await _write(changes);
  }

  Future<void> removeDraft(int tempId) async {
    final changes = await _read();
    changes.removeWhere((change) =>
        change.type == PendingChangeType.create && change.tempId == tempId);
    await _write(changes);
  }

  Future<void> enqueueUpdate(int taskId, Map<String, dynamic> payload) async {
    final changes = await _read();
    final draftIndex = changes.indexWhere((change) =>
        change.type == PendingChangeType.create && change.tempId == taskId);
    if (draftIndex != -1) {
      final draftTask = changes[draftIndex].tryBuildTask();
      if (draftTask != null) {
        changes[draftIndex] = changes[draftIndex].copyWith(
          task: draftTask.applyPatch(payload).toJson(),
        );
      }
      await _write(changes);
      return;
    }

    final updateIndex = changes.indexWhere((change) =>
        change.type == PendingChangeType.update && change.taskId == taskId);
    if (updateIndex != -1) {
      final existingPayload = Map<String, dynamic>.from(
        changes[updateIndex].payload ?? <String, dynamic>{},
      );
      existingPayload.addAll(payload);
      changes[updateIndex] =
          changes[updateIndex].copyWith(payload: existingPayload);
    } else {
      changes.add(PendingTaskChange(
        id: _uuid.v4(),
        type: PendingChangeType.update,
        taskId: taskId,
        payload: Map<String, dynamic>.from(payload),
        createdAt: DateTime.now(),
      ));
    }
    await _write(changes);
  }

  Future<void> enqueueDelete(int taskId) async {
    final changes = await _read();
    final draftIndex = changes.indexWhere((change) =>
        change.type == PendingChangeType.create && change.tempId == taskId);
    if (draftIndex != -1) {
      changes.removeAt(draftIndex);
      await _write(changes);
      return;
    }

    changes.removeWhere((change) =>
        change.type == PendingChangeType.update && change.taskId == taskId);
    changes.removeWhere((change) =>
        change.type == PendingChangeType.delete && change.taskId == taskId);

    changes.add(PendingTaskChange(
      id: _uuid.v4(),
      type: PendingChangeType.delete,
      taskId: taskId,
      createdAt: DateTime.now(),
    ));
    await _write(changes);
  }

  Future<void> removeChange(String changeId) async {
    final changes = await _read();
    changes.removeWhere((change) => change.id == changeId);
    await _write(changes);
  }

  Future<void> retargetTempId(int from, int to) async {
    final changes = await _read();
    bool mutated = false;
    for (var i = 0; i < changes.length; i++) {
      final change = changes[i];
      if (change.type == PendingChangeType.update && change.taskId == from) {
        changes[i] = change.copyWith(taskId: to);
        mutated = true;
      }
      if (change.type == PendingChangeType.delete && change.taskId == from) {
        changes[i] = change.copyWith(taskId: to);
        mutated = true;
      }
    }
    if (mutated) {
      await _write(changes);
    }
  }

  Future<List<TaskModel>> pendingDrafts() async {
    final changes = await _read();
    return changes
        .where((change) => change.type == PendingChangeType.create)
        .map((change) => change.tryBuildTask())
        .whereType<TaskModel>()
        .toList();
  }
}
