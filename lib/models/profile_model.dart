

class ProfileModel {
  final String id;
  final String userId;
  final String name;
  final String color;
  final String? avatarUrl;
  final bool isKids;
  final String? pin;
  final DateTime? lastHeartbeat;
  final Map<String, dynamic>? nowPlaying;
  final String? fcmToken;

  ProfileModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.color,
    this.avatarUrl,
    required this.isKids,
    this.pin,
    this.lastHeartbeat,
    this.nowPlaying,
    this.fcmToken,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'] ?? 'Usuario',
      color: json['color'] ?? 'color-1',
      avatarUrl: json['avatar_url'],
      isKids: json['is_kids'] ?? false,
      pin: json['pin'],
      lastHeartbeat: json['last_heartbeat'] != null 
          ? DateTime.parse(json['last_heartbeat']) 
          : null,
      nowPlaying: json['now_playing'] is Map<String, dynamic> 
          ? json['now_playing'] as Map<String, dynamic>
          : null,
      fcmToken: json['fcm_token'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'color': color,
      'avatar_url': avatarUrl,
      'is_kids': isKids,
      'pin': pin,
      'last_heartbeat': lastHeartbeat?.toIso8601String(),
      'now_playing': nowPlaying,
      'fcm_token': fcmToken,
    };
  }

  bool isOccupiedWithServerNow(DateTime serverNow) {
    if (lastHeartbeat == null) return false;
    final diff = serverNow.difference(lastHeartbeat!).inSeconds;
    return diff < 30;
  }

  bool get isOccupied {
    if (lastHeartbeat == null) return false;
    final diff = DateTime.now().difference(lastHeartbeat!).inSeconds;
    return diff < 30;
  }
}
