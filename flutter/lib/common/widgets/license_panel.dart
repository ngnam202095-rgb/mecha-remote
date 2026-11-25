import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../license.dart';

class LicensePanel extends StatefulWidget {
  final String Function() read;
  final Future<void> Function(String) save;
  final Future<String> Function() deviceId;
  final String deviceName;
  final LicenseApi? api;

  const LicensePanel({
    super.key,
    required this.read,
    required this.save,
    required this.deviceId,
    required this.deviceName,
    this.api,
  });

  @override
  State<LicensePanel> createState() => _LicensePanelState();
}

class _LicensePanelState extends State<LicensePanel> {
  final _key = TextEditingController();
  final _client = http.Client();
  late LicenseStatus? _status = LicenseStatus.read(widget.read());
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _client.close();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool deactivate}) async {
    if (_busy) return;
    final key = deactivate ? _status?.key ?? '' : _key.text.trim();
    if (key.isEmpty) {
      setState(() => _notice = 'Hãy nhập mã bản quyền.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final api = widget.api ?? LicenseApi(_client);
    try {
      final id = await widget.deviceId();
      if (id.isEmpty) throw const LicenseFailure('Chưa lấy được mã thiết bị.');
      if (deactivate) {
        await api.deactivate(key, id);
        await widget.save('');
        _status = null;
      } else {
        final status = await api.activate(key, id, widget.deviceName);
        await widget.save(status.encode());
        _status = status;
      }
      if (mounted) _key.clear();
    } on LicenseFailure catch (error) {
      _notice = error.message;
    } catch (_) {
      _notice = 'Không thể cập nhật bản quyền. Hãy thử lại sau.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gói hiện tại: ${status?.label ?? 'Miễn phí'}',
              style: Theme.of(context).textTheme.titleMedium),
          if (status != null)
            Text('${status.active ? 'Hạn dùng' : 'Đã hết hạn'}: '
                '${DateFormat('dd/MM/yyyy HH:mm').format(status.expiry.toLocal())}'),
          const SizedBox(height: 16),
          if (status?.active != true) ...[
            TextField(
              controller: _key,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Mã bản quyền',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(deactivate: false),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () => _submit(deactivate: false),
              child: const Text('Kích hoạt'),
            ),
          ] else
            OutlinedButton(
              onPressed: _busy ? null : () => _submit(deactivate: true),
              child: const Text('Gỡ kích hoạt máy này'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_notice!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          const Text(
              'Kết nối từ xa vẫn dùng được khi máy chủ bản quyền không phản hồi.'),
        ],
      ),
    );
  }
}
