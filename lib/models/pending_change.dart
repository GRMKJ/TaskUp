import 'dart:convert';

import 'task_model.dart';

enum PendingChangeType { create, update, delete }

class PendingTaskChange {
  const PendingTaskChange({
    required this.id,
    required this.type,
    this.taskId,
    this.tempId,
    this.task,
    this.payload,
    required this.createdAt,
  });

  final String id;
  final PendingChangeType type;
  final int? taskId;
  final int? tempId;
  final Map<String, dynamic>? task;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;

  factory PendingTaskChange.fromJson(Map<String, dynamic> json) {
    return PendingTaskChange(
      id: json['id'] as String,
      type: PendingChangeType.values.firstWhere(
        (value) => value.name == json['type'],
      ),
      taskId: json['taskId'] as int?,
      tempId: json['tempId'] as int?,
      task: (json['task'] as Map<dynamic, dynamic>?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      payload: (json['payload'] as Map<dynamic, dynamic>?)?.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'taskId': taskId,
      'tempId': tempId,
      'task': task,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  PendingTaskChange copyWith({
    String? id,
    PendingChangeType? type,
    int? taskId,
    int? tempId,
    Map<String, dynamic>? task,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
  }) {
    return PendingTaskChange(
      id: id ?? this.id,
      type: type ?? this.type,
      taskId: taskId ?? this.taskId,
      tempId: tempId ?? this.tempId,
      task: task ?? this.task,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static List<PendingTaskChange> decodeList(List<String> raw) {
    return raw
        .map((entry) => PendingTaskChange.fromJson(
              jsonDecode(entry) as Map<String, dynamic>,
            ))
        .toList();
  }

  static List<String> encodeList(List<PendingTaskChange> changes) {
    return changes.map((change) => jsonEncode(change.toJson())).toList();
  }

  TaskModel? tryBuildTask() {
    final snapshot = task;
    if (snapshot == null) return null;
    return TaskModel.fromJson(Map<String, dynamic>.from(snapshot));
  }
}
