import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:vivoweb_flutter/services/supabase_service.dart';
import 'package:vivoweb_flutter/services/session_service.dart';

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final SupabaseService _supabaseService = SupabaseService();
  final SessionService _sessionService = SessionService();

  Future<void> initialize() async {
    try {
      // Nota: Requiere google-services.json en android/app/ para funcionar
      await Firebase.initializeApp();
      
      // Solicitar permisos (iOS/Android 13+)
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('[Push] Permisos concedidos.');
        _getTokenAndRegister();
      }

      // Manejo de mensajes en primer plano
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[Push] Mensaje recibido en primer plano: ${message.notification?.title}');
        // Aquí podrías mostrar un banner local (ej. overlay)
      });

      // Manejo de clicks en notificaciones (app abierta o en background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[Push] El usuario hizo clic en la notificación: ${message.data}');
        // Lógica de navegación profunda (Deep Linking) basada en la data
      });

    } catch (e) {
      debugPrint('[Push] Error inicializando Firebase: $e');
      debugPrint('[Push] Asegúrate de haber agregado google-services.json en android/app/');
    }
  }

  Future<void> _getTokenAndRegister() async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        debugPrint('[Push] Token FCM obtenido: $token');
        _registerTokenInSupabase(token);
      }

      // Escuchar cambios en el token
      _fcm.onTokenRefresh.listen(_registerTokenInSupabase);
    } catch (e) {
      debugPrint('[Push] Error obteniendo token: $e');
    }
  }

  Future<void> _registerTokenInSupabase(String token) async {
    final profile = _sessionService.currentProfile;
    if (profile != null) {
      debugPrint('[Push] Registrando token para el perfil: ${profile.id}');
      await _supabaseService.updateProfileFcmToken(profile.id, token);
    } else {
      debugPrint('[Push] No hay perfil activo para registrar el token aún.');
    }
  }
  
  // Método para sincronizar cuando se cambia de perfil
  void syncTokenWithCurrentProfile() {
    _fcm.getToken().then((token) {
      if (token != null) _registerTokenInSupabase(token);
    });
  }
}

// Handler para mensajes en segundo plano (DEBE ser una función global)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[Push] Manejando mensaje en segundo plano: ${message.messageId}');
}
