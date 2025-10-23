import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:onlin/screens/login_page.dart';
import 'package:onlin/screens/priate_center.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/chat_listScreen.dart';
import 'screens/register_screen.dart';
import 'servers/api_service.dart';
import 'services/friend_notification_service.dart';
import 'services/all_friends_notification_service.dart';

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
                child:LoginPage(),
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
  
  // Initialize friend notification service
  await FriendNotificationService.instance.initialize();
  // Initialize all friends notification service
  await AllFriendsNotificationService.instance.initialize();
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Future<bool> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    print('🔎 登录状态检查 | Token存在: ${prefs.getString('token') != null}');
    final token = prefs.getString('token');
    final email = prefs.getString('email');

    if (token != null && email != null) {
      // 如果用户已登录，获取最新用户信息
      final apiService = ApiService();
      final userInfo = await apiService.getUserInfo(email);
      if (userInfo != null) {
        print('✅ 已更新用户信息');
        return true;
      }
    }
    return false;
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
