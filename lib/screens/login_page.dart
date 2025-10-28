import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:onlin/screens/empty_timetable_page.dart';
import 'package:onlin/servers/api_serverclass.dart';
import 'package:onlin/servers/cache_service.dart';



class LoginPage extends StatefulWidget {
  final bool returnData;
  const LoginPage({super.key, this.returnData = false});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _captchaController = TextEditingController();

  String? sessionId;
  String? captchaBase64;
  bool loading = false;
  String? errorMsg;
  bool rememberCredentials = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
    _tryLoadCacheThenCaptcha();
  }

  Future<void> _tryLoadCacheThenCaptcha() async {
    setState(() {
      loading = true;
      errorMsg = null;
    });
    try {
      // 只有在不是从其他页面调用时才自动跳转
      if (!widget.returnData) {
        final cached = await CacheService.loadTimetable();
        if (cached != null && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => EmptyTimetablePage(timetableJson: cached),
            ),
          );
          return;
        }
      }
    } catch (_) {}
    finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
    await _getCaptcha();
  }

  Future<void> _getCaptcha() async {
    setState(() {
      loading = true;
      errorMsg = null;
      captchaBase64 = null;
      sessionId = null;
      _captchaController.clear();
    });
    try {
      final data = await ApiService.fetchCaptcha();
      setState(() {
        sessionId = data['session_id'];
        captchaBase64 = data['captcha_base64'];
      });
    } catch (e) {
      setState(() {
        errorMsg = '获取验证码失败: $e';
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _login() async {
  if (_userController.text.trim().isEmpty || _passController.text.isEmpty) {
    setState(() {
      errorMsg = '学号和密码不能为空';
    });
    return;
  }
  if (_captchaController.text.isEmpty) {
    setState(() {
      errorMsg = '验证码不能为空';
    });
    return;
  }
  setState(() {
    loading = true;
    errorMsg = null;
  });
  try {
    final resp = await ApiService.fetchTimetable(
      sessionId: sessionId!,
      username: _userController.text,
      password: _passController.text,
      captcha: _captchaController.text,
    );
    print(resp);
    if (resp['need_manual_captcha'] == true) {
      setState(() {
        captchaBase64 = resp['captcha_base64'];
        errorMsg = resp['message'] ?? '验证码错误，请重新输入';
        loading = false;
      });
      return;
    } else if (resp['semesters'] != null || (resp['all_semesters_meta'] != null && resp['default_semester'] != null && resp['default_week'] != null)) {
      // 保存缓存与登录载荷（用于懒加载其它学期）
      await CacheService.saveTimetable(resp);
      await CacheService.saveLoginPayload({
        'username': _userController.text,
        'password': _passController.text,
        'captcha': _captchaController.text,
        'session_id': sessionId ?? resp['session_id'] ?? '',
      });
      
      // 保存记住的账号密码
      await CacheService.saveRememberedCredentials(
        _userController.text,
        _passController.text,
        rememberCredentials,
      );
      setState(() {
        loading = false;
      });
      if (context.mounted) {
        if (widget.returnData) {
          // 如果是从空白页调用的，返回数据
          print('🔄 登录成功，返回课表数据到空白页');
          print('返回的数据结构: $resp');
          
          // 提取并保存周次信息
          await _extractWeekInfoFromMetadata(resp);
          
          Navigator.pop(context, resp);
        } else {
          // 正常跳转到空白课表页面（替代原来的timetable_page）
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => EmptyTimetablePage(timetableJson: resp),
            ),
          );
        }
      }
    } else {
      setState(() {
        errorMsg = resp['detail'] ?? '登录失败，未知错误';
        loading = false;
      });
    }
  } catch (e) {
    setState(() {
      errorMsg = '登录失败: $e';
      loading = false;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    final isCaptchaReady = captchaBase64 != null;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, 
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  "assets/icons/logo.png",
                  width: 32,
                  height: 32, 
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text("课表登录"),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 201, 230, 244),
        elevation: 0,
      ),
      body: Container(
        // decoration: const BoxDecoration(
        //   gradient: LinearGradient(
        //     begin: Alignment.topCenter,
        //     end: Alignment.bottomCenter,
        //     colors: [
        //       const Color.fromARGB(255, 201, 230, 244), 
        //       Color(0xFFE9ECEF), 
        //     ],
        //   ),
        // ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight - MediaQuery.of(context).padding.top - kToolbarHeight,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      // margin: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color.fromARGB(255, 201, 230, 244),
                          Color.fromARGB(255, 248, 249, 250),
                        ],
                      ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "用户登录",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color.fromARGB(255, 205, 201, 244),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "请输入您的学号和密码",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 15),
                            _buildInputField(
                              controller: _userController,
                              label: "学号",
                              icon: Icons.person,
                              enabled: !loading,
                            ),
                            const SizedBox(height: 15),
                            _buildInputField(
                              controller: _passController,
                              label: "密码",
                              icon: Icons.lock,
                              obscureText: true,
                              enabled: !loading,
                            ),
                            const SizedBox(height: 10),
                            // 记住账号密码复选框（右对齐）
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Text(
                                  '记住账号密码',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                Checkbox(
                                  value: rememberCredentials,
                                  onChanged: loading ? null : (value) {
                                    setState(() {
                                      rememberCredentials = value ?? false;
                                    });
                                  },
                                  activeColor: const Color.fromARGB(255, 235, 115, 107),
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            if (isCaptchaReady) ...[
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: _buildInputField(
                                      controller: _captchaController,
                                      label: "验证码",
                                      icon: Icons.security,
                                      enabled: !loading,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    flex: 1,
                                    child: GestureDetector(
                                      onTap: loading ? null : _getCaptcha,
                                      child: Container(
                                        height: 56,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey.shade300),
                                          borderRadius: BorderRadius.circular(12),
                                          color: Colors.grey.shade50,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.memory(
                                            base64Decode(captchaBase64!.split(",").last),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: loading ? null : _getCaptcha,
                                  child: const Text(
                                    "刷新验证码",
                                    style: TextStyle(
                                      color: const Color.fromARGB(255, 154, 209, 251),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            
                            if (errorMsg != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        errorMsg!,
                                        style: TextStyle(
                                          color: Colors.red.shade600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: loading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color.fromARGB(255, 154, 209, 251),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: loading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2, 
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        "登录",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "请使用您的学号和密码登录系统",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 加载记住的账号密码
  Future<void> _loadRememberedCredentials() async {
    try {
      final credentials = await CacheService.loadRememberedCredentials();
      if (credentials != null) {
        setState(() {
          _userController.text = credentials['username'] ?? '';
          _passController.text = credentials['password'] ?? '';
          rememberCredentials = credentials['remember'] ?? false;
        });
        print('✅ 已加载保存的账号密码');
      }
    } catch (e) {
      print('❌ 加载保存的账号密码失败: $e');
    }
  }
  Future<void> _extractWeekInfoFromMetadata(Map<String, dynamic> metadata) async {
    try {
      final currentWeekInfo = metadata['current_week_info'] as Map<String, dynamic>?;
      if (currentWeekInfo != null) {
        print('📅 从登录元数据提取周次信息: $currentWeekInfo');
        await CacheService.saveCurrentWeekInfo(currentWeekInfo);
        
        // 验证保存
        final savedInfo = await CacheService.loadCurrentWeekInfo();
        print('📊 验证保存的周次信息: $savedInfo');
      } else {
        print('⚠️ 登录元数据中没有周次信息');
      }
    } catch (e) {
      print('❌ 从登录元数据提取周次信息失败: $e');
    }
  }
}

 Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    bool enabled = true,
    
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        
        controller: controller,
        obscureText: obscureText,
        enabled: enabled,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color:Color.fromARGB(255, 154, 209, 251)),
          prefixIcon: Icon(
            icon,
            color: const Color.fromARGB(255, 154, 209, 251),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: const Color.fromARGB(255, 154, 209, 251),
              width: 2,
            ),
          ),
          filled: true,
          fillColor: enabled ? Colors.white : Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
