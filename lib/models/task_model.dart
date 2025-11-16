enum TaskPriority { low, medium, high }

extension TaskPriorityX on TaskPriority {
  String get apiValue => name;

  String get displayLabel {
    switch (this) {
      case TaskPriority.high:
        return 'Alta';
      case TaskPriority.medium:
        return 'Media';
      case TaskPriority.low:
        return 'Baja';
    }
  }

  static TaskPriority fromApi(String? value) {
    switch (value) {
      case 'high':
        return TaskPriority.high;
      case 'low':
        return TaskPriority.low;
      case 'medium':
      default:
        return TaskPriority.medium;
    }
  }
}

class TaskModel {
  final int id;
  final String title;
  final TaskPriority priority;
  final bool completed;
  final bool archived;
  final String? description;
  final DateTime? dueAt;
  final bool pendingSync;

  const TaskModel({
    required this.id,
    required this.title,
    required this.priority,
    required this.completed,
    required this.archived,
    this.description,
    this.dueAt,
    this.pendingSync = false,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDue(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw);
      }
      return null;
    }

    return TaskModel(
      id: json['id'] as int,
      title: json['title'] as String,
      priority: TaskPriorityX.fromApi(json['priority'] as String?),
      completed: json['completed'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
      description: json['description'] as String?,
      dueAt: parseDue(json['due_at'] ?? json['dueAt']),
      pendingSync: json['pendingSync'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'priority': priority.apiValue,
      'completed': completed,
      'archived': archived,
      'description': description,
      'due_at': dueAt?.toIso8601String(),
      'pendingSync': pendingSync,
    };
  }

  TaskModel copyWith({
    int? id,
    String? title,
    TaskPriority? priority,
    bool? completed,
    bool? archived,
    String? description,
    DateTime? dueAt,
    bool? pendingSync,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      archived: archived ?? this.archived,
      description: description ?? this.description,
      dueAt: dueAt ?? this.dueAt,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
}

extension TaskModelPatch on TaskModel {
  TaskModel applyPatch(Map<String, dynamic> payload) {
    TaskPriority? patchedPriority;
    final priorityValue = payload['priority'];
    if (priorityValue is String) {
      patchedPriority = TaskPriorityX.fromApi(priorityValue);
    } else if (priorityValue is TaskPriority) {
      patchedPriority = priorityValue;
    }

    return copyWith(
      title: payload['title'] as String?,
      description: payload['description'] as String?,
      completed: payload['completed'] as bool?,
      archived: payload['archived'] as bool?,
      dueAt: _parseDue(payload['due_at']),
      priority: patchedPriority,
      pendingSync: payload['pendingSync'] as bool?,
    );
  }

  bool get isLocalOnly => id.isNegative;
}

DateTime? _parseDue(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw);
  }
  return null;
}
