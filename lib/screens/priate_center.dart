import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:onlin/screens/change_password_screen.dart';
import 'package:onlin/servers/api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

class PrivateCenterScreen extends StatefulWidget {
  const PrivateCenterScreen({super.key});

  @override
  State<PrivateCenterScreen> createState() => _PrivateCenterScreenState();
}

class _PrivateCenterScreenState extends State<PrivateCenterScreen> {
  String? currentUserEmail;
  String? currentUserAvatar;
  String? currentUsername;
  bool isFingerprintEnabled = false;
  BuildContext? _currentContext;
  final LocalAuthentication auth = LocalAuthentication();
  ApiService apiService = ApiService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentContext = context;
  }

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserEmail = prefs.getString('email');
      currentUsername = prefs.getString('username') ?? '用户';
      currentUserAvatar = prefs.getString('avatar');
      isFingerprintEnabled = prefs.getBool('fingerprint_enabled') ?? false;
    });
    
    print('🔍 个人中心数据 | Email: $currentUserEmail | 用户名: $currentUsername | 头像: $currentUserAvatar');
  }

  // 显示大头像
  void _showLargeAvatar(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        width: MediaQuery.of(context).size.width,
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue[200],
              backgroundImage: currentUserAvatar != null && currentUserAvatar!.isNotEmpty
                  ? NetworkImage(currentUserAvatar!)
                  : null,
              radius: 80,
              child: currentUserAvatar == null || currentUserAvatar!.isEmpty
                  ? Text(
                      _getAvatarText(),
                      style: TextStyle(
                        fontSize: 40,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            SizedBox(height: 20),
            Text(
              currentUsername ?? '用户',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              currentUserEmail ?? '未知邮箱',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 获取头像文字
  String _getAvatarText() {
    if (currentUsername == null || currentUsername!.isEmpty) return "?";
    return currentUsername!.trim().characters.first.toUpperCase();
  }

  // 指纹验证相关方法
  Future<bool> _askForFingerprint() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool('fingerprint_enabled') == true) {
      final action = await showDialog<bool>(
        context: _currentContext!,
        builder: (context) => AlertDialog(
          title: Text('关闭指纹验证'),
          content: Text('是否关闭指纹登录？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('否'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('是'),
            ),
          ],
        ),
      );

      if (action == true) {
        bool authenticated = await _authenticate();
        if (authenticated) {
          await prefs.setBool('fingerprint_enabled', false);
          if (!mounted) return true;
          setState(() {
            isFingerprintEnabled = false;
          });
          if (_currentContext != null && mounted) {
            ScaffoldMessenger.of(_currentContext!).showSnackBar(
              SnackBar(content: Text('指纹验证已关闭')),
            );
          }
          return true;
        } else {
          if (_currentContext != null && mounted) {
            ScaffoldMessenger.of(_currentContext!).showSnackBar(
              SnackBar(content: Text('指纹验证失败')),
            );
          }
          return false;
        }
      }
      return false;
    }

    final action = await showDialog<bool>(
      context: _currentContext!,
      builder: (context) => AlertDialog(
        title: Text('启用指纹登录'),
        content: Text('是否启用指纹认证？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('否'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('是'),
          ),
        ],
      ),
    );

    if (action != true) {
      return false;
    }

    bool isAuthenticat = await _authenticate();
    if (isAuthenticat == true) {
      await prefs.setBool('fingerprint_enabled', true);
      if (!mounted) return true;
      setState(() {
        isFingerprintEnabled = true;
      });
      if (_currentContext != null && mounted) {
        ScaffoldMessenger.of(_currentContext!).showSnackBar(
          SnackBar(content: Text('指纹验证已启用')),
        );
      }
      return true;
    } else {
      if (_currentContext != null && mounted) {
        ScaffoldMessenger.of(_currentContext!).showSnackBar(
          SnackBar(content: Text('指纹验证失败')),
        );
      }
      return false;
    }
  }

  Future<bool> _authenticate() async {
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: '请验证您的指纹以继续',
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );

      if (!authenticated) {
        if (_currentContext != null && mounted) {
          ScaffoldMessenger.of(_currentContext!).showSnackBar(
            SnackBar(content: Text('指纹验证失败')),
          );
        }
        if (!mounted) return false;
        Navigator.pushNamedAndRemoveUntil(_currentContext!, '/login', (route) => false);
      }

      return authenticated;
    } catch (e) {
      print(e);
      if (_currentContext != null && mounted) {
        ScaffoldMessenger.of(_currentContext!).showSnackBar(
          SnackBar(content: Text('指纹验证失败')),
        );
      }
      return false;
    }
  }

  // 头像修改界面
  void _updateAvatar() {
    final avatarUrlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改头像'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: avatarUrlController,
              decoration: InputDecoration(
                labelText: '头像URL',
                hintText: '输入新的头像链接',
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final newAvatarUrl = avatarUrlController.text.trim();
                if (newAvatarUrl.isNotEmpty) {
                  try {
                    final response = await apiService.updateAvatar(newAvatarUrl, currentUserEmail!);
                    if (response['success'] == true) {
                      setState(() {
                        currentUserAvatar = newAvatarUrl;
                      });
                      SharedPreferences prefs = await SharedPreferences.getInstance();
                      await prefs.setString('avatar', newAvatarUrl);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('头像更新成功')),
                      );
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('头像更新失败: 服务器返回空响应')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('头像更新失败: $e')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('请输入有效的头像URL')),
                  );
                }
              },
              child: Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  // 退出登录
  void _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认退出登录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await clearAllData();
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
    }
  }

  // 清理数据相关方法
  Future<bool> clearFiles() async {
    try {
      if (!kIsWeb) {
        Directory appDocDir = await getApplicationDocumentsDirectory();
        Directory directory = Directory(appDocDir.path);
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
      print("All files have been cleared.");
      return true;
    } catch (e) {
      print('Error clearing files: $e');
      return false;
    }
  }

  Future<bool> clearSharedPreferences() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('email');
      await prefs.remove('username');
      await prefs.remove('avatar');
      print("SharedPreferences cleared.");
      return true;
    } catch (e) {
      print('Error clearing SharedPreferences: $e');
      return false;
    }
  }

  Future<bool> clearCache() async {
    try {
      var cacheManager = DefaultCacheManager();
      await cacheManager.emptyCache();
      print("Cache has been cleared.");
      return true;
    } catch (e) {
      print('Error clearing cache: $e');
      return false;
    }
  }

  Future<void> clearAllData() async {
    bool filesCleared = await clearFiles();
    bool cacheCleared = await clearCache();
    bool sharedPreferencesCleared = await clearSharedPreferences();

    if (filesCleared && cacheCleared && sharedPreferencesCleared) {
      print('All data cleared successfully.');
    } else {
      print('Some data could not be cleared.');
    }
  }

  // 构建功能按钮
  Widget _buildProfileButton(IconData icon, String text, VoidCallback onPressed) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[50],
          foregroundColor: Colors.blue,
          elevation: 2,
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24),
            SizedBox(width: 16),
            Text(
              text,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            Spacer(),
            Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 201, 230, 244),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 201, 230, 244),
          ),
        ),
        title: Text(
          '个人中心',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
      body: Container(
        
         color: Colors.blue[50], // 统一颜色
         height: MediaQuery.of(context).size.height,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // 用户信息卡片
            Container(
              padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
            topLeft: Radius.circular(50),
            topRight: Radius.circular(50),
          ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _showLargeAvatar(context),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.blue[50],
                      backgroundImage: currentUserAvatar != null && currentUserAvatar!.isNotEmpty
                          ? NetworkImage(currentUserAvatar!)
                          : null,
                      child: currentUserAvatar == null || currentUserAvatar!.isEmpty
                          ? Text(
                              _getAvatarText(),
                              style: TextStyle(
                                fontSize: 30,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                  SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text(
                    '用户名：${currentUsername ?? '用户'}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    
                    '邮箱:${currentUserEmail ?? '未知邮箱'}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  ]
                  ),
                ],
              ),
            ),

            // 功能按钮区域
            Container(
              margin: EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildProfileButton(
                    Icons.lock_outlined,
                    '修改密码',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChangePasswordScreen(),
                        ),
                      );
                    },
                  ),
                  _buildProfileButton(
                    Icons.tag_faces_outlined,
                    '修改头像',
                    _updateAvatar,
                  ),    
                  _buildProfileButton(
                    Icons.fingerprint,
                    '指纹验证',
                    _askForFingerprint,
                  ),
                  _buildProfileButton(
                    Icons.exit_to_app,
                    '退出登录',
                    _handleLogout,
                  ),
                ],
              ),
            ),

            SizedBox(height: 32),
          ],
        ),
      ),
    ),
    );
  }

  @override
  void dispose() {
    _currentContext = null;
    super.dispose();
  }
}
