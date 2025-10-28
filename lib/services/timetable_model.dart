class CourseInfo {
  final String courseName;
  final String classInfo;
  final String teacher;
  final String location;
  final String content;
  final String period;
  final String lesson;
  final String weekName;
  final List<String> periods;

  CourseInfo({
    required this.courseName,
    required this.classInfo,
    required this.teacher,
    required this.location,
    required this.content,
    required this.period,
    required this.lesson,
    required this.weekName,
    required this.periods,
  });

  factory CourseInfo.fromJson(Map<String, dynamic> json) {
    return CourseInfo(
      courseName: json['course_name'] ?? '',
      classInfo: json['class_info'] ?? '',
      teacher: json['teacher'] ?? '',
      location: json['location'] ?? '',
      content: json['content'] ?? '',
      period: json['period'] ?? '',
      lesson: json['lesson'] ?? '',
      weekName: json['week_name'] ?? '',
      periods: (json['periods'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        'course_name': courseName,
        'class_info': classInfo,
        'teacher': teacher,
        'location': location,
        'content': content,
        'period': period,
        'lesson': lesson,
        'week_name': weekName,
        'periods': periods,
      };
}

class TimetableWeek {
  final String weekId;
  final String weekName;
  final Map<String, List<CourseInfo>> courses;

  TimetableWeek({
    required this.weekId,
    required this.weekName,
    required this.courses,
  });

  factory TimetableWeek.fromJson(Map<String, dynamic> json) {
    final courses = <String, List<CourseInfo>>{};
    if (json['courses'] is Map<String, dynamic>) {
      (json['courses'] as Map<String, dynamic>).forEach((k, v) {
        courses[k] = (v as List?)
                ?.map((e) => CourseInfo.fromJson(e))
                .toList() ??
            [];
      });
    }
    return TimetableWeek(
      weekId: json['week_id']?.toString() ?? '',
      weekName: json['week_name'] ?? '',
      courses: courses,
    );
  }
}

class TimetableSemester {
  final String semId;
  final String semName;
  final List<TimetableWeek> weeks;

  TimetableSemester({
    required this.semId,
    required this.semName,
    required this.weeks,
  });

  factory TimetableSemester.fromJson(Map<String, dynamic> json) {
    return TimetableSemester(
      semId: json['sem_id']?.toString() ?? '',
      semName: json['sem_name'] ?? '',
      weeks: (json['weeks'] as List?)
              ?.map((e) => TimetableWeek.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class SemesterMeta {
  final String semId;
  final String semName;

  SemesterMeta({required this.semId, required this.semName});

  factory SemesterMeta.fromJson(Map<String, dynamic> json) {
    return SemesterMeta(
      semId: json['sem_id']?.toString() ?? '',
      semName: json['sem_name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'sem_id': semId,
        'sem_name': semName,
      };
}

class CurrentWeekInfo {
  final int currentWeekValue;
  final String currentWeekText;
  final String currentDate;
  final String currentWeekday;
  final Map<String, dynamic> debugInfo;

  CurrentWeekInfo({
    required this.currentWeekValue,
    required this.currentWeekText,
    required this.currentDate,
    required this.currentWeekday,
    required this.debugInfo,
  });

  factory CurrentWeekInfo.fromJson(Map<String, dynamic> json) {
    return CurrentWeekInfo(
      currentWeekValue: json['current_week_value'] ?? 0,
      currentWeekText: json['current_week_text'] ?? '',
      currentDate: json['current_date'] ?? '',
      currentWeekday: json['current_weekday'] ?? '',
      debugInfo: json['debug_info'] ?? {},
    );
  }
}

class TimetableData {
  final String sessionId;
  final List<TimetableSemester> semesters;
  final String defaultSemester;
  final String defaultWeek;
  final List<SemesterMeta> allSemestersMeta;
  final CurrentWeekInfo? currentWeekInfo;
  final bool lazyLoading;

  TimetableData({
    required this.sessionId,
    required this.semesters,
    required this.defaultSemester,
    required this.defaultWeek,
    required this.allSemestersMeta,
    this.currentWeekInfo,
    required this.lazyLoading,
  });

  factory TimetableData.fromJson(Map<String, dynamic> json) {
    return TimetableData(
      sessionId: json['session_id'] ?? '',
      semesters: (json['semesters'] as List?)
              ?.map((e) => TimetableSemester.fromJson(e))
              .toList() ??
          [],
      defaultSemester: json['default_semester'] ?? '',
      defaultWeek: json['default_week'] ?? '',
      allSemestersMeta: (json['all_semesters_meta'] as List?)
              ?.map((e) => SemesterMeta.fromJson(e))
              .toList() ??
          [],
      currentWeekInfo: json['current_week_info'] != null
          ? CurrentWeekInfo.fromJson(json['current_week_info'])
          : null,
      lazyLoading: json['lazy_loading'] ?? false,
    );
  }
}