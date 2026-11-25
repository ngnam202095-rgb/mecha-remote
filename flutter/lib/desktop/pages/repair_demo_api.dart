import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef RepairJson = Map<String, dynamic>;

const repairPolicy = 'repair-demo/1';
const repairChannel = MethodChannel('mecha/repair');
const repairEnabled = bool.fromEnvironment('MECHA_AI_REPAIR_DEMO');
const repairBase = String.fromEnvironment('MECHA_AI_REPAIR_URL',
    defaultValue: 'http://127.0.0.1:8000');

const repairActions = {
  'audio.read': 'Đọc trạng thái và âm lượng loa mặc định.',
  'audio.set_mute': 'Bật tiếng loa (tối đa 50%).',
  'audio.set_volume': 'Điều chỉnh âm lượng loa (5–50%).',
  'storage.read_system': 'Đọc phần trăm trống của ổ hệ thống.',
  'events.read_summary': 'Đọc thống kê máy in giả lập.',
  'screen.capture_window_mock': 'Tạo bản xem trước mẫu, không chụp màn hình.',
  'screen.share_preview_mock': 'Gửi mã kiểm tra bản mẫu, không gửi ảnh.',
};

const _preview = 'Mecha Remote — Máy in: lỗi kết nối — [đã che]';
final repairPreviewHash = sha256.convert(utf8.encode(_preview)).toString();
const repairPreview = _preview;

String repairDemoDescription(String input) {
  const folds = {
    'a': 'àáảãạăằắẳẵặâầấẩẫậ',
    'd': 'đ',
    'e': 'èéẻẽẹêềếểễệ',
    'i': 'ìíỉĩị',
    'o': 'òóỏõọôồốổỗộơờớởỡợ',
    'u': 'ùúủũụưừứửữự',
    'y': 'ỳýỷỹỵ',
  };
  var text = input.toLowerCase().replaceAll(RegExp(r'[\u0300-\u036f]'), '');
  for (final fold in folds.entries) {
    text = text.replaceAll(RegExp('[${fold.value}]'), fold.key);
  }
  if (RegExp(
          r'\b(otp|mat khau|password|token|so tai khoan|ma xac nhan)\b|\d{6,}')
      .hasMatch(text)) {
    throw const RepairException(
        'Không gửi mật khẩu, mã OTP hoặc số tài khoản.');
  }
  const allowedDescriptions = {
    r'\b(mute|tat tieng)\b': 'Loa bị tắt tiếng',
    r'\b(am luong|qua nho|tieng nho)\b': 'Âm lượng quá nhỏ',
    r'\b(loa|am thanh|mat tieng|khong nghe)\b': 'Loa không phát',
    r'\b(dung luong|day o|o dia|o c|o he thong)\b': 'Ổ hệ thống gần đầy',
    r'\b(may in|in giay|spooler)\b': 'Máy in không hoạt động',
  };
  for (final entry in allowedDescriptions.entries) {
    if (RegExp(entry.key).hasMatch(text)) return entry.value;
  }
  return 'Chưa rõ loại lỗi';
}

String repairNonce() {
  final random = Random.secure();
  return List.generate(
      24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

RepairJson repairMap(Object? value) => value is Map
    ? Map<String, dynamic>.from(value)
    : throw const FormatException();

class RepairException implements Exception {
  const RepairException(this.message);
  final String message;
}

class RepairApi {
  RepairApi(String url) : base = Uri.parse(url) {
    if (!['127.0.0.1', '::1'].contains(base.host) ||
        base.scheme != 'http' ||
        base.userInfo.isNotEmpty ||
        base.path.isNotEmpty && base.path != '/' ||
        base.hasQuery ||
        base.hasFragment) {
      throw const RepairException('Chỉ dùng máy chủ thử trên chính máy này.');
    }
  }

  final Uri base;
  late final _client = http.Client();
  String? _token;
  final device = repairNonce();
  String? publicKey;

  Future<void> login() async {
    final result =
        await post('/demo/session', {'device_id': device, 'plan': 'pro'});
    if (result['demo'] != true ||
        result['device_ref'] != device ||
        result['policy_rev'] != repairPolicy ||
        result['token'] is! String ||
        result['permit_public_key'] is! String) {
      throw const FormatException();
    }
    publicKey = result['permit_public_key'];
    _token = result['token'];
  }

  Future<RepairJson> post(String path, RepairJson data,
          {String? idempotency}) =>
      _request('POST', path, data, idempotency ?? repairNonce());
  Future<RepairJson> get(String path) => _request('GET', path, null, null);
  void close() => _client.close();

  Future<RepairJson> _request(
      String method, String path, RepairJson? body, String? key) async {
    final request = http.Request(method, base.replace(path: '/api/ai/v1$path'))
      ..followRedirects = false;
    final token = _token;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (key != null) request.headers['Idempotency-Key'] = key;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    final response = await (() async {
      final stream = await _client.send(request);
      return http.Response.fromStream(stream);
    })()
        .timeout(const Duration(seconds: 4));
    final result = repairMap(jsonDecode(utf8.decode(response.bodyBytes)));
    if (response.statusCode >= 200 && response.statusCode < 300) return result;
    final error = result['error'];
    final rawCode = error is Map ? error['code'] : result['code'];
    final message = switch (rawCode) {
      'private_data' => 'Không gửi mật khẩu, mã OTP hoặc số tài khoản.',
      'budget_exhausted' => 'Đã hết lượt hỏi trong bản thử.',
      'model_unavailable' => 'Mô hình thử không trả lời. Chưa giữ tiền.',
      'insufficient_funds' => 'Ví thử không đủ. Hãy nạp tiền giả rồi thử lại.',
      'feature_unavailable' => 'Sửa máy tính AI đang tắt ở máy chủ thử.',
      'action_blocked' => 'Thao tác đã đổi hoặc không còn hiệu lực.',
      _ => 'Máy chủ thử không chấp nhận yêu cầu này.',
    };
    throw RepairException(message);
  }
}

Object? _sorted(Object? data) {
  if (data is! Map) return data;
  final keys = data.keys.cast<String>().toList()..sort();
  return <String, Object?>{for (final key in keys) key: _sorted(data[key])};
}

bool _id(Object? value) =>
    value is String && RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value);
bool _hash(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

class RepairOffer {
  RepairOffer._(this.id, this.code, this.hash, this.args, this.expiry);
  final String id, code, hash;
  final RepairJson args;
  final int expiry;

  static RepairOffer parse(
      RepairJson offer, String caseId, String device, int now) {
    final payload = {...offer};
    final hash = payload.remove('payload_hash');
    final id = payload['step_id'];
    final code = payload['code'];
    final expiry = payload['expires_epoch'];
    final args = repairMap(payload['args']);
    if (!_hash(hash) ||
        !_id(id) ||
        !_id(payload['nonce']) ||
        code is! String ||
        !repairActions.containsKey(code) ||
        expiry is! int ||
        expiry <= now ||
        payload.length != 8 ||
        payload['device_ref'] != device ||
        payload['case_id'] != caseId ||
        payload['policy_rev'] != repairPolicy ||
        sha256.convert(utf8.encode(jsonEncode(_sorted(payload)))).toString() !=
            hash) {
      throw const FormatException();
    }
    return RepairOffer._(id as String, code, hash as String, args, expiry);
  }

  RepairJson get native => {'code': code, 'args': args, 'hash': hash};

  Future<({String id, int expires})> verifyPermit(
      Object? permit, String key, String caseId, String device, int now) async {
    if (permit is! String || permit.length > 1500) {
      throw const FormatException();
    }
    final parts = permit.split('.');
    if (parts.length != 2) throw const FormatException();
    final raw = base64Url.decode(base64Url.normalize(parts.first));
    final pub = SimplePublicKey(base64Url.decode(base64Url.normalize(key)),
        type: KeyPairType.ed25519);
    if (!await Ed25519().verify(raw,
        signature: Signature(base64Url.decode(base64Url.normalize(parts.last)),
            publicKey: pub))) {
      throw const FormatException();
    }
    final claims = repairMap(jsonDecode(utf8.decode(raw)));
    final expires = claims['expires_epoch'];
    final permitId = claims['permit_id'];
    if (claims.length != 7 ||
        !_id(permitId) ||
        expires is! int ||
        expires <= now ||
        expires > now + 15 ||
        expires > expiry ||
        claims['payload_hash'] != hash ||
        claims['case_id'] != caseId ||
        claims['step_id'] != id ||
        claims['device_ref'] != device ||
        claims['policy_rev'] != repairPolicy) {
      throw const FormatException();
    }
    return (id: permitId as String, expires: expires);
  }
}

int repairNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

bool get repairEntryAvailable =>
    repairEnabled && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

String repairVnd(Object? amount) {
  if (amount is! int) return '—';
  final digits =
      '$amount'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '$digits ₫';
}
