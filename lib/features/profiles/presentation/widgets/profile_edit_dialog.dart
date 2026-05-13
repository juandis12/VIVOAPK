import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/models/profile_model.dart';
import 'package:vivoweb_flutter/core/utils/avatar_resolver.dart';
import 'package:vivoweb_flutter/features/profiles/presentation/widgets/pin_pad_widget.dart';

class ProfileEditDialog extends StatefulWidget {
  final ProfileModel? profile;
  final String userId;

  const ProfileEditDialog({super.key, this.profile, required this.userId});

  @override
  State<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<ProfileEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _pinController;
  late String _selectedColor;
  late String? _selectedAvatar;
  late bool _isKids;

  final List<String> _avatars = [
    'avatar_damon',
    'avatar_elena',
    'avatar_ironman',
    'avatar_scott',
    'avatar_spiderman',
    'avatar_tanjiro',
    'avatar_wanda',
    'avatar_woody',
    'avatar_vivotv_3d',
    'avatar_stranger_things',
    'avatar_la_casa_de_papel',
    'avatar_el_juego_del_calamar',
    'avatar_stormtrooper',
    'avatar_marvel_shield',
    'avatar_cine_premium',
    'avatar_anime_premium',
    'avatar_gamer_premium',
    'avatar_popcorn_premium'
  ];

  // Normaliza un ID de avatar al formato estándar con extensión
  static String normalizeAvatarId(String raw) {
    return AvatarResolver.normalizeForStorage(raw);
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile?.name ?? '');
    _pinController = TextEditingController(text: widget.profile?.pin ?? '');
    _selectedColor = widget.profile?.color ?? 'color-1';
    // Normalizar el avatar existente al formato estándar (ej: 'avatar_ironman.png')
    _selectedAvatar = widget.profile?.avatarUrl != null
        ? normalizeAvatarId(widget.profile!.avatarUrl!)
        : null;
    _isKids = widget.profile?.isKids ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.profile != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0B122B),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white10),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    isEditing ? 'AJUSTES DE PERFIL' : 'AÑADIR PERFIL',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2),
                  ),
                  const SizedBox(height: 32),

                  // Avatar Display (Dynamic)
                  GestureDetector(
                    onTap: () {
                      // Opcional: mostrar selector de avatares en pantalla completa
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: AppTheme.accent,
                          backgroundImage:
                              AvatarResolver.resolve(_selectedAvatar),
                          child: _selectedAvatar == null
                              ? Text(
                                  _nameController.text.isNotEmpty
                                      ? _nameController.text[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      fontSize: 40,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold))
                              : null,
                        ),
                        if (isEditing)
                          const Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 15,
                              backgroundColor: Colors.blue,
                              child: Icon(Icons.edit,
                                  size: 15, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Name Input
                  TextField(
                    controller: _nameController,
                    onChanged: (v) => setState(() {}),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: 'Nombre',
                      hintStyle: TextStyle(color: Colors.white24),
                      border: InputBorder.none,
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 40),

                  // List of Settings (Premium Style)
                  _buildSettingItem(
                    icon: Icons.child_care,
                    iconColor: Colors.yellow,
                    title: 'Modo Niños',
                    subtitle: 'Contenido filtrado para menores',
                    trailing: Switch(
                      value: _isKids,
                      onChanged: (v) => setState(() => _isKids = v),
                      activeThumbColor: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSettingItem(
                    icon: Icons.lock_outline,
                    iconColor: Colors.lightBlueAccent,
                    title: 'PIN de Perfil',
                    subtitle: _pinController.text.isNotEmpty
                        ? 'Bloqueo activado'
                        : 'Sin seguridad activa',
                    onTap: _setupPinWithPad,
                  ),

                  const SizedBox(height: 32),

                  // Avatar Selector Grid (Scrollable)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('ELEGIR PERSONAJE',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _avatars.length,
                      itemBuilder: (context, index) {
                        final av = _avatars[index];
                        final avNormalized = normalizeAvatarId(av);
                        final isSelected = _selectedAvatar == avNormalized;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedAvatar = avNormalized),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 35,
                              backgroundImage:
                                  AvatarResolver.resolve(avNormalized),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 40),

                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('CANCELAR',
                              style: TextStyle(color: Colors.white54)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final profile = ProfileModel(
                              id: widget.profile?.id ?? const Uuid().v4(),
                              userId: widget.userId,
                              name: _nameController.text.isEmpty
                                  ? 'Usuario'
                                  : _nameController.text,
                              color: _selectedColor,
                              avatarUrl: _selectedAvatar,
                              isKids: _isKids,
                              pin: _pinController.text.length == 4
                                  ? _pinController.text
                                  : null,
                            );
                            Navigator.pop(context, profile);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0B122B),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(isEditing ? 'GUARDAR' : 'CREAR',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isSettingPin)
            PinPadWidget(
              title: _pinStepTitle,
              onCompleted: _handlePinStep,
              onCancel: () => setState(() => _isSettingPin = false),
            ),
        ],
      ),
    );
  }

  bool _isSettingPin = false;
  String _pinStepTitle = "Nuevo PIN";
  String? _tempPin;
  int _currentStep = 0; // 0: Old (if exists), 1: New, 2: Confirm

  void _setupPinWithPad() {
    setState(() {
      _currentStep = widget.profile?.pin != null ? 0 : 1;
      _pinStepTitle =
          _currentStep == 0 ? "Introduce PIN actual" : "Nuevo PIN de 4 dígitos";
      _isSettingPin = true;
    });
  }

  void _handlePinStep(String pin) {
    if (_currentStep == 0) {
      if (pin == widget.profile!.pin) {
        setState(() {
          _currentStep = 1;
          _pinStepTitle = "Nuevo PIN de 4 dígitos";
        });
      } else {
        // Shake logic omitted for brevity or can be added
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("PIN incorrecto")));
      }
    } else if (_currentStep == 1) {
      _tempPin = pin;
      setState(() {
        _currentStep = 2;
        _pinStepTitle = "Confirma el nuevo PIN";
      });
    } else if (_currentStep == 2) {
      if (pin == _tempPin) {
        setState(() {
          _pinController.text = pin;
          _isSettingPin = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("PIN actualizado exitosamente")));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Los PINs no coinciden")));
        setState(() {
          _currentStep = 1;
          _pinStepTitle = "Nuevo PIN de 4 dígitos";
        });
      }
    }
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (onTap != null && trailing == null)
              const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}
