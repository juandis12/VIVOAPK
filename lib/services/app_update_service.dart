import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// URL del archivo version.json en Supabase Storage (bucket "updates").
const String _versionJsonUrl =
    'https://esnrgviozjfjgnbcrduz.supabase.co/storage/v1/object/public/updates/version.json';

/// Servicio OTA: verifica si hay una nueva versión disponible, descarga
/// el APK y lanza la instalación de forma nativa en Android.
///
/// ⚠️ Solo funciona en Android. En iOS no se hace nada.
class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  final Dio _dio = Dio();

  /// Punto de entrada principal. Llama esto desde el Dashboard al iniciar.
  /// Muestra un diálogo si hay una versión más reciente disponible.
  Future<void> checkForUpdate(BuildContext context) async {
    // Solo Android — en iOS no es posible instalar APKs externos
    if (!Platform.isAndroid) return;

    try {
      // 1. Obtener la versión instalada actualmente
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;

      // 2. Consultar el version.json en Supabase Storage
      final response = await _dio
          .get(_versionJsonUrl)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final data = json.decode(response.data is String
          ? response.data
          : json.encode(response.data)) as Map<String, dynamic>;

      final remoteVersionCode = data['versionCode'] as int? ?? 1;
      final remoteVersion = data['version'] as String? ?? '';
      final downloadUrl = data['downloadUrl'] as String? ?? '';
      final releaseNotes = data['releaseNotes'] as String? ?? '';

      // 3. Comparar códigos de versión (buildNumber)
      if (remoteVersionCode <= currentVersionCode) return;
      if (downloadUrl.isEmpty) return;

      // 4. Mostrar diálogo de actualización
      if (context.mounted) {
        _showUpdateDialog(
          context,
          version: remoteVersion,
          releaseNotes: releaseNotes,
          downloadUrl: downloadUrl,
        );
      }
    } catch (e) {
      // Fallo silencioso — no interrumpir al usuario si no hay conexión
      debugPrint('[AppUpdateService] Check falló: $e');
    }
  }

  void _showUpdateDialog(
    BuildContext context, {
    required String version,
    required String releaseNotes,
    required String downloadUrl,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(
        version: version,
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
        onUpdate: () => _downloadAndInstall(context, downloadUrl, version),
      ),
    );
  }

  Future<void> _downloadAndInstall(
    BuildContext context,
    String downloadUrl,
    String version,
  ) async {
    // Solicitar permiso de instalación de apps desconocidas (Android 8+)
    final installStatus = await Permission.requestInstallPackages.request();
    if (!installStatus.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Permiso requerido para instalar actualizaciones. Actívalo en Configuración.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Ruta donde se descarga el APK
    final dir = await getTemporaryDirectory();
    final apkPath = '${dir.path}/vivotv-update-$version.apk';

    // Mostrar diálogo de progreso de descarga
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(
        downloadUrl: downloadUrl,
        savePath: apkPath,
        dio: _dio,
        onComplete: () async {
          Navigator.of(ctx).pop();
          await OpenFile.open(apkPath);
        },
        onError: (err) {
          Navigator.of(ctx).pop();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al descargar: $err'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIÁLOGO: Nueva versión disponible
// ─────────────────────────────────────────────────────────────
class _UpdateDialog extends StatelessWidget {
  final String version;
  final String releaseNotes;
  final String downloadUrl;
  final VoidCallback onUpdate;

  const _UpdateDialog({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F1923),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Text('🚀', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Text(
            'Actualización disponible',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Versión $version',
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (releaseNotes.isNotEmpty)
            Text(
              releaseNotes,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          const SizedBox(height: 8),
          const Text(
            '¿Deseas actualizar VivoTv ahora?',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ahora no',
              style: TextStyle(color: Colors.white38)),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Actualizar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onUpdate();
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DIÁLOGO: Progreso de descarga del APK
// ─────────────────────────────────────────────────────────────
class _DownloadProgressDialog extends StatefulWidget {
  final String downloadUrl;
  final String savePath;
  final Dio dio;
  final VoidCallback onComplete;
  final Function(String) onError;

  const _DownloadProgressDialog({
    required this.downloadUrl,
    required this.savePath,
    required this.dio,
    required this.onComplete,
    required this.onError,
  });

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double? _progress;      // null = indeterminado (Supabase no envió Content-Length)
  int _receivedBytes = 0;
  bool _sizeKnown = false;
  String _status = 'Iniciando descarga...';
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    _cancelToken = CancelToken();
    try {
      await widget.dio.download(
        widget.downloadUrl,
        widget.savePath,
        cancelToken: _cancelToken,
        options: Options(
          // Seguir redirecciones (importante para Supabase Storage)
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(seconds: 30),
        ),
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            if (total > 0) {
              // Supabase envió Content-Length → progreso determinado
              _sizeKnown = true;
              _progress = received / total;
              final mb = (received / 1024 / 1024).toStringAsFixed(1);
              final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
              _status = '$mb MB / $totalMb MB';
            } else {
              // Sin Content-Length → mostrar solo bytes descargados
              _sizeKnown = false;
              _progress = null;
              final mb = (received / 1024 / 1024).toStringAsFixed(1);
              _status = '$mb MB descargados...';
            }
          });
        },
      );
      widget.onComplete();
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) {
        widget.onError(e.message ?? 'Error desconocido');
      }
    } catch (e) {
      widget.onError(e.toString());
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Dialog cerrado');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isIndeterminate = !_sizeKnown;

    return AlertDialog(
      backgroundColor: const Color(0xFF0F1923),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '⬇️ Descargando actualización',
        style: TextStyle(color: Colors.white, fontSize: 15),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          LinearProgressIndicator(
            // null = animación de barra indeterminada
            value: isIndeterminate ? null : _progress,
            backgroundColor: Colors.white12,
            color: const Color(0xFF00E5FF),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            isIndeterminate
                ? '${(_receivedBytes / 1024 / 1024).toStringAsFixed(1)} MB'
                : '${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _status,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
