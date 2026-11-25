import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_hbb/desktop/pages/repair_demo_api.dart';
import 'package:flutter_hbb/desktop/pages/repair_demo_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const now = 1800000000;

RepairJson payload({String code = 'audio.read'}) => {
      'case_id': 'case1',
      'step_id': 'step1',
      'device_ref': 'device1',
      'nonce': 'nonce1',
      'code': code,
      'args': <String, dynamic>{},
      'policy_rev': repairPolicy,
      'expires_epoch': now + 40,
    };

RepairJson signedOffer(RepairJson payload) => {
      ...payload,
      'payload_hash': sha256
          .convert(utf8.encode(jsonEncode(SplayTreeMap.of(payload))))
          .toString(),
    };

void main() {
  test('T04: changed, expired, foreign and unlisted offers are rejected', () {
    final valid = signedOffer(payload());
    expect(
        RepairOffer.parse(valid, 'case1', 'device1', now).code, 'audio.read');
    for (final altered in [
      {
        ...valid,
        'args': {'percent': 45}
      },
      {...valid, 'device_ref': 'other'},
      signedOffer(payload(code: 'shell')),
      signedOffer({...payload(), 'expires_epoch': now}),
    ]) {
      expect(() => RepairOffer.parse(altered, 'case1', 'device1', now),
          throwsFormatException);
    }
    expect(() => RepairOffer.parse(valid, 'case1', 'other', now),
        throwsFormatException);
  });

  test('T04/T07: only a signed, short-lived, bound permit passes', () async {
    final offer =
        RepairOffer.parse(signedOffer(payload()), 'case1', 'device1', now);
    final signing = Ed25519();
    final keyPair = await signing.newKeyPair();
    final publicKey =
        base64Url.encode((await keyPair.extractPublicKey()).bytes);
    final claims = {
      'permit_id': 'permit1',
      'expires_epoch': now + 8,
      'case_id': 'case1',
      'step_id': offer.id,
      'device_ref': 'device1',
      'policy_rev': repairPolicy,
      'payload_hash': offer.hash,
    };

    Future<String> token(RepairJson values) async {
      final raw = utf8.encode(jsonEncode(values));
      final signed = await signing.sign(raw, keyPair: keyPair);
      return '${base64Url.encode(raw)}.${base64Url.encode(signed.bytes)}';
    }

    final valid = await token(claims);
    expect(
        (await offer.verifyPermit(valid, publicKey, 'case1', 'device1', now))
            .id,
        'permit1');
    for (final invalid in [
      'tampered.valid',
      await token({...claims, 'expires_epoch': now}),
      await token({...claims, 'expires_epoch': now + 30}),
      await token({...claims, 'step_id': 'another'}),
      await token({...claims, 'device_ref': 'another'}),
    ]) {
      await expectLater(
          offer.verifyPermit(invalid, publicKey, 'case1', 'device1', now),
          throwsA(anything));
    }
  });

  test('T09: only a local HTTP demo endpoint is accepted', () {
    expect(() => RepairApi('http://192.0.2.1:8000'),
        throwsA(isA<RepairException>()));
    expect(() => RepairApi('http://127.0.0.1:8000/?test=1'),
        throwsA(isA<RepairException>()));
    RepairApi('http://127.0.0.1:8000').close();
  });

  test('T09: the demo never forwards a typed description', () {
    expect(repairDemoDescription('Loa tắt tiếng, email ten@example.invalid'),
        'Loa bị tắt tiếng');
    expect(repairDemoDescription('Ổ hệ thống gần đầy'), 'Ổ hệ thống gần đầy');
    expect(repairDemoDescription('Lỗi khác kèm thông tin cá nhân'),
        'Chưa rõ loại lỗi');
    expect(() => repairDemoDescription('OTP 123456'),
        throwsA(isA<RepairException>()));
  });

  testWidgets('Dừng ngay remains available before a demo session opens',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: RepairDemoPage(hasRemoteClient: () async => false)));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Mở phiên thử'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Dừng ngay'));
    await tester.pump();
    expect(
        find.text(
            'Đã chặn thao tác mới trên máy này. Đóng trang để thoát bản thử.'),
        findsOneWidget);
  });
}
