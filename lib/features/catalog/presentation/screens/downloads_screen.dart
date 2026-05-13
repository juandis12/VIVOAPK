import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vivoweb_flutter/core/theme/app_theme.dart';
import 'package:vivoweb_flutter/services/download_service.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('MIS DESCARGAS', 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: Consumer<DownloadService>(
        builder: (context, service, child) {
          final tasks = service.tasks;

          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_for_offline_outlined, size: 80, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 16),
                  const Text('No tienes descargas aún', 
                    style: TextStyle(color: Colors.white38, fontSize: 16)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                    onPressed: () => context.go('/'),
                    child: const Text('Explorar Contenido'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _DownloadItemTile(task: task, service: service);
            },
          );
        },
      ),
    );
  }
}

class _DownloadItemTile extends StatelessWidget {
  final DownloadTask task;
  final DownloadService service;

  const _DownloadItemTile({required this.task, required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: task.status == 'completed' 
              ? () => context.push('/detail/${task.type}/${task.tmdbId}') 
              : null,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  // Poster
                  Container(
                    width: 70,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white10,
                      image: task.posterPath != null 
                        ? DecorationImage(
                            image: NetworkImage('https://image.tmdb.org/t/p/w200${task.posterPath}'),
                            fit: BoxFit.cover,
                          ) 
                        : null,
                    ),
                    child: task.posterPath == null 
                      ? const Icon(Icons.movie_outlined, color: Colors.white24) 
                      : null,
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.status == 'completed' ? 'Descargado • ${_getFileSize(task.localPath)}' : 'Descargando...',
                          style: TextStyle(color: task.status == 'completed' ? AppTheme.accent : Colors.white38, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        if (task.status == 'downloading')
                          Column(
                            children: [
                              LinearProgressIndicator(
                                value: task.progress,
                                backgroundColor: Colors.white10,
                                color: AppTheme.accent,
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${(task.progress * 100).toInt()}%', 
                                    style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                  GestureDetector(
                                    onTap: () => service.cancelDownload(task.id),
                                    child: const Text('CANCELAR', 
                                      style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else if (task.status == 'completed')
                          const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 16),
                              SizedBox(width: 4),
                              Text('Listo para ver sin conexión', 
                                style: TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w500)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Acciones
                  if (task.status == 'completed')
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
                      onPressed: () => _showDeleteConfirm(context),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.navy,
        title: const Text('¿Eliminar descarga?', style: TextStyle(color: Colors.white)),
        content: Text('Se borrará "${task.title}" de tu dispositivo.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              service.deleteDownload(task.id);
              Navigator.pop(context);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  String _getFileSize(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return 'N/A';
      final bytes = file.lengthSync();
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (e) {
      return 'Error';
    }
  }
}
