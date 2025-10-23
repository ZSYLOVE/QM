import 'dart:io';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  // 获取下载目录路径（公有）
  Future<String?> getDownloadDirectory() async {
    try {
      if (Platform.isAndroid) {
        // 使用 Download/happychat 目录
        const downloadPath = '/storage/emulated/0/Download/happychat';
        final downloadDir = Directory(downloadPath);
        
        // 检查目录是否存在，如果不存在则创建
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        
        // print('使用下载目录: $downloadPath');
        return downloadPath;
      } else if (Platform.isIOS) {
        // iOS使用 Documents/Download/happychat 目录
        final directory = await getApplicationDocumentsDirectory();
        final downloadPath = '${directory.path}/Download/happychat';
        final downloadDir = Directory(downloadPath);
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadPath;
      }
      
      return null;
    } catch (e) {
      print('获取下载目录失败: $e');
      return null;
    }
  }

  // 请求必要权限
  Future<bool> _requestPermissions() async {
    try {
      if (Platform.isAndroid) {
        print('开始请求Android权限...');
        
        // 请求存储权限
        var storageStatus = await Permission.storage.status;
        print('存储权限状态: $storageStatus');
        
        if (!storageStatus.isGranted) {
          print('请求存储权限...');
          storageStatus = await Permission.storage.request();
          print('存储权限请求结果: $storageStatus');
          
          if (!storageStatus.isGranted) {
            print('存储权限被拒绝，尝试请求管理外部存储权限...');
          }
        }

        // 请求管理外部存储权限（用于访问公共下载目录）
        var manageStatus = await Permission.manageExternalStorage.status;
        print('管理外部存储权限状态: $manageStatus');
        
        if (!manageStatus.isGranted) {
          print('请求管理外部存储权限...');
          manageStatus = await Permission.manageExternalStorage.request();
          print('管理外部存储权限请求结果: $manageStatus');
        }

        // 尝试请求媒体权限（Android 13+）
        try {
          var photosStatus = await Permission.photos.status;
          print('媒体权限状态: $photosStatus');
          
          if (!photosStatus.isGranted) {
            print('请求媒体权限...');
            photosStatus = await Permission.photos.request();
            print('媒体权限请求结果: $photosStatus');
          }
        } catch (e) {
          print('媒体权限请求失败（可能是旧版本Android）: $e');
        }

        // 只要有存储权限或管理外部存储权限之一就可以继续
        if (storageStatus.isGranted || manageStatus.isGranted) {
          print('权限检查通过，可以继续下载');
          return true;
        } else {
          print('所有存储权限都被拒绝，但尝试继续下载...');
          // 即使权限被拒绝，也尝试继续下载
          return true;
        }
      }
      
      return true;
    } catch (e) {
      print('请求权限失败: $e');
      // 即使权限请求失败，也尝试继续下载
      return true;
    }
  }

  // 下载文件
  Future<String?> downloadFile(String url, String fileName) async {
    try {
      print('开始下载文件: $fileName');
      print('下载URL: $url');

      // 请求权限（但不强制要求）
      final hasPermission = await _requestPermissions();
      if (!hasPermission) {
        print('权限检查失败，但尝试继续下载...');
      }

      // 获取下载目录
      final downloadPath = await getDownloadDirectory();
      if (downloadPath == null) {
        print('无法获取下载目录，尝试使用备用方案...');
        // 备用方案：使用应用外部存储目录
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final backupPath = '${directory.path}/Download';
          final backupDir = Directory(backupPath);
          if (!await backupDir.exists()) {
            await backupDir.create(recursive: true);
          }
          print('使用备用下载目录: $backupPath');
          
          // 清理文件名（移除特殊字符）
          final cleanFileName2 = cleanFileName(fileName);
          
          // 生成唯一文件名
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final uniqueFileName = '${timestamp}_$cleanFileName2';

          print('最终文件名: $uniqueFileName');

          // 开始下载
          final taskId = await FlutterDownloader.enqueue(
            url: url,
            savedDir: backupPath,
            fileName: uniqueFileName,
            saveInPublicStorage: false, // 保存到应用私有存储
            showNotification: true,    // 显示通知
            openFileFromNotification: true, // 点击通知打开文件
            requiresStorageNotLow: true,    // 需要足够的存储空间
          );

          print('下载任务已启动: $taskId');
          print('文件将保存到: $backupPath/$uniqueFileName');
          
          return '$backupPath/$uniqueFileName';
        } else {
          print('无法获取任何下载目录');
          return null;
        }
      }

      print('下载目录: $downloadPath');

      // 清理文件名（移除特殊字符）
      final cleanFileNamel = cleanFileName(fileName);
      
      // 生成唯一文件名
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uniqueFileName = '${timestamp}_$cleanFileNamel';

      print('最终文件名: $uniqueFileName');

      // 开始下载
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: downloadPath,
        fileName: uniqueFileName,
        saveInPublicStorage: true, // 保存到公共存储
        showNotification: true,    // 显示通知
        openFileFromNotification: true, // 点击通知打开文件
        requiresStorageNotLow: true,    // 需要足够的存储空间
      );

      print('下载任务已启动: $taskId');
      print('文件将保存到: $downloadPath/$uniqueFileName');
      
      final file = File('$downloadPath/$uniqueFileName');
      if (await file.exists()) {
        return file.path;
      }
      
      return null;
    } catch (e) {
      print('下载文件失败: $e');
      return null;
    }
  }

  // 清理文件名（公有）
  String cleanFileName(String fileName) {
    // 移除或替换不允许的字符
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_') // 替换Windows不允许的字符
        .replaceAll(RegExp(r'\s+'), '_')          // 替换空格为下划线
        .trim();
  }

  // 下载图片
  Future<String?> downloadImage(String imageUrl, String fileName) async {
    print('下载图片: $fileName');
    return await downloadFile(imageUrl, fileName);
  }

  // 下载视频
  Future<String?> downloadVideo(String videoUrl, String fileName) async {
    print('下载视频: $fileName');
    return await downloadFile(videoUrl, fileName);
  }

  // 下载音频
  Future<String?> downloadAudio(String audioUrl, String fileName) async {
    print('下载音频: $fileName');
    return await downloadFile(audioUrl, fileName);
  }

  // 下载文档
  Future<String?> downloadDocument(String documentUrl, String fileName) async {
    print('下载文档: $fileName');
    return await downloadFile(documentUrl, fileName);
  }

  // 打开文件
  Future<void> openFile(String filePath) async {
    try {
      print('尝试打开文件: $filePath');
      await OpenFile.open(filePath);
    } catch (e) {
      print('打开文件失败: $e');
      // 尝试使用系统默认应用打开
      try {
        await OpenFile.open(filePath, type: 'application/octet-stream');
      } catch (e2) {
        print('使用默认应用打开文件也失败: $e2');
      }
    }
  }

  // 检查文件是否存在
  Future<bool> fileExists(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  // 获取文件大小
  Future<int?> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 格式化文件大小
  String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  // 获取文件扩展名
  String getFileExtension(String fileName) {
    return fileName.split('.').last.toLowerCase();
  }

  // 获取文件类型图标
  String getFileTypeIcon(String fileName) {
    final extension = getFileExtension(fileName);
    switch (extension) {
      case 'pdf':
        return '📄';
      case 'doc':
      case 'docx':
        return '📝';
      case 'xls':
      case 'xlsx':
        return '📊';
      case 'ppt':
      case 'pptx':
        return '📈';
      case 'txt':
        return '📄';
      case 'zip':
      case 'rar':
      case '7z':
        return '📦';
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
        return '🎵';
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
      case 'flv':
        return '🎬';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return '🖼️';
      default:
        return '📎';
    }
  }

  // 获取文件类型描述
  String getFileTypeDescription(String fileName) {
    final extension = getFileExtension(fileName);
    switch (extension) {
      case 'pdf':
        return 'PDF文档';
      case 'doc':
      case 'docx':
        return 'Word文档';
      case 'xls':
      case 'xlsx':
        return 'Excel表格';
      case 'ppt':
      case 'pptx':
        return 'PowerPoint演示';
      case 'txt':
        return '文本文件';
      case 'zip':
      case 'rar':
      case '7z':
        return '压缩文件';
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
        return '音频文件';
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
      case 'flv':
        return '视频文件';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return '图片文件';
      default:
        return '未知文件';
    }
  }

  // 删除文件
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        print('文件已删除: $filePath');
        return true;
      }
      return false;
    } catch (e) {
      print('删除文件失败: $e');
      return false;
    }
  }

  // 获取下载进度
  Future<double?> getDownloadProgress(String taskId) async {
    try {
      final tasks = await FlutterDownloader.loadTasks();
      final task = tasks!.firstWhere((task) => task.taskId == taskId);
      return task.progress / 100.0;
    } catch (e) {
      return null;
    }
  }

  // 取消下载
  Future<bool> cancelDownload(String taskId) async {
    try {
      await FlutterDownloader.cancel(taskId: taskId);
      print('下载已取消: $taskId');
      return true;
    } catch (e) {
      print('取消下载失败: $e');
      return false;
    }
  }

  // 暂停下载
  Future<bool> pauseDownload(String taskId) async {
    try {
      await FlutterDownloader.pause(taskId: taskId);
      print('下载已暂停: $taskId');
      return true;
    } catch (e) {
      print('暂停下载失败: $e');
      return false;
    }
  }

  // 恢复下载
  Future<bool> resumeDownload(String taskId) async {
    try {
      await FlutterDownloader.resume(taskId: taskId);
      print('下载已恢复: $taskId');
      return true;
    } catch (e) {
      print('恢复下载失败: $e');
      return false;
    }
  }

  // 带进度的下载方法（Dio实现）
  Future<String?> downloadFileWithProgress(
    String url,
    String fileName,
    void Function(double progress)? onProgress,
  ) async {
    try {
      final downloadDir = await getDownloadDirectory();
      if (downloadDir == null) return null;
      final cleanName = cleanFileName(fileName);
      final savePath = '$downloadDir/$cleanName';
      final dio = Dio();

      int lastUpdate = DateTime.now().millisecondsSinceEpoch;

      await dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (total != -1 && onProgress != null) {
            // 只在100ms间隔时才回调
            if (now - lastUpdate > 100 || received == total) {
              onProgress(received / total);
              lastUpdate = now;
            }
          }
        },
      );
      print('文件已保存到: $savePath, 大小: ${File(savePath).lengthSync()} 字节');
      return savePath;
    } catch (e) {
      print('Dio下载失败: $e');
      return null;
    }
  }

  // 带进度的下载方法（FlutterDownloader实现，支持暂停/恢复）
  Future<Map<String, dynamic>?> downloadFileWithProgressAndTaskId(
    String url,
    String fileName,
    void Function(double progress)? onProgress,
  ) async {
    try {
      final downloadDir = await getDownloadDirectory();
      if (downloadDir == null) return null;
      final cleanName = cleanFileName(fileName);
      
      // 生成唯一文件名
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uniqueFileName = '${timestamp}_$cleanName';
      
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: downloadDir,
        fileName: uniqueFileName,
        saveInPublicStorage: true,
        showNotification: true,
        openFileFromNotification: true,
        requiresStorageNotLow: true,
      );

      print('下载任务已启动: $taskId');
      
      // 返回任务ID和文件路径
      return {
        'taskId': taskId,
        'filePath': '$downloadDir/$uniqueFileName',
      };
    } catch (e) {
      print('FlutterDownloader下载失败: $e');
      return null;
    }
  }
} 