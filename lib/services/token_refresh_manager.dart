import 'dart:async';
import 'package:onlin/services/token_manager.dart';
import 'package:onlin/servers/api_service.dart';


/// 在token即将过期时自动刷新
class TokenRefreshManager {
  static final TokenRefreshManager _instance = TokenRefreshManager._internal();
  factory TokenRefreshManager() => _instance;
  TokenRefreshManager._internal();
  
  static TokenRefreshManager get instance => _instance;
  
  Timer? _refreshTimer;
  bool _isRunning = false;
  final ApiService _apiService = ApiService();
  
  /// 启动Token刷新机制
  /// [intervalMinutes] 检查间隔（分钟），默认25分钟
  void start({int intervalMinutes = 25}) {
    if (_isRunning) {
      print('⚠️ Token刷新管理器已在运行');
      return;
    }
    
    _isRunning = true;
    _refreshTimer?.cancel();
    
    // 立即检查一次
    _checkAndRefreshToken();
    
    // 定时检查
    _refreshTimer = Timer.periodic(Duration(minutes: intervalMinutes), (_) {
      _checkAndRefreshToken();
    });
    
    print('✅ Token自动刷新机制已启动（检查间隔: ${intervalMinutes}分钟）');
  }
  
  /// 停止Token刷新机制
  void stop() {
    _isRunning = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    print('🛑 Token自动刷新机制已停止');
  }
  
  /// 检查并刷新Token（如果需要）
  Future<void> _checkAndRefreshToken() async {
    try {
      final token = await TokenManager.instance.getToken();
      if (token == null) {
        print('⚠️ Token不存在，跳过刷新检查');
        return;
      }
      
      // 检查Token是否已过期
      if (TokenManager.instance.isTokenExpired(token)) {
        print('⚠️ Token已过期，尝试刷新');
        await _refreshToken();
        return;
      }
      
      // 检查Token是否即将过期（5分钟内）
      if (TokenManager.instance.isTokenExpiringSoon(token)) {
        print('🔄 Token即将过期，自动刷新');
        await _refreshToken();
        return;
      }
      
      // 验证Token有效性（可选，用于检测被撤销的token）
      final result = await _apiService.verifyToken();
      if (result?['valid'] != true) {
        print('⚠️ Token验证失败，尝试刷新');
        await _refreshToken();
        return;
      }
      
      final expiry = TokenManager.instance.getTokenExpiry(token);
      if (expiry != null) {
        final timeUntilExpiry = expiry.difference(DateTime.now());
        print('✅ Token有效，剩余时间: ${timeUntilExpiry.inMinutes}分钟');
      }
    } catch (e) {
      print('❌ Token刷新检查失败: $e');
    }
  }
  
  /// 刷新Token
  Future<bool> _refreshToken() async {
    try {
      print('🔄 开始刷新Token...');
      
      // 获取当前用户信息
      final userInfo = await TokenManager.instance.getUserInfo();
      final email = userInfo['email'];
      
      if (email == null || email.isEmpty) {
        print('❌ 无法刷新Token: 用户邮箱不存在');
        return false;
      }
      
      // 调用刷新接口
      final result = await _apiService.refreshToken();
      
      if (result != null && result['success'] == true && result['token'] != null) {
        // 保存新Token
        await TokenManager.instance.saveToken(result['token']);
        print('✅ Token刷新成功');
        return true;
      } else {
        print('❌ Token刷新失败: ${result?['error'] ?? '未知错误'}');
        return false;
      }
    } catch (e) {
      print('❌ Token刷新异常: $e');
      return false;
    }
  }
  
  /// 手动触发刷新
  Future<bool> refreshNow() async {
    return await _refreshToken();
  }
  
  /// 检查是否正在运行
  bool get isRunning => _isRunning;
}

