import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'brand.dart';

const _paidPlans = {
  'pro': 'Pro',
  'team': 'Team',
  'business': 'Business',
  'enterprise': 'Enterprise',
};

class LicenseFailure implements Exception {
  final String message;
  const LicenseFailure(this.message);
}

class LicenseStatus {
  final String key;
  final String plan;
  final DateTime expiry;

  const LicenseStatus(this.key, this.plan, this.expiry);

  bool get active => expiry.isAfter(DateTime.now());
  String get label => active ? _paidPlans[plan]! : 'Miễn phí';

  static LicenseStatus parse(String key, Map<String, dynamic> data) {
    final plan = (data['plan'] as String?)?.toLowerCase();
    final expiry = DateTime.tryParse(data['expires_at'] as String? ?? '');
    if (!_paidPlans.containsKey(plan) || expiry == null) {
      throw const FormatException();
    }
    return LicenseStatus(key, plan!, expiry);
  }

  static LicenseStatus? read(String stored) {
    if (stored.isEmpty) return null;
    try {
      final data = jsonDecode(stored) as Map<String, dynamic>;
      return parse(data['license_key'] as String, data);
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
        'license_key': key,
        'plan': plan,
        'expires_at': expiry.toIso8601String(),
      });
}

class LicenseApi {
  final http.Client client;
  final String baseUrl;

  const LicenseApi(this.client, {this.baseUrl = brandLicenseApi});

  Future<LicenseStatus> activate(
      String key, String deviceId, String deviceName) async {
    final data = await _post('activate', {
      'license_key': key,
      'device_id': deviceId,
      'device_name': deviceName,
    });
    try {
      final status = LicenseStatus.parse(key, data);
      if (!status.active) {
        throw const LicenseFailure('Mã bản quyền đã hết hạn.');
      }
      return status;
    } on FormatException {
      throw const LicenseFailure(
          'Máy chủ trả về thông tin bản quyền không hợp lệ.');
    } on TypeError {
      throw const LicenseFailure(
          'Máy chủ trả về thông tin bản quyền không hợp lệ.');
    }
  }

  Future<void> deactivate(String key, String deviceId) async {
    await _post('deactivate', {'license_key': key, 'device_id': deviceId});
  }

  Future<Map<String, dynamic>> _post(
      String action, Map<String, String> data) async {
    late http.Response response;
    try {
      final request =
          http.Request('POST', Uri.parse('$baseUrl/api/licenses/$action'))
            ..followRedirects = false
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode(data);
      response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })()
          .timeout(const Duration(seconds: 8));
    } on Exception {
      throw const LicenseFailure(
          'Không thể kết nối máy chủ bản quyền. Hãy thử lại sau.');
    }
    Map<String, dynamic> body = {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        if (response.statusCode < 400) {
          throw const LicenseFailure(
              'Máy chủ trả về thông tin bản quyền không hợp lệ.');
        }
      }
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (body['ok'] == true || (action == 'deactivate' && body.isEmpty))) {
      return body;
    }
    final reason = [
      body['code'],
      body['error'],
      body['message'],
      body['detail'],
    ].join(' ').toLowerCase();
    if (response.statusCode == 409 ||
        reason.contains('device_limit') ||
        reason.contains('hết lượt') ||
        reason.contains('limit_reached')) {
      throw const LicenseFailure(
          'Mã đã hết lượt kích hoạt. Hãy gỡ một máy cũ rồi thử lại.');
    }
    if (response.statusCode == 410 ||
        reason.contains('expired') ||
        reason.contains('hết hạn')) {
      throw const LicenseFailure('Mã bản quyền đã hết hạn.');
    }
    if (response.statusCode == 404 ||
        response.statusCode == 400 ||
        reason.contains('invalid') ||
        reason.contains('sai mã') ||
        reason.contains('không tìm thấy mã')) {
      throw const LicenseFailure('Mã bản quyền không đúng.');
    }
    throw const LicenseFailure(
        'Máy chủ bản quyền chưa xử lý được yêu cầu. Hãy thử lại sau.');
  }
}

bool addressBookCanAdd(int count, LicenseStatus? status) =>
    status?.active == true || count < brandFreeAddressBookMax;
