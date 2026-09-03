import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


class AccountLockLocalDatasource {
  AccountLockLocalDatasource({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _secureStorage;
  static const _keyPrefix = 'account_lock_';
  static const _sep = '::';

  String _keyFor(String accountId) => '$_keyPrefix$accountId';

  Future<Set<String>> getLockedAccounts() async {
    final all = await _secureStorage.readAll();
    return all.keys
        .where((key) => key.startsWith(_keyPrefix))
        .map((key) => key.substring(_keyPrefix.length))
        .toSet();
  }

  Future<bool> hasPassword(String accountId) async {
    return (await _secureStorage.read(key: _keyFor(accountId))) != null;
  }

  Future<void> setPassword(String accountId, String password) async {
    final salt = _generateSalt();
    final hashedPassword = _hashPassword(password, salt);
    await _secureStorage.write(
      key: _keyFor(accountId),
      value: '$salt$_sep$hashedPassword',
    );
  }

  Future<void> removePassword(String accountId) async {
    await _secureStorage.delete(key: _keyFor(accountId));
  }

  Future<bool> verifyPassword(String accountId, String password) async {
    final stored = await _secureStorage.read(key: _keyFor(accountId));
    if (stored == null) return true; // No password set, so "correct" by default.

    final parts = stored.split(_sep);
    if (parts.length != 2) return false; // Corrupted data.

    final salt = parts[0];
    final storedHash = parts[1];
    final inputHash = _hashPassword(password, salt);

    return storedHash == inputHash;
  }

  String _generateSalt() {
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(saltBytes);
  }

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt$password');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}