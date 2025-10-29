import 'dart:convert';
import 'package:onlin/services/token_service.dart';



/// 优先从内存读取，避免频繁I/O操作
class TokenManager {
  static final TokenManager _instance = TokenManager._internal();
  factory TokenManager() => _instance;
  TokenManager._internal();
  
  static TokenManager get instance => _instance;
  
  // 内存缓存
  String? _cachedToken;
  Map<String, String?>? _cachedUserInfo;
  bool _isInitialized = false;
  
  /// 初始化（应用启动时调用）
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // 从加密存储加载token到内存
      _cachedToken = await TokenService.getToken();
      _cachedUserInfo = await TokenService.getUserInfo();
      _isInitialized = true;
      print('✅ TokenManager已初始化');
    } catch (e) {
      print('❌ TokenManager初始化失败: $e');
    }
  }
  
  /// 获取Token（优先从内存读取）
  Future<String?> getToken() async {
    // 如果内存中有，直接返回
    if (_cachedToken != null) {
      return _cachedToken;
    }
    
    // 内存没有，从加密存储读取
    _cachedToken = await TokenService.getToken();
    return _cachedToken;
  }
  
  /// 保存Token（同时更新内存和存储）
  Future<void> saveToken(String token) async {
    // 更新内存缓存
    _cachedToken = token;
    
    // 保存到加密存储
    await TokenService.saveToken(token);
    
    print('✅ Token已保存（内存+加密存储）');
  }
  
  /// 保存用户信息（同时更新内存和存储）
  Future<void> saveUserInfo({
    required String email,
    required String username,
    String? avatar,
  }) async {
    // 更新内存缓存
    _cachedUserInfo = {
      'email': email,
      'username': username,
      'avatar': avatar,
    };
    
    // 保存到加密存储
    await TokenService.saveUserInfo(
      email: email,
      username: username,
      avatar: avatar,
    );
    
    print('✅ 用户信息已保存（内存+加密存储）');
  }
  
  /// 获取用户信息（优先从内存读取）
  Future<Map<String, String?>> getUserInfo() async {
    // 如果内存中有，直接返回
    if (_cachedUserInfo != null) {
      return _cachedUserInfo!;
    }
    
    // 内存没有，从加密存储读取
    _cachedUserInfo = await TokenService.getUserInfo();
    return _cachedUserInfo ?? {'email': null, 'username': null, 'avatar': null};
  }
  
  /// 清除Token（同步清除内存和存储）
  Future<void> clearToken() async {
    _cachedToken = null;
    await TokenService.deleteToken();
    print('✅ Token已清除（内存+加密存储）');
  }
  
  /// 清除所有登录数据（同步清除内存和存储）
  Future<void> clearAll() async {
    _cachedToken = null;
    _cachedUserInfo = null;
    await TokenService.clearAll();
    print('✅ 所有登录数据已清除（内存+加密存储）');
  }
  
  /// 检查Token是否存在
  Future<bool> hasToken() async {
    if (_cachedToken != null) {
      return true;
    }
    return await TokenService.hasToken();
  }
  
  /// 获取缓存的Token（不触发I/O）
  String? get cachedToken => _cachedToken;
  
  /// 解析JWT token获取过期时间（用于刷新机制）
  Map<String, dynamic>? parseJWT(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }
      
      // 解码payload（base64）
      final payload = parts[1];
      // 添加padding（base64解码需要）
      String normalizedPayload = payload.replaceAll('-', '+').replaceAll('_', '/');
      switch (normalizedPayload.length % 4) {
        case 1:
          normalizedPayload += '===';
          break;
        case 2:
          normalizedPayload += '==';
          break;
        case 3:
          normalizedPayload += '=';
          break;
      }
      
      final decoded = utf8.decode(base64.decode(normalizedPayload));
      return json.decode(decoded) as Map<String, dynamic>;
    } catch (e) {
      print('❌ JWT解析失败: $e');
      return null;
    }
  }
  
  /// 获取Token过期时间
  DateTime? getTokenExpiry(String token) {
    final payload = parseJWT(token);
    if (payload == null || payload['exp'] == null) {
      return null;
    }
    
    final exp = payload['exp'] as int;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  }
  
  /// 检查Token是否即将过期（5分钟内）
  bool isTokenExpiringSoon(String token) {
    final expiry = getTokenExpiry(token);
    if (expiry == null) {
      return false;
    }
    
    final now = DateTime.now();
    final timeUntilExpiry = expiry.difference(now);
    
    // 如果5分钟内过期，返回true
    return timeUntilExpiry.inMinutes < 5 && timeUntilExpiry.inMinutes > 0;
  }
  
  /// 检查Token是否已过期
  bool isTokenExpired(String token) {
    final expiry = getTokenExpiry(token);
    if (expiry == null) {
      return true; // 无法解析，视为过期
    }
    
    return DateTime.now().isAfter(expiry);
  }
}

