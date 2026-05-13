import 'package:flutter/material.dart';

class AvatarResolver {
  /// Base path for local avatar assets in Flutter
  static const String _baseAssetPath = 'assets/images/avatars/';

  /// Resolves an avatar identifier/URL to an ImageProvider.
  /// Handles:
  /// - Full web paths: 'assets/avatars/avatar_ironman.png'
  /// - Format with extension: 'avatar_ironman.png'
  /// - Format without extension: 'avatar_ironman'
  /// - Network URLs: 'https://...'
  /// Resolves an avatar identifier/URL to an ImageProvider.
  static ImageProvider? resolve(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return null;

    // 1. Check if it's a network URL
    if (avatarUrl.startsWith('http')) {
      return NetworkImage(avatarUrl);
    }

    // 2. Extract only the filename from the path
    // This handles 'assets/avatars/avatar_ironman.png' -> 'avatar_ironman.png'
    String filename = avatarUrl.split('/').last;

    // 3. Migrate from .png to .webp automatically for local assets
    if (filename.endsWith('.png')) {
      filename = filename.replaceAll('.png', '.webp');
    }

    // 4. Ensure it has the extension
    final normalizedFilename = filename.contains('.') ? filename : '$filename.webp';

    // 5. Return as AssetImage if it follows the app's naming convention
    if (normalizedFilename.startsWith('avatar_')) {
      return AssetImage('$_baseAssetPath$normalizedFilename');
    }

    return null;
  }

  /// Normalizes a raw string to the canonical 'avatar_name.webp' format for storage.
  static String normalizeForStorage(String raw) {
    String filename = raw.split('/').last;
    if (filename.endsWith('.png')) {
      filename = filename.replaceAll('.png', '.webp');
    }
    return filename.contains('.') ? filename : '$filename.webp';
  }
}
