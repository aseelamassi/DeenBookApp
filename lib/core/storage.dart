import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class Storage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceStorage implements Storage {
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class PendingOperation {
  PendingOperation(this.storage, this.shopId);
  final Storage storage;
  final String shopId;
  String get key => 'pending.$shopId';
  Future<Map<String, dynamic>?> read() async {
    final s = await storage.read(key);
    return s == null ? null : Map<String, dynamic>.from(jsonDecode(s));
  }

  Future<void> save(Map<String, dynamic> value) =>
      storage.write(key, jsonEncode(value));
  Future<void> clear() => storage.delete(key);
}
