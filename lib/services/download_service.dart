import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class DownloadTask {
  final String id;
  final String tmdbId;
  final String title;
  final String type;
  final String? posterPath;
  final String url;
  final String localPath;
  double progress;
  String status; // 'pending', 'downloading', 'completed', 'failed'
  CancelToken? cancelToken;

  DownloadTask({
    required this.id,
    required this.tmdbId,
    required this.title,
    required this.type,
    this.posterPath,
    required this.url,
    required this.localPath,
    this.progress = 0,
    this.status = 'pending',
    this.cancelToken,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'tmdbId': tmdbId,
    'title': title,
    'type': type,
    'posterPath': posterPath,
    'url': url,
    'localPath': localPath,
    'progress': progress,
    'status': status,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    id: json['id'],
    tmdbId: json['tmdbId'],
    title: json['title'],
    type: json['type'],
    posterPath: json['posterPath'],
    url: json['url'],
    localPath: json['localPath'],
    progress: json['progress']?.toDouble() ?? 0,
    status: json['status'],
  );
}

class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal() {
    _init();
  }

  final Dio _dio = Dio();
  final Map<String, DownloadTask> _tasks = {};
  List<DownloadTask> get tasks => _tasks.values.toList();

  Future<void> _init() async {
    await _loadTasksFromStorage();
  }

  Future<String> _getVaultPath() async {
    final docDir = await getApplicationDocumentsDirectory();
    final vault = Directory('${docDir.path}/.vivotv_vault');
    if (!await vault.exists()) {
      await vault.create(recursive: true);
    }
    return vault.path;
  }

  Future<void> startDownload({
    required String tmdbId,
    required String title,
    required String type,
    required String url,
    String? posterPath,
  }) async {
    final id = const Uuid().v4();
    final vaultPath = await _getVaultPath();
    final localPath = '$vaultPath/$id.vivotv'; // Extensión personalizada segura

    final task = DownloadTask(
      id: id,
      tmdbId: tmdbId,
      title: title,
      type: type,
      posterPath: posterPath,
      url: url,
      localPath: localPath,
      status: 'downloading',
      cancelToken: CancelToken(),
    );

    _tasks[id] = task;
    notifyListeners();
    _saveTasksToStorage();

    try {
      // 🚀 VIVO SECURE VAULT: Descarga con encriptación XOR en tiempo real
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(responseType: ResponseType.stream),
        cancelToken: task.cancelToken,
      );

      final file = File(localPath);
      final raf = await file.open(mode: FileMode.write);
      
      int downloaded = 0;
      final total = int.tryParse(response.headers.value('content-length') ?? '-1') ?? -1;

      await for (final chunk in response.data!.stream) {
        // Encriptar el chunk (XOR simple con clave 'VIVOTV')
        final encryptedChunk = _encryptChunk(chunk);
        await raf.writeFrom(encryptedChunk);
        
        downloaded += chunk.length;
        if (total != -1) {
          task.progress = downloaded / total;
          notifyListeners();
        }
      }
      
      await raf.close();
      task.status = 'completed';
      task.progress = 1.0;
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        debugPrint('[Download] Download cancelled: $id');
      } else {
        debugPrint('[Download] Error: $e');
        task.status = 'failed';
      }
    } finally {
      notifyListeners();
      _saveTasksToStorage();
    }
  }

  Uint8List _encryptChunk(List<int> chunk) {
    const key = 'VIVOTV_SECURE_VAULT_2024';
    final keyBytes = utf8.encode(key);
    final result = Uint8List(chunk.length);
    for (int i = 0; i < chunk.length; i++) {
      result[i] = chunk[i] ^ keyBytes[i % keyBytes.length];
    }
    return result;
  }

  void cancelDownload(String id) {
    final task = _tasks[id];
    if (task != null && task.status == 'downloading') {
      task.cancelToken?.cancel();
      _tasks.remove(id);
      notifyListeners();
      _saveTasksToStorage();
    }
  }

  Future<void> deleteDownload(String id) async {
    final task = _tasks[id];
    if (task != null) {
      final file = File(task.localPath);
      if (await file.exists()) {
        await file.delete();
      }
      _tasks.remove(id);
      notifyListeners();
      _saveTasksToStorage();
    }
  }

  Future<void> _saveTasksToStorage() async {
    final vaultPath = await _getVaultPath();
    final metaFile = File('$vaultPath/metadata.json');
    final data = _tasks.values.map((t) => t.toJson()).toList();
    await metaFile.writeAsString(json.encode(data));
  }

  Future<void> _loadTasksFromStorage() async {
    try {
      final vaultPath = await _getVaultPath();
      final metaFile = File('$vaultPath/metadata.json');
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        final List<dynamic> data = json.decode(content);
        for (var item in data) {
          final task = DownloadTask.fromJson(item);
          // Verificar si el archivo aún existe físicamente
          if (await File(task.localPath).exists() || task.status == 'downloading') {
            if (task.status == 'downloading') task.status = 'failed'; // Reset status if app closed during download
            _tasks[task.id] = task;
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Download] Error loading metadata: $e');
    }
  }


  Future<File?> getDecryptedFile(String tmdbId) async {
    final task = _tasks.values.firstWhere((t) => t.tmdbId == tmdbId && t.status == 'completed');
    final encryptedFile = File(task.localPath);
    if (!await encryptedFile.exists()) return null;

    final bytes = await encryptedFile.readAsBytes();
    const key = 'VIVOTV_SECURE_VAULT_2024';
    final keyBytes = utf8.encode(key);
    
    final decryptedBytes = Uint8List(bytes.length);
    for (int i = 0; i < bytes.length; i++) {
      decryptedBytes[i] = bytes[i] ^ keyBytes[i % keyBytes.length];
    }

    final tempDir = await getTemporaryDirectory();
    final decryptedFile = File('${tempDir.path}/playback_${tmdbId}.mp4');
    await decryptedFile.writeAsBytes(decryptedBytes);
    
    return decryptedFile;
  }

  Future<void> clearDecryptedCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      final files = await dir.list().toList();
      for (var file in files) {
        if (file.path.contains('playback_') && file.path.endsWith('.mp4')) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('[Download] Error clearing cache: $e');
    }
  }

  bool isDownloaded(String tmdbId, {int? season, int? episode}) {
    return _tasks.values.any((t) => 
      t.tmdbId == tmdbId && 
      t.status == 'completed' &&
      (season == null || t.title.contains('T$season')) &&
      (episode == null || t.title.contains('E$episode'))
    );
  }

  String? getLocalPath(String tmdbId) {
    try {
      return _tasks.values.firstWhere((t) => t.tmdbId == tmdbId && t.status == 'completed').localPath;
    } catch (_) {
      return null;
    }
  }
}
