import 'dart:async';
import 'package:web/web.dart';

class AuthService {
  late Database _db;

  Future<void> initDB() async {
    final idbFactory = window.indexedDB;
    _db = await idbFactory!.open('taskup_db', version: 2,
        onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains('users')) {
        db.createObjectStore('users', keyPath: 'email');
      }
    });
  }

  Future<void> registerUser(String email, String password) async {
    final txn = _db.transaction('users', 'readwrite');
    final store = txn.objectStore('users');
    await store.put({'email': email, 'password': password});
    await txn.completed;
  }

  Future<bool> loginUser(String email, String password) async {
    final txn = _db.transaction('users', 'readonly');
    final store = txn.objectStore('users');
    final user = await store.getObject(email);
    await txn.completed;
    return user != null && user['password'] == password;
  }

  Future<bool> isLoggedIn() async {
    return window.localStorage.containsKey('loggedUser');
  }

  Future<void> saveSession(String email) async {
    window.localStorage['loggedUser'] = email;
  }

  Future<void> logout() async {
    window.localStorage.remove('loggedUser');
  }

  String? getLoggedUser() {
    return window.localStorage['loggedUser'];
  }
}
