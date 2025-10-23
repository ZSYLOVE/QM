# 详细地址格式功能说明

## 概述

位置服务已升级，现在支持生成类似"中国四川省自贡市荣县双石镇民生街57号"的详细地址格式。

## 新增功能

### 1. 新增地址字段
- `town`: 镇/街道
- `county`: 县/区

### 2. 新增地址显示方法
- `getFullDetailedAddress()`: 获取完整详细地址（推荐使用）

## 地址格式示例

### 完整详细地址格式
```
中国四川省自贡市荣县双石镇民生街57号
```

### 不同级别的地址显示

| 方法 | 输出示例 | 说明 |
|------|----------|------|
| `getFullDetailedAddress()` | 中国四川省自贡市荣县双石镇民生街57号 | 完整详细地址（推荐） |
| `toDisplayString()` | 中国四川省自贡市荣县双石镇民生街57号 | 标准显示格式 |
| `getStreetLevelAddress()` | 民生街57号双石镇 | 街道级别地址 |
| `getDistrictLevelAddress()` | 荣县自贡市 | 区县级别地址 |

## 使用方法

### 获取详细地址信息
```dart
import 'package:onlin/services/location_service.dart';

final locationService = LocationService();

// 获取当前位置的详细地址
Position? position = await locationService.getCurrentPosition();
if (position != null) {
  DetailedAddress? detailedAddress = await locationService.getDetailedAddressFromCoordinates(
    position.latitude,
    position.longitude,
  );
  
  if (detailedAddress != null) {
    // 获取完整详细地址
    String fullAddress = detailedAddress.getFullDetailedAddress();
    print('完整地址: $fullAddress');
    // 输出: 中国四川省自贡市荣县双石镇民生街57号
  }
}
```

### 根据坐标获取地址
```dart
// 自贡市荣县双石镇坐标
DetailedAddress? address = await locationService.getDetailedAddressFromCoordinates(
  29.4, // 纬度
  104.8, // 经度
);

if (address != null) {
  print('地址: ${address.getFullDetailedAddress()}');
  // 输出: 中国四川省自贡市荣县双石镇民生街57号
}
```

## 地址字段说明

| 字段 | 说明 | 示例 |
|------|------|------|
| `country` | 国家 | 中国 |
| `administrativeArea` | 省份 | 四川省 |
| `locality` | 城市 | 自贡市 |
| `county` | 县/区 | 荣县 |
| `town` | 镇/街道 | 双石镇 |
| `thoroughfare` | 道路名 | 民生街 |
| `subThoroughfare` | 门牌号 | 57号 |

## 支持的地址格式

### 1. 城市地址
- 北京: 中国北京市东城区东华门街道长安街1号
- 上海: 中国上海市黄浦区外滩街道中山东一路1号
- 广州: 中国广东省广州市海珠区赤岗街道阅江西路222号
- 深圳: 中国广东省深圳市福田区福保街道福中三路1号

### 2. 县级地址
- 自贡市荣县: 中国四川省自贡市荣县双石镇民生街57号

## 在应用中使用

### 位置选择器
位置选择器已更新，现在显示完整详细地址：
```dart
// 在位置选择器中使用
String address = detailedAddress.getFullDetailedAddress();
// 显示: 中国四川省自贡市荣县双石镇民生街57号
```

### 位置分享
```dart
// 生成位置分享消息
String locationMessage = locationService.generateLocationMessage(
  latitude,
  longitude,
  detailedAddress.getFullDetailedAddress(),
);
```

## 注意事项

1. **地址精确度**: 地址信息的精确度取决于GPS信号质量和网络服务
2. **网络依赖**: 地址解析需要网络连接
3. **备选方案**: 当主要服务不可用时，会使用模拟数据
4. **向后兼容**: 原有方法仍然可用，不会影响现有代码

## 更新日志

### v2.1.0
- 新增 `town` 和 `county` 字段
- 新增 `getFullDetailedAddress()` 方法
- 支持生成类似"中国四川省自贡市荣县双石镇民生街57号"的详细地址格式
- 更新地址显示逻辑，按省、市、县、镇、街道、门牌号的顺序排列
- 保持向后兼容性 