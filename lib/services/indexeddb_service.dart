import 'dart:async';
import 'package:web/web.dart';

class IndexedDBService {
  Database? _db;

  Future<void> initDB() async {
    if (!IdbFactory.supported) {
      print('IndexedDB no está soportado en este navegador');
      return;
    }

    final dbRequest = window.indexedDB!.open('taskup_db', version: 1,
        onUpgradeNeeded: (e) {
      final db = (e.target as Request).result as Database;
      if (!(db.objectStoreNames?.contains('tasks') ?? false)) {
        db.createObjectStore('tasks', autoIncrement: true);
      }
    });

    _db = await dbRequest;
  }

  Future<void> saveTasks(List<Map<String, dynamic>> tasks) async {
    if (_db == null) return;
    final txn = _db!.transaction('tasks', 'readwrite');
    final store = txn.objectStore('tasks');

    await store.clear(); // Limpia las anteriores
    for (final task in tasks) {
      await store.add(task);
    }

    await txn.completed;
  }

  Future<List<Map<String, dynamic>>> loadTasks() async {
    if (_db == null) return [];
    final txn = _db!.transaction('tasks', 'readonly');
    final store = txn.objectStore('tasks');

    final request = store.getAll(null);
    final completer = Completer<List<Map<String, dynamic>>>();

    request.onSuccess.listen((event) {
      final result = request.result;
      if (result != null && result is List) {
        completer.complete(result.cast<Map<String, dynamic>>());
      } else {
        completer.complete([]);
      }
    });

    request.onError.listen((event) {
      completer.completeError(request.error ?? 'Error al leer IndexedDB');
    });

    return completer.future;
  }
}
