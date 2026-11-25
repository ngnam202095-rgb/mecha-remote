import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'repair_demo_api.dart';

class RepairDemoPage extends StatefulWidget {
  const RepairDemoPage({super.key, required this.hasRemoteClient});

  final Future<bool> Function() hasRemoteClient;

  @override
  State<RepairDemoPage> createState() => _RepairDemoPageState();
}

class _RepairDemoPageState extends State<RepairDemoPage> {
  static const active = {'active', 'consulting', 'awaiting_confirmation'};
  static const terminal = {
    'succeeded',
    'failed',
    'cancelled',
    'expired',
    'advice'
  };
  static const auditLabels = {
    'offered': 'Chờ cho phép',
    'permitted': 'Đã cấp phiếu',
    'completed': 'Đã thực hiện',
    'denied': 'Đã từ chối',
    'closed': 'Đã thu hồi',
    'blocked': 'Đã chặn',
    'failed': 'Không thành công',
    'unknown': 'Chưa rõ kết quả',
  };

  final _text = TextEditingController();
  final _questions = <String>[];
  final _consumed = <String>{};
  RepairApi? _api;
  RepairJson? _case, _wallet, _topup;
  String? _error;
  Timer? _timer;
  bool _notice = false, _busy = false, _stopped = false, _beating = false;
  bool _preview = false, _writeMayHaveRun = false;

  String? get _id => _case?['case_id'] as String?;
  String? get _status => _case?['status'] as String?;
  bool get _inProgress => _id != null && !terminal.contains(_status);
  String get _casePath => '/cases/$_id';

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    if (!_stopped) _cancelNative();
    _stopped = true;
    final api = _api;
    if (api != null) {
      unawaited(() async {
        try {
          if (_inProgress) {
            await api.post('$_casePath/finish', {'outcome': 'stop'});
          }
        } catch (_) {
          // Không có heartbeat thì máy chủ tự đóng lượt.
        } finally {
          api.close();
        }
      }());
    }
    super.dispose();
  }

  void _cancelNative() => unawaited(
      repairChannel.invokeMethod<void>('cancel').catchError((Object _) {}));

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _stopped) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on RepairException catch (error) {
      if (mounted && !_stopped) setState(() => _error = error.message);
    } catch (_) {
      if (mounted && !_stopped) {
        setState(() => _error =
            'Không nhận được kết quả hợp lệ từ máy chủ thử. Không chạy lại thao tác.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(RepairJson next) {
    if (!mounted || _stopped) return;
    setState(() {
      _case = next;
      _wallet = repairMap(next['wallet']);
    });
    if (active.contains(_status)) {
      _timer ??=
          Timer.periodic(const Duration(seconds: 4), (_) => _heartbeat());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _heartbeat() async {
    if (_beating || _stopped || !active.contains(_status)) return;
    _beating = true;
    final path = _casePath;
    try {
      if (await widget.hasRemoteClient()) {
        await _stop();
      } else if (!_stopped) {
        await _api!.post('$path/heartbeat',
            {'client_state': 'console', 'policy_rev': repairPolicy});
      }
    } catch (_) {
      if (mounted &&
          _casePath == path &&
          !_stopped &&
          active.contains(_status)) {
        await _stop();
      }
    } finally {
      _beating = false;
    }
  }

  Future<void> _requireConsole() async {
    if (_stopped ||
        await widget.hasRemoteClient() ||
        await repairChannel.invokeMethod<bool>('eligible') != true ||
        _stopped) {
      throw const RepairException(
          'Hãy mở khóa máy, ngắt phiên điều khiển từ xa và dừng dịch vụ Mecha Remote trước khi thử.');
    }
  }

  Future<void> _connect() async {
    await _requireConsole();
    final api = RepairApi(repairBase);
    try {
      await api.login();
      final wallet = await api.get('/wallet');
      if (!mounted || _stopped) {
        api.close();
        return;
      }
      setState(() {
        _api = api;
        _wallet = wallet;
      });
    } catch (_) {
      api.close();
      rethrow;
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    final demoDescription = repairDemoDescription(text);
    await _requireConsole();
    final starting = !_inProgress;
    final next = await _api!.post(starting ? '/cases' : '$_casePath/messages',
        {'text': demoDescription, if (starting) 'notice_version': 'demo/1'});
    if (!mounted || _stopped) return;
    if (starting) {
      _questions.clear();
      _consumed.clear();
      _preview = false;
      _writeMayHaveRun = false;
    }
    _questions.add('Bạn: Đã gửi mô tả.');
    if (next['question'] is String) {
      _questions.add('Mecha: ${next['question']}');
    }
    _show(next);
  }

  Future<void> _accept(Map quote) async {
    await _requireConsole();
    _show(
        await _api!.post('$_casePath/accept', {'quote_id': quote['quote_id']}));
  }

  Future<void> _step(Map step, bool requestConsent) async {
    await _requireConsole();
    final api = _api!;
    final id = _id!;
    final offer =
        RepairOffer.parse(repairMap(step), id, api.device, repairNow());
    if (_consumed.contains(offer.id)) {
      throw const RepairException(
          'Bước đã gửi; hãy cập nhật trạng thái thay vì chạy lại.');
    }
    final path = '$_casePath/steps/${offer.id}';
    try {
      final allowed = requestConsent &&
          await repairChannel.invokeMethod<bool>('approve', offer.native) ==
              true;
      if (_stopped || !mounted) return;
      if (allowed) await _requireConsole();
      final decision = await api.post(
          '$path/decision', {'allow': allowed, 'payload_hash': offer.hash});
      if (_stopped || !mounted) return;
      if (!allowed) {
        _show(repairMap(decision['case']));
        return;
      }
      final permit = await offer.verifyPermit(
          decision['permit'], api.publicKey!, id, api.device, repairNow());
      await _requireConsole();
      if (repairNow() >= permit.expires) {
        throw const RepairException(
            'Phiếu thao tác đã hết hạn. Không chạy lại.');
      }
      if (_stopped || !mounted || !_consumed.add(offer.id)) return;
      final body = <String, dynamic>{
        'permit_id': permit.id,
        'outcome': 'completed'
      };
      try {
        if (offer.code == 'screen.share_preview_mock' &&
            (!_preview || offer.args['preview_hash'] != repairPreviewHash)) {
          throw PlatformException(code: 'blocked');
        }
        if (offer.code == 'audio.set_mute' ||
            offer.code == 'audio.set_volume') {
          _writeMayHaveRun = true;
        }
        final result = await repairChannel.invokeMapMethod<String, dynamic>(
            'execute', offer.native);
        body['typed_result'] = switch (offer.code) {
          'events.read_summary' => {'synthetic': true, 'count': 2},
          'screen.capture_window_mock' || 'screen.share_preview_mock' => {
              'preview_hash': repairPreviewHash
            },
          _ => repairMap(result),
        };
      } on PlatformException catch (error) {
        body['outcome'] = error.code == 'blocked' ? 'blocked' : 'unknown';
      } catch (_) {
        body['outcome'] = 'unknown';
      }
      if (_stopped || !mounted) return;
      if (offer.code == 'screen.capture_window_mock' &&
          body['outcome'] == 'completed') {
        _preview = true;
      }
      _show(await api.post('$path/result', body));
    } finally {
      _cancelNative();
    }
  }

  Future<void> _finish(String value) async {
    await _requireConsole();
    _show(await _api!.post('$_casePath/finish', {'outcome': value}));
  }

  Future<void> _stop() async {
    if (_stopped || !mounted) return;
    setState(() {
      _stopped = true;
      _error = null;
    });
    _timer?.cancel();
    _cancelNative();
    final api = _api;
    if (api != null && _inProgress) {
      try {
        final next = await api.post('$_casePath/finish', {'outcome': 'stop'});
        if (mounted) setState(() => _case = next);
      } catch (_) {
        if (mounted) {
          setState(() => _error =
              'Máy chủ chưa xác nhận đã dừng. Khoản giữ chưa chốt sẽ hết hạn tự động.');
        }
      }
    }
  }

  Future<void> _createTopup() async {
    await _requireConsole();
    final topup = await _api!.post('/wallet/topups', {'amount_vnd': 50000});
    if (mounted && !_stopped) setState(() => _topup = topup);
  }

  Future<void> _applyTopup() async {
    await _requireConsole();
    final api = _api!;
    final topup =
        await api.post('/demo/bank', {'topup_id': _topup!['topup_id']});
    final wallet = await api.get('/wallet');
    if (mounted && !_stopped) {
      setState(() {
        _topup = topup;
        _wallet = wallet;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _case?['quote'];
    final step = _case?['step'];
    final isChat = !_inProgress || _status == 'clarifying';
    final controls = !_busy && !_stopped;
    final audit = _case?['audit'];
    final topup = _topup;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sửa máy tính AI · Bản thử'),
        actions: [
          TextButton.icon(
            onPressed: _stopped ? null : _stop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Dừng ngay'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
              'Chỉ dùng tại máy Windows này. Không gửi mật khẩu, OTP hoặc dữ liệu riêng. Không chuyển tiền thật.'),
          if (_error != null) Text(_error!),
          if (_busy) const LinearProgressIndicator(),
          if (_stopped)
            const Text(
                'Đã chặn thao tác mới trên máy này. Đóng trang để thoát bản thử.')
          else if (_api == null) ...[
            CheckboxListTile(
              value: _notice,
              title: const Text(
                  'Tôi đồng ý gửi loại lỗi và các chỉ số đã cho phép đến máy chủ thử trên máy này. Nội dung gõ không được gửi đi.'),
              onChanged: controls
                  ? (value) => setState(() => _notice = value == true)
                  : null,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: controls && _notice ? () => _run(_connect) : null,
                child: const Text('Mở phiên thử'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text('Ví giả · Khả dụng: ${repairVnd(_wallet?['available_vnd'])}'
                ' · Đang giữ: ${repairVnd(_wallet?['held_vnd'])}'),
            Wrap(spacing: 8, children: [
              OutlinedButton(
                onPressed: controls ? () => _run(_createTopup) : null,
                child: const Text('Tạo nạp ví giả'),
              ),
              if (topup?['status'] == 'pending')
                OutlinedButton(
                  onPressed: controls ? () => _run(_applyTopup) : null,
                  child: const Text('Giả lập chuyển khoản'),
                ),
              if (_id != null)
                TextButton(
                  onPressed: controls
                      ? () =>
                          _run(() async => _show(await _api!.get(_casePath)))
                      : null,
                  child: const Text('Cập nhật trạng thái'),
                ),
            ]),
            if (topup != null)
              Text('Nạp thử: ${topup['transfer_content'] ?? ''} · '
                  '${topup['status'] == 'credited' ? 'Đã ghi có giả' : 'Chưa ghi có'}'),
            if (topup?['status'] == 'pending' && topup?['qr_payload'] is String)
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  children: [
                    const Text('VietQR thử · Không quét để chuyển tiền'),
                    QrImageView(
                        data: topup!['qr_payload'],
                        size: 132,
                        backgroundColor: Colors.white),
                  ],
                ),
              ),
            const Divider(),
            const Text('Hội thoại hỗ trợ',
                style: TextStyle(fontWeight: FontWeight.bold)),
            for (final question in _questions) Text(question),
            if (_case?['message'] case final String status) Text(status),
            if (_case?['advice'] case final String advice) Text(advice),
            if (isChat) ...[
              TextField(
                controller: _text,
                enabled: controls,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Mô tả lỗi bằng tiếng Việt',
                  hintText: 'Ví dụ: Loa bị tắt tiếng',
                ),
                onSubmitted: (_) => _run(_send),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: controls ? () => _run(_send) : null,
                  child: const Text('Gửi mô tả'),
                ),
              ),
            ],
            if (quote is Map) ...[
              Text(
                  'Cấp thợ ${quote['tier']} · Báo giá thử ${repairVnd(quote['amount_vnd'])}'),
              Text('Tiêu chí thu ví giả: ${quote['success_check']}'),
              Wrap(spacing: 8, children: [
                FilledButton(
                  onPressed: controls ? () => _run(() => _accept(quote)) : null,
                  child: const Text('Đồng ý giữ trong ví giả'),
                ),
                TextButton(
                    onPressed: controls ? _stop : null,
                    child: const Text('Không đồng ý')),
              ]),
            ],
            if (step is Map) ...[
              const Divider(),
              Text(
                  'Bước đề xuất: ${repairActions[step['code']] ?? 'Không được hỗ trợ'}'),
              if (step['code'] == 'screen.share_preview_mock' && _preview)
                const Text(
                    'Bản mẫu trên máy (không phải ảnh thật): $repairPreview'),
              Wrap(spacing: 8, children: [
                FilledButton(
                  onPressed:
                      controls ? () => _run(() => _step(step, true)) : null,
                  child: const Text('Xem yêu cầu cho phép'),
                ),
                TextButton(
                  onPressed:
                      controls ? () => _run(() => _step(step, false)) : null,
                  child: const Text('Từ chối bước này'),
                ),
              ]),
            ],
            if (_status == 'awaiting_confirmation')
              Wrap(spacing: 8, children: [
                FilledButton(
                  onPressed:
                      controls ? () => _run(() => _finish('resolved')) : null,
                  child: const Text('Tôi đã nghe được'),
                ),
                TextButton(
                  onPressed:
                      controls ? () => _run(() => _finish('unresolved')) : null,
                  child: const Text('Vẫn chưa nghe được'),
                ),
              ]),
          ],
          if (_writeMayHaveRun &&
              (_stopped ||
                  _error != null ||
                  terminal.contains(_status) && _status != 'succeeded'))
            const Text(
                'Loa có thể đã đổi. Kiểm tra hoặc khôi phục thủ công trong Cài đặt > Hệ thống > Âm thanh.'),
          if (audit is List && audit.isNotEmpty)
            ExpansionTile(
              title: const Text('Nhật ký lượt thử'),
              children: [
                for (final entry in audit.whereType<Map>())
                  ListTile(
                    title: Text(entry['message'] as String? ?? 'Thao tác'),
                    subtitle: Text(auditLabels[entry['status']] ?? 'Chưa rõ'),
                  ),
              ],
            ),
          ExpansionTile(
            title: const Text('Danh mục thao tác được phép'),
            children: [
              for (final label in repairActions.values)
                ListTile(title: Text(label))
            ],
          ),
        ],
      ),
    );
  }
}
