import 'package:flutter/material.dart';
import 'package:onlin/servers/api_service.dart';
import 'package:onlin/servers/socket_service.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _FriendRequestsScreenState createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> friendRequests = [];
  String? email; 
  final ApiService apiService = ApiService(); 
  final SocketService socketService = SocketService();
  
  @override
  void initState() {
    super.initState();
    _loadEmail();
    _initializeSocket();
  }

  void _initializeSocket() async{
    if (email != null) {
      var loginData = await apiService.getLoginData();
      var token = loginData?['token'];
      print(token);
      socketService.connectSocket(email!,token!);
    }
  }

  // 从 SharedPreferences 加载 eamil
  _loadEmail() async {
      var logindata = await apiService.getLoginData();
      var email = logindata?['email'];
    if (email != null) {
      setState(() {
        this.email = email;  
      });
      _fetchFriendRequests(); 
    } else {
      setState(() {
        isLoading = false;  
      });
      print('No eamil found');
    }
  }

  // 获取好友请求
  _fetchFriendRequests() async {
    if (email == null) return;
    try {
      print(email);
      final requests = await apiService.getFriendRequests(email!);
      setState(() {
        friendRequests = requests;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print('Error fetching friend requests: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 201, 230, 244),
        elevation: 2,
        title: Text('好友申请'),
      ),
      body: Container(
        decoration: BoxDecoration(
          // 添加渐变背景
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[50]!, Colors.grey[100]!],
          ),
        ),
      child: isLoading
          ? Center(child: CircularProgressIndicator()) // 显示加载中
          : friendRequests.isEmpty
              ? Center(child: Text('没有新的好友请求！'))
              : ListView.builder(
                  itemCount: friendRequests.length,
                  itemBuilder: (context, index) {
                    final request = friendRequests[index];
                    return ListTile(
                      title: Text(request['username']),
                      subtitle: Text(request['email']),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.check, color: Colors.green),
                            onPressed: () {
                              // 接受好友请求
                              _acceptFriendRequest(request['email']);
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              // 拒绝好友请求
                              _rejectRequest(request['email']);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
      ),
    );
  }

  // 接受好友请求
  void _acceptFriendRequest(String requesterId) async {
    try {
      // 调用API接受好友请求
      var response = await apiService.acceptFriendRequest(email!, requesterId);
      
      if (response != null && response['message'] == 'Friend request accepted') {
        // 发送Socket事件通知双方
        bool sent = await socketService.emitFriendRequestAccepted(email!, requesterId);
        
        if (sent) {
          // 从请求列表中移除
          setState(() {
            friendRequests.removeWhere((request) => request['senderId'] == requesterId);
          });

          // 显示成功消息
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已添加为好友'))
          );

          // 返回到好友列表页面
          Navigator.pop(context);
        } else {
          print('Failed to send socket notification');
          // 即使Socket通知失败，好友关系也已建立，所以仍然显示成功消息
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已添加为好友'))
          );
          Navigator.pop(context,true);
        }
      } else {
        print('Failed to accept friend request: ${response?['error'] ?? 'Unknown error'}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('接受好友请求失败'))
        );
      }
    } catch (e) {
      print('Error accepting friend request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接受好友请求失败'))
      );
    }
  }

  // 拒绝好友请求
  _rejectRequest(String friendEmail) async {
    if (email == null) return;
    final result = await apiService.rejectFriendRequest(email!, friendEmail);

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request rejected')),
      );
      _fetchFriendRequests(); // 刷新请求列表
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject request')),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
