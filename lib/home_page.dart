import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'login_page.dart';
import 'models/task_model.dart';
import 'services/api_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();

  List<TaskModel> tasks = [];
  List<TaskModel> filteredTasks = [];

  final TextEditingController searchController = TextEditingController();
  final TextEditingController newTaskController = TextEditingController();
  TaskPriority selectedPriority = TaskPriority.medium;

  bool _isLoading = true;
  bool _mutating = false;
  String? _accessToken;
  String? _deviceUuid;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _initApp();
    searchController.addListener(_filterTasks);
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken');
    final email = prefs.getString('userEmail');
    if (token == null || token.isEmpty || email == null || email.isEmpty) {
      _redirectToLogin();
      return;
    }

    var deviceUuid = prefs.getString('deviceUuid');
    if (deviceUuid == null || deviceUuid.isEmpty) {
      deviceUuid = const Uuid().v4();
      await prefs.setString('deviceUuid', deviceUuid);
    }

    setState(() {
      _accessToken = token;
      _deviceUuid = deviceUuid;
      _userEmail = email;
    });

    await _hydrateFromCache();
    await _loadTasks(showLoading: tasks.isEmpty);
  }

  Future<void> _hydrateFromCache() async {
    if (_userEmail == null) return;
    final cached = await _api.cachedTasks();
    if (!mounted) return;
    setState(() {
      tasks = cached;
      filteredTasks = List.from(cached);
      _isLoading = false;
    });
  }

  Future<void> _loadTasks({bool showLoading = true}) async {
    if (_accessToken == null || _userEmail == null) return;
    if (showLoading) setState(() => _isLoading = true);
    try {
      await _api.flushPendingChanges(token: _accessToken!, deviceUuid: _deviceUuid);
      final remoteTasks = await _api.fetchTasks(token: _accessToken!);
      if (!mounted) return;
      setState(() {
        tasks = remoteTasks;
        filteredTasks = List.from(remoteTasks);
      });
    } on ApiException catch (err) {
      _showSnack(err.message);
    } catch (_) {
      _showSnack('No se pudieron cargar las tareas');
    } finally {
      if (mounted && showLoading) setState(() => _isLoading = false);
    }
  }

  void _filterTasks() {
    final query = searchController.text.toLowerCase();
    setState(() {
      filteredTasks = tasks
          .where((task) => task.title.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _addTask() async {
    if (_accessToken == null || _mutating) return;
    final title = newTaskController.text.trim();
    if (title.isEmpty) return;

    setState(() => _mutating = true);
    try {
      final newTask = await _api.createTask(
        token: _accessToken!,
        title: title,
        priority: selectedPriority,
        deviceUuid: _deviceUuid,
      );
      setState(() {
        tasks = [newTask, ...tasks];
        filteredTasks = List.from(tasks);
        newTaskController.clear();
        selectedPriority = TaskPriority.medium;
      });
      _maybeNotifyPending(
        newTask,
        inlineMessage:
            'Sin conexión en este momento. La tarea se sincronizará automáticamente.',
      );
    } on ApiException catch (err) {
      _showSnack(err.message);
    } catch (_) {
      _showSnack('No se pudo crear la tarea');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    if (_accessToken == null || _mutating) return;
    setState(() => _mutating = true);
    try {
      final queued = await _api.deleteTask(
        token: _accessToken!,
        taskId: task.id,
        deviceUuid: _deviceUuid,
      );
      setState(() {
        tasks.removeWhere((t) => t.id == task.id);
        filteredTasks = List.from(tasks);
      });
      if (queued) {
        _showSnack(
          'Sin conexión. La eliminación se aplicará cuando vuelvas a estar online.',
        );
      }
    } on ApiException catch (err) {
      _showSnack(err.message);
    } catch (_) {
      _showSnack('No se pudo eliminar la tarea');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _toggleComplete(TaskModel task) async {
    if (_accessToken == null || _mutating) return;
    setState(() => _mutating = true);
    try {
      final updated = await _api.updateTask(
        token: _accessToken!,
        taskId: task.id,
        payload: {'completed': !task.completed},
        deviceUuid: _deviceUuid,
        baseTask: task,
      );
      setState(() {
        tasks = tasks.map((t) => t.id == task.id ? updated : t).toList();
        filteredTasks = tasks
            .where((t) => t.title
                .toLowerCase()
                .contains(searchController.text.toLowerCase()))
            .toList();
      });
      _maybeNotifyPending(
        updated,
        inlineMessage:
            'Sin conexión. Guardamos tus cambios y se sincronizarán automáticamente.',
      );
    } on ApiException catch (err) {
      _showSnack(err.message);
    } catch (_) {
      _showSnack('No se pudo actualizar la tarea');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Color _priorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return Colors.redAccent;
      case TaskPriority.medium:
        return Colors.orangeAccent;
      case TaskPriority.low:
        return Colors.green;
    }
  }

  String _priorityLabel(TaskPriority priority) => priority.displayLabel;

  String _priorityEmoji(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return '🚨';
      case TaskPriority.medium:
        return '⚖️';
      case TaskPriority.low:
        return '🍃';
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
    await prefs.remove('loggedIn');
    await _api.clearCache();

    if (!mounted) return;
    _redirectToLogin();
  }

  void _redirectToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _maybeNotifyPending(TaskModel task, {required String inlineMessage}) {
    if (task.pendingSync || task.id.isNegative) {
      _showSnack(inlineMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text(
          'TaskUp 🧠',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF5A67D8),
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _isLoading ? null : () => _loadTasks(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 16),
                  _buildComposer(),
                  const SizedBox(height: 20),
                  Expanded(child: _buildTaskList()),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: searchController,
        decoration: const InputDecoration(
          hintText: 'Buscar tarea...',
          prefixIcon: Icon(Icons.search, color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: newTaskController,
                decoration: const InputDecoration(
                  hintText: 'Nueva tarea...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: DropdownButton<TaskPriority>(
                value: selectedPriority,
                items: TaskPriority.values
                    .map(
                      (priority) => DropdownMenuItem(
                        value: priority,
                        child: Text('${priority.displayLabel} ${_priorityEmoji(priority)}'),
                      ),
                    )
                    .toList(),
                onChanged: _mutating
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            selectedPriority = value;
                          });
                        }
                      },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue),
              onPressed: _mutating ? null : _addTask,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    if (filteredTasks.isEmpty) {
      return const Center(
        child: Text(
          'No hay tareas por ahora 😴',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredTasks.length,
      itemBuilder: (context, index) {
        final task = filteredTasks[index];
        final priorityLabel = _priorityLabel(task.priority);
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            leading: GestureDetector(
              onTap: _mutating ? null : () => _toggleComplete(task),
              child: Icon(
                task.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                color: task.completed ? Colors.green : Colors.grey,
                size: 28,
              ),
            ),
            title: Text(
              task.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                decoration: task.completed ? TextDecoration.lineThrough : TextDecoration.none,
                color: task.completed ? Colors.grey : Colors.black87,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Prioridad: $priorityLabel',
                  style: TextStyle(
                    color: _priorityColor(task.priority),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (task.pendingSync || task.id.isNegative)
                  const Text(
                    'Pendiente de sincronizar',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _mutating ? null : () => _deleteTask(task),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    newTaskController.dispose();
    super.dispose();
  }
}
