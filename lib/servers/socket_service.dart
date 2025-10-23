import 'package:onlin/baseUrl.dart';
import 'package:onlin/servers/api_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
typedef void UnreadCountCallback(int? count);
class SocketService {
  IO.Socket? _socket;
  bool _isConnected = false;
  String? _currentUserId;
  Function(Map<String, dynamic>)? onNewMessage;
  Function(Map<String, dynamic>)? friendRequestAcceptedCallback;
  bool _isConnecting = false;
  bool _manuallyDisconnected = false;
  // ignore: unused_field
  int?_unreadMessageCount;
  ApiService apiService=ApiService();
  // 重连配置
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  // ignore: constant_identifier_names
  static const int MAX_RECONNECT_ATTEMPTS = 5;
  // ignore: constant_identifier_names
  static const Duration RECONNECT_INTERVAL = Duration(seconds: 5);
  // ignore: constant_identifier_names
  static const Duration RECONNECT_RESET_INTERVAL = Duration(minutes: 1);
  UnreadCountCallback? onUnreadCountUpdated;
  // 心跳检测配置
  Timer? _heartbeatTimer;
  DateTime? _lastHeartbeatResponse;
  // ignore: constant_identifier_names
  static const Duration HEARTBEAT_INTERVAL = Duration(seconds: 30);
  // ignore: constant_identifier_names
  static const Duration HEARTBEAT_TIMEOUT = Duration(seconds: 5);

  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  // 添加公共的 socket getter
  IO.Socket? get socket => _socket;

  bool isConnected() {
    return _isConnected && _socket != null && !_isConnecting;
  }

  Future<bool> connectSocket(String userId, String token) async {
  if (_isConnecting) {
    print('Connection already in progress...');
    return false;
  }

  if (_isConnected && _socket != null && _currentUserId == userId) {
    print('Already connected for user: $userId');
    return true;
  }

  try {
    _isConnecting = true;
    _manuallyDisconnected = false;

    await _cleanupExistingConnection();
    
    print('Initializing new socket connection for user: $userId');
    _currentUserId = userId;

    if (token.isNotEmpty) {   
      print("'token': $token");
      
      // 每次连接前确保初始化一个新的连接
      _socket = IO.io(Baseurl.baseUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'query': {'token': token,'userId':userId},  // 传递最新的 token
        'forceNew': true,  // 关键！！！！强制创建新连接，避免复用
        'reconnection': false, 
        'timeout': 10000,      
        'pingInterval': 25000,
        'pingTimeout': 5000,
      });
    } else {
      print('Token not found');
      return false;
    }

    _setupSocketListeners();
    _socket!.connect();
    
    bool connected = await _waitForConnection();
    if (connected) {
      _startHeartbeat();
      _resetReconnectAttempts();
    }
    return connected;
  } catch (e) {
    print('Socket connection error: $e');
    return false;
  } finally {
    _isConnecting = false;
  }
}

  Future<void> _cleanupExistingConnection() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    if (_socket != null) {
      print('Cleaning up existing connection...');
      _socket!.clearListeners();
      _socket!.disconnect();
      _socket = null;
      _isConnected = false;

      // 等待清理完成
      await Future.delayed(Duration(milliseconds: 500));
    }
  }
 
  void _setupSocketListeners() {
    _socket!.onConnect((_) {
      print('Socket connected successfully');
      print("连接成功");
      _isConnected = true;
      _manuallyDisconnected = false;
      _socket!.emit('user_connected', _currentUserId);
    });

    _socket!.onDisconnect((_) {
      print('Socket disconnected. Manual: $_manuallyDisconnected');
      _isConnected = false;
      if (!_manuallyDisconnected) {
        _handleDisconnection();
      }
    });

    _socket!.onError((error) {
      print('Socket error: $error');
      _isConnected = false;
      if (!_manuallyDisconnected) {
        _handleDisconnection();
      }
    });

    _socket!.onConnectError((error) {
      print('Socket connect error: $error');
      _isConnected = false;
      if (!_manuallyDisconnected) {
        _handleDisconnection();
      }
    });

    _socket!.on('pong', (_) {
      _lastHeartbeatResponse = DateTime.now();
    });
   
    _socket!.on('new_message', (data) {
      print('收到新消息推送: $data'); // 调试输出
      if (onNewMessage != null && data is Map) {
        try {
          onNewMessage!(Map<String, dynamic>.from(data));
        } catch (e) {
          print('处理新消息时出错: $e');
        }
      }
    });
        _socket!.on('friend_request_accepted', (data) {
      if (friendRequestAcceptedCallback!= null && data is Map) {
        friendRequestAcceptedCallback!(Map<String, dynamic>.from(data));
      }
    });
        _socket!.on('call_invite', (data) {
      print('🔔 SocketService 收到 call_invite: $data');
      if (onCallInvite != null && data is Map) {
        print('🔔 调用 onCallInvite 回调');
        onCallInvite!(Map<String, dynamic>.from(data));
      } else {
        print('🔔 onCallInvite 回调为空或数据格式错误');
      }
    });
    _socket!.on('call_signal', (data) {
      print('🔔 SocketService 收到 call_signal: $data');
      if (onCallSignal != null && data is Map) {
        print('🔔 调用 onCallSignal 回调');
        onCallSignal!(Map<String, dynamic>.from(data));
      } else {
        print('🔔 onCallSignal 回调为空，缓存信令');
        if (data is Map) {
          _pendingCallSignals.add(Map<String, dynamic>.from(data));
          print('🔔 已缓存信令，当前缓存数量: ${_pendingCallSignals.length}');
        }
      }
    });
  }

  void _handleDisconnection() {
    if (_manuallyDisconnected || _isConnecting) return;
    
    _startReconnection();
  }

  void _startReconnection() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;

    _reconnectTimer = Timer.periodic(RECONNECT_INTERVAL, (timer) async {
      if (_isConnected || _manuallyDisconnected || _isConnecting) {
        timer.cancel();
        return;
      }

      if (_reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
        timer.cancel();
        print('Max reconnection attempts reached');
        return;
      }

      _reconnectAttempts++;
      print('Reconnection attempt $_reconnectAttempts of $MAX_RECONNECT_ATTEMPTS');

      if (_currentUserId != null) {
        var loginData=await apiService.getLoginData();
        if(loginData==null){
          print('登录数据为空');
          return;
        }
        String token=loginData['token']!;
        await connectSocket(_currentUserId!,token);
      }
    });

    // 一分钟后重置重连次数
    Future.delayed(RECONNECT_RESET_INTERVAL, () {
      _resetReconnectAttempts();
    });
  }

  void _resetReconnectAttempts() {
    _reconnectAttempts = 0;
  }
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(HEARTBEAT_INTERVAL, (timer) {
      if (_isConnected && _socket != null) {
        _socket!.emit('ping');
        
        Future.delayed(HEARTBEAT_TIMEOUT, () {
          if (_lastHeartbeatResponse == null || 
              DateTime.now().difference(_lastHeartbeatResponse!) > HEARTBEAT_TIMEOUT) {
            print('Heartbeat timeout');
            _handleDisconnection();
          }
        });
      }
    });
  }

  Future<void> disconnect() async {
    _manuallyDisconnected = true;
    await _cleanupExistingConnection();
    _resetReconnectAttempts();
  }
 
  void dispose() {
    disconnect();
    _currentUserId = null;
    onNewMessage = null;
    friendRequestAcceptedCallback = null;
  }
   // 语音通话信令回调
  Function(Map<String, dynamic>)? onCallInvite;
  Function(Map<String, dynamic>)? onCallSignal;
  
  // 缓存信令，等待回调设置
  List<Map<String, dynamic>> _pendingCallSignals = [];

  // 发送语音通话邀请
  void sendCallInvite({
    required String callId,
    required String from,
    required String to,
  }) {
    print('🔔 SocketService 发送 call_invite: callId=$callId, from=$from, to=$to');
    _socket?.emit('call_invite', {
      'callId': callId,
      'from': from,
      'to': to,
    });
    print('🔔 call_invite 已发送');
  }

  // 设置信令回调并处理缓存的信令
  void setCallSignalCallback(Function(Map<String, dynamic>) callback) {
    print('🔔 设置 call_signal 回调');
    onCallSignal = callback;
    
    // 处理缓存的信令
    if (_pendingCallSignals.isNotEmpty) {
      print('🔔 处理 ${_pendingCallSignals.length} 个缓存的信令');
      for (var signal in _pendingCallSignals) {
        print('🔔 处理缓存信令: ${signal['type']}');
        callback(signal);
      }
      _pendingCallSignals.clear();
      print('🔔 缓存信令处理完成');
    }
  }

  // 发送信令（offer/answer/ice）
  Future<void> sendCallSignal(Map<String, dynamic> data) async {
    print('🔔 SocketService 发送 call_signal: [38;5;2m${data['type']}[0m');
    print('🔔 call_signal 数据: $data');
    if (_socket != null && _isConnected) {
      _socket!.emit('call_signal', data);
      print('🔔 call_signal 已发送到服务器');
    } else {
      print('🔔 错误: Socket 未连接，无法发送 call_signal');
      print('🔔 Socket 状态: _socket=${_socket != null}, _isConnected=$_isConnected');
    }
  }
  // 发送好友请求接受事件的方法
  Future<bool> emitFriendRequestAccepted(String accepterId, String requesterId) async {
    if (!_isConnected || _socket == null) {
      print('Socket not connected for friend request acceptance');
      return false;
    }

    try {
      final data = {
        'accepterId': accepterId,
        'requesterId': requesterId,
        'timestamp': DateTime.now().toUtc().toIso8601String()
      };

      print('Emitting friend request accepted: $data');
      _socket!.emit('friend_request_accepted', [data]);
      return true;
    } catch (e) {
      print('Error emitting friend request accepted: $e');
      return false;
    }
  }

  Future<bool> sendMessage(String senderId, String receiverId, String content, 
  String image_url, String? audioUrl, int audioDuration,
   {String? videoUrl, String? fileUrl, String? fileName, String? fileSize, int? videoDuration, 
    double? latitude, double? longitude, String? locationAddress}) async {
    if (!_isConnected || _socket == null) {
      print('Socket not connected, attempting to reconnect...');
      if (_currentUserId != null) {
        var loginData=await apiService.getLoginData();  
        String? token=loginData?['token'];
        bool reconnected = await connectSocket(_currentUserId!,token!);
        if (!reconnected) {
          print('Reconnection failed');
          return false;
        }
      } else {
        return false;
      }
    }

    if (senderId != _currentUserId) {
      print('Sender ID mismatch: current=$_currentUserId, sender=$senderId');
      return false;
    }

    try {
      final messageData = {
        'senderId': senderId,
        'receiverId': receiverId,
        'content': content,
        'imageUrl': image_url,
        'audioUrl': audioUrl,
        'videoUrl': videoUrl,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'fileSize': fileSize,
        'audioDuration': audioDuration,
        'videoDuration': videoDuration,
        'latitude': latitude,
        'longitude': longitude,
        'locationAddress': locationAddress
      };

      print('Preparing to send message: $messageData');

      _socket!.emit('new_message', messageData);
      
      final completer = Completer<bool>();
      
      _socket!.once('message_sent', (response) {
        print('Message sent response: $response');
        if (response != null && response['success'] == true) {
          completer.complete(true);
        } else {
          completer.complete(false);
        }
      });

      return await completer.future.timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('Message send timeout');
          return false;
        },
      );

    } catch (e) {
      print('Error sending message: $e');
      return false;
    }
  }
  void rebindListeners(String email, String token) {
    connectSocket(email, token);
  }
  // 等待连接完成
  Future<bool> _waitForConnection() async {
    try {
      final completer = Completer<bool>();
      
      Timer(Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          print('Connection timeout');
          completer.complete(false);
        }
      });

      void onConnectSuccess(_) {
        if (!completer.isCompleted) {
          print('Connection successful');
          completer.complete(true);
        }
      }

      void onConnectError(error) {
        if (!completer.isCompleted) {
          print('Connection error: $error');
          completer.complete(false);
        }
      }

      _socket?.onConnect(onConnectSuccess);
      _socket?.onConnectError(onConnectError);

      final result = await completer.future;

      _socket?.off('connect', onConnectSuccess);
      _socket?.off('connect_error', onConnectError);

      return result;
    } catch (e) {
      print('Error in _waitForConnection: $e');
      return false;
    }
  }
}