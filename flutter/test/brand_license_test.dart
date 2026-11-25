import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/license.dart';
import 'package:flutter_hbb/common/widgets/license_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  test('local license API follows the shared contract', () async {
    final server = await Process.start(
      Platform.isWindows ? 'python' : 'python3',
      ['../mock/license_server.py', '--port', '0'],
    );
    addTearDown(() => server.kill());
    final base = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final client = IOClient(_RealHttpOverrides().createHttpClient(null));
    addTearDown(client.close);
    final api = LicenseApi(client, baseUrl: base);
    final status =
        await api.activate('MECHA-DEMO-PRO', 'demo-device', 'Máy thử');
    expect(status.label, 'Pro');
    expect(LicenseStatus.read(status.encode())?.label, 'Pro');
    for (final (key, reason) in [
      ('MECHA-DEMO-FULL', 'hết lượt'),
      ('MECHA-DEMO-EXPIRED', 'hết hạn'),
      ('MECHA-DEMO-INVALID', 'không đúng')
    ]) {
      await expectLater(
        api.activate(key, 'demo-device', 'Máy thử'),
        throwsA(isA<LicenseFailure>()
            .having((error) => error.message, 'message', contains(reason))),
      );
    }
    await api.deactivate(status.key, 'demo-device');
    server.kill();
    await server.exitCode;
    await expectLater(
      api.activate(status.key, 'demo-device', 'Máy thử'),
      throwsA(isA<LicenseFailure>().having(
          (error) => error.message, 'message', contains('Không thể kết nối'))),
    );
  });

  test('Free cannot add a sixth device; expiry restores the limit', () {
    expect(addressBookCanAdd(4, null), true);
    expect(addressBookCanAdd(5, null), false);
    expect(
        addressBookCanAdd(5, LicenseStatus('fake', 'pro', DateTime.utc(2100))),
        true);
    expect(
        addressBookCanAdd(5, LicenseStatus('fake', 'pro', DateTime.utc(2000))),
        false);
  });

  testWidgets('license panel activates, persists and releases the device',
      (tester) async {
    var stored = '';
    final client = MockClient((request) async {
      final body = jsonDecode(request.body);
      expect(request.method, 'POST');
      expect(body['license_key'], 'MECHA-DEMO-PRO');
      expect(body['device_id'], 'demo-device');
      if (request.url.path == '/api/licenses/activate') {
        expect(body['device_name'], 'Máy thử');
        return http.Response(
            '{"ok":true,"plan":"pro","expires_at":"2099-04-30T00:00:00Z"}',
            200);
      }
      expect(request.url.path, '/api/licenses/deactivate');
      expect(body.containsKey('device_name'), false);
      return http.Response('{"ok":true}', 200);
    });
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: LicensePanel(
        read: () => stored,
        save: (value) async => stored = value,
        deviceId: () async => 'demo-device',
        deviceName: 'Máy thử',
        api: LicenseApi(client),
      )),
    ));
    expect(find.text('Gói hiện tại: Miễn phí'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'MECHA-DEMO-PRO');
    await tester.tap(find.text('Kích hoạt'));
    await tester.pumpAndSettle();
    expect(find.text('Gói hiện tại: Pro'), findsOneWidget);
    expect(find.textContaining('Hạn dùng:'), findsOneWidget);
    expect(LicenseStatus.read(stored)?.plan, 'pro');
    await tester.tap(find.text('Gỡ kích hoạt máy này'));
    await tester.pumpAndSettle();
    expect(find.text('Gói hiện tại: Miễn phí'), findsOneWidget);
    expect(stored, isEmpty);
  });
}
