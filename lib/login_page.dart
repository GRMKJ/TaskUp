import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool isRegisterMode = false;

  Future<void> _loginOrRegister() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUser = prefs.getString('user');
    final storedPass = prefs.getString('password');

    final user = _userController.text.trim();
    final pass = _passwordController.text.trim();

    if (isRegisterMode) {
      if (user.isEmpty || pass.isEmpty) {
        _showMessage('Por favor completa todos los campos');
        return;
      }
      await prefs.setString('user', user);
      await prefs.setString('password', pass);
      _showMessage('Registro exitoso 🎉, inicia sesión ahora');
      setState(() => isRegisterMode = false);
    } else {
      if (user == storedUser && pass == storedPass) {
        await prefs.setBool('loggedIn', true);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } else {
        _showMessage('Usuario o contraseña incorrectos ❌');
      }
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8EAF6),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ],
          ),
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isRegisterMode ? 'Crear Cuenta 🧩' : 'Iniciar Sesión 🔐',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3949AB),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C6BC0),
                  minimumSize: const Size(double.infinity, 45),
                ),
                onPressed: _loginOrRegister,
                child: Text(isRegisterMode ? 'Registrarse' : 'Ingresar'),
              ),
              TextButton(
                onPressed: () {
                  setState(() => isRegisterMode = !isRegisterMode);
                },
                child: Text(isRegisterMode
                    ? '¿Ya tienes cuenta? Inicia sesión'
                    : '¿No tienes cuenta? Regístrate'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
