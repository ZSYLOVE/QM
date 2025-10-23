import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:onlin/globals.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
@pragma('vm:entry-point')
class UpdateComponent extends StatefulWidget {
  static final globalKey = GlobalKey<_UpdateComponentState>();

  // 添加单例模式确保全局唯一
  static UpdateComponent? _instance;
  factory UpdateComponent() => _instance ??= UpdateComponent._();
  UpdateComponent._();

  @override
  _UpdateComponentState createState() => _UpdateComponentState();
}
@pragma('vm:entry-point')
class _UpdateComponentState extends State<UpdateComponent> with WidgetsBindingObserver {
  String _currentVersion = '';
  String _latestVersion = '';
  bool _updateAvailable = false;
  // ignore: unused_field
  bool _isDownloading = false;
  String? _downloadUrl;
  String? _downloadPath;
  @pragma('vm:entry-point')
  @override
  void initState() {
    super.initState();
    _checkForExistingApk();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('📱 应用生命周期状态: $state');
  }

  Future<String?> _getDownloadDirectory() async {
    final externalStorage = await getExternalStorageDirectory();
    if (externalStorage == null) {
      print('❌ 无法获取外部存储目录');
      return null;
    }
    return '${externalStorage.path}/Download';
  }

  Future<void> _checkForExistingApk() async {
    // 检查默认下载目录
    final defaultDownloadPath = await _getDownloadDirectory();
    if (defaultDownloadPath != null) {
      final defaultDirectory = Directory(defaultDownloadPath);
      if (!defaultDirectory.existsSync()) {
        print('❌ 默认下载目录不存在，尝试创建目录: $defaultDownloadPath');
        try {
          await defaultDirectory.create(recursive: true); // 递归创建目录
          print('✅ 默认下载目录创建成功: $defaultDownloadPath');
        } catch (e) {
          print('❌ 默认下载目录创建失败: $e');
        }
      }

      final defaultApkFiles = defaultDirectory.listSync().where((file) {
        return file is File && file.path.endsWith('.apk');
      }).toList();

      if (defaultApkFiles.isNotEmpty) {
        defaultApkFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        final apkFile = defaultApkFiles.first;
        _downloadPath = apkFile.path;
        print('✅ 在默认下载目录发现已下载的安装包: $_downloadPath');
        _showInstallDialog();
        return;
      }
    }

    // 检查 /storage/emulated/0/Download 目录
    const systemDownloadPath = '/storage/emulated/0/Download';
    final systemDirectory = Directory(systemDownloadPath);
    if (!systemDirectory.existsSync()) {
      print('❌ 系统下载目录不存在: $systemDownloadPath');
      _checkForUpdates();
      return;
    }

    final systemApkFiles = systemDirectory.listSync().where((file) {
      return file is File && file.path.endsWith('.apk');
    }).toList();

    if (systemApkFiles.isNotEmpty) {
      systemApkFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      final apkFile = systemApkFiles.first;
      _downloadPath = apkFile.path;
      print('✅ 在系统下载目录发现已下载的安装包: $_downloadPath');
      _showInstallDialog();
    } else {
      print('❌ 未发现已下载的安装包');
      _checkForUpdates();
    }
  }
  @pragma('vm:entry-point')
  Future<void> _checkForUpdates() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _currentVersion = packageInfo.version;
    });

    try {
      final response = await http.get(Uri.parse('http://47.109.39.180:80/latest-version'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _latestVersion = data['versionCode'].toString();
          _downloadUrl = data['download_url'];
          _updateAvailable = _compareVersions(_currentVersion, _latestVersion);
        });

        if (_updateAvailable) {
          _showUpdateDialog();
        }else{
          _showSnackBar();
        }
      }
    } catch (e) {
      print('Error checking for updates: $e');
    }
  }
  @pragma('vm:entry-point')
  bool _compareVersions(String current, String latest) {
    List<int> currentParts = current.split('.').map((e) => int.parse(e)).toList();
    List<int> latestParts = latest.split('.').map((e) => int.parse(e)).toList();

    for (int i = 0; i < latestParts.length; i++) {
      if (latestParts[i] > currentParts[i]) {
        return true;
      } else if (latestParts[i] < currentParts[i]) {
        return false;
      }
    }
    return false;
  }
  @pragma('vm:entry-point')
  void _showUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('发现新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('发现新版本可用，建议立即更新以获得最佳体验。'),
            ],
          ),
        actions: <Widget>[
         TextButton(
            child: Text('暂不更新'),
            onPressed: () {
              Navigator.of(context).pop(); // 关闭当前对话框
              setState(() {
                Global.showUpdateComponent=false;
              });
            },
          ),
            TextButton(
              child: Text('更新'),
              onPressed: () async {
                Navigator.of(context).pop(); // 关闭当前对话框
                _showDownloadingSnackBar(); // 显示下载提示
                await _startDownload(); // 开始下载
                setState(() {
                  Global.showUpdateComponent=false;
                });
              },
            ),
          ],
        );
      },
    );
  }
  void _showSnackBar(){
    setState(() {
      Global.showUpdateComponent=false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('当前已为最新版本，暂无更新！'),
        duration: Duration(seconds: 3), // 3秒后自动关闭
        behavior: SnackBarBehavior.floating, // 悬浮显示
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), // 圆角样式
        ),
      ),
    );
  }


  void _showDownloadingSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('后台静默下载中,请勿退出应用,正常使用软件即可以免更新失败,重启软件即可安装最新版本,大约需要3分钟！'),
        duration: Duration(seconds: 6), // 6秒后自动关闭
        behavior: SnackBarBehavior.floating, // 悬浮显示
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), // 圆角样式
        ),
      ),
    );
  }

  @pragma('vm:entry-point')
  static void callback(String id, int status, int progress) {
    final taskStatus = DownloadTaskStatus.fromInt(status);

    print('下载任务 $id 状态: $taskStatus, 进度: $progress%');

  }
  @pragma('vm:entry-point')
  Future<void> _startDownload() async {
    final downloadPath = await _getDownloadDirectory();
    if (downloadPath == null) {
      print('❌ 无法获取下载目录');
      return;
    }

    // 按照时间命名文件
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _downloadPath = '$downloadPath/app_update_$timestamp.apk';

    // 尝试写入测试文件
    final testFile = File('$downloadPath/test_$timestamp.txt');
    await testFile.writeAsString('Hello, this is a test!');
    print('文件已写入: ${testFile.path}');

    // 验证文件是否存在
    if (await testFile.exists()) {
      print('✅ 路径可正常访问！');
    } else {
      print('❌ 路径访问失败');
    }

    print('开始下载: $_downloadUrl');
    print('下载路径: $downloadPath');

    final taskId = await FlutterDownloader.enqueue(
      url: _downloadUrl!,
      savedDir: downloadPath,
      fileName: 'app_update_$timestamp.apk', // 按照时间命名文件
      saveInPublicStorage: true,
      showNotification: true,
      openFileFromNotification: true,
    );

    print('✅ 下载任务已启动: $taskId');
  }
  @pragma('vm:entry-point')
  void _showInstallDialog() {
    if (_downloadPath == null) {
      print('❌ 下载路径为空');
      return;
    }

    @pragma('vm:entry-point')
    final file = File(_downloadPath!);

    if (!file.existsSync()) {
      print('❌ 文件不存在: $_downloadPath');
      return;
    }

    print('✅ 文件存在，准备安装: $_downloadPath');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('下载完成'),
          content: Text('新版本已下载，是否立即安装？(若您已经安装但还弹出此提示框,说明您没有开启手机的安装后自动删除安装包功能,但您确实为最新版本,请手动删除文件管理器下的Download文件下的安装包即可!)'),
          actions: <Widget>[
            TextButton(
              child: Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('安装'),
              onPressed: () async {
                Navigator.of(context).pop(); // 先关闭对话框
                try {
                 await OpenFile.open(_downloadPath!);
                } catch (e) {
                  print('❌ 安装过程中出错: $e');
                }
              },
            ),
          ],
        );
      },
    );
  }

  @pragma('vm:entry-point')
  @override
  Widget build(BuildContext context) {
    // 绑定 context 到 GlobalKey
    return Container();
  }
}