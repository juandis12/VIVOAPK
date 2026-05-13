class ContentModel {
  final int id;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String type; // 'movie' or 'tv'
  final double voteAverage;
  final String? releaseDate;
  final List<String> genres;
  final List<Map<String, dynamic>> cast;
  final List<ContentModel> similar;
  final List<int> genreIds;
  final int seasons;

  ContentModel({
    required this.id,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    required this.type,
    required this.voteAverage,
    this.releaseDate,
    this.genres = const [],
    this.cast = const [],
    this.similar = const [],
    this.genreIds = const [],
    this.seasons = 1,
    this.progressSeconds = 0,
    this.runtime = 0,
  });

  final int progressSeconds;
  final int runtime;

  factory ContentModel.fromJson(Map<String, dynamic> json, String type) {
    // Genres from TMDB can be objects or just IDs
    List<String> genreNames = [];
    if (json['genres'] != null) {
      genreNames = (json['genres'] as List).map((g) => g['name'].toString()).toList();
    }

    return ContentModel(
      id: json['id'],
      title: json['title'] ?? json['name'] ?? 'Sin título',
      overview: json['overview'],
      posterPath: json['poster_path'],
      backdropPath: json['backdrop_path'],
      type: type,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      releaseDate: json['release_date'] ?? json['first_air_date'],
      genres: genreNames,
      genreIds: json['genre_ids'] != null 
          ? List<int>.from(json['genre_ids']) 
          : (json['genres'] != null 
              ? (json['genres'] as List).map((g) => g['id'] as int).toList()
              : []),
      cast: json['credits']?['cast'] != null 
          ? (json['credits']['cast'] as List).take(10).map((c) => c as Map<String, dynamic>).toList()
          : [],
      similar: json['recommendations']?['results'] != null
          ? (json['recommendations']['results'] as List).take(6).map((r) => ContentModel.fromJson(r, type)).toList()
          : [],
      seasons: json['number_of_seasons'] ?? 1,
      runtime: json['runtime'] ?? (json['episode_run_time'] != null && (json['episode_run_time'] as List).isNotEmpty ? json['episode_run_time'][0] : 0),
    );
  }

  factory ContentModel.fromCache(Map<String, dynamic> json) {
    return ContentModel(
      id: json['id'],
      title: json['title'],
      overview: json['overview'],
      posterPath: json['poster_path'],
      backdropPath: json['backdrop_path'],
      type: json['type'],
      voteAverage: (json['vote_average'] as num).toDouble(),
      releaseDate: json['release_date'],
      genres: List<String>.from(json['genres'] ?? []),
      genreIds: List<int>.from(json['genre_ids'] ?? []),
      seasons: json['seasons'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'overview': overview,
      'poster_path': posterPath,
      'backdrop_path': backdropPath,
      'type': type,
      'vote_average': voteAverage,
      'release_date': releaseDate,
      'genres': genres,
      'genre_ids': genreIds,
      'seasons': seasons,
      'progress_seconds': progressSeconds,
      'runtime': runtime,
    };
  }

  ContentModel copyWith({
    int? progressSeconds,
    int? runtime,
  }) {
    return ContentModel(
      id: id,
      title: title,
      overview: overview,
      posterPath: posterPath,
      backdropPath: backdropPath,
      type: type,
      voteAverage: voteAverage,
      releaseDate: releaseDate,
      genres: genres,
      cast: cast,
      similar: similar,
      genreIds: genreIds,
      seasons: seasons,
      progressSeconds: progressSeconds ?? this.progressSeconds,
      runtime: runtime ?? this.runtime,
    );
  }
}
