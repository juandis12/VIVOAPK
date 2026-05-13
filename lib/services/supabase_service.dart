import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vivoweb_flutter/models/profile_model.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  // Credenciales públicas protegidas por Row Level Security (RLS) en Supabase
  static const String supabaseUrl = 'https://esnrgviozjfjgnbcrduz.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVzbnJndmlvempmamduYmNyZHV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzOTUyNzYsImV4cCI6MjA4OTk3MTI3Nn0._a6k7-91c8u8YOKLW53Y-gza22qAclH1nTGM4hL_wRM';

  Future<void> initialize() async {
    try {
      // debugPrint solo actúa en modo debug — seguro en producción
      debugPrint('[Supabase] Inicializando cliente...');
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      debugPrint('[Supabase] ✅ Cliente inicializado correctamente.');
    } catch (e) {
      debugPrint('[Supabase] ❌ Error de inicialización: $e');
      rethrow;
    }
  }

  SupabaseClient get client => Supabase.instance.client;

  // Métodos de autenticación
  Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp(String email, String password) async {
    return await client.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // Métodos de perfiles
  Future<List<ProfileModel>> getProfiles(String userId) async {
    final response = await client
        .from('vivotv_profiles')
        .select()
        .eq('user_id', userId)
        .order('created_at');
    
    return (response as List).map((json) => ProfileModel.fromJson(json)).toList();
  }

  /// Obtiene perfiles y el tiempo del servidor en una sola llamada (RPC)
  Future<Map<String, dynamic>> getProfilesSynced() async {
    final response = await client.rpc('vivotv_get_profiles_synced');
    
    final List<dynamic> profilesJson = response['profiles'] ?? [];
    final profiles = profilesJson.map((json) => ProfileModel.fromJson(json)).toList();
    final serverNow = DateTime.parse(response['server_now']);

    return {
      'profiles': profiles,
      'server_now': serverNow,
    };
  }

  Future<void> releaseSession(String profileId) async {
    // 1. Liberar en base de datos (RPC)
    await client.rpc('vivotv_release_session', params: {'pid': profileId});

    // 2. Notificar vía Realtime (Broadcast) para cierre inmediato en otros dispositivos
    final channel = client.channel('kickout-$profileId');
    channel.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          (channel as dynamic).send(
            type: 'broadcast',
            event: 'FORCE_EXIT',
            payload: {'profileId': profileId},
          );
        } catch (e) {
          debugPrint('[Realtime] Error enviando expulsión: $e');
        }
        // Desuscribirse después de enviar para limpiar
        client.removeChannel(channel);
      }
    });
  }

  Future<void> upsertProfile(ProfileModel profile) async {
    await client.from('vivotv_profiles').upsert(profile.toJson());
  }

  Future<void> deleteProfile(String profileId) async {
    await client.from('vivotv_profiles').delete().eq('id', profileId);
  }

  Future<void> updateProfileFcmToken(String profileId, String? token) async {
    try {
      await client
          .from('vivotv_profiles')
          .update({'fcm_token': token})
          .eq('id', profileId);
      debugPrint('[Push] ✅ Token FCM registrado exitosamente.');
    } catch (e) {
      debugPrint('[Push] Error registrando token FCM: $e');
    }
  }
}
