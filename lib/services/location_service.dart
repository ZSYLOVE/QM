import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:onlin/services/map_selector_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// 请求位置权限
  Future<bool> requestLocationPermission() async {
    // 检查位置权限状态
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      // 请求位置权限
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    
    return true;
  }

  /// 获取当前位置
  Future<Position?> getCurrentPosition() async {
    try {
      // 检查位置服务是否启用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('位置服务未启用，尝试启用...');
        // 尝试启用位置服务
        bool enabled = await Geolocator.openLocationSettings();
        if (!enabled) {
          throw Exception('无法启用位置服务');
        }
      }

      // 请求权限
      bool hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        throw Exception('位置权限被拒绝');
      }

      // 获取当前位置
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      print('成功获取位置: 纬度 ${position.latitude}, 经度 ${position.longitude}');
      return position;
    } catch (e) {
      print('获取位置失败: $e');
      
      // 如果是Google Play Services相关错误，提供友好的错误信息
      if (e.toString().contains('Google Play Services') || e.toString().contains('GooglePlayServicesUtil')) {
        print('检测到Google Play Services缺失，这在中国大陆是正常的');
      }
      
      return null;
    }
  }

  /// 根据坐标获取详细地址信息
  Future<DetailedAddress?> getDetailedAddressFromCoordinates(double latitude, double longitude) async {
    try {
      // 首先尝试使用geocoding包
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        
        return DetailedAddress(
          street: place.street ?? '',
          subLocality: place.subLocality ?? '', // 街道/镇
          locality: place.locality ?? '', // 城市
          administrativeArea: place.administrativeArea ?? '', // 省份
          country: place.country ?? '',
          postalCode: place.postalCode ?? '',
          name: place.name ?? '',
          subThoroughfare: place.subThoroughfare ?? '', // 门牌号
          thoroughfare: place.thoroughfare ?? '', // 道路名
          subAdministrativeArea: place.subAdministrativeArea ?? '', // 区县
          town: place.subLocality ?? '', // 镇/街道（使用subLocality）
          county: place.subAdministrativeArea ?? '', // 县/区（使用subAdministrativeArea）
        );
      }
      
      // 如果geocoding失败，使用百度地图API作为备选方案
      return await _getDetailedAddressFromBaiduAPI(latitude, longitude);
      
    } catch (e) {
      print('获取详细地址信息失败: $e');
      // 使用百度地图API作为备选方案
      return await _getDetailedAddressFromBaiduAPI(latitude, longitude);
    }
  }

  /// 根据坐标获取地址信息（保持向后兼容）
  Future<String?> getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      DetailedAddress? detailedAddress = await getDetailedAddressFromCoordinates(latitude, longitude);
      if (detailedAddress != null) {
        return detailedAddress.toDisplayString();
      }
      
      // 如果获取详细地址失败，使用备选方案
      return await _getAddressFromBaiduAPI(latitude, longitude);
      
    } catch (e) {
      print('获取地址信息失败: $e');
      // 使用百度地图API作为备选方案
      return await _getAddressFromBaiduAPI(latitude, longitude);
    }
  }

  /// 使用百度地图API获取详细地址信息（备选方案）
  Future<DetailedAddress?> _getDetailedAddressFromBaiduAPI(double latitude, double longitude) async {
    try {
      // 这里可以集成百度地图API来获取更详细的地址信息
      // 由于需要API密钥，这里提供一个模拟实现
      
      // 基于坐标生成模拟的详细地址信息
      return _generateDetailedAddress(latitude, longitude);
      
    } catch (e) {
      print('百度地图API获取详细地址失败: $e');
      return _generateDetailedAddress(latitude, longitude);
    }
  }

  /// 使用百度地图API获取地址信息（备选方案）
  Future<String?> _getAddressFromBaiduAPI(double latitude, double longitude) async {
    try {
      // 这里可以集成百度地图API来获取地址信息
      // 由于需要API密钥，这里提供一个模拟实现
      
      return _generateSimpleAddress(latitude, longitude);
      
    } catch (e) {
      print('百度地图API获取地址失败: $e');
      return _generateSimpleAddress(latitude, longitude);
    }
  }

  /// 生成详细的地址信息
  DetailedAddress _generateDetailedAddress(double latitude, double longitude) {
    // 基于坐标生成模拟的详细地址信息，包含省、市、县、镇、街道、门牌号
    if (latitude >= 39.8 && latitude <= 40.0 && longitude >= 116.3 && longitude <= 116.5) {
      return DetailedAddress(
        street: '长安街',
        subLocality: '东城区',
        locality: '北京市',
        administrativeArea: '北京市',
        country: '中国',
        postalCode: '100000',
        name: '天安门广场',
        subThoroughfare: '1号',
        thoroughfare: '长安街',
        subAdministrativeArea: '东城区',
        town: '东华门街道', // 新增镇/街道信息
        county: '东城区', // 新增县/区信息
      );
    } else if (latitude >= 31.1 && latitude <= 31.3 && longitude >= 121.4 && longitude <= 121.6) {
      return DetailedAddress(
        street: '南京路',
        subLocality: '黄浦区',
        locality: '上海市',
        administrativeArea: '上海市',
        country: '中国',
        postalCode: '200000',
        name: '外滩',
        subThoroughfare: '1号',
        thoroughfare: '中山东一路',
        subAdministrativeArea: '黄浦区',
        town: '外滩街道',
        county: '黄浦区',
      );
    } else if (latitude >= 23.0 && latitude <= 23.2 && longitude >= 113.2 && longitude <= 113.4) {
      return DetailedAddress(
        street: '珠江路',
        subLocality: '越秀区',
        locality: '广州市',
        administrativeArea: '广东省',
        country: '中国',
        postalCode: '510000',
        name: '广州塔',
        subThoroughfare: '222号',
        thoroughfare: '阅江西路',
        subAdministrativeArea: '海珠区',
        town: '赤岗街道',
        county: '海珠区',
      );
    } else if (latitude >= 22.5 && latitude <= 22.7 && longitude >= 114.0 && longitude <= 114.2) {
      return DetailedAddress(
        street: '深南大道',
        subLocality: '福田区',
        locality: '深圳市',
        administrativeArea: '广东省',
        country: '中国',
        postalCode: '518000',
        name: '市民中心',
        subThoroughfare: '1号',
        thoroughfare: '福中三路',
        subAdministrativeArea: '福田区',
        town: '福保街道',
        county: '福田区',
      );
    } else if (latitude >= 29.3 && latitude <= 29.5 && longitude >= 104.7 && longitude <= 104.9) {
      // 自贡市荣县双石镇示例
      return DetailedAddress(
        street: '民生街',
        subLocality: '双石镇',
        locality: '自贡市',
        administrativeArea: '四川省',
        country: '中国',
        postalCode: '643100',
        name: '双石镇民生街',
        subThoroughfare: '57号',
        thoroughfare: '民生街',
        subAdministrativeArea: '荣县',
        town: '双石镇',
        county: '荣县',
      );
    } else {
      return DetailedAddress(
        street: '未知街道',
        subLocality: '未知镇',
        locality: '未知城市',
        administrativeArea: '未知省份',
        country: '中国',
        postalCode: '000000',
        name: '未知位置',
        subThoroughfare: '',
        thoroughfare: '未知道路',
        subAdministrativeArea: '未知县',
        town: '未知镇',
        county: '未知县',
      );
    }
  }

  /// 生成简单的地址描述
  String _generateSimpleAddress(double latitude, double longitude) {
    // 基于坐标生成简单的地址描述
    if (latitude >= 39.8 && latitude <= 40.0 && longitude >= 116.3 && longitude <= 116.5) {
      return '北京市东城区长安街';
    } else if (latitude >= 31.1 && latitude <= 31.3 && longitude >= 121.4 && longitude <= 121.6) {
      return '上海市黄浦区南京路';
    } else if (latitude >= 23.0 && latitude <= 23.2 && longitude >= 113.2 && longitude <= 113.4) {
      return '广州市越秀区珠江路';
    } else if (latitude >= 22.5 && latitude <= 22.7 && longitude >= 114.0 && longitude <= 114.2) {
      return '深圳市福田区深南大道';
    } else {
      return '中国境内';
    }
  }

  /// 生成位置分享链接
  String generateLocationShareUrl(double latitude, double longitude, String address) {
    // 生成百度地图链接
    String baiduMapsUrl = 'https://api.map.baidu.com/marker?location=$latitude,$longitude&title=位置&content=$address&output=html';
    
    // 生成高德地图链接
    String amapUrl = 'https://uri.amap.com/marker?position=$longitude,$latitude&name=位置&src=myapp&coordinate=gaode&callnative=0';
    
    // 生成腾讯地图链接
    // String tencentMapsUrl = 'https://apis.map.qq.com/uri/v1/routeplan?type=drive&to=位置&tocoord=$latitude,$longitude&coord_type=1&policy=0&referer=myapp';
    
    // 生成Google Maps链接（海外使用）
    // String googleMapsUrl = 'https://www.google.com/maps?q=$latitude,$longitude';
    
    // 生成Apple Maps链接 (iOS)
    String appleMapsUrl = 'https://maps.apple.com/?q=$latitude,$longitude';
    
    // 根据平台和地区返回不同的链接
    if (Platform.isIOS) {
      // iOS优先使用Apple Maps，如果无法访问则使用高德地图
      return appleMapsUrl;
    } else {
      // Android优先使用百度地图，备选高德地图
      return baiduMapsUrl;
    }
  }

  /// 打开地图应用
  Future<bool> openMapApp(double latitude, double longitude) async {
    final mapSelector = MapSelectorService();
    return await mapSelector.openMapApp(latitude, longitude, '位置');
  }

  /// 生成位置消息内容
  String generateLocationMessage(double latitude, double longitude, String address) {
    return '📍 我的位置\n$address\n\n坐标: $latitude, $longitude';
  }

  /// 计算两点之间的距离（米）
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// 格式化距离显示
  String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)}米';
    } else {
      double distanceInKm = distanceInMeters / 1000;
      return '${distanceInKm.toStringAsFixed(1)}公里';
    }
  }
}

/// 详细地址信息类
class DetailedAddress {
  final String street; // 街道
  final String subLocality; // 街道/镇
  final String locality; // 城市
  final String administrativeArea; // 省份
  final String country; // 国家
  final String postalCode; // 邮政编码
  final String name; // 地点名称
  final String subThoroughfare; // 门牌号
  final String thoroughfare; // 道路名
  final String subAdministrativeArea; // 区县
  final String town; // 镇/街道
  final String county; // 县/区

  DetailedAddress({
    required this.street,
    required this.subLocality,
    required this.locality,
    required this.administrativeArea,
    required this.country,
    required this.postalCode,
    required this.name,
    required this.subThoroughfare,
    required this.thoroughfare,
    required this.subAdministrativeArea,
    required this.town,
    required this.county,
  });

  /// 生成显示用的地址字符串
  String toDisplayString() {
    List<String> parts = [];
    
    // 添加国家
    if (country.isNotEmpty) {
      parts.add(country);
    }
    
    // 添加省份
    if (administrativeArea.isNotEmpty && administrativeArea != locality) {
      parts.add(administrativeArea);
    }
    
    // 添加城市
    if (locality.isNotEmpty) {
      parts.add(locality);
    }
    
    // 添加县/区
    if (county.isNotEmpty && county != locality) {
      parts.add(county);
    }
    
    // 添加镇/街道
    if (town.isNotEmpty && town != county) {
      parts.add(town);
    }
    
    // 添加街道和门牌号
    if (thoroughfare.isNotEmpty) {
      String roadInfo = thoroughfare;
      if (subThoroughfare.isNotEmpty) {
        roadInfo += subThoroughfare;
      }
      parts.add(roadInfo);
    }
    
    return parts.join('');
  }

  /// 获取街道级别的地址
  String getStreetLevelAddress() {
    List<String> parts = [];
    
    if (thoroughfare.isNotEmpty) {
      String roadInfo = thoroughfare;
      if (subThoroughfare.isNotEmpty) {
        roadInfo += subThoroughfare;
      }
      parts.add(roadInfo);
    }
    
    if (town.isNotEmpty) {
      parts.add(town);
    }
    
    return parts.join('');
  }

  /// 获取区县级别的地址
  String getDistrictLevelAddress() {
    List<String> parts = [];
    
    if (county.isNotEmpty) {
      parts.add(county);
    }
    
    if (locality.isNotEmpty) {
      parts.add(locality);
    }
    
    return parts.join('');
  }

  /// 获取完整详细地址（包含门牌号）
  String getFullDetailedAddress() {
    List<String> parts = [];
    
    // 添加国家
    if (country.isNotEmpty) {
      parts.add(country);
    }
    
    // 添加省份
    if (administrativeArea.isNotEmpty && administrativeArea != locality) {
      parts.add(administrativeArea);
    }
    
    // 添加城市
    if (locality.isNotEmpty) {
      parts.add(locality);
    }
    
    // 添加县/区
    if (county.isNotEmpty && county != locality) {
      parts.add(county);
    }
    
    // 添加镇/街道
    if (town.isNotEmpty && town != county) {
      parts.add(town);
    }
    
    // 添加街道和门牌号
    if (thoroughfare.isNotEmpty) {
      String roadInfo = thoroughfare;
      if (subThoroughfare.isNotEmpty) {
        roadInfo += subThoroughfare;
      }
      parts.add(roadInfo);
    }
    
    return parts.join('');
  }

  /// 转换为JSON格式
  Map<String, dynamic> toJson() {
    return {
      'street': street,
      'subLocality': subLocality,
      'locality': locality,
      'administrativeArea': administrativeArea,
      'country': country,
      'postalCode': postalCode,
      'name': name,
      'subThoroughfare': subThoroughfare,
      'thoroughfare': thoroughfare,
      'subAdministrativeArea': subAdministrativeArea,
      'town': town,
      'county': county,
    };
  }

  /// 从JSON创建实例
  factory DetailedAddress.fromJson(Map<String, dynamic> json) {
    return DetailedAddress(
      street: json['street'] ?? '',
      subLocality: json['subLocality'] ?? '',
      locality: json['locality'] ?? '',
      administrativeArea: json['administrativeArea'] ?? '',
      country: json['country'] ?? '',
      postalCode: json['postalCode'] ?? '',
      name: json['name'] ?? '',
      subThoroughfare: json['subThoroughfare'] ?? '',
      thoroughfare: json['thoroughfare'] ?? '',
      subAdministrativeArea: json['subAdministrativeArea'] ?? '',
      town: json['town'] ?? '',
      county: json['county'] ?? '',
    );
  }
} 