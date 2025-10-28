import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static const String _keyTimetable = 'timetable_cache_v2';
  static const String _keyLoginPayload = 'login_payload_v2';
  static const String _keyTimetableBackup = 'timetable_backup_v2';
  static const String _keyLastSyncTime = 'last_sync_time_v2';
  static const String _keyCurrentWeekInfo = 'current_week_info_v2';
  static const String _keyRememberCredentials = 'remember_credentials_v2';
  static const int _ttlSeconds = 7 * 24 * 60 * 60; // 7 days (延长缓存时间)
  static const int _backupRetentionDays = 30; // 备份保留30天

  static Future<void> saveTimetable(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    
    // 创建带版本信息的数据包
    final payload = {
      'timestamp': timestamp,
      'version': '2.0',
      'data': data,
      'checksum': _calculateChecksum(data),
    };
    
    try {
      // 保存当前数据前，先备份旧数据
      await _backupCurrentTimetable(prefs);
      
      // 保存新课表数据
      await prefs.setString(_keyTimetable, jsonEncode(payload));
      
      // 更新最后同步时间
      await prefs.setInt(_keyLastSyncTime, timestamp);
      
      print('✅ 课表数据已持久化保存 (版本: 2.0)');
    } catch (e) {
      print('❌ 保存课表数据失败: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> loadTimetable() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyTimetable);
    if (raw == null) return null;
    
    try {
      final decoded = jsonDecode(raw);
      final ts = decoded['timestamp'] as int? ?? 0;
      final version = decoded['version'] as String? ?? '1.0';
      final data = decoded['data'] as Map<String, dynamic>?;
      final checksum = decoded['checksum'] as String?;
      
      // 检查数据是否过期
      final now = DateTime.now().millisecondsSinceEpoch;
      if ((now - ts) / 1000 > _ttlSeconds) {
        print('⚠️ 课表数据已过期，尝试加载备份');
        await prefs.remove(_keyTimetable);
        return await _loadBackupTimetable(prefs);
      }
      
      // 检查数据完整性
      if (data != null && checksum != null) {
        final currentChecksum = _calculateChecksum(data);
        if (currentChecksum != checksum) {
          print('⚠️ 课表数据校验失败，尝试加载备份');
          return await _loadBackupTimetable(prefs);
        }
      }
      
      print('✅ 课表数据加载成功 (版本: $version)');
      return data;
    } catch (e) {
      print('❌ 加载课表数据失败: $e，尝试加载备份');
      return await _loadBackupTimetable(prefs);
    }
  }

  static Future<void> saveLoginPayload(Map<String, String> payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLoginPayload, jsonEncode(payload));
  }

  static Future<Map<String, String>?> loadLoginPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLoginPayload);
    if (raw == null) return null;
    final data = Map<String, dynamic>.from(jsonDecode(raw));
    return data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTimetable);
    await prefs.remove(_keyLoginPayload);
    await prefs.remove(_keyTimetableBackup);
    await prefs.remove(_keyLastSyncTime);
    await prefs.remove(_keyCurrentWeekInfo);
    await prefs.remove(_keyRememberCredentials);
    print('🗑️ 所有缓存数据已清除');
  }

  // 获取最后同步时间
  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyLastSyncTime);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }

  // 检查数据是否过期
  static Future<bool> isDataExpired() async {
    final lastSync = await getLastSyncTime();
    if (lastSync == null) return true;
    
    final now = DateTime.now();
    final diff = now.difference(lastSync).inSeconds;
    return diff > _ttlSeconds;
  }

  // 保存当前周信息
  static Future<void> saveCurrentWeekInfo(Map<String, dynamic> weekInfo) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    
    // 增强周信息，添加最后更新时的周次信息
    final enhancedWeekInfo = Map<String, dynamic>.from(weekInfo);
    enhancedWeekInfo['last_sync_week_text'] = weekInfo['current_week_text'];
    enhancedWeekInfo['last_sync_week_value'] = weekInfo['current_week_value'];
    enhancedWeekInfo['last_sync_date'] = now.toIso8601String();
    
    final payload = {
      'timestamp': now.millisecondsSinceEpoch,
      'weekInfo': enhancedWeekInfo,
    };
    await prefs.setString(_keyCurrentWeekInfo, jsonEncode(payload));
    print('✅ 当前周信息已保存: $enhancedWeekInfo');
  }

  // 加载当前周信息
  static Future<Map<String, dynamic>?> loadCurrentWeekInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCurrentWeekInfo);
    if (raw == null) return null;
    
    try {
      final decoded = jsonDecode(raw);
      final weekInfo = decoded['weekInfo'] as Map<String, dynamic>?;
      // print('✅ 当前周信息已加载: $weekInfo');
      return weekInfo;
    } catch (e) {
      print('❌ 加载当前周信息失败: $e');
      return null;
    }
  }

  // 获取缓存状态信息
  static Future<Map<String, dynamic>> getCacheStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = await getLastSyncTime();
    final hasMainData = prefs.containsKey(_keyTimetable);
    final hasBackupData = prefs.containsKey(_keyTimetableBackup);
    final hasLoginData = prefs.containsKey(_keyLoginPayload);
    final hasWeekInfo = prefs.containsKey(_keyCurrentWeekInfo);
    
    return {
      'hasMainData': hasMainData,
      'hasBackupData': hasBackupData,
      'hasLoginData': hasLoginData,
      'hasWeekInfo': hasWeekInfo,
      'lastSyncTime': lastSync?.toIso8601String(),
      'isExpired': await isDataExpired(),
      'ttlSeconds': _ttlSeconds,
    };
  }

  // 计算当前是第几周
  static Future<String> calculateCurrentWeek() async {
    try {
      final weekInfo = await loadCurrentWeekInfo();
      if (weekInfo == null) {
        return '第1周';
      }
      
      // 优先使用元数据中的当前周次
      final currentWeekText = weekInfo['current_week_text'] as String?;
      if (currentWeekText != null && currentWeekText.isNotEmpty) {
        // print('📅 使用元数据中的当前周次: $currentWeekText');
        return currentWeekText;
      }
      
      // 如果有周次数值，转换为文本
      final currentWeekValue = weekInfo['current_week_value'] as int?;
      if (currentWeekValue != null && currentWeekValue > 0) {
        final weekText = '第${currentWeekValue}周';
        print('📅 使用周次数值转换为文本: $weekText');
        return weekText;
      }
      
      // 基于最后更新时间计算当前周次
      final lastSyncTime = await getLastSyncTime();
      if (lastSyncTime != null) {
        final calculatedWeek = _calculateWeekFromLastSync(lastSyncTime, weekInfo);
        if (calculatedWeek != null) {
          print('📅 基于最后更新时间计算周次: $calculatedWeek');
          return calculatedWeek;
        }
      }
      
      print('⚠️ 没有找到有效的周次信息');
      return '第1周';
    } catch (e) {
      print('❌ 计算当前周次失败: $e');
      return '第1周';
    }
  }

  // 基于最后更新时间计算周次（周一为一周开始）
  static String? _calculateWeekFromLastSync(DateTime lastSyncTime, Map<String, dynamic> weekInfo) {
    try {
      // 获取最后更新时的周次信息
      final lastSyncWeekText = weekInfo['last_sync_week_text'] as String?;
      final lastSyncWeekValue = weekInfo['last_sync_week_value'] as int?;
      
      // 确定最后更新时的周次
      int lastSyncWeek;
      if (lastSyncWeekValue != null && lastSyncWeekValue > 0) {
        lastSyncWeek = lastSyncWeekValue;
      } else if (lastSyncWeekText != null && lastSyncWeekText.isNotEmpty) {
        // 从文本中提取周次数字
        final match = RegExp(r'第(\d+)周').firstMatch(lastSyncWeekText);
        if (match != null) {
          lastSyncWeek = int.parse(match.group(1)!);
        } else {
          return null;
        }
      } else {
        return null;
      }
      
      // 计算从最后更新到现在的周数（周一为一周开始）
      final now = DateTime.now();
      final weeksPassed = _calculateWeeksPassedFromMonday(lastSyncTime, now);
      
      // 计算当前周次
      final currentWeek = lastSyncWeek + weeksPassed;
      
      // 确保周数在合理范围内
      final weekNumber = currentWeek.clamp(1, 20);
      
      print('📊 周次计算详情（周一为一周开始）:');
      print('  - 最后更新: $lastSyncTime (${_getWeekdayName(lastSyncTime.weekday)})');
      print('  - 最后更新周次: 第${lastSyncWeek}周');
      print('  - 当前时间: $now (${_getWeekdayName(now.weekday)})');
      print('  - 已过周数: $weeksPassed 周');
      print('  - 计算当前周次: 第${weekNumber}周');
      
      return '第${weekNumber}周';
    } catch (e) {
      print('❌ 基于最后更新时间计算周次失败: $e');
      return null;
    }
  }

  // 计算从周一为基准的周数差
  static int _calculateWeeksPassedFromMonday(DateTime startDate, DateTime endDate) {
    // 获取开始日期所在周的周一
    final startMonday = _getMondayOfWeek(startDate);
    // 获取结束日期所在周的周一
    final endMonday = _getMondayOfWeek(endDate);
    
    // 计算两个周一之间的天数差
    final daysDiff = endMonday.difference(startMonday).inDays;
    
    // 计算周数差
    final weeksDiff = (daysDiff / 7).floor();
    
    print('📅 周一基准计算:');
    print('  - 开始周一: $startMonday');
    print('  - 结束周一: $endMonday');
    print('  - 天数差: $daysDiff 天');
    print('  - 周数差: $weeksDiff 周');
    
    return weeksDiff;
  }

  // 获取指定日期所在周的周一
  static DateTime _getMondayOfWeek(DateTime date) {
    // weekday: 1=Monday, 2=Tuesday, ..., 7=Sunday
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  // 获取星期几的中文名称
  static String _getWeekdayName(int weekday) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return weekdays[weekday - 1];
  }

  // 保存记住的账号密码
  static Future<void> saveRememberedCredentials(String username, String password, bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    if (remember) {
      await prefs.setString(_keyRememberCredentials, jsonEncode({
        'username': username,
        'password': password,
        'remember': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));
      print('✅ 账号密码已保存');
    } else {
      await prefs.remove(_keyRememberCredentials);
      print('🗑️ 已清除保存的账号密码');
    }
  }

  // 加载记住的账号密码
  static Future<Map<String, dynamic>?> loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyRememberCredentials);
    if (raw == null) return null;
    
    try {
      final decoded = jsonDecode(raw);
      final remember = decoded['remember'] as bool? ?? false;
      if (!remember) return null;
      
      print('✅ 已加载保存的账号密码');
      return {
        'username': decoded['username'] as String? ?? '',
        'password': decoded['password'] as String? ?? '',
        'remember': remember,
      };
    } catch (e) {
      print('❌ 加载保存的账号密码失败: $e');
      return null;
    }
  }

  // 手动更新周次（当用户手动更新课表时调用）
  static Future<void> updateWeekManually(int weekNumber) async {
    try {
      final weekInfo = await loadCurrentWeekInfo();
      if (weekInfo != null) {
        // 更新周次信息
        weekInfo['current_week_text'] = '第${weekNumber}周';
        weekInfo['current_week_value'] = weekNumber;
        weekInfo['last_sync_week_text'] = '第${weekNumber}周';
        weekInfo['last_sync_week_value'] = weekNumber;
        weekInfo['last_sync_date'] = DateTime.now().toIso8601String();
        
        // 重新保存
        await saveCurrentWeekInfo(weekInfo);
        print('✅ 周次已手动更新为: 第${weekNumber}周');
      } else {
        // 如果没有周信息，创建新的
        final newWeekInfo = {
          'current_week_text': '第${weekNumber}周',
          'current_week_value': weekNumber,
          'last_sync_week_text': '第${weekNumber}周',
          'last_sync_week_value': weekNumber,
          'last_sync_date': DateTime.now().toIso8601String(),
        };
        await saveCurrentWeekInfo(newWeekInfo);
        print('✅ 创建新的周次信息: 第${weekNumber}周');
      }
    } catch (e) {
      print('❌ 手动更新周次失败: $e');
    }
  }

  // 计算数据校验和
  static String _calculateChecksum(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    return jsonString.hashCode.toString();
  }

  // 备份当前课表数据
  static Future<void> _backupCurrentTimetable(SharedPreferences prefs) async {
    try {
      final currentData = prefs.getString(_keyTimetable);
      if (currentData != null) {
        await prefs.setString(_keyTimetableBackup, currentData);
        print('📦 课表数据已备份');
        
        // 清理过期备份
        await _cleanupExpiredBackups(prefs);
      }
    } catch (e) {
      print('⚠️ 备份课表数据失败: $e');
    }
  }

  // 清理过期备份
  static Future<void> _cleanupExpiredBackups(SharedPreferences prefs) async {
    try {
      final backupRaw = prefs.getString(_keyTimetableBackup);
      if (backupRaw != null) {
        final decoded = jsonDecode(backupRaw);
        final ts = decoded['timestamp'] as int? ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // 如果备份超过保留期，删除备份
        if ((now - ts) / 1000 > _backupRetentionDays * 24 * 60 * 60) {
          await prefs.remove(_keyTimetableBackup);
          print('🗑️ 过期备份已清理');
        }
      }
    } catch (e) {
      print('⚠️ 清理备份失败: $e');
    }
  }

  // 从备份加载课表数据
  static Future<Map<String, dynamic>?> _loadBackupTimetable(SharedPreferences prefs) async {
    try {
      final backupRaw = prefs.getString(_keyTimetableBackup);
      if (backupRaw == null) return null;
      
      final decoded = jsonDecode(backupRaw);
      final data = decoded['data'] as Map<String, dynamic>?;
      
      if (data != null) {
        print('✅ 从备份恢复课表数据');
        return data;
      }
    } catch (e) {
      print('❌ 从备份加载课表数据失败: $e');
    }
    return null;
  }
} 