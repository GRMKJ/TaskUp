import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskup/config/oauth_config.dart';
import 'package:uuid/uuid.dart';

import 'home_page.dart';
import 'services/api_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final ApiService _api = ApiService();

  late final GoogleSignIn _googleAuth;

  bool isRegisterMode = false;
  bool _isLoading = false;
  String? _googleDebugStatus;

  @override
  void initState() {
    super.initState();

    final platformClientId = kIsWeb
        ? kGoogleWebClientId
        : (kDebugMode ? kGoogleAndroidDebugClientId : kGoogleAndroidClientId);

    _googleAuth = GoogleSignIn(
      clientId: platformClientId,
      serverClientId: kGoogleBackendClientId,
    );

    if (kDebugMode && !kIsWeb) {
      _googleDebugStatus = 'Android clientId activo: $platformClientId';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loginOrRegister() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final displayName = _displayNameController.text.trim();
    

    if (email.isEmpty || password.isEmpty || (isRegisterMode && displayName.isEmpty)) {
      _showMessage('Completa todos los campos');
      return;
    }

    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> tokens;

      if (isRegisterMode) {
        tokens = await _api.register(
          email: email,
          password: password,
          displayName: displayName,
        );
      } else {
        tokens = await _api.login(
          email: email,
          password: password,
        );
      }

      await _persistSession(tokens, email);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } on ApiException catch (err) {
      _showMessage(err.message);
    } catch (_) {
      _showMessage('No se pudo conectar con el servidor');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

Future<void> _loginWithGoogle() async {
  if (_isLoading) return;
  setState(() => _isLoading = true);

  try {
    debugPrint('🔥 Iniciando flujo de Google Sign-In');

    final googleUser = await _googleAuth.signIn();
    debugPrint('👉 googleUser: $googleUser');

    if (googleUser == null) {
      _showMessage("Inicio cancelado");
      debugPrint('⚠️ Login cancelado por usuario');
      return;
    }

    final googleAuth = await googleUser.authentication;
    debugPrint('🔑 googleAuth.idToken: ${googleAuth.idToken}');
    debugPrint('🔑 googleAuth.accessToken: ${googleAuth.accessToken}');

    String? tokenToSend;

    if (kIsWeb) {
      // En web necesitamos idToken
      tokenToSend = googleAuth.idToken;
    } else {
      // En Android también usamos idToken (serverClientId configurado en GoogleSignIn)
      tokenToSend = googleAuth.idToken;
    }

    if (tokenToSend == null || tokenToSend.isEmpty) {
      _showMessage("Error obteniendo el token de Google");
      debugPrint('❌ Token nulo o vacío');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final deviceUuid = prefs.getString('deviceUuid');
    debugPrint('📱 deviceUuid: $deviceUuid');

    final tokens = await _api.loginWithGoogle(
      idToken: tokenToSend,
      deviceUuid: deviceUuid,
    );
    debugPrint('✅ Tokens recibidos del backend: $tokens');

    await _persistSession(tokens, googleUser.email);
    debugPrint('💾 Sesión persistida para: ${googleUser.email}');

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );

  } catch (e, s) {
    _showMessage("No se pudo iniciar sesión con Google");
    debugPrint('❌ Error en Google Sign-In: $e');
    debugPrint('📄 Stack trace: $s');
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  Future<void> _persistSession(Map<String, dynamic> tokens, String email) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = tokens['access_token'] as String?;
    final refreshToken = tokens['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw ApiException('Respuesta inesperada del servidor');
    }

    await prefs.setString('accessToken', accessToken);
    await prefs.setString('refreshToken', refreshToken);
    await prefs.setString('userEmail', email);
    await prefs.setBool('loggedIn', true);

    final deviceUuid = await _ensureDeviceUuid(prefs);
    await _safeDeviceRegistration(accessToken, deviceUuid);
  }

  Future<String> _ensureDeviceUuid(SharedPreferences prefs) async {
    final existing = prefs.getString('deviceUuid');
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final newId = const Uuid().v4();
    await prefs.setString('deviceUuid', newId);
    return newId;
  }

  Future<void> _safeDeviceRegistration(String token, String deviceUuid) async {
    final platform = _platformValue();
    try {
      await _api.registerDevice(
        token: token,
        deviceUuid: deviceUuid,
        platform: platform,
        deviceName: 'TaskUp $platform',
        appVersion: '1.0.0',
      );
    } catch (_) {
      // Si falla el registro del dispositivo, no bloqueamos el inicio de sesión.
    }
  }

  String _platformValue() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return 'desktop';
      default:
        return 'web';
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
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ],
          ),
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/icon/icon.png',
                height: 80,
              ),
              const SizedBox(height: 12),
              const Text(
                'TaskUp',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 12),
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
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  border: OutlineInputBorder(),
                ),
              ),
              if (isRegisterMode) ...[
                const SizedBox(height: 15),
                TextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre a mostrar',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
                onPressed: _isLoading ? null : _loginOrRegister,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        isRegisterMode ? 'Registrarse' : 'Ingresar',
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _loginWithGoogle,
                icon: const Icon(Icons.g_mobiledata, color: Color(0xFFDB4437)),
                label: const Text('Continuar con Google'),
              ),
              if (kDebugMode && _googleDebugStatus != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF90CAF9)),
                  ),
                  child: Text(
                    'DEBUG: $_googleDebugStatus',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF0D47A1)),
                  ),
                ),
              ],
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
