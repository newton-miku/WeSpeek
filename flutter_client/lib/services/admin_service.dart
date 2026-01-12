import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../models/admin_stats.dart';

class AdminService {
  final String baseUrl;

  AdminService(this.baseUrl);

  Future<String> _getAdminAuthStr(String adminKey) async {
    final challengeUrl = Uri.parse('$baseUrl/api/admin/challenge');
    final response = await http.get(challengeUrl);

    if (response.statusCode != 200) {
      throw Exception('Failed to get challenge: ${response.statusCode}');
    }

    final Map<String, dynamic> data = json.decode(response.body);
    final String nonce = data['nonce'];

    // HMAC-SHA256(key=adminKey, data=nonce)
    final key = utf8.encode(adminKey);
    final bytes = utf8.encode(nonce);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);

    return '$nonce:$digest';
  }

  Future<ServerStats> fetchServerStats(String adminKey) async {
    final authStr = await _getAdminAuthStr(adminKey);

    final statsUrl = Uri.parse('$baseUrl/api/admin/status');
    final response = await http.get(
      statsUrl,
      headers: {'X-Admin-Auth': authStr},
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 401) {
        throw Exception('Unauthorized');
      }
      throw Exception('Failed to load stats: ${response.statusCode}');
    }

    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    return ServerStats.fromJson(jsonResponse);
  }
}
