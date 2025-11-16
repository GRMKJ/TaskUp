import 'package:flutter/material.dart';
import 'services/indexeddb_service.dart';
import 'login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ------------------- MODELO DE TAREA -------------------
class Task {
  String title;
  String priority;
  bool completed;

  Task({
    required this.title,
    required this.priority,
    this.completed = false,
  });
}

// ------------------- HOME PAGE -------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _dbService = IndexedDBService(); // 💾 Servicio IndexedDB

  List<Task> tasks = [];
  List<Task> filteredTasks = [];

  final TextEditingController searchController = TextEditingController();
  final TextEditingController newTaskController = TextEditingController();
  String selectedPriority = 'Media';

  @override
  void initState() {
    super.initState();
    _initApp(); // 🔹 Inicializa base de datos
    searchController.addListener(_filterTasks);
  }

  // 🧠 Inicialización y carga desde IndexedDB
  Future<void> _initApp() async {
    await _dbService.initDB();
    final savedTasks = await _dbService.loadTasks();
    if (savedTasks.isNotEmpty) {
      setState(() {
        tasks = savedTasks
            .map((t) => Task(
                  title: t['title'],
                  priority: t['priority'],
                  completed: t['completed'] ?? false,
                ))
            .toList();
        filteredTasks = List.from(tasks);
      });
    } else {
      setState(() {
        tasks = [
          Task(title: 'Estudiar Flutter', priority: 'Alta'),
          Task(title: 'Hacer ejercicio', priority: 'Media'),
          Task(title: 'Leer 20 min', priority: 'Baja'),
        ];
        filteredTasks = List.from(tasks);
      });
      _saveToDB();
    }
  }

  // 🔍 Filtro
  void _filterTasks() {
    final query = searchController.text.toLowerCase();
    setState(() {
      filteredTasks =
          tasks.where((task) => task.title.toLowerCase().contains(query)).toList();
    });
  }

  // ➕ Agregar tarea
  void _addTask() {
    final title = newTaskController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      tasks.add(Task(title: title, priority: selectedPriority));
      filteredTasks = List.from(tasks);
      newTaskController.clear();
      selectedPriority = 'Media';
    });

    _saveToDB();
  }

  // 🗑️ Eliminar tarea
  void _deleteTask(Task task) {
    setState(() {
      tasks.remove(task);
      filteredTasks = List.from(tasks);
    });

    _saveToDB();
  }

  // ✅ Completar tarea
  void _toggleComplete(Task task) {
    setState(() {
      task.completed = !task.completed;
    });

    _saveToDB();
  }

  // 💾 Guardar tareas actuales en IndexedDB
  void _saveToDB() {
    _dbService.saveTasks(
      tasks
          .map((t) => {
                'title': t.title,
                'priority': t.priority,
                'completed': t.completed,
              })
          .toList(),
    );
  }

  // 🎨 Color por prioridad
  Color _priorityColor(String priority) {
    switch (priority) {
      case 'Alta':
        return Colors.redAccent;
      case 'Media':
        return Colors.orangeAccent;
      case 'Baja':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // 🔒 Cerrar sesión
  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
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
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 🔍 Buscador
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
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
            ),
            const SizedBox(height: 16),

            // 📝 Nueva tarea + prioridad
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
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
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: DropdownButton<String>(
                        value: selectedPriority,
                        items: const [
                          DropdownMenuItem(value: 'Alta', child: Text('Alta 🚨')),
                          DropdownMenuItem(value: 'Media', child: Text('Media ⚖️')),
                          DropdownMenuItem(value: 'Baja', child: Text('Baja 🍃')),
                        ],
                        onChanged: (value) {
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
                      onPressed: _addTask,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 📋 Lista de tareas
            Expanded(
              child: filteredTasks.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay tareas por ahora 😴',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredTasks.length,
                      itemBuilder: (context, index) {
                        final task = filteredTasks[index];
                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            leading: GestureDetector(
                              onTap: () => _toggleComplete(task),
                              child: Icon(
                                task.completed
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color:
                                    task.completed ? Colors.green : Colors.grey,
                                size: 28,
                              ),
                            ),
                            title: Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                decoration: task.completed
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                color: task.completed
                                    ? Colors.grey
                                    : Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              'Prioridad: ${task.priority}',
                              style: TextStyle(
                                color: _priorityColor(task.priority),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () => _deleteTask(task),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    newTaskController.dispose();
    super.dispose();
  }
}
