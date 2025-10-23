import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AllFriendsNotificationService {
  static final AllFriendsNotificationService _instance = AllFriendsNotificationService._internal();
  factory AllFriendsNotificationService() => _instance;
  AllFriendsNotificationService._internal();

  final AudioPlayer _notificationPlayer = AudioPlayer();
  
  // 全局通知设置
  bool _allFriendsNotificationEnabled = true;
  bool _allFriendsVibrationEnabled = true;
  bool _allFriendsSoundEnabled = true;

  // 获取单例实例
  static AllFriendsNotificationService get instance => _instance;

  // 初始化服务
  Future<void> initialize() async {
    await _loadSettings();
  }

  // 加载全局通知设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _allFriendsNotificationEnabled = prefs.getBool('all_friends_notification_enabled') ?? true;
      _allFriendsVibrationEnabled = prefs.getBool('all_friends_vibration_enabled') ?? true;
      _allFriendsSoundEnabled = prefs.getBool('all_friends_sound_enabled') ?? true;
    } catch (e) {
      print('加载全局好友通知设置失败: $e');
    }
  }

  // 保存全局通知设置
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('all_friends_notification_enabled', _allFriendsNotificationEnabled);
      await prefs.setBool('all_friends_vibration_enabled', _allFriendsVibrationEnabled);
      await prefs.setBool('all_friends_sound_enabled', _allFriendsSoundEnabled);
    } catch (e) {
      print('保存全局好友通知设置失败: $e');
    }
  }

  // 触发全局好友新消息通知
  Future<void> triggerAllFriendsMessageNotification() async {
    if (!_allFriendsNotificationEnabled) return;
    
    try {
      // 检查设备是否支持震动
      if (await Vibration.hasVibrator() == true) {
        // 震动通知
        if (_allFriendsVibrationEnabled) {
          Vibration.vibrate(duration: 300);
        }
        
        // 铃声通知
        if (_allFriendsSoundEnabled) {
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
      print('全局好友新消息通知触发失败: $e');
      // 如果震动失败，尝试简单的震动
      try {
        if (_allFriendsVibrationEnabled && await Vibration.hasVibrator() == true) {
          Vibration.vibrate(duration: 200);
        }
      } catch (e2) {
        print('备用震动也失败了: $e2');
      }
    }
  }

  // 切换全局好友新消息通知开关
  Future<void> toggleAllFriendsMessageNotification() async {
    _allFriendsNotificationEnabled = !_allFriendsNotificationEnabled;
    await _saveSettings();
  }

  // 切换全局好友新消息震动开关
  Future<void> toggleAllFriendsMessageVibration() async {
    _allFriendsVibrationEnabled = !_allFriendsVibrationEnabled;
    await _saveSettings();
  }

  // 切换全局好友新消息铃声开关
  Future<void> toggleAllFriendsMessageSound() async {
    _allFriendsSoundEnabled = !_allFriendsSoundEnabled;
    await _saveSettings();
  }

  // 获取全局通知设置状态
  bool get allFriendsNotificationEnabled => _allFriendsNotificationEnabled;
  bool get allFriendsVibrationEnabled => _allFriendsVibrationEnabled;
  bool get allFriendsSoundEnabled => _allFriendsSoundEnabled;

  // 释放资源
  void dispose() {
    _notificationPlayer.dispose();
  }
} 