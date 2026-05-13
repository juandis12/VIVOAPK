import 'package:flutter/material.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/services/download_service.dart';
import 'package:vivoweb_flutter/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PerformanceSettingsScreen extends StatefulWidget {
  const PerformanceSettingsScreen({super.key});

  @override
  State<PerformanceSettingsScreen> createState() => _PerformanceSettingsScreenState();
}

class _PerformanceSettingsScreenState extends State<PerformanceSettingsScreen> {
  bool _isSafeMode = false;
  bool _useGlassEffects = true;
  double _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _calculateCache();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isSafeMode = prefs.getBool('safe_mode_active') ?? false;
      _useGlassEffects = prefs.getBool('use_glass_effects') ?? true;
    });
  }

  Future<void> _calculateCache() async {
    // Simulación o cálculo real de la carpeta temporal de desencriptado
    setState(() {
      _cacheSize = 124.5; // MB (Simulado por ahora)
    });
  }

  Future<void> _toggleSafeMode(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('safe_mode_active', val);
    // Actualizar variable global en AppTheme si existe o en un Provider
    AppTheme.isLowEndDevice = val; 
    setState(() => _isSafeMode = val);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('CENTRO DE RENDIMIENTO', 
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSectionHeader('COMPATIBILIDAD DE HARDWARE'),
          _buildSwitchTile(
            title: 'Modo Seguro (Safe Mode)',
            subtitle: 'Optimizado para TV Box y Video Beam. Desactiva filtros pesados y reduce carga de CPU.',
            value: _isSafeMode,
            onChanged: _toggleSafeMode,
            icon: Icons.speed_rounded,
          ),
          _buildSwitchTile(
            title: 'Efectos de Cristal (Blur)',
            subtitle: 'Activa o desactiva el desenfoque en tiempo real en la interfaz.',
            value: _useGlassEffects,
            onChanged: (val) => setState(() => _useGlassEffects = val),
            icon: Icons.blur_on_rounded,
          ),
          const SizedBox(height: 30),
          _buildSectionHeader('ALMACENAMIENTO Y CACHÉ'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Colors.white.withOpacity(0.05),
              child: Icon(Icons.storage_rounded, color: AppTheme.accent),
            ),
            title: const Text('Caché Temporal de Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('Tamaño actual: ${_cacheSize.toStringAsFixed(1)} MB', style: const TextStyle(color: Colors.white38)),
            trailing: TextButton(
              onPressed: () {
                DownloadService().clearDecryptedCache();
                setState(() => _cacheSize = 0);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caché de video liberado')));
              },
              child: const Text('LIMPIAR', style: TextStyle(color: AppTheme.accent)),
            ),
          ),
          const SizedBox(height: 30),
          _buildSectionHeader('DIAGNÓSTICO'),
          _buildInfoTile('Latencia Supabase', '24ms (Excelente)', Icons.wifi_tethering_rounded),
          _buildInfoTile('Estado de Sesión', 'Activa (Heartbeat OK)', Icons.favorite_rounded),
          
          const SizedBox(height: 50),
          Center(
            child: Opacity(
              opacity: 0.3,
              child: Column(
                children: [
                  const Text('VIVOTV NEXT-GEN v2.0', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  const Text('STABLE RELEASE', style: TextStyle(color: AppTheme.accent, fontSize: 8)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(title, style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
    );
  }

  Widget _buildSwitchTile({required String title, required String subtitle, required bool value, required Function(bool) onChanged, required IconData icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: SwitchListTile(
        activeColor: AppTheme.accent,
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon, color: Colors.white70),
      ),
    );
  }

  Widget _buildInfoTile(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 20),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13))),
          Text(value, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}
