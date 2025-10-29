import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:onlin/screens/priate_center.dart';
import 'package:onlin/screens/empty_timetable_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/chat_listScreen.dart';
import 'screens/register_screen.dart';
import 'servers/api_service.dart';
import 'services/friend_notification_service.dart';
import 'services/all_friends_notification_service.dart';
import 'services/token_manager.dart';
import 'services/token_refresh_manager.dart';

class MainTabScaffold extends StatefulWidget {
  @override
  State<MainTabScaffold> createState() => _MainTabScaffoldState();
}

class _MainTabScaffoldState extends State<MainTabScaffold> {
  int _selectedIndex = 0;
  bool _navBarCollapsed = false; // 初始为false，完整导航栏

  final List<IconData> _tabIcons = [
    Icons.message_outlined,
    Icons.calendar_month_outlined,
    Icons.person_2_outlined,
  ];

  void setNavBarCollapsed(bool collapsed) {
    // 只在状态变化时setState，避免初始就收缩
    if (_navBarCollapsed != collapsed) {
      setState(() {
        _navBarCollapsed = collapsed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double navBarLeft = 24;
    final double navBarRight = _navBarCollapsed ? MediaQuery.of(context).size.width - 88 : 24;
    final Color navBarColor = const Color.fromARGB(255, 201, 230, 244);
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              _CollapsibleScrollTab(
                child: ChatListScreen(),
                onScrollCollapse: () => setNavBarCollapsed(true),
                onScrollExpand: () => setNavBarCollapsed(false),
              ),
              _CollapsibleScrollTab(
                child: EmptyTimetablePage(timetableJson: null),
                onScrollCollapse: () => setNavBarCollapsed(true),
                onScrollExpand: () => setNavBarCollapsed(false),
              ),
              _CollapsibleScrollTab(
                child: PrivateCenterScreen(),
                onScrollCollapse: () => setNavBarCollapsed(true),
                onScrollExpand: () => setNavBarCollapsed(false),
              ),
            ],
          ),
          AnimatedPositioned(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: navBarLeft,
            right: navBarRight,
            bottom: 16,
            child: _navBarCollapsed
                ? GestureDetector(
                    onTap: () {
                      setNavBarCollapsed(false);
                    },
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 300),
                      width: 64,
                      height: 56,
                      decoration: BoxDecoration(
                        color: navBarColor,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                      ),
                      child: Center(
                        child: Icon(
                          _tabIcons[_selectedIndex],
                          size: 32,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: PhysicalModel(
                      color: Colors.transparent,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(28),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BottomNavigationBar(
                          backgroundColor: navBarColor,
                          selectedItemColor: Colors.blue[800],
                          unselectedItemColor: Colors.black54,
                          currentIndex: _selectedIndex,
                          type: BottomNavigationBarType.fixed,
                          elevation: 0,
                          onTap: (index) {
                            setState(() {
                              _selectedIndex = index;
                            });
                          },
                          items: const [
                            BottomNavigationBarItem(
                              icon: Icon(Icons.message_outlined),
                              label: '消息',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(Icons.calendar_month_outlined
                              ),
                              label: '课程表',
                            ),
                            BottomNavigationBarItem(
                              icon: Icon(Icons.person_2_outlined),
                              label: '个人中心',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CollapsibleScrollTab extends StatelessWidget {
  final Widget child;
  final VoidCallback? onScrollCollapse;
  final VoidCallback? onScrollExpand;
  const _CollapsibleScrollTab({required this.child, this.onScrollCollapse, this.onScrollExpand});

  @override
  Widget build(BuildContext context) {
    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.direction == ScrollDirection.idle) {
          if (onScrollExpand != null) onScrollExpand!();
        } else {
          if (onScrollCollapse != null) onScrollCollapse!();
        }
        return false;
      },
      child: child,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plugin must be initialized before using
  await FlutterDownloader.initialize(
      debug: true, // optional: set to false to disable printing logs to console (default: true)
      ignoreSsl: true // option: set to false to disable working with http links (default: false)
  );

  // Initialize local storage
  await SharedPreferences.getInstance();
  
  // Initialize TokenManager（加载token到内存缓存）
  await TokenManager.instance.initialize();
  
  // Token自动刷新机制将在_checkLoginStatus验证成功后启动
  // 不需要在这里启动，避免重复启动
  
  // Initialize friend notification service
  await FriendNotificationService.instance.initialize();
  // Initialize all friends notification service
  await AllFriendsNotificationService.instance.initialize();
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Future<bool> _checkLoginStatus() async {
    // 使用TokenManager检查token
    final hasToken = await TokenManager.instance.hasToken();
    print('🔎 登录状态检查 | Token存在: $hasToken');

    if (hasToken) {
      // 专门的Token验证接口
      final apiService = ApiService();
      try {
        final result = await apiService.verifyToken();
        if (result != null && result['success'] == true && result['valid'] == true) {
          print('✅ Token验证成功');
          
          // 启动Token自动刷新机制（如果尚未运行）
          if (!TokenRefreshManager.instance.isRunning) {
            TokenRefreshManager.instance.start(intervalMinutes: 25);
          }
          
          // 更新用户信息
          final email = result['email'];
          if (email != null) {
            final userInfo = await apiService.getUserInfo(email);
            if (userInfo != null) {
              print('✅ 已更新用户信息');
            }
          }
          return true;
        } else {
          // Token无效、过期或未登录
          final code = result?['code'];
          if (code == 'NO_TOKEN') {
            print('🔒 用户未登录');
          } else if (code == 'TOKEN_EXPIRED') {
            print('🔒 Token已过期，清除登录数据');
          } else {
            print('🔒 Token无效或过期，清除登录数据');
          }
          // 使用TokenManager清除（同步清除内存和加密存储）
          await TokenManager.instance.clearAll();
          return false;
        }
      } catch (e) {
        // 如果Token过期，清除登录数据
        if (e.toString().contains('TOKEN_EXPIRED')) {
          print('🔒 Token已过期，清除登录数据');
          await TokenManager.instance.clearAll();
        } else if (e.toString().contains('Token is null') || e.toString().contains('NO_TOKEN')) {
          print('🔒 用户未登录');
        }
        return false;
      }
    } else {
      // Token为空，用户未登录
      print('🔒 Token为空，用户未登录');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Happy Chat',
      navigatorKey: navigatorKey,
      home: FutureBuilder<bool>(
        future: _checkLoginStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data! ? MainTabScaffold() : LoginScreen();
        },
      ),
      routes: {
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/main': (context) => MainTabScaffold(),
        '/priatecenter': (context) =>PrivateCenterScreen(),
      },
      theme: ThemeData(
        useMaterial3:true,
        appBarTheme: const AppBarTheme(
          surfaceTintColor: Colors.transparent,
        ),
      ),
    );
  }
}
