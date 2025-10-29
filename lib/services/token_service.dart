import 'package:flutter_secure_storage/flutter_secure_storage.dart';


/// 使用系统KeyStore加密存储token，提高安全性
class TokenService {
  static const _storage = FlutterSecureStorage();
  
  // Android配置：使用加密的KeyStore
  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );
  
  // iOS配置：使用Keychain
  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  
  // 存储密钥
  static const String _keyToken = 'jwt_token';
  static const String _keyEmail = 'user_email';
  static const String _keyUsername = 'user_username';
  static const String _keyAvatar = 'user_avatar';
  
  /// 保存Token
  static Future<void> saveToken(String token) async {
    try {
      await _storage.write(
        key: _keyToken,
        value: token,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
      print('✅ Token已加密存储');
    } catch (e) {
      print('❌ Token存储失败: $e');
      rethrow;
    }
  }
  
  /// 获取Token
  static Future<String?> getToken() async {
    try {
      final token = await _storage.read(
        key: _keyToken,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
      return token;
    } catch (e) {
      print('❌ Token读取失败: $e');
      return null;
    }
  }
  
  /// 保存用户信息
  static Future<void> saveUserInfo({
    required String email,
    required String username,
    String? avatar,
  }) async {
    try {
      await Future.wait([
        _storage.write(
          key: _keyEmail,
          value: email,
          aOptions: _androidOptions,
          iOptions: _iosOptions,
        ),
        _storage.write(
          key: _keyUsername,
          value: username,
          aOptions: _androidOptions,
          iOptions: _iosOptions,
        ),
        if (avatar != null)
          _storage.write(
            key: _keyAvatar,
            value: avatar,
            aOptions: _androidOptions,
            iOptions: _iosOptions,
          ),
      ]);
      print('✅ 用户信息已加密存储');
    } catch (e) {
      print('❌ 用户信息存储失败: $e');
      rethrow;
    }
  }
  
  /// 获取用户信息
  static Future<Map<String, String?>> getUserInfo() async {
    try {
      final values = await Future.wait([
        _storage.read(key: _keyEmail, aOptions: _androidOptions, iOptions: _iosOptions),
        _storage.read(key: _keyUsername, aOptions: _androidOptions, iOptions: _iosOptions),
        _storage.read(key: _keyAvatar, aOptions: _androidOptions, iOptions: _iosOptions),
      ]);
      
      return {
        'email': values[0],
        'username': values[1],
        'avatar': values[2],
      };
    } catch (e) {
      print('❌ 用户信息读取失败: $e');
      return {'email': null, 'username': null, 'avatar': null};
    }
  }
  
  /// 删除Token
  static Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _keyToken, aOptions: _androidOptions, iOptions: _iosOptions);
      print('✅ Token已删除');
    } catch (e) {
      print('❌ Token删除失败: $e');
    }
  }
  
  /// 清除所有登录数据
  static Future<void> clearAll() async {
    try {
      await Future.wait([
        _storage.delete(key: _keyToken, aOptions: _androidOptions, iOptions: _iosOptions),
        _storage.delete(key: _keyEmail, aOptions: _androidOptions, iOptions: _iosOptions),
        _storage.delete(key: _keyUsername, aOptions: _androidOptions, iOptions: _iosOptions),
        _storage.delete(key: _keyAvatar, aOptions: _androidOptions, iOptions: _iosOptions),
      ]);
      print('✅ 所有登录数据已清除');
    } catch (e) {
      print('❌ 清除登录数据失败: $e');
      rethrow;
    }
  }
  
  /// 检查Token是否存在
  static Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}

