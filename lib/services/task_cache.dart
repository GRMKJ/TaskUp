import 'package:flutter/foundation.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:idb_shim/idb_io.dart';
import 'package:path_provider/path_provider.dart';

import '../models/task_model.dart';

class TaskCache {
  TaskCache._();

  static final TaskCache instance = TaskCache._();

  static const _dbName = 'taskup_tasks';
  static const _storeName = 'tasks';

  Future<Database>? _opening;

  Future<Database> _database() {
    _opening ??= _openDb();
    return _opening!;
  }

  Future<Database> _openDb() async {
    final factory = await _resolveFactory();
    final db = await factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (VersionChangeEvent event) {
        final database = event.database;
        if (!database.objectStoreNames.contains(_storeName)) {
          database.createObjectStore(_storeName, keyPath: 'id');
        }
      },
    );
    return db;
  }

  Future<IdbFactory> _resolveFactory() async {
    if (kIsWeb) {
      return idbFactoryBrowser;
    }
    final dir = await getApplicationSupportDirectory();
    return getIdbFactorySembastIo('${dir.path}/taskup_indexed_db');
  }

  Future<List<TaskModel>> readAll() async {
    try {
      final db = await _database();
      final txn = db.transaction(_storeName, idbModeReadOnly);
      final store = txn.objectStore(_storeName);
      final records = await store.getAll();
      await txn.completed;
        return records
          .whereType<Map>()
          .map((raw) => TaskModel.fromJson(Map<String, dynamic>.from(raw)))
          .toList()
        ..sort((a, b) => b.id.compareTo(a.id));
    } catch (err) {
      debugPrint('TaskCache.readAll failed: $err');
      return const [];
    }
  }

  Future<TaskModel?> read(int id) async {
    try {
      final db = await _database();
      final txn = db.transaction(_storeName, idbModeReadOnly);
      final record = await txn.objectStore(_storeName).getObject(id);
      await txn.completed;
      if (record is Map) {
        return TaskModel.fromJson(Map<String, dynamic>.from(record));
      }
      return null;
    } catch (err) {
      debugPrint('TaskCache.read failed: $err');
      return null;
    }
  }

  Future<void> replaceAll(List<TaskModel> tasks) async {
    try {
      final db = await _database();
      final txn = db.transaction(_storeName, idbModeReadWrite);
      final store = txn.objectStore(_storeName);
      await store.clear();
      for (final task in tasks) {
        await store.put(task.toJson());
      }
      await txn.completed;
    } catch (err) {
      debugPrint('TaskCache.replaceAll failed: $err');
    }
  }

  Future<void> upsert(TaskModel task) async {
    try {
      final db = await _database();
      final txn = db.transaction(_storeName, idbModeReadWrite);
      await txn.objectStore(_storeName).put(task.toJson());
      await txn.completed;
    } catch (err) {
      debugPrint('TaskCache.upsert failed: $err');
    }
  }

  Future<void> remove(int id) async {
    try {
      final db = await _database();
      final txn = db.transaction(_storeName, idbModeReadWrite);
      await txn.objectStore(_storeName).delete(id);
      await txn.completed;
    } catch (err) {
      debugPrint('TaskCache.remove failed: $err');
    }
  }

  Future<void> clear() async {
    try {
      final db = await _database();
      final txn = db.transaction(_storeName, idbModeReadWrite);
      await txn.objectStore(_storeName).clear();
      await txn.completed;
    } catch (err) {
      debugPrint('TaskCache.clear failed: $err');
    }
  }
}
