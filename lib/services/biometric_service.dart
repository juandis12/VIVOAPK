import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Autentícate para acceder al perfil'}) async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true, // Forzamos biometría para que el PIN sea el respaldo manual de la app
        ),
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'VivoTv Seguridad',
            biometricHint: 'Usa tu huella para entrar',
            cancelButton: 'Cancelar',
          ),
        ],
      );
      return didAuthenticate;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
