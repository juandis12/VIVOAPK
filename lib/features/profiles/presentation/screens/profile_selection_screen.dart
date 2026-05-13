import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/models/profile_model.dart';
import 'package:vivoweb_flutter/services/supabase_service.dart';
import 'package:vivoweb_flutter/features/profiles/presentation/widgets/pin_pad_widget.dart';
import 'package:vivoweb_flutter/services/session_service.dart';
import 'package:go_router/go_router.dart';
import 'package:vivoweb_flutter/services/biometric_service.dart';
import 'package:vivoweb_flutter/features/profiles/presentation/widgets/profile_edit_dialog.dart';
import 'package:vivoweb_flutter/core/utils/avatar_resolver.dart';
import 'package:uuid/uuid.dart';

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final BiometricService _biometricService = BiometricService();
  
  List<ProfileModel> _profiles = [];
  bool _isLoading = true;
  bool _isManageMode = false;
  bool _showPinPad = false;
  bool _showIntro = false;
  ProfileModel? _introProfile;
  ProfileModel? _selectedProfile;
  final GlobalKey<PinPadWidgetState> _pinPadKey = GlobalKey<PinPadWidgetState>();

  DateTime _serverNow = DateTime.now();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isManageMode && !_showPinPad) {
        _loadProfiles();
      }
    });
  }

  Future<void> _loadProfiles() async {
    try {
      final syncData = await _supabaseService.getProfilesSynced();
      if (mounted) {
        setState(() {
          _profiles = syncData['profiles'];
          _serverNow = syncData['server_now'];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profiles: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onProfileTap(ProfileModel profile) async {
    if (_isManageMode) {
      _editProfile(profile);
      return;
    }

    // 1. Re-verificación de ocupación (Seguridad 10X)
    final syncData = await _supabaseService.getProfilesSynced();
    final freshProfiles = syncData['profiles'] as List<ProfileModel>;
    final freshServerNow = syncData['server_now'] as DateTime;
    
    final dbP = freshProfiles.firstWhere((x) => x.id == profile.id, orElse: () => profile);

    if (dbP.isOccupiedWithServerNow(freshServerNow)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este perfil se acaba de ocupar. Elige otro.'), backgroundColor: AppTheme.error),
        );
      }
      _loadProfiles();
      return;
    }

    if (profile.pin != null) {
      // Intentar biometría primero
      final canBio = await _biometricService.isAvailable();
      if (canBio) {
        final success = await _biometricService.authenticate(
          reason: 'Escanea tu huella para entrar a ${profile.name}',
        );
        if (success) {
          _enterProfile(profile);
          return;
        }
      }

      // Si falla biometría o no disponible, mostrar PIN
      setState(() {
        _selectedProfile = profile;
        _showPinPad = true;
      });
    } else {
      _enterProfile(profile);
    }
  }

  Future<void> _enterProfile(ProfileModel profile) async {
    setState(() {
      _showIntro = true;
      _introProfile = profile;
      _showPinPad = false;
    });

    // setProfile sincroniza con Supabase (cross-device)
    await SessionService().setProfile(profile);

    // Esperar a que la animación cinemática termine (2.2 segundos para paridad con Web)
    await Future.delayed(const Duration(milliseconds: 2200));

    if (mounted) context.go('/dashboard');
  }

  Future<void> _addProfile() async {
    final user = _supabaseService.client.auth.currentUser;
    if (user == null) return;

    final newProfile = await showDialog<ProfileModel>(
      context: context,
      builder: (context) => ProfileEditDialog(userId: user.id),
    );

    if (newProfile != null) {
      setState(() => _isLoading = true);
      try {
        await _supabaseService.upsertProfile(newProfile);
        await _loadProfiles();
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al crear perfil: $e'), backgroundColor: AppTheme.error),
          );
        }
      }
    }
  }

  Future<void> _editProfile(ProfileModel profile) async {
    final updatedProfile = await showDialog<ProfileModel>(
      context: context,
      builder: (context) => ProfileEditDialog(profile: profile, userId: profile.userId),
    );

    if (updatedProfile != null) {
      setState(() => _isLoading = true);
      try {
        await _supabaseService.upsertProfile(updatedProfile);
        await _loadProfiles();
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al actualizar perfil: $e'), backgroundColor: AppTheme.error),
          );
        }
      }
    }
  }

  void _handlePinCompleted(String pin) {
    if (_selectedProfile?.pin == pin) {
      _enterProfile(_selectedProfile!);
    } else {
      _pinPadKey.currentState?.triggerShake();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN incorrecto'), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: AppTheme.backgroundDecoration),
          
          Center(
            child: _isLoading
                ? const CircularProgressIndicator(color: AppTheme.accent)
                : _profiles.isEmpty && !_isManageMode
                    ? _FirstProfileSetup(
                        onCreate: (name) async {
                          final user = _supabaseService.client.auth.currentUser;
                          if (user == null) return;
                          
                          final randomColor = 'color-${(1 + (DateTime.now().millisecond % 4))}';
                          final newProfile = ProfileModel(
                            id: const Uuid().v4(),
                            userId: user.id,
                            name: name,
                            color: randomColor,
                            isKids: false,
                          );
                          
                          setState(() => _isLoading = true);
                          await _supabaseService.upsertProfile(newProfile);
                          await _enterProfile(newProfile);
                        },
                      )
                    : SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isManageMode ? 'Administrar Perfiles' : '¿Quién está viendo?',
                                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                              const SizedBox(height: 60),

                              // Profiles Grid + Add Button
                              Wrap(
                                spacing: 40,
                                runSpacing: 40,
                                alignment: WrapAlignment.center,
                                children: [
                                  ..._profiles.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final p = entry.value;
                                    return _TVFocusWrapper(
                                      autofocus: index == 0,
                                      onTap: () => _onProfileTap(p),
                                      child: _ProfileCard(
                                        profile: p,
                                        serverNow: _serverNow,
                                        isManageMode: _isManageMode,
                                        onTap: () => _onProfileTap(p),
                                        onRelease: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Liberar Perfil'),
                                              content: const Text('¿Deseas liberar este perfil a la fuerza? Se cerrará la sesión en el otro dispositivo.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
                                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('LIBERAR', style: TextStyle(color: Colors.red))),
                                              ],
                                            ),
                                          );
                                          
                                          if (confirm == true) {
                                            await _supabaseService.releaseSession(p.id);
                                            _loadProfiles();
                                          }
                                        },
                                      ),
                                    );
                                  }),
                                  
                                  if (_profiles.length < 4)
                                    _TVFocusWrapper(
                                      onTap: _addProfile,
                                      child: _AddProfileCard(onTap: _addProfile),
                                    ),
                                ],
                              ),

                              const SizedBox(height: 80),

                              OutlinedButton(
                                onPressed: () => setState(() => _isManageMode = !_isManageMode),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: _isManageMode ? AppTheme.accent : AppTheme.textSecondary),
                                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                                ),
                                child: Text(
                                  _isManageMode ? 'LISTO' : 'ADMINISTRAR PERFILES',
                                  style: TextStyle(color: _isManageMode ? AppTheme.accent : AppTheme.textSecondary, letterSpacing: 2),
                                ),
                              ),
                              
                              const SizedBox(height: 20),
                              TextButton(
                                onPressed: () async {
                                  await _supabaseService.signOut();
                                  if (mounted) context.go('/auth');
                                },
                                child: const Text('Cerrar Sesión', style: TextStyle(color: AppTheme.textSecondary)),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),

          if (_showPinPad)
            PinPadWidget(
              key: _pinPadKey,
              title: "Introduce tu código",
              profileName: _selectedProfile?.name,
              onCompleted: _handlePinCompleted,
              onCancel: () => setState(() => _showPinPad = false),
            ),

          if (_showIntro && _introProfile != null)
            _WelcomeIntro(profile: _introProfile!),
        ],
      ),
    );
  }
}

class _AddProfileCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddProfileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 60),
          ),
          const SizedBox(height: 16),
          const Text('Añadir', style: TextStyle(color: AppTheme.textSecondary, fontSize: 18)),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final ProfileModel profile;
  final DateTime serverNow;
  final bool isManageMode;
  final VoidCallback onTap;
  final VoidCallback onRelease;

  const _ProfileCard({
    required this.profile, 
    required this.serverNow,
    required this.isManageMode, 
    required this.onTap,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    final avatarImage = AvatarResolver.resolve(profile.avatarUrl);
    final isOccupied = profile.isOccupiedWithServerNow(serverNow);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4), // Netflix usa bordes muy sutiles
              gradient: avatarImage == null 
                  ? _getGradientForColor(profile.color)
                  : null,
              image: avatarImage != null
                  ? DecorationImage(image: avatarImage, fit: BoxFit.cover)
                  : null,
              border: Border.all(
                color: isManageMode ? Colors.white54 : Colors.transparent, 
                width: 2
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                )
              ],
            ),
            child: Stack(
              children: [
                if (avatarImage == null)
                  Center(
                    child: Text(
                      profile.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 60,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                
                if (profile.isKids)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.yellow,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NIÑOS',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                
                if (isManageMode)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(Icons.edit, color: Colors.white, size: 40),
                    ),
                  ),

                if (isOccupied && !isManageMode)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'EN USO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: onRelease,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              minimumSize: Size.zero,
                            ),
                            child: const Text('LIBERAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Telemetría visual
                if (isOccupied && profile.nowPlaying != null && !isManageMode)
                   Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text('VIENDO AHORA', style: TextStyle(color: Colors.red, fontSize: 8, fontWeight: FontWeight.bold)),
                          Text(
                            profile.nowPlaying?['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            profile.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  LinearGradient _getGradientForColor(String colorKey) {
    switch (colorKey) {
      case 'color-1':
        return const LinearGradient(colors: [Color(0xFFBB86FC), Color(0xFF9D4EDD)]);
      case 'color-2':
        return const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)]);
      case 'color-3':
        return const LinearGradient(colors: [Color(0xFFDB2777), Color(0xFF9D174D)]);
      case 'color-4':
        return const LinearGradient(colors: [Color(0xFF059669), Color(0xFF065F46)]);
      default:
        return const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1E40AF)]);
    }
  }
}

class _FirstProfileSetup extends StatefulWidget {
  final Function(String) onCreate;
  const _FirstProfileSetup({required this.onCreate});

  @override
  State<_FirstProfileSetup> createState() => _FirstProfileSetupState();
}

class _FirstProfileSetupState extends State<_FirstProfileSetup> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('¡Bienvenido!', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 10),
          const Text('¿Cómo quieres que te llamemos en VivoTV?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          const SizedBox(height: 40),
          CircleAvatar(
            radius: 80,
            backgroundColor: AppTheme.accent,
            child: Text(
              _controller.text.isEmpty ? '?' : _controller.text[0].toUpperCase(),
              style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Escribe tu nombre',
              hintStyle: TextStyle(color: Colors.white24),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 60),
          ElevatedButton(
            onPressed: () {
              if (_controller.text.trim().isNotEmpty) {
                widget.onCreate(_controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Empezar a disfrutar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// Wrapper para manejar el foco en Android TV / Video Beam
class _TVFocusWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus;

  const _TVFocusWrapper({
    required this.child,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_TVFocusWrapper> createState() => _TVFocusWrapperState();
}

class _TVFocusWrapperState extends State<_TVFocusWrapper> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
            (event.logicalKey == LogicalKeyboardKey.select || 
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack, // Efecto elástico Netflix
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused ? Colors.white : Colors.transparent,
                width: 3,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: AppTheme.accent.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _WelcomeIntro extends StatelessWidget {
  final ProfileModel profile;

  const _WelcomeIntro({required this.profile});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, opacity, child) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF0B122B).withOpacity(opacity),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar con Zoom
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.5, end: 1.3),
                duration: const Duration(milliseconds: 1800),
                curve: Curves.easeInOutCubic,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image(
                          image: AvatarResolver.resolve(profile.avatarUrl) ?? 
                                 const AssetImage('assets/images/avatars/avatar_1.webp'),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: Colors.grey[900],
                            child: const Icon(Icons.person, color: Colors.white54, size: 40),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 60),
              // Texto de Bienvenida
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
                builder: (context, textOpacity, child) {
                  return Opacity(
                    opacity: textOpacity,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - textOpacity)),
                      child: Text(
                        'BIENVENIDO DE NUEVO, ${profile.name.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontFamily: 'Manrope',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
