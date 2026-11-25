import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/platform_model.dart';
import '../brand.dart';
import '../license.dart';
import 'license_panel.dart';

const _licenseStatusKey = 'brand-license-status';

LicenseStatus? readBrandLicense() =>
    LicenseStatus.read(bind.mainGetLocalOption(key: _licenseStatusKey));

Widget buildBrandLicensePanel() => LicensePanel(
      read: () => bind.mainGetLocalOption(key: _licenseStatusKey),
      save: (value) =>
          bind.mainSetLocalOption(key: _licenseStatusKey, value: value),
      deviceId: () => bind.mainGetUuid(),
      deviceName: Platform.operatingSystem == 'android'
          ? 'Android'
          : Platform.localHostname,
    );

Widget buildBrandSourceCredit() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
            'Phát triển từ RustDesk · Bản quyền © Purslane Tech Pte. Ltd.'),
        const Text('Giấy phép: AGPL-3.0'),
        TextButton(
          onPressed: () => launchUrl(Uri.parse(brandSourceUrl.isEmpty
              ? 'https://github.com/rustdesk/rustdesk'
              : brandSourceUrl)),
          child: Text(brandSourceUrl.isEmpty
              ? 'Mã nguồn RustDesk gốc'
              : 'Mã nguồn của bản này'),
        ),
      ],
    );
