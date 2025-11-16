import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pending_change.dart';
import '../models/task_model.dart';
import 'task_cache.dart';
import 'task_change_queue.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  ApiService({http.Client? client, TaskCache? cache, TaskChangeQueue? queue})
      : _client = client ?? http.Client(),
        _cache = cache ?? TaskCache.instance,
        _queue = queue ?? TaskChangeQueue.instance;

  final http.Client _client;
  final TaskCache _cache;
  final TaskChangeQueue _queue;

  static const String baseUrl = 'http://127.0.0.1:8000';

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> _baseHeaders({String? token, String? deviceUuid}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (deviceUuid != null && deviceUuid.isNotEmpty) {
      headers['X-Device-UUID'] = deviceUuid;
    }
    return headers;
  }

  Future<Map<String, dynamic>> _processResponse(http.Response response) async {
    final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return (data as Map<String, dynamic>?) ?? <String, dynamic>{};
    }
    throw ApiException(
      data is Map<String, dynamic> && data['detail'] != null
          ? data['detail'].toString()
          : 'Unexpected error (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Future<Map<String, dynamic>> login({required String email, required String password}) async {
    final response = await _client.post(
      _uri('/auth/login'),
      headers: _baseHeaders(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _processResponse(response);
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _client.post(
      _uri('/auth/register'),
      headers: _baseHeaders(),
      body: jsonEncode({'email': email, 'password': password, 'display_name': displayName}),
    );
    return _processResponse(response);
  }

  Future<void> registerDevice({
    required String token,
    required String deviceUuid,
    required String platform,
    String? deviceName,
    String? appVersion,
  }) async {
    final response = await _client.post(
      _uri('/devices'),
      headers: _baseHeaders(token: token),
      body: jsonEncode({
        'device_uuid': deviceUuid,
        'device_name': deviceName,
        'platform': platform,
        'app_version': appVersion,
      }),
    );
    await _processResponse(response);
  }

  Future<List<TaskModel>> fetchTasks({
    required String token,
    bool onlyActive = true,
  }) async {
    try {
      final response = await _client.get(
        _uri('/tasks', {'limit': '250', 'only_active': onlyActive.toString()}),
        headers: _baseHeaders(token: token),
      );
      final data = await _processResponse(response);
      final items = data['items'] as List<dynamic>? ?? <dynamic>[];
      final tasks = items
          .map((json) => TaskModel.fromJson(json as Map<String, dynamic>))
          .where((task) => !task.archived)
          .map((task) => task.copyWith(pendingSync: false))
          .toList();
      final drafts = await _queue.pendingDrafts();
      final merged = [...drafts, ...tasks];
      await _cache.replaceAll(merged);
      return merged;
    } catch (err) {
      if (_looksOffline(err)) {
        return _cache.readAll();
      }
      rethrow;
    }
  }

  Future<TaskModel> createTask({
    required String token,
    required String title,
    required TaskPriority priority,
    String? description,
    String? deviceUuid,
  }) async {
    try {
      final response = await _client.post(
        _uri('/tasks'),
        headers: _baseHeaders(token: token, deviceUuid: deviceUuid),
        body: jsonEncode({
          'title': title,
          'priority': priority.apiValue,
          if (description != null && description.isNotEmpty) 'description': description,
        }),
      );
      final data = await _processResponse(response);
      final created = TaskModel.fromJson(data);
      await _cache.upsert(created);
      return created;
    } catch (err) {
      if (_looksOffline(err)) {
        final tempId = _nextTempId();
        final localTask = TaskModel(
          id: tempId,
          title: title,
          priority: priority,
          completed: false,
          archived: false,
          description: description,
          pendingSync: true,
        );
        await _cache.upsert(localTask);
        await _queue.enqueueCreate(localTask);
        return localTask;
      }
      rethrow;
    }
  }

  Future<TaskModel> updateTask({
    required String token,
    required int taskId,
    required Map<String, dynamic> payload,
    String? deviceUuid,
    TaskModel? baseTask,
  }) async {
    final baseline = baseTask ?? await _cache.read(taskId);
    if (baseline == null) {
      throw ApiException('No se encontró la tarea local para actualizar');
    }
    final requestBody = _composeUpdatePayload(baseline, payload);
    try {
      final response = await _client.put(
        _uri('/tasks/$taskId'),
        headers: _baseHeaders(token: token, deviceUuid: deviceUuid),
        body: jsonEncode(requestBody),
      );
      final data = await _processResponse(response);
      final updated = TaskModel.fromJson(data);
      await _cache.upsert(updated);
      return updated;
    } catch (err) {
      if (_looksOffline(err)) {
        final updated = baseline.applyPatch(payload).copyWith(pendingSync: true);
        await _cache.upsert(updated);
        await _queue.enqueueUpdate(taskId, requestBody);
        return updated;
      }
      rethrow;
    }
  }

  Future<bool> deleteTask({
    required String token,
    required int taskId,
    String? deviceUuid,
  }) async {
    try {
      final response = await _client.delete(
        _uri('/tasks/$taskId'),
        headers: _baseHeaders(token: token, deviceUuid: deviceUuid),
      );
      await _processResponse(response);
      await _cache.remove(taskId);
      return false;
    } catch (err) {
      if (_looksOffline(err)) {
        await _cache.remove(taskId);
        await _queue.enqueueDelete(taskId);
        return true;
      }
      rethrow;
    }
  }

  Future<void> flushPendingChanges({
    required String token,
    String? deviceUuid,
  }) async {
    final pending = await _queue.all();
    if (pending.isEmpty) return;
    for (final change in pending) {
      try {
        switch (change.type) {
          case PendingChangeType.create:
            final snapshot = Map<String, dynamic>.from(change.task ?? {});
            final payload = _taskCreatePayload(snapshot);
            final response = await _client.post(
              _uri('/tasks'),
              headers: _baseHeaders(token: token, deviceUuid: deviceUuid),
              body: jsonEncode(payload),
            );
            final data = await _processResponse(response);
            final created = TaskModel.fromJson(data);
            if (change.tempId != null) {
              await _cache.remove(change.tempId!);
              await _queue.retargetTempId(change.tempId!, created.id);
            }
            await _cache.upsert(created);
            await _queue.removeChange(change.id);
            break;
          case PendingChangeType.update:
            final response = await _client.put(
              _uri('/tasks/${change.taskId}'),
              headers: _baseHeaders(token: token, deviceUuid: deviceUuid),
              body: jsonEncode(change.payload ?? <String, dynamic>{}),
            );
            final data = await _processResponse(response);
            final updated = TaskModel.fromJson(data);
            await _cache.upsert(updated);
            await _queue.removeChange(change.id);
            break;
          case PendingChangeType.delete:
            final response = await _client.delete(
              _uri('/tasks/${change.taskId}'),
              headers: _baseHeaders(token: token, deviceUuid: deviceUuid),
            );
            await _processResponse(response);
            await _cache.remove(change.taskId!);
            await _queue.removeChange(change.id);
            break;
        }
      } catch (err) {
        if (_looksOffline(err)) {
          break;
        }
        rethrow;
      }
    }
  }

  Future<List<TaskModel>> cachedTasks() => _cache.readAll();

  Future<void> clearCache() => _cache.clear();

  bool _looksOffline(Object err) {
    if (err is ApiException) return false;
    final message = err.toString().toLowerCase();
    return err is http.ClientException || message.contains('socketexception');
  }

  int _nextTempId() => -DateTime.now().microsecondsSinceEpoch;

  Map<String, dynamic> _composeUpdatePayload(
    TaskModel baseline,
    Map<String, dynamic> patch,
  ) {
    final payload = <String, dynamic>{
      'title': baseline.title,
      'description': baseline.description,
      'priority': baseline.priority.apiValue,
      'due_at': baseline.dueAt?.toIso8601String(),
      'completed': baseline.completed,
      'archived': baseline.archived,
    };
    patch.forEach((key, value) {
      payload[key] = value;
    });

    final priorityValue = payload['priority'];
    if (priorityValue is TaskPriority) {
      payload['priority'] = priorityValue.apiValue;
    }

    final dueValue = payload['due_at'];
    if (dueValue is DateTime) {
      payload['due_at'] = dueValue.toIso8601String();
    }

    return payload;
  }

  Map<String, dynamic> _taskCreatePayload(Map<String, dynamic> snapshot) {
    final payload = <String, dynamic>{
      'title': snapshot['title'],
      'priority': snapshot['priority'],
      'description': snapshot['description'],
      'due_at': snapshot['due_at'],
    };

    if (payload['priority'] is TaskPriority) {
      payload['priority'] = (payload['priority'] as TaskPriority).apiValue;
    }
    final dueValue = payload['due_at'];
    if (dueValue is DateTime) {
      payload['due_at'] = dueValue.toIso8601String();
    }
    return payload;
  }
}
