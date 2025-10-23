import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkUtils {
  static Future<bool> isNetworkAvailable() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }
      
      // 尝试连接到一个可靠的服务器来验证网络连接
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> isServerReachable(String serverUrl) async {
    try {
      final uri = Uri.parse(serverUrl);
      final socket = await Socket.connect(uri.host, uri.port, timeout: Duration(seconds: 5));
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  static String getNetworkErrorMessage(dynamic error) {
    if (error is SocketException) {
      if (error.message.contains('Connection reset by peer')) {
        return '服务器连接被重置，请稍后重试';
      } else if (error.message.contains('Connection refused')) {
        return '无法连接到服务器，请检查网络设置';
      } else if (error.message.contains('Network is unreachable')) {
        return '网络不可达，请检查网络连接';
      } else {
        return '网络连接异常，请检查网络设置';
      }
    } else if (error is HttpException) {
      return 'HTTP请求异常，请稍后重试';
    } else if (error is TimeoutException) {
      return '请求超时，请检查网络连接';
    } else {
      return '网络异常: $error';
    }
  }

  static Future<void> waitForNetworkConnection() async {
    while (!await isNetworkAvailable()) {
      await Future.delayed(Duration(seconds: 2));
    }
  }
} 