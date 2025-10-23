class Message {
  final int id;
  final String? content;
  final String senderId;
  final String receiverId;
  final DateTime timestamp;
  final bool isMe;  // 判断是否是当前用户发送的消息
  final String? status;  // 状态字段：sending, sent, failed
  final String? audioUrl;  // 语音消息的URL字段
  final String? imageUrl;
  final String? videoUrl;  // 视频消息的URL字段
  final String? fileUrl;   // 文件消息的URL字段
  final String? fileName;  // 文件名
  final String? fileSize;  // 文件大小
  final int? audioDuration; // 语音时长字段
  final int? videoDuration; // 视频时长字段
  final double? latitude;  // 位置消息的纬度
  final double? longitude; // 位置消息的经度
  final String? locationAddress; // 位置消息的地址
  final bool visibleToSender;
  final bool visibleToReceiver;

  Message({
    required this.id,
    this.content,
    required this.senderId,
    required this.receiverId,
    required this.timestamp,
    required this.isMe,
    this.status,
    this.audioUrl,  // 语音消息的URL字段
    this.imageUrl,
    this.videoUrl,  // 视频消息的URL字段
    this.fileUrl,   // 文件消息的URL字段
    this.fileName,  // 文件名
    this.fileSize,  // 文件大小
    this.audioDuration, // 语音时长字段
    this.videoDuration, // 视频时长字段
    this.latitude,  // 位置消息的纬度
    this.longitude, // 位置消息的经度
    this.locationAddress, // 位置消息的地址
    this.visibleToSender = true,
    this.visibleToReceiver = true,
  });

  factory Message.fromJson(Map<String, dynamic> json, String currentUserId) {
    // 调试输出
    print('Processing message: $json');
    
    // 统一处理字段名，兼容数据库格式和API响应格式
    final content = json['content'] as String?;
    final senderId = json['sender_id'] as String? ?? json['senderId'] as String?;
    final receiverId = json['receiver_id'] as String? ?? json['receiverId'] as String?;
    final timestamp = json['created_at'] as String? ?? json['timestamp'] as String?; // 数据库用created_at
    final status = json['status'] as String?;
    final audioUrl = json['audio_url'] as String? ?? json['audioUrl'] as String?;
    final imageUrl = json['image_url'] as String? ?? json['imageUrl'] as String?;
    final videoUrl = json['video_url'] as String? ?? json['videoUrl'] as String?;
    final fileUrl = json['file_url'] as String? ?? json['fileUrl'] as String?;
    final fileName = json['file_name'] as String? ?? json['fileName'] as String?;
    final fileSize = json['file_size'] as String? ?? json['fileSize'] as String?;
    final audioDuration = json['audioDuration'] as int?;
    final videoDuration = json['video_duration'] as int? ?? json['videoDuration'] as int?;
    // 处理位置字段，支持多种数据格式和字段名
    double? latitude;
    double? longitude;
    String? locationAddress;
    
    // 尝试多种字段名格式
    final latValue = json['latitude'] ?? json['lat'] ?? json['location_latitude'];
    final lngValue = json['longitude'] ?? json['lng'] ?? json['location_longitude'];
    final addressValue = json['location_address'] ?? json['locationAddress'] ?? json['address'] ?? json['locationName'];
    
    // 处理纬度
    if (latValue != null) {
      if (latValue is double) {
        latitude = latValue;
      } else if (latValue is int) {
        latitude = latValue.toDouble();
      } else if (latValue is String) {
        latitude = double.tryParse(latValue);
      }
    }
    
    // 处理经度
    if (lngValue != null) {
      if (lngValue is double) {
        longitude = lngValue;
      } else if (lngValue is int) {
        longitude = lngValue.toDouble();
      } else if (lngValue is String) {
        longitude = double.tryParse(lngValue);
      }
    }
    
    // 处理地址
    if (addressValue != null) {
      locationAddress = addressValue.toString();
    }
    
    // 调试位置字段
    if (content?.contains('📍 我的位置') == true || latitude != null || longitude != null) {
      print('🔍 位置消息字段处理:');
      print('  - 原始latitude: ${json['latitude']} (类型: ${json['latitude']?.runtimeType})');
      print('  - 原始longitude: ${json['longitude']} (类型: ${json['longitude']?.runtimeType})');
      print('  - 原始location_address: ${json['location_address']} (类型: ${json['location_address']?.runtimeType})');
      print('  - 处理后latitude: $latitude');
      print('  - 处理后longitude: $longitude');
      print('  - 处理后locationAddress: $locationAddress');
    }
    
    if (senderId == null || timestamp == null) {
      throw Exception('Missing required fields: senderId or timestamp');
    }
    
    // 解析时间戳并转换为北京时间
    DateTime parsedTimestamp;
    try {
      // 先解析为UTC时间
      parsedTimestamp = DateTime.parse(timestamp);
      // 转换为北京时间 (UTC+8)
      parsedTimestamp = parsedTimestamp.add(Duration(hours: 8));
    } catch (e) {
      print('Error parsing timestamp: $timestamp, error: $e');
      // 如果解析失败，使用当前时间
      parsedTimestamp = DateTime.now();
    }
    
    return Message(
      id: json['id'] ?? json['messageId'], 
      content: content,
      senderId: senderId,
      receiverId: receiverId ?? '',
      timestamp: parsedTimestamp,
      isMe: senderId == currentUserId,
      status: status,
      audioUrl: audioUrl,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      audioDuration: audioDuration,
      videoDuration: videoDuration,
      latitude: latitude,
      longitude: longitude,
      locationAddress: locationAddress,
      visibleToSender: json['visible_to_sender'] == 1,
      visibleToReceiver: json['visible_to_receiver'] == 1,
    );
  }

  Message copyWith({
    int? id,
    String? content,
    String? senderId,
    String? receiverId,
    DateTime? timestamp,
    bool? isMe,
    String? status,
    String? audioUrl,
    String? imageUrl,
    String? videoUrl,
    String? fileUrl,
    String? fileName,
    String? fileSize,
    int? audioDuration,
    int? videoDuration,
    double? latitude,
    double? longitude,
    String? locationAddress,
    bool? visibleToSender,
    bool? visibleToReceiver,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      timestamp: timestamp ?? this.timestamp,
      isMe: isMe ?? this.isMe,
      status: status ?? this.status,
      audioUrl: audioUrl ?? this.audioUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      audioDuration: audioDuration ?? this.audioDuration,
      videoDuration: videoDuration ?? this.videoDuration,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAddress: locationAddress ?? this.locationAddress,
      visibleToSender: visibleToSender ?? this.visibleToSender,
      visibleToReceiver: visibleToReceiver ?? this.visibleToReceiver,
    );
  }

  // 判断消息是否已撤回
  bool get isRevoked => !visibleToSender && !visibleToReceiver;

  // 判断当前用户是否可见
  bool isVisibleFor(String userId) {
    if (senderId == userId) {
      return visibleToSender;
    } else if (receiverId == userId) {
      return visibleToReceiver;
    }
    return false;
  }
}