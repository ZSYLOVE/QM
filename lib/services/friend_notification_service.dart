import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onlin/services/all_friends_notification_service.dart';

class FriendNotificationService {
  static final FriendNotificationService _instance = FriendNotificationService._internal();
  factory FriendNotificationService() => _instance;
  FriendNotificationService._internal();

  final AudioPlayer _notificationPlayer = AudioPlayer();
  
  // 好友通知设置缓存
  final Map<String, Map<String, bool>> _friendSettings = {};

  // 获取单例实例
  static FriendNotificationService get instance => _instance;

  // 初始化服务
  Future<void> initialize() async {
    await _loadAllSettings();
  }

  // 加载所有好友的通知设置
  Future<void> _loadAllSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith('friend_notification_')) {
          final friendEmail = key.replaceFirst('friend_notification_', '');
          final settings = prefs.getStringList('friend_notification_$friendEmail') ?? [];
          
          _friendSettings[friendEmail] = {
            'enabled': settings.contains('enabled'),
            'vibration': settings.contains('vibration'),
            'sound': settings.contains('sound'),
          };
        }
      }
    } catch (e) {
      print('加载好友通知设置失败: $e');
    }
  }

  // 保存特定好友的通知设置
  Future<void> _saveFriendSettings(String friendEmail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = _friendSettings[friendEmail] ?? {};
      final settingsList = <String>[];
      
      if (settings['enabled'] == true) settingsList.add('enabled');
      if (settings['vibration'] == true) settingsList.add('vibration');
      if (settings['sound'] == true) settingsList.add('sound');
      
      await prefs.setStringList('friend_notification_$friendEmail', settingsList);
    } catch (e) {
      print('保存好友通知设置失败: $e');
    }
  }

  // 获取好友的通知设置
  Map<String, bool> getFriendSettings(String friendEmail) {
    return _friendSettings[friendEmail] ?? {
      'enabled': true,
      'vibration': true,
      'sound': true,
    };
  }

  // 触发特定好友的新消息通知
  Future<void> triggerFriendMessageNotification(String friendEmail) async {
    final settings = getFriendSettings(friendEmail);
    if (!settings['enabled']!) return;
    
    // 检查全局好友通知设置
    final allFriendsService = AllFriendsNotificationService.instance;
    if (!allFriendsService.allFriendsNotificationEnabled) return;
    
    try {
      // 检查设备是否支持震动
      if (await Vibration.hasVibrator() == true) {
        // 震动通知 - 需要同时满足好友设置和全局设置
        if (settings['vibration']! && allFriendsService.allFriendsVibrationEnabled) {
          Vibration.vibrate(duration: 300);
        }
        
        // 铃声通知 - 需要同时满足好友设置和全局设置
        if (settings['sound']! && allFriendsService.allFriendsSoundEnabled) {
          try {
            // 尝试播放内置铃声文件
            await _notificationPlayer.play(AssetSource('audio/notification.mp3'));
          } catch (e) {
            print('铃声播放失败，使用震动模式代替: $e');
            // 如果铃声播放失败，使用震动模式模拟铃声
            Future.delayed(Duration(milliseconds: 100), () {
              Vibration.vibrate(pattern: [0, 150, 100, 300, 100, 150], intensities: [0, 128, 0, 128, 0, 128]);
            });
          }
        }
      }
    } catch (e) {
      print('好友新消息通知触发失败: $e');
      // 如果震动失败，尝试简单的震动
      try {
        if (settings['vibration']! && allFriendsService.allFriendsVibrationEnabled && await Vibration.hasVibrator() == true) {
          Vibration.vibrate(duration: 200);
        }
      } catch (e2) {
        print('备用震动也失败了: $e2');
      }
    }
  }

  // 切换特定好友的新消息通知开关
  Future<void> toggleFriendMessageNotification(String friendEmail) async {
    if (!_friendSettings.containsKey(friendEmail)) {
      _friendSettings[friendEmail] = {
        'enabled': true,
        'vibration': true,
        'sound': true,
      };
    }
    
    _friendSettings[friendEmail]!['enabled'] = !(_friendSettings[friendEmail]!['enabled'] ?? true);
    await _saveFriendSettings(friendEmail);
  }

  // 切换特定好友的新消息震动开关
  Future<void> toggleFriendMessageVibration(String friendEmail) async {
    if (!_friendSettings.containsKey(friendEmail)) {
      _friendSettings[friendEmail] = {
        'enabled': true,
        'vibration': true,
        'sound': true,
      };
    }
    
    _friendSettings[friendEmail]!['vibration'] = !(_friendSettings[friendEmail]!['vibration'] ?? true);
    await _saveFriendSettings(friendEmail);
  }

  // 切换特定好友的新消息铃声开关
  Future<void> toggleFriendMessageSound(String friendEmail) async {
    if (!_friendSettings.containsKey(friendEmail)) {
      _friendSettings[friendEmail] = {
        'enabled': true,
        'vibration': true,
        'sound': true,
      };
    }
    
    _friendSettings[friendEmail]!['sound'] = !(_friendSettings[friendEmail]!['sound'] ?? true);
    await _saveFriendSettings(friendEmail);
  }

  // 获取特定好友的通知设置状态
  bool isFriendNotificationEnabled(String friendEmail) {
    return getFriendSettings(friendEmail)['enabled'] ?? true;
  }

  bool isFriendVibrationEnabled(String friendEmail) {
    return getFriendSettings(friendEmail)['vibration'] ?? true;
  }

  bool isFriendSoundEnabled(String friendEmail) {
    return getFriendSettings(friendEmail)['sound'] ?? true;
  }

  // 测试特定好友的通知
  Future<void> testFriendNotification(String friendEmail) async {
    await triggerFriendMessageNotification(friendEmail);
  }

  // 删除好友的通知设置
  Future<void> removeFriendSettings(String friendEmail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('friend_notification_$friendEmail');
      _friendSettings.remove(friendEmail);
    } catch (e) {
      print('删除好友通知设置失败: $e');
    }
  }

  // 释放资源
  void dispose() {
    _notificationPlayer.dispose();
  }
} 