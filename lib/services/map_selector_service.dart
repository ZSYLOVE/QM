import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

class MapSelectorService {
  static final MapSelectorService _instance = MapSelectorService._internal();
  factory MapSelectorService() => _instance;
  MapSelectorService._internal();

  /// 根据平台和地区生成地图URL列表
  List<String> getMapUrls(double latitude, double longitude, String address) {
    List<String> mapUrls = [];
    
    if (Platform.isIOS) {
      // iOS平台地图优先级
      mapUrls = [
        // Apple Maps (iOS原生)
        'https://maps.apple.com/?q=$latitude,$longitude',
        // 高德地图 (iOS版)
        'https://uri.amap.com/marker?position=$longitude,$latitude&name=位置&src=myapp&coordinate=gaode&callnative=0',
        // 百度地图 (iOS版)
        'https://api.map.baidu.com/marker?location=$latitude,$longitude&title=位置&content=$address&output=html',
        // 腾讯地图 (iOS版)
        'https://apis.map.qq.com/uri/v1/routeplan?type=drive&to=位置&tocoord=$latitude,$longitude&coord_type=1&policy=0&referer=myapp',
      ];
    } else {
      // Android平台地图优先级
      mapUrls = [
        // 百度地图 (Android版，中国大陆最常用)
        'https://api.map.baidu.com/marker?location=$latitude,$longitude&title=位置&content=$address&output=html',
        // 高德地图 (Android版)
        'https://uri.amap.com/marker?position=$longitude,$latitude&name=位置&src=myapp&coordinate=gaode&callnative=0',
        // 腾讯地图 (Android版)
        'https://apis.map.qq.com/uri/v1/routeplan?type=drive&to=位置&tocoord=$latitude,$longitude&coord_type=1&policy=0&referer=myapp',
        // 华为地图 (Android版，华为设备)
        'https://developer.huawei.com/consumer/cn/agconnect/location',
      ];
    }
    
    return mapUrls;
  }

  /// 生成Web地图URL（作为备选方案）
  String getWebMapUrl(double latitude, double longitude, String address) {
    // 优先使用百度地图Web版，在中国大陆访问最稳定
    return 'https://api.map.baidu.com/marker?location=$latitude,$longitude&title=位置&content=$address&output=html';
  }

  /// 智能打开地图应用
  Future<bool> openMapApp(double latitude, double longitude, String address) async {
    try {
      List<String> mapUrls = getMapUrls(latitude, longitude, address);
      
      // 尝试打开每个地图应用
      for (String urlTemplate in mapUrls) {
        String url = urlTemplate
            .replaceAll('\$latitude', latitude.toString())
            .replaceAll('\$longitude', longitude.toString())
            .replaceAll('\$address', Uri.encodeComponent(address));
        
        try {
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            print('成功打开地图应用: ${url.split('?')[0]}');
            return true;
          }
        } catch (e) {
          print('尝试打开地图应用失败: ${url.split('?')[0]}, 错误: $e');
          continue;
        }
      }
      
      // 如果所有地图应用都无法打开，使用Web地图
      return await _openWebMap(latitude, longitude, address);
      
    } catch (e) {
      print('打开地图应用失败: $e');
      return false;
    }
  }

  /// 打开Web地图
  Future<bool> _openWebMap(double latitude, double longitude, String address) async {
    try {
      String webMapUrl = getWebMapUrl(latitude, longitude, address);
      webMapUrl = webMapUrl
          .replaceAll('\$latitude', latitude.toString())
          .replaceAll('\$longitude', longitude.toString())
          .replaceAll('\$address', Uri.encodeComponent(address));
      
      if (await canLaunchUrl(Uri.parse(webMapUrl))) {
        await launchUrl(Uri.parse(webMapUrl), mode: LaunchMode.inAppWebView);
        print('使用Web地图打开位置');
        return true;
      }
      
      return false;
    } catch (e) {
      print('打开Web地图失败: $e');
      return false;
    }
  }

  /// 获取地图应用安装建议
  String getMapAppSuggestion() {
    if (Platform.isIOS) {
      return '建议安装高德地图或百度地图以获得更好的体验';
    } else {
      return '建议安装百度地图或高德地图以获得更好的体验';
    }
  }

  /// 获取地图应用下载链接
  Map<String, String> getMapAppDownloadLinks() {
    if (Platform.isIOS) {
      return {
        '高德地图': 'https://apps.apple.com/cn/app/gao-de-di-tu-dao-hang-bus/id461703208',
        '百度地图': 'https://apps.apple.com/cn/app/baidu-di-tu-dao-hang-bus/id452186370',
        '腾讯地图': 'https://apps.apple.com/cn/app/tencent-map/id481623674',
      };
    } else {
      return {
        '百度地图': 'https://mobile.baidu.com/map/',
        '高德地图': 'https://mobile.amap.com/',
        '腾讯地图': 'https://map.qq.com/mobile/',
      };
    }
  }

  /// 检查是否在中国大陆（简单判断）
  bool isInMainlandChina() {
    // 这里可以根据实际需求实现更精确的地理位置判断
    // 目前简单返回true，假设用户在中国大陆
    return true;
  }

  /// 根据地区获取推荐地图应用
  List<String> getRecommendedMapApps() {
    if (isInMainlandChina()) {
      if (Platform.isIOS) {
        return ['高德地图', '百度地图', '腾讯地图'];
      } else {
        return ['百度地图', '高德地图', '腾讯地图'];
      }
    } else {
      if (Platform.isIOS) {
        return ['Apple Maps', 'Google Maps'];
      } else {
        return ['Google Maps', '百度地图'];
      }
    }
  }
} 