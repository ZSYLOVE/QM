import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenExpiredService {
  static final TokenExpiredService _instance = TokenExpiredService._internal();
  factory TokenExpiredService() => _instance;
  TokenExpiredService._internal();

  static TokenExpiredService get instance => _instance;

  // 检查响应是否包含Token过期错误
  bool isTokenExpired(Map<String, dynamic> response) {
    if (response.containsKey('code') && response['code'] == 'TOKEN_EXPIRED') {
      return true;
    }
    if (response.containsKey('error') && 
        response['error'].toString().contains('Token已过期')) {
      return true;
    }
    return false;
  }

  // 检查HTTP状态码和响应体
  bool isTokenExpiredFromResponse(int statusCode, String responseBody) {
    if (statusCode == 401) {
      try {
        final response = Map<String, dynamic>.from(
          Uri.parse('data:application/json,$responseBody').data?.contentAsBytes() != null 
            ? {} 
            : {}
        );
        return isTokenExpired(response);
      } catch (e) {
        // 如果解析失败，检查响应体是否包含Token过期信息
        return responseBody.contains('Token已过期') || 
               responseBody.contains('TOKEN_EXPIRED');
      }
    }
    return false;
  }

  // 显示Token过期对话框
  void showTokenExpiredDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('身份验证失败'),
            ],
          ),
          content: Text(
            '您的登录已过期，请重新登录以继续使用。',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // 清除本地存储的登录信息
                await _clearLoginData();
                
                // 关闭对话框
                Navigator.of(context).pop();
                
                // 跳转到登录页面
                Navigator.pushNamedAndRemoveUntil(
                  context, 
                  '/login', 
                  (route) => false
                );
              },
              child: Text(
                '重新登录',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // 清除登录数据
  Future<void> _clearLoginData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('email');
      await prefs.remove('username');
      await prefs.remove('avatar');
      print('✅ 已清除本地登录数据');
    } catch (e) {
      print('❌ 清除登录数据失败: $e');
    }
  }

  // 处理API响应，检查Token过期
  void handleApiResponse(BuildContext context, int statusCode, String responseBody) {
    if (isTokenExpiredFromResponse(statusCode, responseBody)) {
      print('🔒 检测到Token过期，显示重新登录对话框');
      showTokenExpiredDialog(context);
    }
  }

  // 处理API响应对象
  void handleApiResponseObject(BuildContext context, Map<String, dynamic> response) {
    if (isTokenExpired(response)) {
      print('🔒 检测到Token过期，显示重新登录对话框');
      showTokenExpiredDialog(context);
    }
  }
}
