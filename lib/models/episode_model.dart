class EpisodeModel {
  final int tmdbId;
  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String? overview;
  final String? stillPath;
  final String? streamUrl;
  final int? runtime;
  final int progressSeconds;
  final bool isWatched;

  EpisodeModel({
    required this.tmdbId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.stillPath,
    this.streamUrl,
    this.runtime,
    this.progressSeconds = 0,
    this.isWatched = false,
  });

  factory EpisodeModel.fromJson(Map<String, dynamic> json, int tmdbId, int seasonNumber, {String? streamUrl, int progressSeconds = 0, bool isWatched = false}) {
    return EpisodeModel(
      tmdbId: tmdbId,
      seasonNumber: seasonNumber,
      episodeNumber: json['episode_number'],
      name: json['name'] ?? 'Episodio ${json['episode_number']}',
      overview: json['overview'],
      stillPath: json['still_path'],
      streamUrl: streamUrl,
      runtime: json['runtime'],
      progressSeconds: progressSeconds,
      isWatched: isWatched,
    );
  }
}
