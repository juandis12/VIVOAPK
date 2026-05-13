import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TMDBService {
  static final TMDBService _instance = TMDBService._internal();
  factory TMDBService() => _instance;
  TMDBService._internal();

  final http.Client client = http.Client();

  static const String apiKey = '743275e25bcea0a320b87d2af271a136';
  static const String baseUrl = 'https://api.themoviedb.org/3';
  static const String imageBaseUrl = 'https://image.tmdb.org/t/p/w500';

  // ─── ENDPOINT LIGERO ────────────────────────────────────────────────────────
  // Solo trae los datos necesarios para mostrar tarjetas en el catálogo:
  // poster_path, title/name, genres, id, vote_average.
  // NO descarga videos, créditos ni recomendaciones. ~70% más rápido por item.
  Future<Map<String, dynamic>> getContentSummary(String type, int id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/$type/$id?api_key=$apiKey&language=es-ES'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      throw Exception('TMDB summary HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('[TMDB] Error en getContentSummary($type/$id): $e');
      rethrow;
    }
  }

  // ─── ENDPOINT COMPLETO ───────────────────────────────────────────────────────
  // Solo se usa en ContentDetailScreen. Descarga videos, créditos y recomendaciones.
  Future<Map<String, dynamic>> getContentDetails(String type, int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/$type/$id?api_key=$apiKey&language=es-ES&append_to_response=videos,recommendations,credits'),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener detalles de TMDB');
    }
  }

  Future<List<dynamic>> searchContent(String query) async {
    final response = await http.get(
      Uri.parse('$baseUrl/search/multi?api_key=$apiKey&query=$query&language=es-ES'),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Error en la búsqueda de TMDB');
    }
  }

  Future<List<dynamic>> getTrending(String type) async {
    final response = await http.get(
      Uri.parse('$baseUrl/trending/$type/week?api_key=$apiKey&language=es-ES'),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body)['results'];
    } else {
      throw Exception('Error al obtener tendencias');
    }
  }

  Future<Map<String, dynamic>> fetchFromTMDB(String endpoint, Map<String, String> params) async {
    final queryParams = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final response = await http.get(
      Uri.parse('$baseUrl$endpoint?api_key=$apiKey&language=es-ES&$queryParams'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error fetching from TMDB endpoint: $endpoint');
    }
  }

  String getImageUrl(String? path, {String size = 'w500'}) {
    if (path == null) return '';
    return 'https://image.tmdb.org/t/p/$size$path';
  }
}

