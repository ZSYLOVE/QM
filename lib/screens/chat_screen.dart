import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:onlin/components/microphone_animation.dart';
import 'package:onlin/servers/api_service.dart';
import 'package:onlin/servers/message.dart';
import 'package:onlin/servers/socket_service.dart';
import 'dart:async';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:onlin/components/audio_wave.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:onlin/servers/download_service.dart';
import 'package:onlin/components/video_player_widget.dart';
import 'package:onlin/components/upload_progress_dialog.dart';
import 'package:onlin/services/friend_notification_service.dart';
import 'package:onlin/services/all_friends_notification_service.dart';
import 'package:onlin/services/location_service.dart';
import 'package:onlin/screens/location_picker_screen.dart';
// 时间转换工具
class TimeUtils {
  static DateTime parseUtcToLocal(String utcTime) {
    try {
      // 解析UTC时间
      final utcDateTime = DateTime.parse(utcTime);
      // 转换为北京时间 (UTC+8)
      return utcDateTime.add(Duration(hours: 8));
    } catch (e) {
      print('Error parsing UTC time: $utcTime, error: $e');
      // 如果解析失败，返回当前时间
      return DateTime.now();
    }
  }
  
  static String formatTime(DateTime time, [String format = 'HH:mm']) {
    return DateFormat(format).format(time);
  }
}

class ChatScreen extends StatefulWidget {
  final String friendEmail;
  final String friendNickname;
  final List<Map<String, dynamic>> friendsList;
  final String? currentUserAvatar;
  final String? avatarUrl;
  const ChatScreen({
    super.key,
    required this.friendEmail,
    required this.friendNickname,
    required this.friendsList,
    required this.currentUserAvatar,
    required this.avatarUrl,
  });

  @override
  // ignore: library_private_types_in_public_api
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  late List<Map<String, dynamic>> friendsList;
  List<Message> messages = [];
  late String userToken;
  late String userEmail;  // 当前用户邮箱
  late String userNickname;  // 当前用户昵称
  late String friendEmail;  // 好友邮箱
  late String friendNickname;  // 好友昵称
  bool isLoading = true;
  final SocketService _socketService = SocketService();
  ApiService apiService = ApiService();
  final DownloadService _downloadService = DownloadService();
  final ScrollController _scrollController = ScrollController();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isSocketConnected = false;
  Timer? _connectionCheckTimer;
  bool _showEmojiPicker = false;
  final FocusNode _focusNode = FocusNode();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  String? _recordedFilePath;
  bool _isRecording = false;
  Timer? _microphoneBlinkTimer;
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  String? _currentAudioUrl;
  Timer? _recordingTimer;
  int recordingSeconds = 0; // 录音时长（秒）
  double _startY = 0; // 记录开始滑动的 Y 坐标
  bool _showCancel = false; // 是否显示取消发送的提示
  double _currentVolume = 0.5; // 当前音量值
  Timer? _volumeTimer; // 音量检测定时器
  Timer? _fileStatusTimer; // 文件状态检查定时器
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _pendingCallSignals = [];
  bool _isVoiceMode = false;
  bool _inputBarVisible = true;
  double _inputBarHeight = 80;
  final GlobalKey _inputBarKey = GlobalKey();
  final Map<String, bool> _fileDownloading = {}; // cacheKey -> 是否正在下载
  final Map<String, UniqueKey> _fileFutureKeys = {}; // cacheKey -> UniqueKey
  final Map<String, ValueNotifier<double>> _fileProgressNotifier = {}; // cacheKey -> 进度
  bool _isImageDownloading = false;
  bool _isVideoDownloading = false;
  bool _isKeyboardVisible = false;

  bool _isSystemKeyboardAnimating = false; // 系统键盘动画s状态

  final Map<String, String?> _filePathCache = {}; // 文件路径缓存

  @override
  void initState() {
    super.initState();
    print('🔔 ChatScreen 初始化');
    
    _requestPermission();
    friendEmail = widget.friendEmail;
    friendNickname = widget.friendNickname;
    
    // 初始化好友通知服务
    FriendNotificationService.instance.initialize();
    // 初始化全局好友通知服务
    AllFriendsNotificationService.instance.initialize();
    
    _initializeChat();
    // print('🔔 设置 onCallInvite 监听');
    // _socketService.onCallInvite = _onCallInvite;
    _socketService.onNewMessage = _handleNewMessage;
    _socketService.onCallSignal = _handleCallSignal;
    _setupHeartbeat();
    _startConnectionCheck();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmojiPicker) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });
    
    // 监听键盘状态变化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        final wasKeyboardVisible = _isKeyboardVisible;
        _isKeyboardVisible = keyboardHeight > 0;
        
        // 检测系统键盘动画状态
        if (wasKeyboardVisible != _isKeyboardVisible) {
          _isSystemKeyboardAnimating = true;
          
          // 清理内存缓存以减少GC压力
          _clearMemoryCache();
          
          // 系统键盘动画通常需要300-500ms
          Future.delayed(Duration(milliseconds: 500), () {
            _isSystemKeyboardAnimating = false;
          });
        }
        
        // 只在键盘状态改变时触发滚动，并且只在键盘弹出时
        if (wasKeyboardVisible != _isKeyboardVisible && _isKeyboardVisible) {
          // 延迟滚动，等待系统键盘动画完成
          Future.delayed(Duration(milliseconds: 600), () { // 增加延迟等待系统键盘完全稳定
            if (mounted && !_isSystemKeyboardAnimating) {
              _scrollToBottom();
            }
          });
        }
      }
    });
    _initRecorder();
    
    // 启动文件状态检查定时器（每30秒检查一次）
    _fileStatusTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _checkFileStatus();
    });
    
    print('🔔 ChatScreen 初始化完成');
  }

  Future<void> _requestPermission() async {
    final status = await Permission.microphone.request();
    if (status.isDenied) {
      print('录音权限被拒绝');
    }
  }

  Future<void> _initRecorder() async {
    await _recorder.openRecorder();
  }

  void _setupHeartbeat() {
    // 每30秒检查一次连接状态
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _checkConnection();
    });

    // 如果断开连接，每5秒尝试重连一次
    _reconnectTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!_isSocketConnected) {
        _reconnectSocket();
      }
    });
  }

  Future<void> _checkConnection() async {
    if (_socketService.isConnected()) {
      setState(() {
        _isSocketConnected = true;
      });
    } else {
      setState(() {
        _isSocketConnected = false;
      });
      await _reconnectSocket();
    }
  }

  Future<void> _reconnectSocket() async {
    var loginData = await apiService.getLoginData();
    if (loginData != null) {
      userToken = loginData['token']!;
    }
    if (!_isSocketConnected) {
      try {
        bool connected = await _socketService.connectSocket(userEmail,userToken);
        if (connected) {
          setState(() {
            _isSocketConnected = true;
          });
          _socketService.onNewMessage = _handleNewMessage;
          print('Socket重连成功，刷新消息');
          await _loadChatHistory(); // 重连后刷新消息
        }
      } catch (e) {
        print('Reconnection failed: $e');
      }
    }
  }

  Future<void> _initializeChat() async {
    try {
      setState(() {
      });

      var loginData = await apiService.getLoginData();
      if (loginData != null) {
        setState(() {
          userToken = loginData['token']!;
          userEmail = loginData['email']!;
          userNickname = loginData['username'] ?? userEmail;
        });

        // 确保socket连接
        bool connected = await _socketService.connectSocket(userEmail, userToken);
        if (connected) {
          _socketService.onNewMessage = _handleNewMessage;
          print('Socket连接成功，开始加载聊天历史');
        } else {
          print('Socket连接失败，尝试重连');
          _showReconnectOption();
        }

        // 加载聊天历史
        await _loadChatHistory();

        _jumpToBottomWithRetry();

         _batchCheckFileStatus();
        // 立即标记消息为已读
        await _markMessagesAsRead();

      }
    } catch (e) {
      print('Error initializing chat: $e');
      _showReconnectOption();
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // 标记消息为已读
  Future<void> _markMessagesAsRead() async {
    try {
      await apiService.markMessagesAsRead(userEmail, friendEmail);
      print('消息已标记为已读');
    } catch (e) {
      print('标记消息为已读失败: $e');
    }
  }

  Future<void> _loadChatHistory() async {
    setState(() {
      isLoading = true;
    });

    try {
      print('Loading chat history...');
      final history = await apiService.getChatHistory(userEmail, friendEmail);
      print('Loaded ${history.length} messages');
      if (history.isNotEmpty) {
        print('消息时间范围: ${history.first.timestamp} ~ ${history.last.timestamp}');
      }



      if (mounted) {
        setState(() {
          messages = history.map((message) {
            // 调试位置字段
            if (message.content?.contains('📍 我的位置') == true) {
              print('DEBUG: 发现位置消息 - ID: ${message.id}');
              print('DEBUG: 原始位置字段 - latitude: ${message.latitude}, longitude: ${message.longitude}, locationAddress: ${message.locationAddress}');
              print('DEBUG: 消息内容: ${message.content}');
            }
            
            // 特殊处理：如果消息内容包含位置坐标，尝试提取坐标信息
            double? extractedLatitude = message.latitude;
            double? extractedLongitude = message.longitude;
            String? extractedLocationAddress = message.locationAddress;
            
            // 如果后端没有提供位置字段，但消息内容包含坐标，尝试从内容中提取
            if (extractedLatitude == null && extractedLongitude == null && 
                message.content?.contains('坐标:') == true) {
              final content = message.content as String;
              final coordinateMatch = RegExp(r'坐标:\s*([\d.]+),\s*([\d.]+)').firstMatch(content);
              if (coordinateMatch != null) {
                extractedLatitude = double.tryParse(coordinateMatch.group(1) ?? '');
                extractedLongitude = double.tryParse(coordinateMatch.group(2) ?? '');
                
                // 提取地址信息
                final addressMatch = RegExp(r'📍 我的位置\n(.*?)\n\n坐标:').firstMatch(content);
                if (addressMatch != null) {
                  extractedLocationAddress = addressMatch.group(1);
                }
                
                print('DEBUG: 从聊天历史提取位置信息 - ID: ${message.id}, 纬度: $extractedLatitude, 经度: $extractedLongitude, 地址: $extractedLocationAddress');
              }
            }
            
            return Message(
              id: message.id,
              content: message.content,
              senderId: message.senderId,
              receiverId: message.receiverId,
              timestamp: message.timestamp,
              isMe: message.isMe,
              audioUrl: message.audioUrl,
              imageUrl: message.imageUrl,
              videoUrl: message.videoUrl,
              fileUrl: message.fileUrl,
              fileName: message.fileName,
              fileSize: message.fileSize,
              audioDuration: message.audioDuration,
              videoDuration: message.videoDuration,
              latitude: extractedLatitude,
              longitude: extractedLongitude,
              locationAddress: extractedLocationAddress,
            );
          }).toList();
          isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();

        });
      }
    } catch (e) {
      print('Error loading chat history: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载聊天记录失败'),
            action: SnackBarAction(
              label: '重试',
              onPressed: _loadChatHistory,
            ),
          ),
        );
      }
    }
  }


  // 批量检查文件状态，避免在UI中频繁检查
  Future<void> _batchCheckFileStatus() async {
    try {
      final downloadDir = await _downloadService.getDownloadDirectory();
      if (downloadDir == null) return;

      // 收集所有需要检查的文件
      final filesToCheck = <String, String>{};
      for (final message in messages) {
        if (message.fileUrl != null && message.fileUrl!.isNotEmpty && message.fileName != null) {
          final cacheKey = '${friendEmail}_${message.fileUrl}';
          if (!_filePathCache.containsKey(cacheKey)) {
            filesToCheck[message.fileUrl!] = message.fileName!;
          }
        }
      }

      // 批量检查文件状态
      for (final entry in filesToCheck.entries) {
        final fileUrl = entry.key;
        final fileName = entry.value;
        final cacheKey = '${friendEmail}_$fileUrl';
        
        final cleanFileName = _downloadService.cleanFileName(fileName);
        final filePath = '$downloadDir/$cleanFileName';
        final exists = await _downloadService.fileExists(filePath);
        
        _filePathCache[cacheKey] = exists ? filePath : null;
      }

      // 刷新UI
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('批量检查文件状态失败: $e');
    }
  }
  
  void _handleNewMessage(Map<String, dynamic> data) {
  if (!mounted) return;

  print('📨 收到新消息推送: $data');
  
  // 触发好友特定的新消息通知
  FriendNotificationService.instance.triggerFriendMessageNotification(friendEmail);
  
  // 转换UTC时间为本地时间
  final utcTimestamp = data['timestamp'] as String;
  final localTime = TimeUtils.parseUtcToLocal(utcTimestamp);
  
  print('📨 收到新消息推送: $data');
  print('UTC时间: $utcTimestamp');
  print('本地时间: ${localTime.toString()}');
  final normalizedData = _normalizeMessageData(data);
  normalizedData['timestamp'] = localTime.toString();

  // 处理ID字段，确保类型正确
  int messageId;
  if (normalizedData['id'] != null) {
    messageId = normalizedData['id'] is int ? normalizedData['id'] : int.parse(normalizedData['id'].toString());
  } else {
    messageId = DateTime.now().millisecondsSinceEpoch;
  }

  // 特殊处理：如果消息内容包含位置坐标，尝试提取坐标信息
  double? extractedLatitude = normalizedData['latitude'];
  double? extractedLongitude = normalizedData['longitude'];
  String? extractedLocationAddress = normalizedData['locationAddress'];
  
  // 如果后端没有提供位置字段，但消息内容包含坐标，尝试从内容中提取
  if (extractedLatitude == null && extractedLongitude == null && 
      normalizedData['content']?.contains('坐标:') == true) {
    final content = normalizedData['content'] as String;
    final coordinateMatch = RegExp(r'坐标:\s*([\d.]+),\s*([\d.]+)').firstMatch(content);
    if (coordinateMatch != null) {
      extractedLatitude = double.tryParse(coordinateMatch.group(1) ?? '');
      extractedLongitude = double.tryParse(coordinateMatch.group(2) ?? '');
      
      // 提取地址信息
      final addressMatch = RegExp(r'📍 我的位置\n(.*?)\n\n坐标:').firstMatch(content);
      if (addressMatch != null) {
        extractedLocationAddress = addressMatch.group(1);
      }
      
      print('DEBUG: 从消息内容提取位置信息 - 纬度: $extractedLatitude, 经度: $extractedLongitude, 地址: $extractedLocationAddress');
    }
  }
  
  final newMessage = Message(
    id: messageId,
    content: normalizedData['content'],
    senderId: normalizedData['senderId'],
    receiverId: normalizedData['receiverId'] ?? friendEmail,
    timestamp: localTime,
    isMe: normalizedData['senderId'] == userEmail,
    status: 'sent',
    audioUrl: normalizedData['audioUrl'] ?? '',
    imageUrl: normalizedData['imageUrl'] ?? '',
    videoUrl: normalizedData['videoUrl'] ?? '',
    fileUrl: normalizedData['fileUrl'] ?? '',
    fileName: normalizedData['fileName'] ?? '',
    fileSize: normalizedData['fileSize'] ?? '',
    audioDuration: normalizedData['audioDuration'] ?? 0,
    videoDuration: normalizedData['videoDuration'] ?? 0,
    // 使用提取的位置字段
    latitude: extractedLatitude,
    longitude: extractedLongitude,
    locationAddress: extractedLocationAddress,
  );

  // 查找是否存在重复消息（内容 + 发送方 + 时间相近）
  final index = messages.indexWhere((msg) =>
    msg.senderId == newMessage.senderId &&
    msg.content == newMessage.content &&
    msg.timestamp.difference(newMessage.timestamp).inSeconds.abs() < 2
  );

  if (index != -1) {
    print('🔄 替换已有的临时消息为服务器消息');
    setState(() {
      messages[index] = newMessage;
    });
  } else {
    print('➕ 添加新消息');
    setState(() {
      messages.add(newMessage);
    });
  }

  // 标记为已读（只要是聊天窗口内的消息，都直接标记）
  _markMessagesAsRead();

  // 滚动到底部
  Future.delayed(Duration(milliseconds: 100), _scrollToBottom);
}


  // 统一处理消息数据格式，兼容数据库格式和实时消息格式
  Map<String, dynamic> _normalizeMessageData(Map<String, dynamic> data) {
    return {
      'id': data['id'] ?? data['messageId'], // 兼容两种ID字段格式
      'content': data['content'],
      'senderId': data['senderId'] ?? data['sender_id'],
      'receiverId': data['receiverId'] ?? data['receiver_id'],
      'timestamp': data['timestamp'] ?? data['timestamp'], 
      'audioUrl': data['audioUrl'] ?? data['audio_url'],
      'imageUrl': data['imageUrl'] ?? data['image_url'],
      'videoUrl': data['videoUrl'] ?? data['video_url'],
      'fileUrl': data['fileUrl'] ?? data['file_url'],
      'fileName': data['fileName'] ?? data['file_name'],
      'fileSize': data['fileSize'] ?? data['file_size'],
      'audioDuration': data['audioDuration'],
      'videoDuration': data['videoDuration'] ?? data['video_duration'],
      // 添加位置字段标准化
      'latitude': data['latitude'] ?? data['lat'],
      'longitude': data['longitude'] ?? data['lng'],
      'locationAddress': data['locationAddress'] ?? data['location_address'] ?? data['address'],
    };
  }

  Timer? _scrollTimer;
  
  void _scrollToBottom() {
    // 如果系统键盘优化模式启用且系统键盘正在动画，跳过滚动
    if (_shouldPauseOperations()) {
      return;
    }
    
    // 如果键盘正在动画，完全跳过滚动
    if (_isSystemKeyboardAnimating) {
      return;
    }
    
    // 防抖处理，避免频繁滚动
    _scrollTimer?.cancel();
    final debounceTime = _isSystemKeyboardAnimating ? 200 : 150;
    _scrollTimer = Timer(Duration(milliseconds: debounceTime), () {
      if (_scrollController.hasClients && mounted && !_shouldPauseOperations() && !_isSystemKeyboardAnimating) {
        // 使用更高效的滚动方式
        final maxScroll = _scrollController.position.maxScrollExtent;
        final threshold = _isSystemKeyboardAnimating ? 200 : 150;
        if (_scrollController.offset < maxScroll - threshold) {
          final duration = _isSystemKeyboardAnimating ? 400 : 300;
          _scrollController.animateTo(
            maxScroll,
            duration: Duration(milliseconds: duration),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _showReconnectOption() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('聊天服务连接失败'),
          action: SnackBarAction(
            label: '重试',
            onPressed: _initializeChat,
          ),
        ),
      );
    }
  }

  void _startConnectionCheck() {
    _connectionCheckTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _isSocketConnected = _socketService.isConnected();
        });
      }
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _connectionCheckTimer?.cancel();
    _scrollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _recorder.closeRecorder();
    _microphoneBlinkTimer?.cancel();
    _player.closePlayer();
    _recordingTimer?.cancel();
    _volumeTimer?.cancel();
    _fileStatusTimer?.cancel();
    
    // 清理当前聊天对象的缓存
    _clearCurrentChatCache();
    
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当页面重新获得焦点时，刷新消息
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !isLoading) {
        _refreshMessagesIfNeeded();
      }
    });
  }

  // 检查是否需要刷新消息
  Future<void> _refreshMessagesIfNeeded() async {
    try {
      final currentHistory = await apiService.getChatHistory(userEmail, friendEmail);
      if (currentHistory.length != messages.length) {
        print('检测到消息数量变化，刷新消息列表');
        await _loadChatHistory();
      }
    } catch (e) {
      print('检查消息更新失败: $e');
    }
  }

  // 清理当前聊天对象的缓存
  void _clearCurrentChatCache() {
    final keysToRemove = <String>[];
    
    // 清理文件路径缓存
    for (final key in _filePathCache.keys) {
      if (key.startsWith('${friendEmail}_')) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _filePathCache.remove(key);
    }
    
    // 清理下载状态缓存
    keysToRemove.clear();
    for (final key in _fileDownloading.keys) {
      if (key.startsWith('${friendEmail}_')) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _fileDownloading.remove(key);
    }
    
    // 清理进度通知器
    keysToRemove.clear();
    for (final key in _fileProgressNotifier.keys) {
      if (key.startsWith('${friendEmail}_')) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _fileProgressNotifier.remove(key);
    }
    
    // 清理FutureBuilder键
    keysToRemove.clear();
    for (final key in _fileFutureKeys.keys) {
      if (key.startsWith('${friendEmail}_')) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _fileFutureKeys.remove(key);
    }
    
    print('已清理聊天对象 $friendEmail 的缓存');
  }

 Future<void> _sendMessage() async {
  String content = _controller.text.trim();
  if (content.isEmpty) return;

  // 先清空输入框，提升用户体验
  _controller.clear();
  
  // 记录发送开始时间
  final sendStartTime = DateTime.now().toLocal();
  final tempId = sendStartTime.millisecondsSinceEpoch;
  final now = DateTime.now();
  // 滚动到底部
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _scrollToBottom();
  });

  try {
      final tempId = now.millisecondsSinceEpoch;
      setState(() {
            messages.add(Message(
            id: tempId,
            content: content,
            senderId: userEmail,
            receiverId: friendEmail,
            timestamp: now,
            isMe: true,
            audioUrl: '',
            imageUrl: '',
            videoUrl: '',
            fileUrl: '',
            fileName: '',
            fileSize: '',
            audioDuration: 0,
            videoDuration: 0,
        ));
      });
    // 调用API发送消息
    var response = await apiService.sendMessage(
      senderId: userEmail,
      receiverId: friendEmail,
      content: content,
    );
    
    if (response != null && response['success'] != false) {
      //发送成功时，创建消息对象
      
      // 通过 WebSocket 立即推送消息
      bool sentViaSocket = await _socketService.sendMessage(
        userEmail,  
        friendEmail,  
        content,  
        '',  
        '', 
        0, 
      );

      if (sentViaSocket) {
        print('WebSocket 推送消息成功');
      }
        // WebSocket 推送成功后，立即更新 UI
        setState(() {
          int idx = messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
          messages[idx] = Message(
            id: response['id'],
            content: content,
            senderId: userEmail,
            receiverId: friendEmail,
            timestamp: now,
            isMe: true,
            audioUrl: '',
            imageUrl: '',
            videoUrl: '',
            fileUrl: '',
            fileName: '',
            fileSize: '',
            audioDuration: 0,
            videoDuration: 0,
          );
      };
        });

        // 确保消息列表滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
    } else {
      // 发送失败，更新消息状态为失败
      setState(() {
        int idx = messages.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(
            status: 'failed',
          );
        }
      });

      // 显示错误提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发送消息失败，请重试'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: '重试',
            textColor: Colors.white,
            onPressed: () {
              // 移除失败的消息，重新发送
              setState(() {
                messages.removeWhere((m) => m.id == tempId);
              });
              _controller.text = content;
              _sendMessage();
            },
          ),
        ),
      );
    }
  } catch (e) {
    print('发送消息异常: $e');
    
    // 发送异常，更新消息状态为失败
    setState(() {
      int idx = messages.indexWhere((m) => m.id == tempId);
      if (idx != -1) {
        messages[idx] = messages[idx].copyWith(
          status: 'failed',
        );
      }
    });
    
    // 显示错误提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('网络错误，发送失败'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: '重试',
          textColor: Colors.white,
          onPressed: () {
            // 移除失败的消息，重新发送
            setState(() {
              messages.removeWhere((m) => m.id == tempId);
            });
            _controller.text = content;
            _sendMessage();
          },
        ),
      ),
    );
  }
}



  @override
  Widget build(BuildContext context) {
    // 获取键盘高度和安全区域
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isKeyboardVisible = keyboardHeight > 0;
    
    // 动态获取输入栏高度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _inputBarKey.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox;
        final newHeight = box.size.height;
        if (_inputBarHeight != newHeight) {
          setState(() {
            _inputBarHeight = newHeight;
          });
        }
      }
    });
    
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('加载中...'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载聊天记录...', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.blue[50],
      resizeToAvoidBottomInset: false, // 改为false，手动处理键盘
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 201, 230, 244),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              friendNickname,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              friendEmail,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isSocketConnected ? Colors.green : Colors.red,
                ),
              ),
            ),
          ),

          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadChatHistory,
            tooltip: '刷新聊天记录',
          ),
          PopupMenuButton<String>(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            onSelected: (value) async {
              if (value == 'clear') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('清空聊天记录'),
                    content: Text('确定要清空与该好友的聊天记录吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('清空', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _clearChatHistory();
                }
              } else if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('删除好友'),
                    content: Text('确定要删除该好友吗？此操作不可恢复！'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('删除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _deleteFriend();
                }
              } else if (value == 'notification') {
                await FriendNotificationService.instance.toggleFriendMessageNotification(friendEmail);
                setState(() {}); // 刷新UI
              } else if (value == 'vibration') {
                await FriendNotificationService.instance.toggleFriendMessageVibration(friendEmail);
                setState(() {}); // 刷新UI
              } else if (value == 'sound') {
                await FriendNotificationService.instance.toggleFriendMessageSound(friendEmail);
                setState(() {}); // 刷新UI
              } 
            },
            itemBuilder: (context) => [
              // 通知设置分隔线
              PopupMenuItem(
                enabled: false,
                child: Text(
                  '${friendNickname}的通知设置',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 新消息通知开关
              PopupMenuItem(
                value: 'notification',
                child: Row(
                  children: [
                    Icon(
                      FriendNotificationService.instance.isFriendNotificationEnabled(friendEmail) ? Icons.notifications_active : Icons.notifications_off,
                      color: FriendNotificationService.instance.isFriendNotificationEnabled(friendEmail) ? Colors.blue : Colors.grey,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text('新消息通知'),
                    Spacer(),
                    Icon(
                      FriendNotificationService.instance.isFriendNotificationEnabled(friendEmail) ? Icons.check : Icons.close,
                      color: FriendNotificationService.instance.isFriendNotificationEnabled(friendEmail) ? Colors.blue : Colors.grey,
                      size: 16,
                    ),
                  ],
                ),
              ),
              // 震动开关
              PopupMenuItem(
                value: 'vibration',
                child: Row(
                  children: [
                    Icon(
                      FriendNotificationService.instance.isFriendVibrationEnabled(friendEmail) ? Icons.vibration : Icons.vibration_sharp,
                      color: FriendNotificationService.instance.isFriendVibrationEnabled(friendEmail) ? Colors.blue : Colors.grey,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text('震动提醒'),
                    Spacer(),
                    Icon(
                      FriendNotificationService.instance.isFriendVibrationEnabled(friendEmail) ? Icons.check : Icons.close,
                      color: FriendNotificationService.instance.isFriendVibrationEnabled(friendEmail) ? Colors.blue : Colors.grey,
                      size: 16,
                    ),
                  ],
                ),
              ),
              // 铃声开关
              PopupMenuItem(
                value: 'sound',
                child: Row(
                  children: [
                    Icon(
                      FriendNotificationService.instance.isFriendSoundEnabled(friendEmail) ? Icons.music_note : Icons.music_off,
                      color: FriendNotificationService.instance.isFriendSoundEnabled(friendEmail) ? Colors.blue : Colors.grey,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text('铃声提醒'),
                    Spacer(),
                    Icon(
                      FriendNotificationService.instance.isFriendSoundEnabled(friendEmail) ? Icons.check : Icons.close,
                      color: FriendNotificationService.instance.isFriendSoundEnabled(friendEmail) ? Colors.blue : Colors.grey,
                      size: 16,
                    ),
                  ],
                ),
              ),

              // 分隔线
              PopupMenuItem(
                enabled: false,
                child: Text(
                  '消息设置',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 清空聊天记录
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('清空聊天记录'),
                  ],
                ),
              ),
              // 删除好友
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('删除好友', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    // 如果键盘正在动画，跳过滚动监听
                    if (_isSystemKeyboardAnimating) {
                      return false;
                    }
                    
                    if (notification.direction == ScrollDirection.idle) {
                      // 停止滑动
                      if (!_inputBarVisible) {
                        setState(() {
                          _inputBarVisible = true;
                        });
                      }
                    } else {
                      // 正在滑动
                      if (_inputBarVisible && notification.metrics.pixels > 200) { // 增加阈值
                        setState(() {
                          _inputBarVisible = false;
                        });
                      }
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: _loadChatHistory,
                    child: messages.isEmpty
                      ? _buildEmptyChat()
                      : ListView.builder(
                          cacheExtent: _isSystemKeyboardAnimating ? 50 : 500, // 键盘动画时大幅减少缓存
                          controller: _scrollController,
                          padding: EdgeInsets.only(
                            bottom: _inputBarHeight + keyboardHeight + bottomPadding,
                          ),
                          itemCount: messages.length,
                          reverse: false, // 确保消息按时间顺序显示
                          physics: _isSystemKeyboardAnimating ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(), // 键盘动画时禁用滚动
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: false,
                          itemExtent: null, // 允许动态高度
                          prototypeItem: null, // 不使用原型项
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final showTimestamp = _shouldShowTimestamp(index);
                            final revokedByMe = index > 0 && messages[index - 1].isRevoked && messages[index - 1].senderId == userEmail;

                            return RepaintBoundary(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showTimestamp)
                                    _buildTimestampDivider(message.timestamp, revokedByMe: revokedByMe),
                                  _buildMessageBubble(message),
                                ],
                              ),
                            );
                          },
                        ),
                  ),
                ),
              ),
            ],
          ),
          // 悬浮输入栏 - 考虑键盘高度
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboardHeight + bottomPadding,
            child: AnimatedSlide(
              offset: _inputBarVisible ? Offset(0, 0) : Offset(0, 1),
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: RepaintBoundary(
                child: _buildMessageInput(),
              ),
            ),
          ),
          // 录音动画
          if (_isRecording)
            Center(
              child: MicrophoneAnimation(
                recordingSeconds: recordingSeconds,
                showCancel: _showCancel,
                volume: _currentVolume,
              ),
            ),
        ],
      ),
    );
  }

  bool _shouldShowTimestamp(int index) {
    if (index == 0) return true;
    final currentMessage = messages[index];
    final previousMessage = messages[index - 1];
    return _isNewTimeGroup(currentMessage.timestamp, previousMessage.timestamp) || previousMessage.isRevoked;
  }

  bool _isNewTimeGroup(DateTime current, DateTime previous) {
    return current.difference(previous).inMinutes >= 5;
  }

  Widget _buildTimestampDivider(DateTime timestamp, {bool revokedByMe = false}) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.0),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            revokedByMe ? '你撤回了一条信息' : _formatTimestamp(timestamp),
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();

    // 如果是今天的消息
    if (timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day) {
      return '今天 ${_formatTime(timestamp)}';
    }

    // 如果是昨天的消息
    final yesterday = now.subtract(Duration(days: 1));
    if (timestamp.year == yesterday.year &&
        timestamp.month == yesterday.month &&
        timestamp.day == yesterday.day) {
      return '昨天 ${_formatTime(timestamp)}';
    }

    // 如果是本周的消息（不是今天/昨天，且不是未来）
    final difference = now.difference(timestamp);
    if (difference.inDays < 7 && difference.inDays > 0) {
      return '${_getWeekday(timestamp)} ${_formatTime(timestamp)}';
    }

    // 如果是今年的消息
    if (timestamp.year == now.year) {
      return '${timestamp.month}月${timestamp.day}日 ${_formatTime(timestamp)}';
    }

    // 其他情况
    return '${timestamp.year}年${timestamp.month}月${timestamp.day}日 ${_formatTime(timestamp)}';
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  String _getWeekday(DateTime timestamp) {
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[timestamp.weekday - 1];
  }

  Widget _buildMessageBubble(Message message) {
    final isMe = message.senderId == userEmail;
    final bool isPlaying = _player.isPlaying && _currentAudioUrl == message.audioUrl;
    final String nickname = isMe ? userNickname : friendNickname;
    final String email = isMe ? userEmail : friendEmail;

    // 只渲染可见消息
    if (!message.isVisibleFor(userEmail)) return SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) _buildAvatar(nickname, email),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onLongPressStart: (details) async {
                final isMe = message.senderId == userEmail;
                final pageContext = context;
                final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                final selected = await showMenu<String>(
                  context: context,
                  position: RelativeRect.fromRect(
                    details.globalPosition & const Size(1, 1), // 更贴近气泡
                    Offset.zero & overlay.size,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  items: [
                    if (isMe)
                      PopupMenuItem(
                        value: 'revoke',
                        height: 48,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.undo, color: Colors.blue, size: 22),
                            SizedBox(width: 8),
                            Text('撤回', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 16)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      height: 48,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red, size: 22),
                          SizedBox(width: 8),
                          Text('删除', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 16)),
                        ],
                      ),
                    ),
                  ],
                );
                if (selected == 'revoke') {
                  await Future.delayed(Duration(milliseconds: 200));
                  final now = DateTime.now().toUtc();
                  final beijingTime = now.add(Duration(hours: 8));
                  print('撤回消息：${beijingTime}');
                  print('撤回消息${message.timestamp}');
                  final diff = beijingTime.difference(message.timestamp);
                  print('撤回检查: 当前UTC=$beijingTime, 消息时间=${message.timestamp}, 差值=${diff.inSeconds}秒');
                  if (diff.inMinutes >= 2||diff.inSeconds < 0) {
                    ScaffoldMessenger.of(pageContext).showSnackBar(
                      SnackBar(content: Text('只能在2分钟内撤回消息')),
                    );
                    return;
                  }
                  if (message.id < 10000000000000) {
                    final success = await apiService.revokeMessage(message.id, userEmail);
                    if (success) {
                      setState(() {
                        final idx = messages.indexWhere((m) => m.id == message.id);
                        if (idx != -1) {
                          messages[idx] = messages[idx].copyWith(
                            visibleToSender: false,
                            visibleToReceiver: false,
                          );
                        }
                      });
                    } else {
                      ScaffoldMessenger.of(pageContext).showSnackBar(SnackBar(content: Text('撤回失败')));
                    }
                  } else {
                    ScaffoldMessenger.of(pageContext).showSnackBar(
                      SnackBar(content: Text('消息还未同步，无法撤回')),
                    );
                  }
                } else if (selected == 'delete') {
                  await Future.delayed(Duration(milliseconds: 200));
                  final success = await apiService.deleteMessage(message.id, userEmail);
                  if (success) {
                    setState(() {
                      final idx = messages.indexWhere((m) => m.id == message.id);
                      if (idx != -1) {
                        if (isMe) {
                          messages[idx] = messages[idx].copyWith(visibleToSender: false);
                        } else {
                          messages[idx] = messages[idx].copyWith(visibleToReceiver: false);
                        }
                      }
                    });
                  } else {
                    ScaffoldMessenger.of(pageContext).showSnackBar(SnackBar(content: Text('删除失败')));
                  }
                }
              },
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? Colors.blue[600] : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isMe ? 20 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: message.isRevoked
                  ? Text('消息已撤回', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 如果是图片消息
                        if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ImageViewerPage(imageUrl: message.imageUrl!),
                                ),
                              );
                            },
                            child: Container(
                              width: 120, // 设置图片宽度
                              height: 120, // 设置图片高度
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8.0),
                                color: Colors.grey[200],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: CachedNetworkImage(
                                  imageUrl: message.imageUrl!,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 240, // 限制内存缓存大小
                                  memCacheHeight: 240,
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey[200],
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey[200],
                                    child: Center(
                                      child: Icon(Icons.error, color: Colors.grey[600]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // 如果是视频消息
                        if (message.videoUrl != null && message.videoUrl!.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => VideoViewerPage(videoUrl: message.videoUrl!),
                                ),
                              );
                            },
                            child: Container(
                              width: 200,
                              height: 150,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8.0),
                                color: Colors.black,
                              ),
                              child: Stack(
                                children: [
                                  // 使用占位符而不是直接加载视频播放器
                                  Container(
                                    width: 200,
                                    height: 150,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8.0),
                                      color: Colors.grey[800],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.video_file,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.play_arrow,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // 如果是文件消息
                        if (message.fileUrl != null && message.fileUrl!.isNotEmpty)
                          Builder(
                            builder: (context) {
                              // 生成唯一的缓存键
                              final cacheKey = '${friendEmail}_${message.fileUrl}';
                              final isDownloading = _fileDownloading[cacheKey] == true;
                              Widget trailing;
                              if (isDownloading && _fileProgressNotifier.containsKey(cacheKey)) {
                                // 下载中，trailing 显示进度条
                                trailing = SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: ValueListenableBuilder<double>(
                                    valueListenable: _fileProgressNotifier[cacheKey]!,
                                    builder: (context, progress, child) {
                                      final safeValue = (progress > 0 && progress <= 1.0) ? progress : 0.01;
                                      final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
                                      return Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            value: safeValue,
                                            strokeWidth: 3,
                                          ),
                                          Text(
                                            '$percent%',
                                            style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                );
                              } else {
                                // 非下载中，trailing 显示下载按钮或空
                                // 首先检查缓存，避免频繁的文件系统访问
                                final cachedPath = _filePathCache[cacheKey];
                                if (cachedPath != null) {
                                  // 只用缓存，不再异步检查
                                  trailing = Icon(Icons.check_circle, color: Colors.green, size: 24);
                                } else if (cachedPath == null && _filePathCache.containsKey(cacheKey)) {
                                  trailing = Icon(Icons.download, color: Colors.blue, size: 24);
                                } else {
                                  // 首次查找本地文件
                                  trailing = FutureBuilder<String?>(
                                    key: _fileFutureKeys[cacheKey],
                                    future: _findLocalFilePath(message.fileUrl!, message.fileName ?? '文件'),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        );
                                      }
                                      final localPath = snapshot.data;
                                      final isDownloaded = localPath != null;
                                      if (isDownloaded) {
                                        // 只在这里更新缓存
                                        _filePathCache[cacheKey] = localPath;
                                        return Icon(Icons.check_circle, color: Colors.green, size: 24);
                                      } else {
                                        _filePathCache[cacheKey] = null;
                                        return Icon(Icons.download, color: Colors.blue, size: 24);
                                      }
                                    },
                                  );
                                }
                              }
                              return GestureDetector(
                                onTap: () async {
                                  if (!isDownloading) {
                                    print('点击文件: ${message.fileName}, URL: ${message.fileUrl}');
                                    final cacheKey = '${friendEmail}_${message.fileUrl}';
                                    String? localPath = _filePathCache[cacheKey];

                                    // 如果缓存有路径，检查文件是否真的存在
                                    if (localPath != null) {
                                      final fileExists = await _downloadService.fileExists(localPath);
                                      if (fileExists) {
                                        print('尝试打开文件: $localPath');
                                        try {
                                          await _downloadService.openFile(localPath);
                                        } catch (e) {
                                          print('打开文件失败: $e');
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('打开文件失败: $e')),
                                          );
                                        }
                                        return; // 已处理，直接返回
                                      } else {
                                        // 文件不存在，清理缓存
                                        print('文件不存在，清除缓存并准备下载');
                                        _filePathCache.remove(cacheKey);
                                        setState(() {});
                                        localPath = null;
                                      }
                                    }

                                    // 缓存没有路径或文件已被删除，查找本地路径（可能是首次下载）
                                    if (localPath == null) {
                                      final foundPath = await _findLocalFilePath(message.fileUrl!, message.fileName ?? '文件');
                                      if (foundPath != null) {
                                        final fileExists = await _downloadService.fileExists(foundPath);
                                        if (fileExists) {
                                          print('尝试打开文件: $foundPath');
                                          try {
                                            await _downloadService.openFile(foundPath);
                                          } catch (e) {
                                            print('打开文件失败: $e');
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('打开文件失败: $e')),
                                            );
                                          }
                                          return;
                                        }
                                      }
                                      // 文件未下载，开始下载
                                      print('文件未下载，开始下载');
                                      await _onFileTap(message.fileUrl!, message.fileName ?? '文件');
                                    }
                                  }
                                },
                                child: Container(
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _downloadService.getFileTypeIcon(message.fileName ?? ''),
                                        style: TextStyle(fontSize: 24),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              message.fileName ?? '文件',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (message.fileSize != null)
                                              Text(
                                                message.fileSize!,
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      trailing,
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        // 如果是语音消息
                        if (message.audioUrl != null && message.audioUrl!.isNotEmpty)
                          InkWell(
                            onTap: () {
                              print('尝试播放音频: ${message.audioUrl}');
                              if (isPlaying) {
                                _player.stopPlayer();
                              } else {
                                _playAudio(message.audioUrl!);
                              }
                            },
                            child: Container(
                              width:58,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                // ignore: deprecated_member_use
                                color: isPlaying ? Colors.blue.withOpacity(0.3) : Colors.transparent,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isMe) ...[
                                    Text(
                                      '${message.audioDuration ?? 0}″',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: AudioWave(
                                      isPlaying: isPlaying,
                                      size: 20,
                                    ),
                                  ),
                                  if (!isMe) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '${message.audioDuration ?? 0}″',
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        // 如果是位置消息
                        if (message.latitude != null && message.longitude != null)
                          GestureDetector(
                            onTap: () {
                              _openLocationInMap(message.latitude!, message.longitude!);
                            },
                            child: Container(
                              width: 200,
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green[200]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        color: Colors.green[600],
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        '位置',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.green[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    message.locationAddress ?? '未知位置',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '点击查看地图',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // 如果位置字段为空但内容包含位置信息，也显示位置卡片
                        if (message.latitude == null && message.longitude == null && message.content?.contains('📍 我的位置') == true)
                          GestureDetector(
                            onTap: () {
                              // 尝试从内容中提取坐标
                              final content = message.content as String;
                              final coordinateMatch = RegExp(r'坐标:\s*([\d.]+),\s*([\d.]+)').firstMatch(content);
                              if (coordinateMatch != null) {
                                final lat = double.tryParse(coordinateMatch.group(1) ?? '');
                                final lng = double.tryParse(coordinateMatch.group(2) ?? '');
                                if (lat != null && lng != null) {
                                  _openLocationInMap(lat, lng);
                                }
                              }
                            },
                            child: Container(
                              width: 200,
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green[200]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        color: Colors.green[600],
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        '位置',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.green[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '位置信息',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '点击查看地图',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 如果是文本消息
                        if (message.content != null && message.content!.isNotEmpty)
                          Text(
                            message.content!,
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 16,
                            ),
                          ),
                        // 时间戳
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('HH:mm').format(message.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: isMe ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
              ),
          ),
          const SizedBox(width: 8),
          if (isMe) _buildAvatar(nickname, email),
        ],
      ),
    );
  }

  Widget _buildAvatar(String nickname, String email) {
    // 判断是否是当前用户
    final isCurrentUser = email == userEmail;

    // 获取头像链接
    Future<String?> fetchAvatarUrl() async {
      if (isCurrentUser) {
        return widget.currentUserAvatar;
      } else {
        return widget.avatarUrl;
      }
    }

    return FutureBuilder<String?>(
      future: fetchAvatarUrl(),
      builder: (context, snapshot) {
        String? avatarUrl = snapshot.data;

        return Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue[100],
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.blue[900],
                  fontWeight: FontWeight.bold,
                ),
              )
                  : null,
            ),
            SizedBox(height: 4),
            Container(
              constraints: BoxConstraints(maxWidth: 60),
              child: Column(
                children: [
                  Text(
                    nickname,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 8,
                      color: Colors.grey[400],
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
  Widget _buildMessageInput() {
    return Container(
      key: _inputBarKey,
      width: MediaQuery.of(context).size.width,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    // 输入框或按住说话
                    Expanded(
                      child: !_isVoiceMode
                          ? RepaintBoundary(
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                maxLines: null,
                                minLines: 1,
                                textInputAction: TextInputAction.newline,
                                keyboardType: TextInputType.multiline,
                                enableInteractiveSelection: true,
                                decoration: InputDecoration(
                                  hintText: '输入消息...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                onTap: () {
                                  if (_showEmojiPicker) {
                                    setState(() {
                                      _showEmojiPicker = false;
                                    });
                                  }
                                },
                                                              onChanged: (value) {
                                // 如果键盘正在动画，跳过滚动
                                if (_isSystemKeyboardAnimating) {
                                  return;
                                }
                                
                                // 输入时自动滚动到底部 - 优化性能
                                // 减少滚动频率，避免与系统键盘冲突
                                if (value.length > 50 || value.contains('\n')) { // 增加阈值
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    _scrollToBottom();
                                  });
                                }
                              },
                              ),
                            )
                          : GestureDetector(
                              onLongPressStart: (details) {
                                _startY = details.globalPosition.dy;
                                _startRecording();
                              },
                              onLongPressMoveUpdate: (details) {
                                final dy = _startY - details.globalPosition.dy;
                                setState(() {
                                  _showCancel = dy > 50;
                                });
                              },
                              onLongPressEnd: (details) {
                                if (_showCancel) {
                                  _stopRecording(cancel: true);
                                } else {
                                  _stopRecording();
                                }
                                setState(() {
                                  _showCancel = false;
                                });
                              },
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '按住说话',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    if (!_isVoiceMode)
                      IconButton(
                        icon: Icon(Icons.send),
                        color: const Color.fromARGB(255, 82, 174, 248),
                        onPressed: () {
                          _sendMessage();
                          setState(() {
                            _showEmojiPicker = false;
                          });
                        },
                      ),
                  ],
                ),
                // 工具栏
                Row(
                  children: [
                    SizedBox(width: 20),
                    IconButton(
                      icon: Icon(_isVoiceMode ? Icons.keyboard_alt : Icons.mic_none_outlined, color: Colors.black),
                      onPressed: () {
                        _toggleVoiceMode();
                      },
                    ),
                    SizedBox(width: 20),
                    IconButton(
                      icon: Icon(Icons.photo_outlined, color: Colors.black),
                      onPressed: _pickImage,
                    ),
                    const SizedBox(width:20),
                    IconButton(
                      icon: Icon(Icons.emoji_emotions_outlined, color: Colors.black),
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _showEmojiPicker = !_showEmojiPicker;
                        });
                      },
                    ),
                    SizedBox(width: 20),
                    IconButton(
                      icon: Icon(Icons.camera_alt_outlined, color: Colors.black),
                      onPressed: _takePhoto,
                    ),
                    SizedBox(width: 20),
                    IconButton(
                      icon: Icon(Icons.add_circle_outline, color: Colors.black),
                      onPressed: _showMoreOptions,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!_isVoiceMode)
            Offstage(
              offstage: !_showEmojiPicker,
              child: SizedBox(
                height: 250,
                child: EmojiPicker(
                  onEmojiSelected: (Category? category, Emoji emoji) {
                    _onEmojiSelected(emoji);
                  },
                  config: Config(
                    emojiViewConfig: EmojiViewConfig(
                      emojiSizeMax: 32,
                      columns: 7,
                      verticalSpacing: 0,
                      horizontalSpacing: 0,
                      gridPadding: EdgeInsets.zero,
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      indicatorColor: Colors.blue,
                      iconColor: Colors.grey,
                      iconColorSelected: Colors.blue,
                    ),
                    skinToneConfig: SkinToneConfig(
                      enabled: true,
                      dialogBackgroundColor: Colors.white,
                      indicatorColor: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onEmojiSelected(Emoji emoji) {
    final text = _controller.text;
    final selection = _controller.selection;

    // 如果没有光标，直接追加到末尾
    if (!selection.isValid || selection.start < 0 || selection.end < 0) {
      _controller.text += emoji.emoji;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      return;
    }

    final newText = text.replaceRange(
      selection.start,
      selection.end,
      emoji.emoji,
    );
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: selection.start + emoji.emoji.length);
  }

  // 添加空聊天记录显示
  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            '暂无聊天记录',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            '开始和${friendNickname}聊天吧！',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearChatHistory() async {
    try {
      setState(() { isLoading = true; });
      await apiService.clearChatHistory(userEmail, friendEmail);
      setState(() {
        messages.clear();
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('聊天记录已清空'))
      );
    } catch (e) {
      setState(() { isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空聊天记录失败'))
      );
    }
  }

  Future<void> _deleteFriend() async {
    try {
      setState(() { isLoading = true; });
      await apiService.deleteFriend(userEmail, friendEmail);
      
      // 清理好友的通知设置
      await FriendNotificationService.instance.removeFriendSettings(friendEmail);
      
      setState(() { isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('好友已删除'))
      );
      Navigator.pop(context); // 返回到好友列表
    } catch (e) {
      setState(() { isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除好友失败'))
      );
    }
  }
  Future<void> _startRecording() async {
    print('开始录音');
    try {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _recorder.startRecorder(toFile: path);
      setState(() {
        _recordedFilePath = path; // 记录文件路径
        recordingSeconds = 0; // 重置计时器
        _isRecording = true; // 开始录音
        _showCancel = false; // 重置取消发送状态
        _currentVolume = 0.5; // 重置音量
      });
      _startRecordingTimer(); // 启动录音计时器
      _startVolumeDetection(); // 启动音量检测
    } catch (e) {
      print('录音失败: $e');
    }
  }
  Future<void> _stopRecording({bool cancel = false}) async {
    try {
      _recordingTimer?.cancel(); // 停止录音计时器
      _volumeTimer?.cancel(); // 停止音量检测
      await _recorder.stopRecorder();
      setState(() {
        _isRecording = false;
        _currentVolume = 0.5; // 重置音量
      });

      // 录音时长太短判断
      if (!cancel && (recordingSeconds < 1)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('录音时长太短')),
        );
        return;
      }

      if (!cancel && _recordedFilePath != null) {
        final file = File(_recordedFilePath!);
        final uploadResult = await apiService.uploadFile(file);

        if (uploadResult['success']) {
          final audioUrl = uploadResult['url']!;
          final now = DateTime.now();
          final tempId = now.millisecondsSinceEpoch;
          setState(() {
            messages.add(Message(
              id: tempId,
              content: '',
              senderId: userEmail,
              receiverId: friendEmail,
              timestamp: now,
              isMe: true,
              audioUrl: audioUrl,
              audioDuration: recordingSeconds,
            ));
          });
          final response = await apiService.sendMessage(
            senderId: userEmail,
            receiverId: friendEmail,
            audioUrl: audioUrl,
            content: '',
            audioDuration: recordingSeconds,
          );
          if (response != null) {
            bool sent = await _socketService.sendMessage(
              userEmail,
              friendEmail,
              '',
              '',
              audioUrl,
              recordingSeconds,
            );
            if (!sent) {
              print('语音发送失败');
              return;
            }
          

            setState(() {
              int idx = messages.indexWhere((m) => m.id == tempId);
              if (idx != -1) {
                messages[idx] = Message(
                  id: response['messageId'] ?? response['id'],
                  content: response['content'],
                  senderId: response['senderId'],
                  receiverId: response['receiverId'],
                  timestamp: TimeUtils.parseUtcToLocal(response['timestamp']),
                  isMe: true,
                  audioUrl: response['audioUrl'],
                  imageUrl: response['imageUrl'],
                  videoUrl: response['videoUrl'],
                  fileUrl: response['fileUrl'],
                  fileName: response['fileName'],
                  fileSize: response['fileSize'],
                  audioDuration: response['audioDuration'],
                  videoDuration: response['videoDuration'],
                );
              }
            });
          }
          print('语音发送成功');
          Future.delayed(Duration(milliseconds: 100), () {
            _scrollToBottom();
          });
        } else {
          // 显示错误信息
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(uploadResult['error'] ?? '语音上传失败'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('停止录音失败: $e');
    }
  }

  void _startRecordingTimer() {
    _recordingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        recordingSeconds++;
      });
    });
  }

  void _startVolumeDetection() {
    // 模拟音量检测
    _volumeTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (_isRecording) {
        setState(() {
          // 模拟音量变化，实际应该从录音器获取真实音量
          _currentVolume = 0.3 + (math.Random().nextDouble() * 0.7);
        });
      }
    });
  }

  Future<void> _playAudio(String audioUrl) async {
    if (audioUrl.isEmpty) {
      print('音频URL为空');
      return;
    }

    try {
      await _player.stopPlayer(); // 先停止当前播放
      await _player.openPlayer();
      await _player.startPlayer(fromURI: audioUrl, whenFinished: () {
        setState(() {
          _currentAudioUrl = null;
        });
      });
      setState(() {
        _currentAudioUrl = audioUrl;
      });
    } catch (e) {
      print('播放语音失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法播放语音消息')),
      );
    }
  }
  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      File imageFile = File(pickedFile.path);
      final fileSize = await imageFile.length();
      final formattedSize = _downloadService.formatFileSize(fileSize);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return UploadProgressDialog(
            title: '发送图片',
            fileName: pickedFile.name,
            fileSize: formattedSize,
            uploadFuture: apiService.uploadFile(imageFile),
            onSuccess: (result) {
              _sendImageMessage(result['url']!);
            },
            onError: (error) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(error),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                ),
              );
            },
          );
        },
      );
    }
  }
  Future<void> _sendImageMessage(String imageUrl) async {
    try {
      final now = DateTime.now();
      final tempId = now.millisecondsSinceEpoch;
      setState(() {
        messages.add(Message(
          id: tempId,
          content: '',
          senderId: userEmail,
          receiverId: friendEmail,
          timestamp: now,
          isMe: true,
          imageUrl: imageUrl,
        ));
      });
      var response = await apiService.sendMessage(
        senderId: userEmail,
        receiverId: friendEmail,
        content: '',
        imageUrl: imageUrl,
        audioUrl: '',
        audioDuration: 0,
      );
      if (response != null) {
      bool sent = await _socketService.sendMessage(
          userEmail,
          friendEmail,
          '', // 图片消息的 content 为空
          imageUrl,
          '',
          0,
        );

        if (!sent) {
          print('Failed to send real-time message');
        }
        setState(() {
          int idx = messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            messages[idx] = Message(
              id: response['messageId'] ?? response['id'],
              content: response['content'],
              senderId: response['senderId'],
              receiverId: response['receiverId'],
              timestamp: now,
              isMe: true,
              audioUrl: response['audioUrl'],
              imageUrl: response['imageUrl'],
              videoUrl: response['videoUrl'],
              fileUrl: response['fileUrl'],
              fileName: response['fileName'],
              fileSize: response['fileSize'],
              audioDuration: response['audioDuration'],
              videoDuration: response['videoDuration'],
            );
          }
        });
      }
      Future.delayed(Duration(milliseconds: 100), () {
        _scrollToBottom();
      });
    } catch (e) {
      print('发送图片消息失败: $e');
    }
  }

  Future<void> _takePhoto() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('需要摄像头权限才能拍照')),
        );
        return;
      }
    }
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      File imageFile = File(pickedFile.path);
      final fileSize = await imageFile.length();
      final formattedSize = _downloadService.formatFileSize(fileSize);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return UploadProgressDialog(
            title: '发送图片',
            fileName: pickedFile.name,
            fileSize: formattedSize,
            uploadFuture: apiService.uploadFile(imageFile),
            onSuccess: (result) {
              _sendImageMessage(result['url']!);
            },
            onError: (error) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(error),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                ),
              );
            },
          );
        },
      );
    }
  }
  void _handleCallSignal(Map<String, dynamic> signal) async {
    print('🔔 收到 call_signal: $signal');
    _pendingCallSignals.add(signal);
  }

  void _toggleVoiceMode() {
    setState(() {
      _isVoiceMode = !_isVoiceMode;
      _showEmojiPicker = false;
      FocusScope.of(context).unfocus();
    });
    Future.delayed(Duration(milliseconds: 100), () {
      _scrollToBottom();
    });
  }

  // 选择视频
  Future<void> _pickVideo() async {
    final XFile? pickedFile = await _picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile != null) {
      File videoFile = File(pickedFile.path);
      final fileSize = await videoFile.length();
      final formattedSize = _downloadService.formatFileSize(fileSize);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return UploadProgressDialog(
            title: '发送视频',
            fileName: pickedFile.name,
            fileSize: formattedSize,
            uploadFuture: apiService.uploadFile(videoFile),
            onSuccess: (result) {
              _sendVideoMessage(result['url']!, result['filename']);
            },
            onError: (error) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(error),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                ),
              );
            },
          );
        },
      );
    }
  }

  // 发送视频消息
  Future<void> _sendVideoMessage(String videoUrl, String fileName) async {
    try {
      final now = DateTime.now();
      final tempId = now.millisecondsSinceEpoch;
      setState(() {
        messages.add(Message(
          id: tempId,
          content: '',
          senderId: userEmail,
          receiverId: friendEmail,
          timestamp: now,
          isMe: true,
          videoUrl: videoUrl,
          fileName: fileName,
        ));
      });
      var response = await apiService.sendMessage(
        senderId: userEmail,
        receiverId: friendEmail,
        content: '',
        videoUrl: videoUrl,
        fileName: fileName,
        audioUrl: '',
        imageUrl: '',
        fileUrl: '',
        fileSize: '',
        audioDuration: 0,
        videoDuration: 0,
      );
      if (response!=null) { 
      
        bool sent = await _socketService.sendMessage(
          userEmail,
          friendEmail,
          '', // 视频消息的 content 为空
          '', // imageUrl
          '', // audioUrl
          0, // audioDuration
          videoUrl: videoUrl,
          fileName: fileName,
        );

        if (!sent) {
          print('Failed to send real-time video message');
        }
      
        setState(() {
          int idx = messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            messages[idx] = Message(
              id: response['messageId'] ?? response['id'],
              content: response['content'],
              senderId: response['senderId'],
              receiverId: response['receiverId'],
              timestamp: now,
              isMe: true,
              audioUrl: response['audioUrl'],
              imageUrl: response['imageUrl'],
              videoUrl: response['videoUrl'],
              fileUrl: response['fileUrl'],
              fileName: response['fileName'],
              fileSize: response['fileSize'],
              audioDuration: response['audioDuration'],
              videoDuration: response['videoDuration'],
            );
          }
        });
      }
      Future.delayed(Duration(milliseconds: 100), () {
        _scrollToBottom();
      });
    } catch (e) {
      print('发送视频消息失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送视频失败，请重试')),
      );
    }
  }

  // 显示更多选项
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
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
              

              
              // 第一行选项
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildModernOptionItem(
                          icon: Icons.videocam_outlined,
                          title: '视频',
                          subtitle: '分享视频',
                          color: Colors.red[400]!,
                          onTap: () {
                            Navigator.pop(context);
                            _pickVideo();
                          },
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: _buildModernOptionItem(
                          icon: Icons.attach_file,
                          title: '文件',
                          subtitle: '发送文件',
                          color: Colors.blue[400]!,
                          onTap: () {
                            Navigator.pop(context);
                            _pickFile();
                          },
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: _buildModernOptionItem(
                          icon: Icons.location_on,
                          title: '位置',
                          subtitle: '分享位置',
                          color: Colors.green[400]!,
                          onTap: () {
                            Navigator.pop(context);
                            _showLocationPicker();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // 第二行选项
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildModernOptionItem(
                          icon: Icons.contact_phone,
                          title: '联系人',
                          subtitle: '分享联系人',
                          color: Colors.purple[400]!,
                          onTap: () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('联系人分享功能开发中...')),
                            );
                          },
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: _buildModernOptionItem(
                          icon: Icons.poll,
                          title: '投票',
                          subtitle: '创建投票',
                          color: Colors.orange[400]!,
                          onTap: () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('投票功能开发中...')),
                            );
                          },
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: _buildModernOptionItem(
                          icon: Icons.more_horiz,
                          title: '更多',
                          subtitle: '更多功能',
                          color: Colors.grey[400]!,
                          onTap: () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('更多功能开发中...')),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // 构建现代化选项项
  Widget _buildModernOptionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color,
                    color.withOpacity(0.8),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            SizedBox(height: 12),
            Flexible(
              child: Text(
                '$title\n$subtitle',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                  height: 1.2,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 选择文件
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String fileName = result.files.single.name;
        int fileSize = result.files.single.size;
        // 显示上传进度对话框
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return UploadProgressDialog(
              title: '上传文件',
              fileName: fileName,
              fileSize: _downloadService.formatFileSize(fileSize),
              uploadFuture: apiService.uploadFile(file),
              onSuccess: (result) {
                _sendFileMessage(
                  result['url']!,
                  result['filename'],
                  _downloadService.formatFileSize(fileSize),
                );
              },
              onError: (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(error),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 5),
                  ),
                );
              },
            );
          },
        );
      }
    } catch (e) {
      print('选择文件失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败，请重试')),
      );
    }
  }

  // 发送文件消息
  Future<void> _sendFileMessage(String fileUrl, String fileName, String fileSize) async {
    try {
      final now = DateTime.now();
      final tempId = now.millisecondsSinceEpoch;
      setState(() {
        messages.add(Message(
          id: tempId,
          content: '',
          senderId: userEmail,
          receiverId: friendEmail,
          timestamp: now,
          isMe: true,
          fileUrl: fileUrl,
          fileName: fileName,
          fileSize: fileSize,
        ));
      });
      var response = await apiService.sendMessage(
        senderId: userEmail,
        receiverId: friendEmail,
        content: '',
        fileUrl: fileUrl,
        fileName: fileName,
        fileSize: fileSize,
        audioUrl: '',
        imageUrl: '',
        videoUrl: '',
        audioDuration: 0,
        videoDuration: 0,
      );
      // 通过 WebSocket 立即推送消息
      bool sentViaSocket = await _socketService.sendMessage(
          userEmail,
          friendEmail,
          '', // 文件消息的 content 为空
          '', // imageUrl
          '', // audioUrl
          0, // audioDuration
          fileUrl: fileUrl,
          fileName: fileName,
          fileSize: fileSize,
      );

      if (sentViaSocket) {
        print('WebSocket 推送消息成功');
      }
      if (response != null) {
        setState(() {
          int idx = messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            messages[idx] = Message(
              id: response['messageId'] ?? response['id'],
              content: response['content'],
              senderId: response['senderId'],
              receiverId: response['receiverId'],
              timestamp:now,
              isMe: true,
              audioUrl: response['audioUrl'],
              imageUrl: response['imageUrl'],
              videoUrl: response['videoUrl'],
              fileUrl: response['fileUrl'],
              fileName: response['fileName'],
              fileSize: response['fileSize'],
              audioDuration: response['audioDuration'],
              videoDuration: response['videoDuration'],
            );
          }
        });
      }
      Future.delayed(Duration(milliseconds: 100), () {
        _scrollToBottom();
      });
    } catch (e) {
      print('发送文件消息失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送文件失败，请重试')),
      );
    }
  }

  // 检查是否应该暂停操作
  bool _shouldPauseOperations() {
    return _isSystemKeyboardAnimating;
  }

  // 清理内存缓存
  void _clearMemoryCache() {
    if (_isSystemKeyboardAnimating) {
      // 清理文件路径缓存
      _filePathCache.clear();
      // 清理下载状态缓存
      _fileDownloading.clear();
      // 清理进度通知器
      _fileProgressNotifier.clear();
      // 清理FutureBuilder键
      _fileFutureKeys.clear();
    }
  }

  // 查找本地已下载文件路径（如有返回路径，否则null）
  Future<String?> _findLocalFilePath(String fileUrl, String fileName) async {
    // 如果系统键盘正在动画，跳过文件查找
    if (_shouldPauseOperations()) {
      return null;
    }
    
    // 生成唯一的缓存键，包含文件URL和当前聊天对象信息
    final cacheKey = '${friendEmail}_$fileUrl';
    
    // 检查缓存
    if (_filePathCache.containsKey(cacheKey)) {
      return _filePathCache[cacheKey];
    }
    
    try {
      final downloadDir = await _downloadService.getDownloadDirectory();
      if (downloadDir != null) {
        // 使用传入的fileName参数，而不是从URL提取
        final cleanFileName = _downloadService.cleanFileName(fileName);
        final filePath = '$downloadDir/$cleanFileName';
        final exists = await _downloadService.fileExists(filePath);
        if (exists) {
          // 缓存结果
          _filePathCache[cacheKey] = filePath;
          return filePath;
        }
      }
    } catch (e) {
      print('查找本地文件失败: $e');
    }
    
    // 缓存null结果
    _filePathCache[cacheKey] = null;
    return null;
  }

  // 聊天文件消息点击：只负责下载，下载完成后setState刷新
  Future<void> _onFileTap(String fileUrl, String fileName) async {
    // 生成唯一的缓存键
    final cacheKey = '${friendEmail}_$fileUrl';
    
    final isDownloading = _fileDownloading[cacheKey] == true;
    if (isDownloading) return;
    if (!_fileProgressNotifier.containsKey(cacheKey)) {
      _fileProgressNotifier[cacheKey] = ValueNotifier<double>(0.0);
    }
    final notifier = _fileProgressNotifier[cacheKey]!;
    setState(() {
      _fileDownloading[cacheKey] = true;
    });
    final result = await _downloadService.downloadFileWithProgress(
      fileUrl,
      fileName,
      (progress) {
        notifier.value = progress;
      },
    );
    setState(() {
      _fileDownloading[cacheKey] = false;
      if (result != null) {
        notifier.value = 1.0;
        // 更新文件路径缓存，确保FutureBuilder能立即找到文件
        _filePathCache[cacheKey] = result;
        _fileFutureKeys[cacheKey] = UniqueKey(); // 强制刷新FutureBuilder
        print('下载完成，文件路径已缓存: $result');
      } else {
        _fileProgressNotifier.remove(cacheKey);
        print('下载失败，清理进度通知器');
      }
    });
    // 保险：延迟再刷新一次UI，确保FutureBuilder能感知到文件已存在
    if (result != null) {
      Future.delayed(Duration(milliseconds: 100), () {
        setState(() {});
      });
    }
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败，请重试')),
      );
    }
  }

  // 检查文件状态，清理不存在的文件缓存
  Future<void> _checkFileStatus() async {
    if (!mounted) return;
    
    final keysToRemove = <String>[];
    
    for (final entry in _filePathCache.entries) {
      final cacheKey = entry.key;
      final filePath = entry.value;
      
      if (filePath != null) {
        final exists = await _downloadService.fileExists(filePath);
        if (!exists) {
          keysToRemove.add(cacheKey);
        }
      }
    }
    
    // 移除不存在的文件缓存
    for (final key in keysToRemove) {
      _filePathCache.remove(key);
      _fileFutureKeys[key] = UniqueKey(); // 强制刷新FutureBuilder
    }
    
    // 如果有文件被删除，刷新UI
    if (keysToRemove.isNotEmpty) {
      setState(() {});
      print('已清理 ${keysToRemove.length} 个不存在的文件缓存');
    }
  }

  void _jumpToBottomWithRetry([int retries = 5]) {
    if (retries <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(Duration(milliseconds: 50), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          // 如果没到底部，再试一次
          if ((_scrollController.position.maxScrollExtent - _scrollController.offset).abs() > 10) {
            _jumpToBottomWithRetry(retries - 1);
          }
        }
      });
    });
  }

  // 打开位置在地图中
  void _openLocationInMap(double latitude, double longitude) {
    final locationService = LocationService();
    locationService.openMapApp(latitude, longitude);
  }

  // 显示位置选择器
  void _showLocationPicker() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          onLocationSelected: (latitude, longitude, address) {
            _sendLocationMessage(latitude, longitude, address);
          },
        ),
      ),
    );
  }

  // 发送位置消息
  Future<void> _sendLocationMessage(double latitude, double longitude, String address) async {
    try {
      final now = DateTime.now();
      final tempId = now.millisecondsSinceEpoch;
      
      // 生成位置消息内容
      final locationService = LocationService();
      final locationContent = locationService.generateLocationMessage(latitude, longitude, address);
      
      setState(() {
        messages.add(Message(
          id: tempId,
          content: locationContent,
          senderId: userEmail,
          receiverId: friendEmail,
          timestamp: now,
          isMe: true,
          latitude: latitude,
          longitude: longitude,
          locationAddress: address,
        ));
      });

      // 调用API发送位置消息
      print('DEBUG: 发送位置消息到API - 纬度: $latitude, 经度: $longitude, 地址: $address');
      var response = await apiService.sendMessage(
        senderId: userEmail,
        receiverId: friendEmail,
        content: locationContent,
        latitude: latitude,
        longitude: longitude,
        locationAddress: address,
      );

      if (response != null && response['success'] != false) {
        // 通过WebSocket推送位置消息
        bool sentViaSocket = await _socketService.sendMessage(
          userEmail,
          friendEmail,
          locationContent,
          '', // imageUrl
          '', // audioUrl
          0, // audioDuration
          latitude: latitude,
          longitude: longitude,
          locationAddress: address,
        );

        if (sentViaSocket) {
          print('WebSocket推送位置消息成功');
        }

        // 更新消息ID和位置信息
        setState(() {
          int idx = messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            // 检查后端返回的数据是否包含位置信息
            final responseData = response['data'] ?? response;
            final responseLatitude = responseData['latitude'] ?? latitude;
            final responseLongitude = responseData['longitude'] ?? longitude;
            final responseLocationAddress = responseData['locationAddress'] ?? responseData['location_address'] ?? address;
            
            print('DEBUG: 更新位置消息 - 后端返回的坐标: $responseLatitude, $responseLongitude');
            
            messages[idx] = Message(
              id: response['id'],
              content: locationContent,
              senderId: userEmail,
              receiverId: friendEmail,
              timestamp: now,
              isMe: true,
              latitude: responseLatitude,
              longitude: responseLongitude,
              locationAddress: responseLocationAddress,
            );
          }
        });

        // 滚动到底部
        Future.delayed(Duration(milliseconds: 100), () {
          _scrollToBottom();
        });
      } else {
        // 发送失败，更新消息状态
        setState(() {
          int idx = messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            messages[idx] = messages[idx].copyWith(status: 'failed');
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送位置消息失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('发送位置消息异常: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发送位置消息失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

String getOriginalFileNameFromUrl(String url) {
  final uri = Uri.parse(url);
  return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'file';
}

class ImageViewerPage extends StatefulWidget {
  final String imageUrl;
  const ImageViewerPage({Key? key, required this.imageUrl}) : super(key: key);

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  bool _isDownloaded = false;
  bool _isDownloading = false;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkLocalFile();
  }

  Future<void> _checkLocalFile() async {
    final downloadService = DownloadService();
    final downloadDir = await downloadService.getDownloadDirectory();
    if (downloadDir != null) {
      final fileName = getOriginalFileNameFromUrl(widget.imageUrl);
      final filePath = '$downloadDir/$fileName';
      final exists = await downloadService.fileExists(filePath);
      if (exists) {
        setState(() {
          _isDownloaded = true;
          _localPath = filePath;
        });
      }
    }
  }

  Future<void> _downloadImage() async {
    setState(() { _isDownloading = true; });
    try {
      final downloadService = DownloadService();
      final fileName = getOriginalFileNameFromUrl(widget.imageUrl);
      final result = await downloadService.downloadFileWithProgress(
        widget.imageUrl,
        fileName,
        null,
      );
      if (result != null) {
        setState(() {
          _isDownloaded = true;
          _localPath = result;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('图片已下载到: $result'),
            action: SnackBarAction(
              label: '打开',
              onPressed: () {
                downloadService.openFile(result);
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败，请重试')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $e')),
      );
    } finally {
      setState(() { _isDownloading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider = _localPath != null
        ? FileImage(File(_localPath!))
        : NetworkImage(widget.imageUrl) as ImageProvider;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 201, 230, 244),
        title: const Text('查看图片'),
        actions: [
          if (!_isDownloaded && !_isDownloading)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _downloadImage,
            ),
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: PhotoView(
        imageProvider: imageProvider,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
      ),
    );
  }
}

class VideoViewerPage extends StatefulWidget {
  final String videoUrl;
  const VideoViewerPage({Key? key, required this.videoUrl}) : super(key: key);

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  bool _isDownloaded = false;
  bool _isDownloading = false;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkLocalFile();
  }

  Future<void> _checkLocalFile() async {
    final downloadService = DownloadService();
    final downloadDir = await downloadService.getDownloadDirectory();
    if (downloadDir != null) {
      final fileName = getOriginalFileNameFromUrl(widget.videoUrl);
      final filePath = '$downloadDir/$fileName';
      final exists = await downloadService.fileExists(filePath);
      if (exists) {
        setState(() {
          _isDownloaded = true;
          _localPath = filePath;
        });
      }
    }
  }

  Future<void> _downloadVideo() async {
    setState(() { _isDownloading = true; });
    try {
      final downloadService = DownloadService();
      final fileName = getOriginalFileNameFromUrl(widget.videoUrl);
      final result = await downloadService.downloadFileWithProgress(
        widget.videoUrl,
        fileName,
        null,
      );
      if (result != null) {
        setState(() {
          _isDownloaded = true;
          _localPath = result;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('视频已下载到: $result'),
            action: SnackBarAction(
              label: '打开',
              onPressed: () {
                downloadService.openFile(result);
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败，请重试')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $e')),
      );
    } finally {
      setState(() { _isDownloading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 201, 230, 244),
        title: const Text('播放视频'),
        actions: [
          if (!_isDownloaded && !_isDownloading)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _downloadVideo,
            ),
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: VideoPlayerWidget(
        videoUrl: _localPath ?? widget.videoUrl,
        autoPlay: true,
        showControls: true,
        fullScreen: true,
      ),
    );
  }
}
