import 'package:flutter/material.dart';
import 'splash_page.dart';

void main() {
  runApp(const TaskUpApp());
}

class TaskUpApp extends StatelessWidget {
  const TaskUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TaskUp',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const SplashPage(),
    );
  }
}
