import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _httpClient;
  final FlutterSecureStorage _storage;

  static const String _tokenStorageKey = 'device_auth_token';
  static const String _baseUrlStorageKey = 'api_base_url';

  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    FlutterSecureStorage? storage,
  })  : _httpClient = httpClient ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenStorageKey, value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenStorageKey);
  }

  Future<void> saveBaseUrl(String url) async {
    await _storage.write(key: _baseUrlStorageKey, value: url);
  }

  Future<String?> getStoredBaseUrl() async {
    return await _storage.read(key: _baseUrlStorageKey);
  }

  Future<Map<String, String>> _buildHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Never _handleError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>?;
      if (err != null) {
        throw ApiException(
          code: err['code'] as String? ?? 'UNKNOWN_ERROR',
          message: err['message'] as String? ?? 'An unexpected error occurred.',
          requestId: err['requestId'] as String?,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
    }

    throw ApiException(
      code: 'HTTP_${response.statusCode}',
      message: 'Server returned HTTP ${response.statusCode}: ${response.reasonPhrase}',
      statusCode: response.statusCode,
    );
  }

  Future<WorkStatus> getStatus() async {
    final uri = Uri.parse('$baseUrl/api/v1/status');
    final headers = await _buildHeaders();
    final response = await _httpClient.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return WorkStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    _handleError(response);
  }

  Future<WorkStatus> clockIn({required String requestId, String source = 'flutter_app'}) async {
    final uri = Uri.parse('$baseUrl/api/v1/clock-in');
    final headers = await _buildHeaders();
    final body = jsonEncode({
      'requestId': requestId,
      'source': source,
    });

    final response = await _httpClient.post(uri, headers: headers, body: body);
    if (response.statusCode == 200) {
      return WorkStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    _handleError(response);
  }

  Future<WorkStatus> clockOut({
    required String requestId,
    String source = 'flutter_app',
    String? note,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/clock-out');
    final headers = await _buildHeaders();
    final payload = <String, dynamic>{
      'requestId': requestId,
      'source': source,
    };
    if (note != null && note.trim().isNotEmpty) {
      payload['note'] = note.trim();
    }
    final body = jsonEncode(payload);

    final response = await _httpClient.post(uri, headers: headers, body: body);
    if (response.statusCode == 200) {
      return WorkStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    _handleError(response);
  }

  Future<List<TrackingEvent>> getEvents({
    required DateTime from,
    required DateTime to,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/events').replace(queryParameters: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    });
    final headers = await _buildHeaders();
    final response = await _httpClient.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((item) => TrackingEvent.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    _handleError(response);
  }

  Future<UndoResult> undo({
    required String eventId,
    required String requestId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/undo');
    final headers = await _buildHeaders();
    final body = jsonEncode({
      'eventId': eventId,
      'requestId': requestId,
    });

    final response = await _httpClient.post(uri, headers: headers, body: body);
    if (response.statusCode == 200) {
      return UndoResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    _handleError(response);
  }

  Future<Map<String, dynamic>> submitManualShift({
    required DateTime clockInAt,
    required DateTime clockOutAt,
    required String reason,
    required String requestId,
    String? adminToken,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/admin/events/manual');
    final headers = await _buildHeaders();
    if (adminToken != null && adminToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $adminToken';
    }
    final body = jsonEncode({
      'clockInAt': clockInAt.toUtc().toIso8601String(),
      'clockOutAt': clockOutAt.toUtc().toIso8601String(),
      'reason': reason,
      'requestId': requestId,
    });

    final response = await _httpClient.post(uri, headers: headers, body: body);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    _handleError(response);
  }

  Future<({Uint8List bytes, String filename, double totalHours, int totalShifts})> generateReport({
    required DateTime startDate,
    required DateTime endDate,
    required String preset,
    bool includeNotes = false,
    bool includeStats = false,
    bool includeSource = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/reports/generate');
    final headers = await _buildHeaders();
    final body = jsonEncode({
      'startDate': startDate.toUtc().toIso8601String(),
      'endDate': endDate.toUtc().toIso8601String(),
      'preset': preset,
      'options': {
        'includeNotes': includeNotes,
        'includeStats': includeStats,
        'includeSource': includeSource,
      },
    });

    final response = await _httpClient.post(uri, headers: headers, body: body);
    if (response.statusCode == 200) {
      final cd = response.headers['content-disposition'] ?? '';
      final fnMatch = RegExp(r'filename="([^"]+)"').firstMatch(cd);
      final filename = fnMatch != null ? fnMatch.group(1)! : 'work-hours-report.xlsx';
      final totalHours = double.tryParse(response.headers['x-total-hours'] ?? '0') ?? 0.0;
      final totalShifts = int.tryParse(response.headers['x-total-shifts'] ?? '0') ?? 0;

      return (
        bytes: response.bodyBytes,
        filename: filename,
        totalHours: totalHours,
        totalShifts: totalShifts,
      );
    }
    _handleError(response);
  }

  Future<Map<String, dynamic>?> getLatestReport() async {
    final uri = Uri.parse('$baseUrl/api/v1/reports/latest');
    final headers = await _buildHeaders();
    final response = await _httpClient.get(uri, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 404) {
      return null;
    }
    _handleError(response);
  }

  Future<Uint8List> downloadReport(String filename) async {
    final encoded = Uri.encodeComponent(filename);
    final uri = Uri.parse('$baseUrl/api/v1/reports/download/$encoded');
    final headers = await _buildHeaders();
    final response = await _httpClient.get(uri, headers: headers);
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    _handleError(response);
  }
}
