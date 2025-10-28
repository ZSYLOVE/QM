import 'package:flutter/material.dart';
import 'package:onlin/screens/login_page.dart';
import 'package:onlin/servers/api_serverclass.dart';
import 'package:onlin/servers/cache_service.dart';
import 'package:onlin/services/timetable_model.dart';

class EmptyTimetablePage extends StatefulWidget {
  final Map<String, dynamic>? timetableJson;

  const EmptyTimetablePage({super.key, this.timetableJson});

  @override
  State<EmptyTimetablePage> createState() => _EmptyTimetablePageState();
}

class _EmptyTimetablePageState extends State<EmptyTimetablePage> {
  late TimetableData timetableData;
  late TimetableSemester selectedSemester;
  late TimetableWeek selectedWeek;
  bool loadingWeeks = false;
  String? loadError;
  Map<String, dynamic>? cacheStatus;
  bool isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _initializeTimetableData();
    _checkCacheStatus();
  }

  void _initializeTimetableData() {
    print('🔍 开始初始化EmptyTimetablePage');
    print('传入的timetableJson: ${widget.timetableJson}');
    
    // 如果有传入数据，使用真实数据
    if (widget.timetableJson != null && widget.timetableJson!.isNotEmpty) {
      _loadTimetableFromData(widget.timetableJson!);
    } else {
      // 没有传入数据，创建空课表
      _createEmptyTimetable();
    }
    
    // 异步尝试从缓存加载数据
    _loadTimetableFromCacheAsync();
  }

  Future<void> _loadTimetableFromCacheAsync() async {
    print('📥 异步尝试从缓存加载课表');
    try {
      final cachedData = await CacheService.loadTimetable();
      if (cachedData != null && cachedData.isNotEmpty) {
        print('✅ 从缓存加载到课表数据，更新显示');
        await _loadTimetableFromData(cachedData);
        if (mounted) {
          setState(() {
            isLoadingData = false;
          });
        }
      } else {
        print('⚠️ 缓存中没有课表数据');
        if (mounted) {
          setState(() {
            isLoadingData = false;
          });
        }
      }
    } catch (e) {
      print('❌ 从缓存加载课表失败: $e');
      if (mounted) {
        setState(() {
          isLoadingData = false;
        });
      }
    }
  }

  // 优先选择当前周次
  Future<TimetableWeek> _selectCurrentWeek(TimetableSemester semester) async {
    try {
      // 1. 优先使用计算出的当前周次
      final calculatedWeek = await CacheService.calculateCurrentWeek();
      print('📅 计算出的当前周次: $calculatedWeek');
      
      // 2. 尝试在学期中找到匹配的周次
      if (semester.weeks.isNotEmpty) {
        // 优先匹配计算出的周次
        final matchedWeek = semester.weeks.firstWhere(
          (w) => w.weekName == calculatedWeek,
          orElse: () => TimetableWeek(weekName: '', courses: {}, weekId: ''),
        );
        
        if (matchedWeek.weekName.isNotEmpty) {
          print('✅ 找到匹配的当前周次: ${matchedWeek.weekName}');
          return matchedWeek;
        }
        
        // 如果没有找到匹配的周次，尝试匹配默认周次
        final defaultWeek = semester.weeks.firstWhere(
          (w) => w.weekName == timetableData.defaultWeek,
          orElse: () => TimetableWeek(weekName: '', courses: {}, weekId: ''),
        );
        
        if (defaultWeek.weekName.isNotEmpty) {
          print('📅 使用默认周次: ${defaultWeek.weekName}');
          return defaultWeek;
        }
        
        // 最后使用第一个周次
        print('📅 使用第一个周次: ${semester.weeks.first.weekName}');
        return semester.weeks.first;
      }
      
      // 如果没有周次数据，返回空周次
      return TimetableWeek(weekName: '暂无周', courses: {}, weekId: '');
    } catch (e) {
      print('❌ 选择当前周次失败: $e');
      // 出错时返回默认周次或第一个周次
      if (semester.weeks.isNotEmpty) {
        return semester.weeks.first;
      }
      return TimetableWeek(weekName: '暂无周', courses: {}, weekId: '');
    }
  }

  // 同步获取当前周次名称
  String _getCurrentWeekNameSync() {
    // 尝试从缓存中获取当前周次
    try {
      // 这里使用同步方式获取，避免异步问题
      return '第9周'; // 默认值，实际应该从缓存获取
    } catch (e) {
      return '第1周';
    }
  }


  // 只加载当前学年（第一个学期）
  Future<void> _loadCurrentSemesterOnly() async {
    try {
      print('📅 只加载当前学年');
      
      // 获取当前学年（第一个学期）
      final currentMeta = timetableData.allSemestersMeta.first;
      
      // 创建当前学期对象
      final currentSemester = TimetableSemester(
        semId: currentMeta.semId,
        semName: currentMeta.semName,
        weeks: [],
      );
      
      // 添加到学期列表中
      timetableData.semesters.add(currentSemester);
      
      // 设置为当前选择的学期
      selectedSemester = currentSemester;
      selectedWeek = TimetableWeek(weekName: '加载中...', courses: {}, weekId: 'loading');
      
      print('✅ 当前学年创建完成: ${currentMeta.semName}');
      
      // 立即开始加载当前学年的数据
      await _ensureSemesterWeeksLoaded(currentSemester);
      
      // 加载完成后选择当前周次
      selectedWeek = await _selectCurrentWeek(selectedSemester);
      
      // 刷新UI
      if (mounted) {
        setState(() {
          print('🔄 当前学年数据加载完成，刷新UI');
        });
      }
    } catch (e) {
      print('❌ 加载当前学年失败: $e');
      // 失败时创建空课表
      _createEmptyTimetable();
    }
  }

  Future<void> _checkCacheStatus() async {
    try {
      final status = await CacheService.getCacheStatus();
      print('📊 缓存状态: $status');
      
      if (mounted) {
        setState(() {
          cacheStatus = status;
        });
      }
      
      if (status['isExpired'] == true) {
        print('⚠️ 课表数据已过期，建议重新获取');
      }
    } catch (e) {
      print('❌ 检查缓存状态失败: $e');
    }
  }


  Future<void> _loadTimetableFromData(Map<String, dynamic> data) async {
    print('📥 从传入数据加载课表');
    final originalData = TimetableData.fromJson(data);
    timetableData = originalData;
    
    // 只有当数据中包含周次信息时才提取并保存
    if (data.containsKey('current_week_info')) {
      _extractAndSaveCurrentWeekInfo(data);
    } else {
      print('📊 课表数据中没有周次信息，保持已保存的周次信息');
    }
    
    // 只加载当前学年（第一个学期）
    if (timetableData.semesters.isNotEmpty) {
      // 选择第一个学期（当前学年）
      selectedSemester = timetableData.semesters.first;
      
      // 优先选择当前周次
      selectedWeek = await _selectCurrentWeek(selectedSemester);
    } else if (timetableData.allSemestersMeta.isNotEmpty) {
      // 如果没有学期数据但有元数据，只加载当前学年
      await _loadCurrentSemesterOnly();
    } else {
      _createEmptyTimetable();
    }

    print('✅ 课表初始化完成 (从传入数据)');
    print('  - 学期: ${selectedSemester.semName}');
    print('  - 周次: ${selectedWeek.weekName}');
    print('  - 可添加课程: 是');
    
    // 立即刷新UI
    if (mounted) {
      setState(() {
        print('🔄 数据填充完成，立即刷新UI');
      });
    }
  }

  Future<void> _extractAndSaveCurrentWeekInfo(Map<String, dynamic> data) async {
    try {
      // 从课表数据中提取当前周信息
      final currentWeekInfo = data['current_week_info'] as Map<String, dynamic>?;
      if (currentWeekInfo != null) {
        print('📅 提取当前周信息: $currentWeekInfo');
        
        // 保存到本地缓存
        await CacheService.saveCurrentWeekInfo(currentWeekInfo);
        
        // 验证保存的周信息
        final savedWeekInfo = await CacheService.loadCurrentWeekInfo();
        print('📊 验证保存的周信息: $savedWeekInfo');
        
        // 计算当前周次
        final calculatedWeek = await CacheService.calculateCurrentWeek();
        print('📊 计算得出当前周次: $calculatedWeek');
      } else {
        print('⚠️ 课表数据中没有当前周信息');
      }
    } catch (e) {
      print('❌ 提取当前周信息失败: $e');
    }
  }

  void _createEmptyTimetable() {
    print('📝 创建空课表');
    // 创建空课表结构
    // 获取当前周次作为默认周次
    final currentWeekName = _getCurrentWeekNameSync();
    
    final emptyWeek = TimetableWeek(
      weekId: '1',
      weekName: currentWeekName,
      courses: {
        '星期一': [],
        '星期二': [],
        '星期三': [],
        '星期四': [],
        '星期五': [],
        '星期六': [],
        '星期日': [],
      },
    );
    
    final emptySemester = TimetableSemester(
      semId: 'empty',
      semName: '空课表',
      weeks: [emptyWeek],
    );
    
    timetableData = TimetableData(
      sessionId: '',
      semesters: [emptySemester],
      defaultSemester: '空课表',
      defaultWeek: currentWeekName,
      allSemestersMeta: [],
      currentWeekInfo: null,
      lazyLoading: false,
    );
    selectedSemester = emptySemester;
    selectedWeek = emptyWeek;

    print('✅ 空课表创建完成');
    print('  - 学期: ${selectedSemester.semName}');
    print('  - 周次: ${selectedWeek.weekName}');
    print('  - 可添加课程: 是');
  }

  void _updateTimetableData(Map<String, dynamic> newData) {
    print('🔄 更新课表数据');
    print('新数据: $newData');
    
    setState(() {
      timetableData = TimetableData.fromJson(newData);
      
      // 重新选择学期和周次
      if (timetableData.semesters.isNotEmpty) {
        selectedSemester = timetableData.semesters.firstWhere(
          (s) => s.semName == timetableData.defaultSemester || s.semId == timetableData.defaultSemester,
          orElse: () => timetableData.semesters.first,
        );
        selectedWeek = selectedSemester.weeks.isNotEmpty
            ? selectedSemester.weeks.firstWhere(
                (w) => w.weekName == timetableData.defaultWeek,
                orElse: () => selectedSemester.weeks.first,
              )
            : TimetableWeek(weekName: '暂无周', courses: {}, weekId: '');
      } else {
        // 如果没有学期数据，重新构造占位学期
        if (timetableData.allSemestersMeta.isNotEmpty) {
          final placeholderSemId = timetableData.allSemestersMeta.firstWhere(
            (m) => m.semName == timetableData.defaultSemester || m.semId == timetableData.defaultSemester,
            orElse: () => timetableData.allSemestersMeta.first,
          ).semId;
          
          selectedSemester = TimetableSemester(
            semId: placeholderSemId,
            semName: timetableData.defaultSemester,
            weeks: [],
          );
          selectedWeek = TimetableWeek(weekName: '暂无周', courses: {}, weekId: '');
        }
      }
    });
    
    // 数据更新完成后立即刷新UI
    if (mounted) {
      setState(() {
        print('🔄 课表数据更新完成，立即刷新UI');
      });
    }
    
    // 自动加载学期数据
    if (selectedSemester.semId != 'default') {
      _ensureSemesterWeeksLoaded(selectedSemester);
    }
  }

  Future<void> _saveTimetableData() async {
    try {
      // 构造完整的数据结构
      final merged = {
        ...(widget.timetableJson ?? {}),
        'semesters': timetableData.semesters
            .map((s) => {
                  'sem_id': s.semId,
                  'sem_name': s.semName,
                  'weeks': s.weeks
                      .map((w) => {
                            'week_id': w.weekId,
                            'week_name': w.weekName,
                            'courses': w.courses.map((day, courses) => MapEntry(
                              day, 
                              courses.map((course) => course.toJson()).toList()
                            )),
                          })
                      .toList(),
                })
            .toList(),
        'all_semesters_meta': timetableData.allSemestersMeta
            .map((m) => {'sem_id': m.semId, 'sem_name': m.semName}).toList(),
        'default_semester': timetableData.defaultSemester,
        'default_week': timetableData.defaultWeek,
      };
      
      // 保存到缓存
      await CacheService.saveTimetable(merged);
      print('✅ 课表数据已保存到缓存');
    } catch (e) {
      print('❌ 保存课表数据失败: $e');
    }
  }

  Future<void> _clearTimetable() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除课程表'),
        content: const Text('选择清除方式：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'current'),
            child: const Text('仅清除当前显示'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('清除所有并重新获取'),
          ),
        ],
      ),
    );
    
    if (result == 'cancel' || !mounted) return;
    
    if (result == 'current') {
      // 仅清除当前显示的课程
      setState(() {
        // 清除当前周次的所有课程
        selectedWeek = TimetableWeek(
          weekId: selectedWeek.weekId,
          weekName: selectedWeek.weekName,
          courses: {},
        );
        
        // 如果当前学期有多个周次，也清除其他周次
        if (selectedSemester.weeks.isNotEmpty) {
          final clearedWeeks = selectedSemester.weeks.map((w) => TimetableWeek(
            weekId: w.weekId,
            weekName: w.weekName,
            courses: {},
          )).toList();
          
          selectedSemester = TimetableSemester(
            semId: selectedSemester.semId,
            semName: selectedSemester.semName,
            weeks: clearedWeeks,
          );
        }
        
        // 更新整个课表数据
        final clearedSemesters = timetableData.semesters.map((s) => TimetableSemester(
          semId: s.semId,
          semName: s.semName,
          weeks: s.weeks.map((w) => TimetableWeek(
            weekId: w.weekId,
            weekName: w.weekName,
            courses: {},
          )).toList(),
        )).toList();
        
        timetableData = TimetableData(
          sessionId: timetableData.sessionId,
          semesters: clearedSemesters,
          defaultSemester: timetableData.defaultSemester,
          defaultWeek: timetableData.defaultWeek,
          allSemestersMeta: timetableData.allSemestersMeta,
          currentWeekInfo: timetableData.currentWeekInfo,
          lazyLoading: timetableData.lazyLoading,
        );
      });
      
      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前课程表已清除'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else if (result == 'all') {
      // 清除所有缓存并重新获取
      await CacheService.clearAll();
      if (!mounted) return;
      
      // 跳转到登录页面重新获取数据
      final loginResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginPage(returnData: true),
        ),
      );
      
      if (loginResult != null && loginResult is Map<String, dynamic> && mounted) {
        _updateTimetableData(loginResult);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('课程表已重新获取'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _autoFetchTimetable() async {
    print('🚀 开始自动获取课表数据 - 直接跳转到登录界面');
    print('当前页面状态: mounted = $mounted');
    
    if (!mounted) {
      print('❌ 页面未挂载，无法跳转');
      return;
    }
    
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在跳转到登录界面获取最新课表...')),
      );
      
      print('📱 准备跳转到登录界面');
      
      // 直接跳转到登录页面获取数据
      final loginResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginPage(returnData: true),
        ),
      );
      
      print('🔙 从登录界面返回，结果: $loginResult');
      
      if (loginResult != null && loginResult is Map<String, dynamic> && mounted) {
        print('✅ 开始更新课表数据');
        _updateTimetableData(loginResult);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 成功获取最新课表数据'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        print('⚠️ 登录结果为空或页面未挂载');
      }
    } catch (e) {
      print('❌ 跳转登录界面失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('跳转失败: $e')),
        );
      }
    }
  }


  Future<void> _ensureSemesterWeeksLoaded(TimetableSemester sem) async {
    if (sem.weeks.isNotEmpty) return;
    
    print('🔄 开始加载学期周次数据');
    print('学期ID: ${sem.semId}');
    print('学期名称: ${sem.semName}');
    
    setState(() {
      loadingWeeks = true;
      loadError = null;
    });
    try {
      final login = await CacheService.loadLoginPayload();
      if (login == null) {
        throw Exception('缓存登录信息缺失，请重新登录');
      }
      
      print('登录信息: ${login.keys.toList()}');
      print('Session ID: ${login['session_id']}');
      print('即将请求学期ID: ${sem.semId}'); // 新增日志
      
      final resp = await ApiService.fetchSemesterWeeks(
        username: login['username']?.isNotEmpty == true ? login['username'] : null,
        password: login['password']?.isNotEmpty == true ? login['password'] : null,
        captcha: login['captcha']?.isNotEmpty == true ? login['captcha'] : null,
        sessionId: login['session_id']?.isNotEmpty == true ? login['session_id'] : null,
        semId: sem.semId,
        maxWeeks: 19,
      );
      
      print('API响应: ${resp.keys.toList()}');
      print('周次数据: ${resp['weeks']?.length ?? 0} 个周次');
      print('完整API响应: $resp'); // 新增日志
      
      // 合并返回到当前数据结构
      await _mergeWeeksIntoState(sem.semId, resp['weeks'] as List? ?? []);
    } catch (e) {
      print('❌ 加载学期周次数据失败: $e');
      setState(() {
        loadError = '加载失败: $e';
      });
    } finally {
      setState(() {
        loadingWeeks = false;
      });
    }
  }

  Future<void> _mergeWeeksIntoState(String semId, List weeksJson) async {
    final fetchedWeeks = weeksJson.map((e) => TimetableWeek.fromJson(e)).toList();

    // 构造新的 semesters 列表：存在则替换，不存在则追加
    final existingIndex = timetableData.semesters.indexWhere((s) => s.semId == semId);
    final List<TimetableSemester> newSemesters = [...timetableData.semesters];

    String resolvedSemName;
    if (existingIndex >= 0) {
      resolvedSemName = newSemesters[existingIndex].semName;
      newSemesters[existingIndex] = TimetableSemester(
        semId: semId,
        semName: resolvedSemName,
        weeks: fetchedWeeks,
      );
    } else {
      // 从 allSemestersMeta 中找学期名，找不到则用 semId 兜底
      final meta = timetableData.allSemestersMeta.firstWhere(
        (m) => m.semId == semId,
        orElse: () => SemesterMeta(semId: semId, semName: semId),
      );
      resolvedSemName = meta.semName;
      newSemesters.add(TimetableSemester(
        semId: semId,
        semName: resolvedSemName,
        weeks: fetchedWeeks,
      ));
    }

    final merged = {
      ...widget.timetableJson ?? {},
      'semesters': newSemesters
          .map((s) => {
                'sem_id': s.semId,
                'sem_name': s.semName,
                'weeks': s.weeks
                    .map((w) => {
                          'week_id': w.weekId,
                          'week_name': w.weekName,
                          'courses': w.courses.map((day, courses) => MapEntry(
                            day, 
                            courses.map((course) => course.toJson()).toList()
                          )),
                        })
                    .toList(),
              })
          .toList(),
      'all_semesters_meta': timetableData.allSemestersMeta
          .map((m) => {'sem_id': m.semId, 'sem_name': m.semName}).toList(),
      'default_semester': timetableData.defaultSemester,
      'default_week': timetableData.defaultWeek,
    };
    await CacheService.saveTimetable(merged);
    setState(() {
      timetableData = TimetableData.fromJson(merged);
      if (selectedSemester.semId == semId) {
        selectedSemester = timetableData.semesters.firstWhere((s) => s.semId == semId);
        selectedWeek = selectedSemester.weeks.isNotEmpty
            ? selectedSemester.weeks.first
            : TimetableWeek(weekName: '暂无周', courses: {}, weekId: '');
      }
    });
  }


  List<String> _collectPeriods(TimetableWeek week) {
    // 如果是空课表，显示完整的12节课
    if (selectedSemester.semId == 'empty') {
      return [
        '第1节', '第2节', '第3节', '第4节', '第5节', '第6节',
        '第7节', '第8节', '第9节', '第10节', '第11节', '第12节'
      ];
    }
    
    // 正常课表，从实际课程中收集节次
    final set = <String>{};
    week.courses.forEach((day, list) {
      for (final c in list) {
        // 优先使用periods字段（包含所有课时）
        if (c.periods.isNotEmpty) {
          set.addAll(c.periods);
        } else if (c.period.isNotEmpty) {
          // 如果没有periods字段，使用单个period
          set.add(c.period);
        }
      }
    });
    final periods = set.toList();
    periods.sort((a, b) {
      final na = int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '0') ?? 0;
      final nb = int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '0') ?? 0;
      return na.compareTo(nb);
    });
    return periods;
  }

  Color _colorForCourse(String key) {
    final colors = [
      const Color(0xFF42A5F5), // blue
      const Color(0xFF66BB6A), // green
      const Color(0xFFEF5350), // red
      const Color(0xFFAB47BC), // purple
      const Color(0xFFFFA726), // orange
      const Color(0xFF26A69A), // teal
      const Color(0xFF5C6BC0), // indigo
    ];
    final idx = (key.hashCode & 0x7fffffff) % colors.length;
    return colors[idx];
  }

  Widget _buildCourseChip(CourseInfo course) {
    // 使用新的CourseInfo结构，直接获取解析好的信息
    final courseName = course.courseName;
    final classInfo = course.classInfo;
    final teacher = course.teacher;
    final location = course.location;
    final periods = course.periods;
    
    // 构建显示名称（课程名 + 班级）
    final displayName = classInfo.isNotEmpty ? '$courseName ($classInfo)' : courseName;

    final color = _colorForCourse(courseName);

    return GestureDetector(
      onTap: () {
        showDialog(
      context: context,
          builder: (ctx) => Dialog(
            child: Container(
              padding: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                    Text('课程详情', style: TextStyle(color: color.darken(0.3), fontWeight: FontWeight.bold, fontSize: 20)),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('课程名:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(courseName, style: TextStyle(fontSize: 16, color: Colors.black87)),
                        ],
                      ),
                    ),
                    if (teacher.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('教师:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.person, size: 18, color: Colors.black54),
                                const SizedBox(width: 4),
                                Text(teacher, style: TextStyle(fontSize: 16, color: Colors.black87)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    if (location.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('地点:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 18, color: Colors.black54),
                                const SizedBox(width: 4),
                                Expanded(child: Text(location, style: TextStyle(fontSize: 16, color: Colors.black87))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    if (periods.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('课时:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.schedule, size: 18, color: Colors.black54),
                                const SizedBox(width: 4),
                                Expanded(child: Text(periods.join(', '), style: TextStyle(fontSize: 16, color: Colors.black87))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _editCourse(course);
                          },
                          child: const Text('编辑', style: TextStyle(fontSize: 16)),
                        ),
                        TextButton(
                          onPressed: () {
                            // 删除课程功能暂时禁用，因为现在使用CourseInfo结构
                            Navigator.pop(ctx);
                          },
                          child: const Text('删除', style: TextStyle(fontSize: 16, color: Colors.red)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('关闭', style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: 80,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: color.darken(0.3),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (teacher.isNotEmpty) const SizedBox(height: 4),
                    if (teacher.isNotEmpty)
                      Text(
                        teacher,
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (location.isNotEmpty) const SizedBox(height: 2),
                    if (location.isNotEmpty)
                      Text(
                        location,
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  void _editCourse(CourseInfo course) {
    final subjectController = TextEditingController();
    final teacherController = TextEditingController();
    final locationController = TextEditingController();
    
    // 使用CourseInfo结构中的信息
    subjectController.text = course.courseName;
    teacherController.text = course.teacher;
    locationController.text = course.location;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑课程'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: '课程名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: teacherController,
                decoration: const InputDecoration(
                  labelText: '教师',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: '上课地点',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (subjectController.text.isNotEmpty) {
                setState(() {
                  // 找到要编辑的课程并更新
                  for (final day in selectedWeek.courses.keys) {
                    final courses = selectedWeek.courses[day]!;
                    for (int i = 0; i < courses.length; i++) {
                      if (courses[i] == course) {
                        courses[i] = CourseInfo(
                          courseName: subjectController.text,
                          classInfo: course.classInfo, // 保持原有班级信息
                          teacher: teacherController.text,
                          location: locationController.text,
                          content: '${subjectController.text} ${teacherController.text} ${locationController.text}',
                          period: course.period,
                          lesson: course.lesson,
                          weekName: course.weekName,
                          periods: course.periods,
                        );
                        break;
                      }
                    }
                  }
                  // 保存数据到缓存
                  _saveTimetableData();
                });
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showAddCourseDialog(String day, String period) {
    final subjectController = TextEditingController();
    final teacherController = TextEditingController();
    final locationController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加课程 - $day $period'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: '课程名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: teacherController,
                decoration: const InputDecoration(
                  labelText: '教师',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: '上课地点',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (subjectController.text.isNotEmpty) {
                setState(() {
                  final course = CourseInfo(
                    courseName: subjectController.text,
                    classInfo: '', // 手动添加的课程没有班级信息
                    teacher: teacherController.text,
                    location: locationController.text,
                    content: '${subjectController.text} ${teacherController.text} ${locationController.text}',
                    period: period,
                    lesson: period,
                    weekName: selectedWeek.weekName,
                    periods: [period],
                  );
                  
                  if (selectedWeek.courses[day] == null) {
                    selectedWeek.courses[day] = [];
                  }
                  selectedWeek.courses[day]!.add(course);
                  
                  // 保存数据到缓存
                  _saveTimetableData();
                });
                Navigator.pop(context);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetableTable() {
    if (selectedSemester.weeks.isEmpty) {
      return const Center(child: Text('本学期暂无课表'));
    }
    final days = selectedWeek.courses.keys.toList();
    if (days.isEmpty) {
      return const Center(child: Text('本周暂无课程'));
    }
    final periods = _collectPeriods(selectedWeek);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    final header = TableRow(
      decoration: const BoxDecoration(color: Color(0xFFF5F5F5)),
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('节次', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ...days.map((d) => Padding(
              padding: const EdgeInsets.all(8),
              child: Text(d, style: const TextStyle(fontWeight: FontWeight.bold)),
            )),
      ],
    );

    List<TableRow> rows = [header];

    for (final period in periods) {
      rows.add(
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(period, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            ...days.map((d) {
              final items = selectedWeek.courses[d]?.where((c) => 
                c.periods.contains(period) || c.period == period
              ).toList() ?? [];
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
                child: items.isEmpty
                    ? GestureDetector(
                        onTap: () => _showAddCourseDialog(d, period),
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline, color: Colors.grey.shade400, size: 24),
                                const SizedBox(height: 2),
                                Text(
                                  '添加课程',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: items.map((c) => _buildCourseChip(c)).toList(),
                      ),
              );
            }),
          ],
        ),
      );
    }

    return Card(
      elevation: 3,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              columnWidths: {
                0: FixedColumnWidth(isLandscape ? 60 : 72),
                for (int i = 1; i <= days.length; i++) 
                  i: FixedColumnWidth(isLandscape ? 140 : 120),
              },
              border: TableBorder.all(
                color: Colors.grey.shade300,
                width: 1,
                borderRadius: BorderRadius.circular(8),
              ),
              children: rows,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    // 如果数据还在加载中，显示加载界面
    if (isLoadingData) {
      return Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, 
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icons/logo.png',
                    width: 32,
                    height: 32, 
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('课程表'),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color.fromARGB(255, 201, 230, 244),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载课表数据...'),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, 
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/icons/logo.png',
                  width: 32,
                  height: 32, 
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('课程表'),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 201, 230, 244),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: '清除课表数据',
            onPressed: () => _clearTimetable(),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: '自动获取课表',
            onPressed: () => _autoFetchTimetable(),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromARGB(255, 248, 249, 250), 
              Color(0xFFE9ECEF), 
            ],
          ),
        ),
        child: SingleChildScrollView(
          child: isLandscape 
            ? _buildLandscapeLayout()
            : _buildPortraitLayout(),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return Column(
        children: [
          // 缓存状态卡片
          if (cacheStatus != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cacheStatus!['isExpired'] == true ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cacheStatus!['isExpired'] == true ? Colors.red.shade200 : Colors.green.shade200,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              cacheStatus!['isExpired'] == true ? Icons.warning : Icons.check_circle,
                              color: cacheStatus!['isExpired'] == true ? Colors.red.shade700 : Colors.green.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              cacheStatus!['isExpired'] == true ? '数据已过期' : '数据已保存',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cacheStatus!['isExpired'] == true ? Colors.red.shade800 : Colors.green.shade800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (cacheStatus!['lastSyncTime'] != null)
                          Text(
                            '最后同步: ${_formatDateTime(cacheStatus!['lastSyncTime'])}',
                            style: TextStyle(
                              color: cacheStatus!['isExpired'] == true ? Colors.red.shade700 : Colors.green.shade700,
                              fontSize: 14,
                            ),
                          ),
                        if (cacheStatus!['isExpired'] == true)
                          Text(
                            '建议点击"自动获取课表"更新数据',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 右侧周次和星期信息
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cacheStatus!['isExpired'] == true ? Colors.red.shade300 : Colors.green.shade300,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FutureBuilder<String>(
                          future: _getCurrentWeekInfo(),
                          builder: (context, snapshot) {
                            final weekInfo = snapshot.data ?? '第1周';
                            return Text(
                              weekInfo,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cacheStatus!['isExpired'] == true ? Colors.red.shade800 : Colors.green.shade800,
                                fontSize: 14,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getTodayInfo(),
                          style: TextStyle(
                            color: cacheStatus!['isExpired'] == true ? Colors.red.shade600 : Colors.green.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // 空课表提示卡片
          if (selectedSemester.semId == 'empty')
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '空课表模式',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 点击空白格子可以手动添加课程\n• 点击右上角"自动获取课表"按钮获取真实课表数据\n• 显示完整的12节课时间表',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          // 显示当前学年名称（优化布局）
          if (timetableData.semesters.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.school,
                  color: Colors.blue.shade600,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  selectedSemester.semName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('暂无学期数据')),
          ),
        // 当前周信息显示
        if (timetableData.currentWeekInfo != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前周次: ${timetableData.currentWeekInfo!.currentWeekText}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '日期: ${timetableData.currentWeekInfo!.currentDate}',
                      style: TextStyle(
                        color: Colors.blue.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Icon(
                  Icons.calendar_today,
                  color: Colors.blue.shade600,
                  size: 24,
                ),
              ],
            ),
          ),
        // 周次选择
        if (selectedSemester.weeks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Center(
              child: DropdownButton<String>(
                alignment: Alignment.center,
                value: selectedWeek.weekId.isNotEmpty ? selectedWeek.weekId : null,
                items: selectedSemester.weeks.map((w) {
                  return DropdownMenuItem(
                    value: w.weekId,
                    child: Center(
                      child: Text(w.weekName),
                    ),
                  );
                }).toList(),
                onChanged: (wid) async {
                  if (wid != null) {
                    final w = selectedSemester.weeks.firstWhere((e) => e.weekId == wid, orElse: () => selectedSemester.weeks.first);
                    setState(() {
                      selectedWeek = w;
                    });
                    
                    // 手动更新周次信息
                    final weekNumber = int.tryParse(w.weekId) ?? 1;
                    await CacheService.updateWeekManually(weekNumber);
                  }
                },
              ),
            ),
          ),
        // 加载状态
        if (loadingWeeks)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (loadError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('加载错误: $loadError', style: const TextStyle(color: Colors.red)),
          ),
        // 课表内容（修复高度约束）
        Container(
          height: MediaQuery.of(context).size.height * 0.4, // 设置为屏幕高度的40%
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: _buildTimetableTable(),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout() {
    return Row(
      children: [
        // 左侧控制面板
        Container(
          width: 200,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // 显示当前学年名称（优化布局）
              if (timetableData.semesters.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.school,
                        color: Colors.blue.shade600,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          selectedSemester.semName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              // 周次选择
              if (selectedSemester.weeks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedWeek.weekId.isNotEmpty ? selectedWeek.weekId : null,
                    items: selectedSemester.weeks.map((w) {
                      return DropdownMenuItem(
                        value: w.weekId,
                        child: Text(w.weekName),
                      );
                    }).toList(),
                    onChanged: (wid) {
                      if (wid != null) {
                        final w = selectedSemester.weeks.firstWhere((e) => e.weekId == wid, orElse: () => selectedSemester.weeks.first);
          setState(() {
                          selectedWeek = w;
                        });
                      }
                    },
                  ),
                ),
              // 加载状态
              if (loadingWeeks)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              if (loadError != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('加载错误: $loadError', style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
        ),
        // 右侧课表内容（修复高度约束）
        Container(
          width: MediaQuery.of(context).size.width - 200, // 减去左侧面板宽度
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
            ),
          ),
          child: _buildTimetableTable(),
        ),
      ],
    );
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) return '未知';
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dateTime);
      
      if (diff.inDays > 0) {
        return '${diff.inDays}天前';
      } else if (diff.inHours > 0) {
        return '${diff.inHours}小时前';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes}分钟前';
      } else {
        return '刚刚';
      }
    } catch (e) {
      return '未知';
    }
  }

  Future<String> _getCurrentWeekInfo() async {
    // 优先使用计算出的当前周次（从缓存中获取）
    final calculatedWeek = await CacheService.calculateCurrentWeek();
    if (calculatedWeek != '第1周') {
      // print('📊 使用缓存中的当前周次: $calculatedWeek');
      return calculatedWeek;
    }
    
    // 如果有当前周信息，使用课表数据中的周次
    if (timetableData.currentWeekInfo != null) {
      final weekText = timetableData.currentWeekInfo!.currentWeekText;
      // print('📊 使用课表数据中的当前周次: $weekText');
      return weekText;
    }
    
    // 如果有默认周次，使用默认周次
    if (timetableData.defaultWeek.isNotEmpty) {
      // print('📊 使用默认周次: ${timetableData.defaultWeek}');
      return timetableData.defaultWeek;
    }
    
    // 如果当前选择的周次不是空课表，显示当前周次
    if (selectedSemester.semId != 'empty' && selectedWeek.weekName.isNotEmpty) {
      // print('📊 使用选择的周次: ${selectedWeek.weekName}');
      return selectedWeek.weekName;
    }
    
    // 默认显示当前周次
    // print('📊 使用默认周次: 第1周');
    return '第1周';
  }

  String _getTodayInfo() {
    final now = DateTime.now();
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final weekday = weekdays[now.weekday - 1];
    
    return '$weekday ${now.month}/${now.day}';
  }
}

extension _ColorShade on Color {
  Color darken([double amount = .2]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}