import 'dart:async';

import 'package:flutter/foundation.dart';
// ignore: undefined_shown_name
import 'dart:io' show InternetAddress, PathSetting, SocketException, join;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:onlin/globals.dart';
import 'package:onlin/screens/FriendRequestsScreen.dart';
import 'package:onlin/screens/chat_screen.dart';
import 'package:onlin/screens/priate_center.dart';
import 'package:onlin/servers/api_service.dart';
import 'package:onlin/servers/socket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:onlin/components/update_component.dart';
import 'package:onlin/services/all_friends_notification_service.dart';
import 'package:onlin/services/token_expired_service.dart';


class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> friendsList = [];
  List<Map<String, dynamic>> filteredFriendsList = [];
  bool isLoading = false;
  ApiService apiService = ApiService();
  final SocketService socketService = SocketService();
  String? currentUserEmail;
  List<String> pinnedFriends = []; // 存储顶置好友email
  MobileScannerController cameraController = MobileScannerController();
  bool isScanning = false;
  bool showQRCode = false; // 控制是否显示二维码
  bool isCameraLoading = true;
  String? currentUserAvatar; // 用户头像
  String? currentUsername;   // 用户昵称
  bool isConnected = true; // 添加网络连接状态变量
  StreamSubscription? _connectivitySubscription; // 添加网络状态监听
  Map<String, int> unreadMessageCounts = {}; // email -> count
  Map<String, String?> avatarCache = {}; // 用于缓存头像链接
  bool _wasDisconnected = false;
  final LocalAuthentication auth = LocalAuthentication();
  bool isFingerprintEnabled = false; // 存储指纹登录状态
  BuildContext? _currentContext;

  @override
  void initState() {
    super.initState();
    _initSocket(); // 初始化 socket 服务
    _bindSocketListeners(); // 绑定监听器
    
    // 初始化全局好友通知服务
    AllFriendsNotificationService.instance.initialize();
    // socketService.onCallInvite = _onCallInvite;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      //如果已启用指纹登录，进入页面时自动触发验证
      SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('fingerprint_enabled') ?? false) {
        bool isAuthenticated = await _authenticate();
        if (!isAuthenticated) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        }
      }
      _initializeData();
    });
    _loadPinnedFriends();
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          cameraController = MobileScannerController();
          cameraController.start().then((_) {
            print('Camera started successfully');
          }).catchError((error) {
            print('Failed to start camera: $error');
          });
        });
      }
    });
    _initNetworkCheck();
    _fetchAllUnreadMessageCounts(); // 获取所有好友的未读消息数量
  }

  void _bindSocketListeners() {
    socketService.onNewMessage = (data) {
      if (!mounted) return;
      print('聊天列表收到新消息，更新未读数量');
      
      // 触发全局新消息通知
              AllFriendsNotificationService.instance.triggerAllFriendsMessageNotification();
      
      // 立即更新未读消息数量
      _fetchAllUnreadMessageCounts();
    };
    socketService.friendRequestAcceptedCallback = (data) {
      if (!mounted) return;
      setState(() {
        _loadFriends();
      });
    };
  }

  void _initializeData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserEmail = prefs.getString('email');
      currentUsername = prefs.getString('username') ?? '用户';
      currentUserAvatar = prefs.getString('avatar');
      // isFingerprintEnabled = prefs.getBool('fingerprint_enabled') ?? false; // 获取指纹登录状态
    });
    
    print('🔍 本地存储数据 | Email: $currentUserEmail | 用户名: $currentUsername | 头像: $currentUserAvatar');

    String? token = prefs.getString('token');
    if (token != null && currentUserEmail != null) {
      bool connected = await socketService.connectSocket(currentUserEmail!, token);
      if (connected) {
        print('Socket连接成功');
        _loadFriends();
        _fetchUnreadMessageCount();
        
      }
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
  // 从后端加载好友列表
  void _loadFriends() async {
    if (currentUserEmail == null) return;
    setState(() { isLoading = true; });

    try {
      var response = await apiService.getFriendsList(currentUserEmail!);
      for (int i = 0; i < response.length; i++) {
        response[i]['originalIndex'] = i;
      }
      response.sort((a, b) {
        final aPinned = pinnedFriends.contains(a['email']);
        final bPinned = pinnedFriends.contains(b['email']);
        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;
        return 0;
      });

      setState(() {
        friendsList = response;
        filteredFriendsList = List.from(friendsList); // 强制同步
        isLoading = false;
      });

      print('Friends list loaded: ${friendsList.length} friends');
      _fetchAllUnreadMessageCounts();
    } catch (e) {
      setState(() { isLoading = false; });
      print('Error loading friends list: $e');
      
      // 检查是否是Token过期错误
      if (e.toString().contains('TOKEN_EXPIRED')) {
        print('🔒 检测到Token过期，显示重新登录对话框');
        TokenExpiredService.instance.showTokenExpiredDialog(context);
        return;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载好友列表失败'))
      );
    }
  }

  // 搜索好友
  void _searchFriends(String query) {
    setState(() {
      filteredFriendsList = friendsList
          .where((friend) => 
              friend['email'].toLowerCase().contains(query.toLowerCase()) ||
              friend['username'].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  // 发送好友请求
  void _sendFriendRequest(String email) async {
    var logindata = await apiService.getLoginData();
    var userId = logindata?['email'];

    setState(() {
      isLoading = true;
    });

    // 打印请求的数据，检查是否正确
    print("Sending friend request to $email with userId $userId");

    try {
      var response = await apiService.sendFriendRequest(userId!, email);

      setState(() {
        isLoading = false;
      });

      // 检查Token过期
      if (response != null && response['code'] == 'TOKEN_EXPIRED') {
        print('🔒 检测到Token过期，显示重新登录对话框');
        TokenExpiredService.instance.showTokenExpiredDialog(context);
        return;
      }

      if (response != null && response['message'] == 'Friend request sent') {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Friend request sent!')));
      } else {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send friend request')));
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      
      // 检查是否是Token过期错误
      if (e.toString().contains('TOKEN_EXPIRED')) {
        print('🔒 检测到Token过期，显示重新登录对话框');
        TokenExpiredService.instance.showTokenExpiredDialog(context);
        return;
      }
      
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send friend request')));
    }
  }
    

  Future<void> _loadPinnedFriends() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      pinnedFriends = prefs.getStringList('pinned_friends') ?? [];
    });
  }

  Future<void> _savePinnedFriends() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinned_friends', pinnedFriends);
  }

  void _sortFriends() {
    setState(() {
      friendsList.sort((a, b) {
        final aPinned = pinnedFriends.contains(a['email']);
        final bPinned = pinnedFriends.contains(b['email']);
        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;
        // 都没顶置或都顶置，按原始顺序
        return (a['originalIndex'] as int).compareTo(b['originalIndex'] as int);
      });
      filteredFriendsList = List.from(friendsList);
    });
  }

  // 扫码结果处理方法
  void _handleScanResult(BarcodeCapture barcodes) {
    final Barcode? barcode = barcodes.barcodes.firstOrNull;
    if (barcode != null && barcode.rawValue != null) {
      setState(() {
        isScanning = false;
      });
      // 处理扫码结果
      _sendFriendRequest(barcode.rawValue!);
      // 显示一个提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('尝试发送好友请求给: ${barcode.rawValue}')),
      );
    }
  }

  void _switchCamera() {
    setState(() {
      cameraController.switchCamera();
    });
  }

  // 扫码界面
  Widget _buildScanner() {
    return Scaffold(
      appBar: AppBar(
        title: Text('扫一扫', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 201, 230, 244),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body:Scaffold(
        backgroundColor: Colors.blue[50],
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            onDetect: _handleScanResult,
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('取消扫码'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: IconButton(
              icon: Icon(Icons.cameraswitch),
              onPressed: _switchCamera,
            ),
          ),
        ],
      ),
    ),
    );
  }

  // 二维码界面
  Widget _buildQRCode() {
    if (currentUserEmail == null) return Container();

    return Scaffold(
      appBar: AppBar(
        title: Text('我的二维码', style: TextStyle(color: Colors.black87)),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 201, 230, 244),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body:Scaffold(
        backgroundColor: Colors.blue[50],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            QrImageView(
              data: currentUserEmail!,
              version: QrVersions.auto,
              size: 200.0,
            ),
            SizedBox(height: 20),
            Text(
              '我的二维码',
              style: TextStyle(
                fontSize: 18,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('关闭二维码'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                backgroundColor: Colors.blue[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _checkCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      await Permission.camera.request();
    }
  }



  String _getAvatarText() {
    if (currentUsername == null || currentUsername!.isEmpty) return "?";
    // 获取第一个中文字符或英文字母
    return currentUsername!.trim().characters.first.toUpperCase();
  }

  // 初始化网络检查
  void _initNetworkCheck() async {
    await _checkNetworkConnection(); // 立即检查一次
    // 添加网络状态监听
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) async {
      // 添加延迟以确保网络状态准确
      await Future.delayed(Duration(seconds: 1));
      final isActuallyConnected = await _isInternetAvailable();
      setState(() {
        isConnected = isActuallyConnected;
      });
      if (!isActuallyConnected) {
        _wasDisconnected = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('网络连接已断开'))
        );
      } else {
        if (_wasDisconnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('网络已连接'))
          );
          _wasDisconnected = false;
        }
        _loadFriends(); // 网络恢复时重新加载数据
      }
    });
  }

  // 检查网络是否真正可用
  Future<bool> _isInternetAvailable() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  // 修改网络检查方法
  Future<void> _checkNetworkConnection() async {
    try {
      final isActuallyConnected = await _isInternetAvailable();
      setState(() {
        isConnected = isActuallyConnected;
      });
    } catch (e) {
      print('网络检查错误: $e');
      setState(() {
        isConnected = false;
      });
    }
  }

Future<void> _fetchUnreadMessageCount() async {
  try {
    final response = await apiService.getUnreadMessageCount(currentUserEmail!);
    print('未读消息数量: ${response['unreadCount']}'); // 调试输出
    setState(() {
    });
  } catch (e) {
    print('Error fetching unread message count: $e');
  }
}

  // 初始化 Socket 连接
  void _initSocket() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? email = prefs.getString('email');
    String? token = prefs.getString('token');
    if (email != null) {
         bool connected = await socketService.connectSocket(email,token!);
        if (connected) {
          print('Socket connected');
        } else {
          print("socket not connected");
        }
    }
  }

  // 获取所有好友的未读消息数量
  Future<void> _fetchAllUnreadMessageCounts() async {
    if (friendsList.isEmpty) return;
    
    Map<String, int> newCounts = {};
    for (var friend in friendsList) {
      final count = await _fetchUnreadMessageCountForFriend(friend['email']);
      newCounts[friend['email']] = count;
      print('刷新未读数: ${friend['email']} -> $count');
    }
    
    if (mounted) {
      setState(() {
        unreadMessageCounts = newCounts;
      });
    }
  }

  // 获取单个好友的未读消息数量
  Future<int> _fetchUnreadMessageCountForFriend(String friendEmail) async {
    try {
      final response = await apiService.getUnreadMessageCountForFriend(currentUserEmail!, friendEmail);
      return response['unreadCount'] ?? 0;
    } catch (e) {
      print('Error fetching unread message count for $friendEmail: $e');
      
      // 检查是否是Token过期错误
      if (e.toString().contains('TOKEN_EXPIRED')) {
        print('🔒 检测到Token过期，显示重新登录对话框');
        TokenExpiredService.instance.showTokenExpiredDialog(context);
        return 0;
      }
      
      return 0;
    }
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
            currentUsername ?? '用户',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            
          ),
        ),
        leading: GestureDetector(
          // onTap: () => Navigator.push(
          //   context,
          //   MaterialPageRoute(
          //     builder: (context) => const PrivateCenterScreen(),
          //   ),
          // ),
          child: Padding(
            padding: EdgeInsets.only(left: 20),
            child: CircleAvatar(
              backgroundColor: Colors.blue[200],
              backgroundImage: currentUserAvatar != null && currentUserAvatar!.isNotEmpty
                  ? NetworkImage(currentUserAvatar!)
                  : null,
              child: currentUserAvatar == null || currentUserAvatar!.isEmpty
                  ? Text(
                      _getAvatarText(),
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold
                      ),
                    )
                  : null,
            ),
          ),
        ),
        actions: [
          // 通知设置按钮
          IconButton(
            icon: Icon(
              AllFriendsNotificationService.instance.allFriendsNotificationEnabled ? Icons.notifications_active : Icons.notifications_off,
              color: AllFriendsNotificationService.instance.allFriendsNotificationEnabled ? const Color.fromARGB(255, 103, 94, 94) : Colors.grey,
            ),
            onPressed: () => _showNotificationSettings(),
            tooltip: '好友通知设置',
          ),
          IconButton(
            icon: Icon(Icons.qr_code_2_outlined),
            onPressed: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => _buildQRCode()),
                );
            },
          ),
          PopupMenuButton<String>(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 8,
            position: PopupMenuPosition.under,
            offset: Offset(0, 10),
            color: Colors.white,
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.people_outline, color: Colors.blue[20], size: 20),
                      SizedBox(width: 12),
                      Text(
                        '好友请求',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'add',
                  child: Row(
                    children: [
                      Icon(Icons.person_add_outlined, color: Colors.blue[20], size: 20),
                      SizedBox(width: 12),
                      Text(
                        '添加好友',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'scan',
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_scanner, color: Colors.blue[20], size: 20),
                      SizedBox(width: 12),
                      Text(
                        '扫一扫',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ];
            },
            onSelected: (value) async {
              if (value == 'add') {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: Colors.blue[50],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: Text('添加好友'),
                    content: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '输入好友邮箱',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('取消'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          String email = _searchController.text;
                          if (email.isNotEmpty) {
                            _sendFriendRequest(email);
                            Navigator.pop(context);
                          }
                        },
                        child: Text('发送请求'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                );
              } else if (value == 'view') {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => FriendRequestsScreen(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      var begin = Offset(1.0, 0.0);
                      var end = Offset.zero;
                      var curve = Curves.easeInOut;
                      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                      return SlideTransition(
                        position: animation.drive(tween),
                        child: child,
                      );
                    },
                    transitionDuration: Duration(milliseconds: 300),
                  ),
                );
              } else if (value == 'scan') {
                await _checkCameraPermission();
               Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => _buildScanner()),
                );
              }
            },
            child: Padding(
              padding: EdgeInsets.all(10.0),
              child: Icon(
                Icons.add_outlined,
              ),
            ),
          ),
        ],
      ), 

      body: !isConnected
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '网络连接不可用',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _checkNetworkConnection,
                    child: Text('重试'),
                  ),
                ],
              ),
            )
          : isScanning
              ? _buildScanner()
              : showQRCode
                  ? _buildQRCode()
                  : Container(
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(15),
            topRight: Radius.circular(15),
          ),
        ),
       child: Column(
         children: [
              Visibility(
                visible: Global.showUpdateComponent,
                  child: UpdateComponent(),
           ),
       SizedBox(
         height:8,
       ), 
       Container(
        width: 420,
        height: 30,
        margin: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white),
          color: Colors.blue[20],
          borderRadius: BorderRadius.circular(20),
        ),
        child: TextField(
          controller: _searchController,
          style: TextStyle(
          fontSize: 16,
          height: 1.2, 
        ),
          decoration: InputDecoration(
            hintText: '搜索好友...',
            hintStyle: TextStyle(color: Colors.grey[400]),  
            prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal:10, vertical:7), // Ensure padding is uniform
          ),
          onChanged: _searchFriends,
        ),
      ),
            isLoading
              ? Center(child: CircularProgressIndicator())
              : Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      _loadFriends();
                    },
                    child: filteredFriendsList.isEmpty
                      ? ListView(
                          children: [
                            Container(
                              height: MediaQuery.of(context).size.height - 200, // 留出足够空间显示空状态
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.people_outline,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      '暂无好友',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            backgroundColor: Colors.blue[50],
                                            title: Text('添加好友'),
                                            content: TextField(
                                              controller: _searchController,
                                              decoration: InputDecoration(
                                                hintText: '输入好友邮箱',
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: Text('取消'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  String email = _searchController.text;
                                                  if (email.isNotEmpty) {
                                                    _sendFriendRequest(email);
                                                    Navigator.pop(context);
                                                  }
                                                },
                                                child: Text('发送请求'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      icon: Icon(Icons.person_add),
                                      label: Text('添加好友'),
                                      style: ElevatedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          itemCount: filteredFriendsList.length,
                          itemBuilder: (context, index) {
                            final friend = filteredFriendsList[index];
                            final isPinned = pinnedFriends.contains(friend['email']);
                            final unreadCount = unreadMessageCounts[friend['email']] ?? 0;

                            return FutureBuilder<String?>(
                              future: _getAvatar(friend['email']),
                              builder: (context, snapshot) {
                                String? avatarUrl = snapshot.data;

                                return Slidable(
                                  key: ValueKey(friend['email']),
                                  endActionPane: ActionPane(
                                    motion: const DrawerMotion(),
                                    children: [
                                      if (!isPinned)
                                        SlidableAction(
                                          onPressed: (context) async {
                                            setState(() {
                                              if (!pinnedFriends.contains(friend['email'])) {
                                                pinnedFriends.add(friend['email']);
                                              }
                                            });
                                            await _savePinnedFriends();
                                            _sortFriends();
                                          },
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                          icon: Icons.vertical_align_top,
                                          label: '顶置',
                                        ),
                                      if (isPinned)
                                        SlidableAction(
                                          onPressed: (context) async {
                                            setState(() {
                                              pinnedFriends.remove(friend['email']);
                                            });
                                            await _savePinnedFriends();
                                            _sortFriends();
                                          },
                                          backgroundColor: Colors.grey,
                                          foregroundColor: Colors.white,
                                          icon: Icons.push_pin_outlined,
                                          label: '取消顶置',
                                        ),
                                    ],
                                  ),
                                  child: Card(
                                    margin: EdgeInsets.symmetric(
                                      horizontal:8,
                                      vertical: 2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                    color: Colors.blue[50],
                                    child: ListTile(
                                      minTileHeight: 10,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 2,
                                      ),
                                      leading: CircleAvatar(
                                        radius: 24,
                                        backgroundColor: Colors.blue[100],
                                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                            ? NetworkImage(avatarUrl)
                                            : null,
                                        child: avatarUrl == null || avatarUrl.isEmpty
                                            ? Text(
                                                friend['username'][0].toUpperCase(),
                                                style: TextStyle(
                                                  color: Colors.blue[900],
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )
                                            : null,
                                      ),
                                      title: Text(
                                        friend['username'],
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: const Color.fromARGB(255, 84, 81, 81),
                                        ),
                                      ),
                                      subtitle: Text(
                                        friend['email'],
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 15,
                                        ),
                                      ),
                                      trailing: unreadCount > 0
                                          ? Badge(
                                              label: Text('$unreadCount'),
                                              backgroundColor: Colors.red,
                                            )
                                          : null,
                                      onTap: () {
                                        apiService.markMessagesAsRead(currentUserEmail!, friend['email']);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ChatScreen(
                                              friendEmail: friend['email'],
                                              friendNickname: friend['username'],
                                              friendsList: friendsList,
                                              avatarUrl: avatarUrl,
                                              currentUserAvatar: currentUserAvatar,
                                            ),
                                          ),
                                        ).then((_) {
                                          _loadFriends();
                                          _bindSocketListeners();
                                          apiService.markMessagesAsRead(currentUserEmail!, friend['email']);
                                        });
                                      },
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
            )],
      ),
    ),
    );
  }

  Future<String?> _getAvatar(String email) async {
    try {
      // 清除缓存
      avatarCache.remove(email); // 每次获取头像之前先删除缓存

      // 调用 apiService 获取头像链接
      final response = await apiService.getUserAvatar(email);
      if (response != null && response['avatar'] != null) {
        String avatarUrl = response['avatar'];
        avatarCache[email] = avatarUrl; // 缓存头像链接
        return avatarUrl; // 返回新的头像链接
      }

      return null; // 如果没有头像链接，返回 null
    } catch (e) {
      print('Error getting avatar for $email: $e');
      
      // 检查是否是Token过期错误
      if (e.toString().contains('TOKEN_EXPIRED')) {
        print('🔒 检测到Token过期，显示重新登录对话框');
        TokenExpiredService.instance.showTokenExpiredDialog(context);
        return null;
      }
      
      return null;
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    _connectivitySubscription?.cancel(); // 取消监听
    super.dispose();
  }

  // 显示通知设置面板
  void _showNotificationSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖拽指示器
                  Container(
                    width: 40,
                    height: 4,
                    margin: EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  
                  // 标题
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.notifications, color: Colors.blue, size: 24),
                        SizedBox(width: 12),
                        Text(
                          '全局通知设置',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // 通知开关
                  _buildNotificationSettingItem(
                    icon: Icons.notifications_active,
                    title: '好友消息通知',
                    subtitle: '接收所有好友的新消息通知',
                    value: AllFriendsNotificationService.instance.allFriendsNotificationEnabled,
                    onChanged: (value) async {
                      await AllFriendsNotificationService.instance.toggleAllFriendsMessageNotification();
                      // 立即刷新模态框状态
                      setModalState(() {});
                      // 同时刷新主界面状态，让APP bar图标也更新
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  
                  // 震动开关
                  _buildNotificationSettingItem(
                    icon: Icons.vibration,
                    title: '震动提醒',
                    subtitle: '好友新消息时震动',
                    value: AllFriendsNotificationService.instance.allFriendsVibrationEnabled,
                    onChanged: (value) async {
                      await AllFriendsNotificationService.instance.toggleAllFriendsMessageVibration();
                      // 立即刷新模态框状态
                      setModalState(() {});
                      // 同时刷新主界面状态
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  
                  // 铃声开关
                  _buildNotificationSettingItem(
                    icon: Icons.music_note,
                    title: '铃声提醒',
                    subtitle: '好友新消息时播放铃声',
                    value: AllFriendsNotificationService.instance.allFriendsSoundEnabled,
                    onChanged: (value) async {
                      await AllFriendsNotificationService.instance.toggleAllFriendsMessageSound();
                      // 立即刷新模态框状态
                      setModalState(() {});
                      // 同时刷新主界面状态
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  
                  SizedBox(height: 16),
              ],
              ),
          ),
        );
        
        },
      ),
    );
  }

  // 构建通知设置项
  Widget _buildNotificationSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.blue, size: 20),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }
}
