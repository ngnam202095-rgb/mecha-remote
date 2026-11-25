import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import '../brand.dart';
import '../formatter/id_formatter.dart';
import '../license.dart';
import 'brand_settings.dart';

const _localBookKey = 'brand-address-book';

class BrandAddressBook extends StatefulWidget {
  const BrandAddressBook({super.key});

  @override
  State<BrandAddressBook> createState() => _BrandAddressBookState();
}

class _BrandAddressBookState extends State<BrandAddressBook> {
  final _id = IDTextEditingController();
  final _devices = <String>[];
  bool _saving = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final data = bind.mainGetLocalOption(key: _localBookKey);
    if (data.isEmpty) return;
    try {
      _devices.addAll((jsonDecode(data) as List).whereType<String>().toSet());
    } on FormatException {
      _notice = 'Không đọc được danh bạ trên máy này.';
    } on TypeError {
      _notice = 'Không đọc được danh bạ trên máy này.';
    }
  }

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _save(List<String> devices) async {
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await bind.mainSetLocalOption(
          key: _localBookKey, value: jsonEncode(devices));
      if (!mounted) return;
      _devices
        ..clear()
        ..addAll(devices);
      _id.clear();
    } catch (_) {
      _notice = 'Không thể lưu danh bạ. Hãy thử lại.';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _add() {
    if (_saving) return;
    final id = _id.id;
    if (!RegExp(r'^[0-9]{9}$').hasMatch(id)) {
      setState(() => _notice = 'Hãy nhập ID gồm 9 chữ số.');
    } else if (_devices.contains(id)) {
      setState(() => _notice = 'Thiết bị này đã có trong danh bạ.');
    } else if (!addressBookCanAdd(_devices.length, readBrandLicense())) {
      setState(() => _notice =
          'Gói miễn phí lưu tối đa $brandFreeAddressBookMax thiết bị. '
              'Hãy nâng cấp trong Cài đặt → Bản quyền để thêm thiết bị.');
    } else {
      _save([..._devices, id]);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _id,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\s]')),
                      IDTextInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'ID thiết bị',
                      hintText: '123 456 789',
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _add,
                  child: const Text('Thêm thiết bị'),
                ),
              ],
            ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_notice!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: _devices.isEmpty
                  ? const Center(
                      child: Text('Chưa lưu thiết bị nào trên máy này.'))
                  : ListView(
                      children: [
                        for (final id in _devices)
                          ListTile(
                            title: Text(formatID(id)),
                            leading: const Icon(Icons.devices_outlined),
                            onTap: () => connect(context, id),
                            trailing: IconButton(
                              tooltip: 'Xóa thiết bị',
                              onPressed: _saving
                                  ? null
                                  : () => _save(_devices
                                      .where((item) => item != id)
                                      .toList()),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      );
}
