// ignore_for_file: dead_code_on_catch_subtype

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:onlin/baseUrl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onlin/servers/message.dart';
import 'package:onlin/utils/network_utils.dart';
import 'package:onlin/services/token_expired_service.dart';
import 'package:flutter/material.dart';

class ApiService {
  
  // 用户注册
  Future<bool> register(String username, String email, String phonenumber, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('${Baseurl.baseUrl}/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'username': username,
              'email': email,
              'phone_number': phonenumber,
              'password': password,
            }),
          )
          .timeout(Duration(seconds: 10), onTimeout: () {
        print('Request timeout');
        throw Exception('Request timed out');
      });

      print("response: ${response.body}"); // 打印响应内容

      if (response.statusCode == 201) {
        return true; // 注册成功
      } else {
        // 检查响应的Content-Type是否为JSON
        if (response.headers['content-type']?.contains('application/json') ?? false) {
          var data = json.decode(response.body);
          print('Registration failed: ${data['error']}');
        } else {
          print('Expected JSON response, but got: ${response.headers['content-type']}');
        }
        return false; // 注册失败
      }
    } catch (e) {
      print('Error in register: $e');
      return false; // 网络错误或其他异常
    }
  }

  // 用户登录
  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${Baseurl.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveLoginData(data['token'], data['email'], data['username'], data['avatar'] ?? '');
        return data;
      }
      return null;
    } catch (e) {
      print('Error logging in: $e');
      return null;
    }
  }

  // 发送消息
  Future<Map<String, dynamic>?> sendMessage({
    required String senderEmail,
    required String receiverEmail,
    String? audioUrl,
    String? content,
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
  }) async {
    try {
      print('发送消息请求: senderEmail=$senderEmail, receiverEmail=$receiverEmail, content=$content');
      
      final response = await http.post(
        Uri.parse('${Baseurl.baseUrl}/messages/sendMessage'),
        headers: await getHeaders(),
        body: jsonEncode({
          'senderEmail': senderEmail,  
          'receiverEmail': receiverEmail,  
          'content': content ?? '',
          'imageUrl': imageUrl,
          'videoUrl': videoUrl,
          'fileUrl': fileUrl,
          'fileName': fileName,
          'fileSize': fileSize,
          'audioUrl': audioUrl,
          'audioDuration': audioDuration,
          'videoDuration': videoDuration,
          'latitude': latitude,
          'longitude': longitude,
          'locationAddress': locationAddress,
        }),
      );

      print('发送消息响应状态: ${response.statusCode}');
      print('发送消息响应内容: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messageData = data['data'] as Map<String, dynamic>?;
        
        if (messageData != null) {
          // 添加成功标志
          messageData['success'] = true;
          print('消息发送成功: $messageData');
          return messageData;
        } else {
          print('响应数据格式错误: $data');
          return {'success': false, 'error': '响应数据格式错误'};
        }
      } else {
        // 检查Token过期
        if (response.statusCode == 401) {
          try {
            final errorData = json.decode(response.body);
            if (errorData['code'] == 'TOKEN_EXPIRED') {
              print('🔒 Token已过期，需要重新登录');
              return {'success': false, 'error': 'TOKEN_EXPIRED', 'code': 'TOKEN_EXPIRED'};
            }
          } catch (e) {
            // 解析失败，检查响应体内容
            if (response.body.contains('Token已过期')) {
              print('🔒 Token已过期，需要重新登录');
              return {'success': false, 'error': 'TOKEN_EXPIRED', 'code': 'TOKEN_EXPIRED'};
            }
          }
        }
        print('消息发送失败: ${response.statusCode} - ${response.body}');
        return {'success': false, 'error': '服务器错误: ${response.statusCode}'};
      }
    } catch (e) {
      print('消息发送异常: $e');
      return {'success': false, 'error': '网络错误: $e'};
    }
  }

  // 获取好友列表
  Future<List<Map<String, dynamic>>> getFriendsList(String userEmail) async {
    try {
      final response = await http.get(
        Uri.parse('${Baseurl.baseUrl}/api/friends/list/$userEmail'),
        headers: await getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['friends']);
      } else {
        print('Failed to get friends list: ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting friends list: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> sendFriendRequest(String userEmail, String friendEmail) async {
    try {
      final response = await http.post(
        Uri.parse('${Baseurl.baseUrl}/api/friends/request'),  
        headers: await getHeaders(),
        body: json.encode({'userId': userEmail, 'friendEmail': friendEmail}),
      );

      // 如果状态码是 200，表示请求成功
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        // 处理错误或非 200 状态码的情况
        print('Error: ${response.statusCode}, ${response.body}');
        return null;
      }
    } catch (e) {
      // 如果请求发生错误，打印错误信息
      print('Error sending friend request: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getFriendRequests(String userEmail) async {
    final response = await http.post(
      Uri.parse('${Baseurl.baseUrl}/api/friends/requests'), 
      headers: await getHeaders(),
      body: json.encode({
        'userEmail': userEmail,
      }),
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      if (responseData['requests'] != null) {
        return List<Map<String, dynamic>>.from(responseData['requests']);
      }
    } else {
      throw Exception('Failed to load friend requests');
    }

    return [];
  }

  // 接受好友请求
  Future<Map<String, dynamic>?> acceptFriendRequest(String userEmail, String friendEmail) async {
    try {
      final response = await http.post(
        Uri.parse('${Baseurl.baseUrl}/api/friends/accept'),
        headers: await getHeaders(),
        body: jsonEncode({
          'userId': userEmail,  // userId 就是 userEmail
          'friendId': friendEmail,  // friendId 就是 friendEmail
        }),
      );

      if (response.statusCode == 200) {
        print('Friend request accepted successfully');
        return jsonDecode(response.body);
      } else {
        print('Failed to accept friend request: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error accepting friend request: $e');
      return null;
    }
  }

  // 拒绝好友请求
  Future<Map<String, dynamic>?> rejectFriendRequest(String userEmail, String friendEmail) async {
    try {
      final response = await http.post(
        Uri.parse('${Baseurl.baseUrl}/api/friends/reject'),
        headers: await getHeaders(),
        body: json.encode({'userId': userEmail, 'friendId': friendEmail}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return null;
      }
    } catch (e) {
      print('Error rejecting friend request: $e');
      return null;
    }
  }

  // 保存登录数据到SharedPreferences
  Future<void> _saveLoginData(String token, String email, String username, String avatar) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('email', email);
    await prefs.setString('username', username);
    await prefs.setString('avatar', avatar);
    print('✅ 已存储用户数据 | Token: ${token.isNotEmpty} | Email: $email | 用户名: $username | 头像: $avatar');
  }

  // 从SharedPreferences读取token和email
  Future<Map<String, String>?> getLoginData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    String? email = prefs.getString('email');
    String? username = prefs.getString('username');
    String? avatar = prefs.getString('avatar');
    if (token != null && email != null && username != null&& avatar != null) {
      return {
        'token': token,
        'email': email,
        'username':username,
        'avatar':avatar,
      };
    } else {
      return null; // 如果没有保存数据，返回null
    }
  }

  // 获取好友信息
  Future<Map<String, dynamic>> getFriendInfo(String email) async {
    try {
      // 使用好友列表 API 获取用户信息
      final response = await http.get(
        Uri.parse('${Baseurl.baseUrl}/api/friends/list/$email'),
        headers: await getHeaders(),
      );

      print('Friend info response: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final friends = data['friends'] as List;
        
        // 在好友列表中查找指定邮箱的好友信息
        final friendInfo = friends.firstWhere(
          (friend) => friend['email'] == email,
          orElse: () => {'username': email, 'email': email},
        );

        return {
          'username': friendInfo['username'] ?? email,
          'email': friendInfo['email'] ?? email,
        };
      } else {
        print('Failed to get friend info: ${response.statusCode}');
        return {'username': email, 'email': email};
      }
    } catch (e) {
      print('Error getting friend info: $e');
      return {'username': email, 'email': email};
    }
  }

  // 获取聊天历史
  Future<List<Message>> getChatHistory(String userEmail, String friendEmail) async {
    try {
      print('Fetching chat history for user $userEmail with friend $friendEmail');
      
      final uri = Uri.parse('${Baseurl.baseUrl}/messages/history/$userEmail')
          .replace(queryParameters: {
        'otherUserId': friendEmail, 
        '_t': DateTime.now().millisecondsSinceEpoch.toString(), // 禁用缓存   
      });

      print('Requesting URL: $uri');

      final response = await http.get(
        uri,
        headers: await getHeaders(),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> messages = responseData['messages'] ?? [];
        
        print('Found ${messages.length} messages');
        
        return messages.map((msg) {
          try {
            print('Parsing message: $msg'); // 添加调试信息
            print('Message ID field: ${msg['id']} vs ${msg['messageId']}'); // 检查ID字段
            
            // 特别检查位置消息的字段
            if (msg['content']?.toString().contains('📍 我的位置') == true) {
              print('🔍 发现位置消息，检查字段:');
              print('  - latitude: ${msg['latitude']} (类型: ${msg['latitude']?.runtimeType})');
              print('  - longitude: ${msg['longitude']} (类型: ${msg['longitude']?.runtimeType})');
              print('  - location_address: ${msg['location_address']} (类型: ${msg['location_address']?.runtimeType})');
              print('  - lat: ${msg['lat']} (类型: ${msg['lat']?.runtimeType})');
              print('  - lng: ${msg['lng']} (类型: ${msg['lng']?.runtimeType})');
              print('  - address: ${msg['address']} (类型: ${msg['address']?.runtimeType})');
              print('  - locationName: ${msg['locationName']} (类型: ${msg['locationName']?.runtimeType})');
              print('  - 所有字段: ${msg.keys.toList()}');
              print('  - 完整消息数据: $msg');
            }
            
            return Message.fromJson(msg, userEmail);
          } catch (e) {
            print('Error parsing message: $msg');
            print('Error details: $e');
            return null;
          }
        })
        .where((message) => message != null)
        .cast<Message>()
        .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp)); // 按时间顺序排序
      } else {
        // 检查Token过期
        if (response.statusCode == 401) {
          try {
            final errorData = json.decode(response.body);
            if (errorData['code'] == 'TOKEN_EXPIRED') {
              print('🔒 Token已过期，需要重新登录');
              throw Exception('TOKEN_EXPIRED');
            }
          } catch (e) {
            // 解析失败，检查响应体内容
            if (response.body.contains('Token已过期')) {
              print('🔒 Token已过期，需要重新登录');
              throw Exception('TOKEN_EXPIRED');
            }
          }
        }
        print('Error response: ${response.body}');
        throw Exception('Failed to load chat history: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting chat history: $e');
      return [];
    }
  }

  Future<Map<String, String>> getHeaders() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    if (token == null) {
      throw Exception('Token is null');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<bool> clearChatHistory(String userEmail, String friendEmail) async {
    final url = Uri.parse('${Baseurl.baseUrl}/messages/clearHistory');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: jsonEncode({
          'userEmail': userEmail,
          'friendEmail': friendEmail,
        }),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        print('清空聊天记录失败: ${response.body}');
        return false;
      }
    } catch (e) {
      print('清空聊天记录异常: $e');
      return false;
    }
  }
  
  Future<Map<String, dynamic>> updateAvatar(String avatarUrl, String userEmail) async {
    try {
      print('Sending request to update avatar: $avatarUrl'); // 调试信息
      var response = await http.post(
        Uri.parse('${Baseurl.baseUrl}/auth/change-avatar'),
        headers: await getHeaders(),
        body: jsonEncode({'avatarUrl': avatarUrl, 'userId': userEmail}), 
      );
      print('Response status: ${response.statusCode}'); // 调试信息
      print('Response body: ${response.body}'); // 调试信息
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update avatar');
      }
    } catch (e) {
      print('Error updating avatar: $e');
      return {};
    }
  }

  Future<bool> deleteFriend(String userEmail, String friendEmail) async {
    final url = Uri.parse('${Baseurl.baseUrl}/api/friends/delete');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: jsonEncode({
          'userEmail': userEmail,
          'friendEmail': friendEmail,
        }),
      );
      if (response.statusCode == 200) {
        // 你可以根据后端返回内容进一步判断
        return true;
      } else {
        print('删除好友失败: ${response.body}');
        return false;
      }
    } catch (e) {
      print('删除好友异常: $e');
      return false;
    }
  }

  Future<bool> changePassword(String email,String currentPassword, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('${Baseurl.baseUrl}/auth/change-password'),
        headers: await getHeaders(),
        body: json.encode({
          'email':email,
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      print('Error changing password: $e');
      return false;
    }
  }

  // 获取未读消息数量的方法
  Future<Map<String, dynamic>> getUnreadMessageCount(String email) async {
    try {
      final response = await http.get(
        Uri.parse('${Baseurl.baseUrl}/messages/unread-count?userId=$email'),
        headers: await getHeaders(),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'unreadCount': 0};
    } catch (e) {
      print('Error getting unread message count: $e');
      return {'unreadCount': 0};
    }
  }
    Future<Map<String, dynamic>> getUnreadMessageCountForFriend(
      String userEmail, 
      String friendEmail
    ) async {
      try {
        final uri = Uri.parse('${Baseurl.baseUrl}/messages/unreadcount').replace(
          queryParameters: {
            'userId': userEmail,  // userId 就是 userEmail
            'friendId': friendEmail,  // friendId 就是 friendEmail
            '_t': DateTime.now().millisecondsSinceEpoch.toString(), // 添加防缓存参数
          },
        );

        final response = await http.get(
          uri,
          headers: await getHeaders(),
        );

        if (response.statusCode == 200) {
          return json.decode(response.body);
        } else {
          print('获取未读消息计数失败: ${response.statusCode} ${response.body}');
          return {'unreadCount': 0};
        }
      } catch (e) {
        print('获取未读消息计数异常: $e');
        return {'unreadCount': 0};
      }
    }
// 标记消息为已读的方法
Future<bool> markMessagesAsRead(String userEmail, String friendEmail) async {
  // 添加参数验证（防御性编程）
  if (userEmail.isEmpty || friendEmail.isEmpty) {
    print('⚠️ 无效参数: userEmail=$userEmail, friendEmail=$friendEmail');
    return false;
  }

  try {
    final uri = Uri.parse('${Baseurl.baseUrl}/messages/markAsRead').replace(
      queryParameters: {
        'userId': userEmail,  // userId 就是 userEmail
        'friendId': friendEmail,  // friendId 就是 friendEmail
        '_t': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    print('📨 标记消息为已读: $uri');

    final response = await http.post(
      uri,
      headers: await getHeaders(),
    );

    if (response.statusCode == 200) {
      print('✅ 消息已成功标记为已读');
      return true;
    }
    
    // 添加详细的错误日志
    print('❌ 标记失败 (${response.statusCode}): ${response.body}');
    return false;
  } catch (e) {
    print('❌ 标记异常: ${e.toString()}');
    return false;
  }
}

  Future<Map<String, dynamic>?> getUserAvatar(String email) async {
    try {
      final response = await http.get(
        Uri.parse('${Baseurl.baseUrl}/api/friends/avatar?email=$email'),
        headers: await getHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return null;
      }
    } catch (e) {
      print('Error fetching user avatar: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> uploadFile(File file) async {
    return await _uploadFileWithRetry(file, maxRetries: 3);
  }

  Future<Map<String, dynamic>> _uploadFileWithRetry(File file, {int maxRetries = 3}) async {
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        // 检查文件是否存在
        if (!await file.exists()) {
          return {
            'success': false,
            'error': '文件不存在',
          };
        }

        // 检查文件大小（500MB限制）
        final fileSize = await file.length();
        final maxSize = 500 * 1024 * 1024; // 500MB
        if (fileSize > maxSize) {
          return {
            'success': false,
            'error': '文件大小超过限制（最大500MB）',
          };
        }

        // 检查网络连接
        if (!await NetworkUtils.isNetworkAvailable()) {
          retryCount++;
          if (retryCount >= maxRetries) {
            return {
              'success': false,
              'error': '网络连接不可用，请检查网络设置',
            };
          }
          await Future.delayed(Duration(seconds: 2 * retryCount));
          continue;
        }

        // 检查服务器是否可达
        if (!await NetworkUtils.isServerReachable('${Baseurl.baseUrl}')) {
          retryCount++;
          if (retryCount >= maxRetries) {
            return {
              'success': false,
              'error': '服务器暂时不可达，请稍后重试',
            };
          }
          await Future.delayed(Duration(seconds: 3 * retryCount));
          continue;
        }

        final uri = Uri.parse('${Baseurl.baseUrl}/messages/upload');
        final request = http.MultipartRequest('POST', uri);

        // 添加认证头
        final headers = await getHeaders();
        request.headers.addAll(headers);

        // 添加文件
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        // 发送请求，设置较长的超时时间用于大文件上传
        final streamedResponse = await request.send().timeout(
          Duration(minutes: 30), // 30分钟超时，适合大文件上传
          onTimeout: () {
            throw TimeoutException('上传超时，请检查网络连接或尝试上传较小的文件');
          },
        );

        if (streamedResponse.statusCode == 200) {
          final responseData = await streamedResponse.stream.bytesToString();
          final jsonResponse = jsonDecode(responseData);
          return {
            'success': true,
            'url': jsonResponse['url'] as String?,
            'filename': jsonResponse['filename'] as String?,
            'size': jsonResponse['size'] as int?,                                                                                                           
            
          };
        } else {
          final responseData = await streamedResponse.stream.bytesToString();
          Map<String, dynamic> errorResponse;
          try {
            errorResponse = jsonDecode(responseData);
          } catch (e) {
            errorResponse = {'error': '服务器响应格式错误'};
          }
          return {
            'success': false,
            'error': errorResponse['error'] ?? '文件上传失败',
          };
        }
  } on TimeoutException catch (e) {
    print('文件上传超时: $e');
    return {
      'success': false,
      'error': e.message ?? '上传超时，请检查网络连接',
    };
  } on SocketException catch (e) {
    print('网络连接异常 (尝试 ${retryCount + 1}/$maxRetries): $e');
    retryCount++;
    if (retryCount >= maxRetries) {
      return {
        'success': false,
        'error': NetworkUtils.getNetworkErrorMessage(e),
      };
    }
    // 等待一段时间后重试
    await Future.delayed(Duration(seconds: 2 * retryCount));
    continue;
  } on HttpException catch (e) {
    print('HTTP请求异常 (尝试 ${retryCount + 1}/$maxRetries): $e');
    retryCount++;
    if (retryCount >= maxRetries) {
      return {
        'success': false,
        'error': NetworkUtils.getNetworkErrorMessage(e),
      };
    }
    // 等待一段时间后重试
    await Future.delayed(Duration(seconds: 2 * retryCount));
    continue;
  } on TimeoutException catch (e) {
    print('文件上传超时 (尝试 ${retryCount + 1}/$maxRetries): $e');
    retryCount++;
    if (retryCount >= maxRetries) {
      return {
        'success': false,
        'error': NetworkUtils.getNetworkErrorMessage(e),
      };
    }
    // 等待一段时间后重试
    await Future.delayed(Duration(seconds: 5 * retryCount));
    continue;
  } catch (e) {
    print('文件上传异常 (尝试 ${retryCount + 1}/$maxRetries): $e');
    retryCount++;
    if (retryCount >= maxRetries) {
      return {
        'success': false,
        'error': NetworkUtils.getNetworkErrorMessage(e),
      };
    }
    // 等待一段时间后重试
    await Future.delayed(Duration(seconds: 3 * retryCount));
    continue;
  }
  }
  
  // 如果所有重试都失败了
  return {
    'success': false,
    'error': '上传失败，请稍后重试',
  };
}

  // 获取用户信息方法（公共接口）
  Future<Map<String, dynamic>?> getUserInfopublic(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${Baseurl.baseUrl}/auth/public-userinfo?email=$email'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'username': data['username'],
          'avatar': data['avatar'],
        };
      } else {
        print('Failed to get user info: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error getting user info: $e');
      return null;
    }
  }


// 获取用户信息的方法
Future<Map<String, dynamic>?> getUserInfo(String email) async {
  try {
    final response = await http.post(
      Uri.parse('${Baseurl.baseUrl}/auth/userinfo?email=$email'),
      headers: await getHeaders(),
    );
    final storedData = await getLoginData();
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && storedData?['token'] != data['token'] ||
        storedData?['avatar'] != data['avatar'] || storedData?['username'] != data['username']) {
      await _saveLoginData(data['token'], data['email'], data['username'], data['avatar'] ?? '');
      return data;
    }
    return null;
  } catch (e) {
    print('Error getting user info: $e');
    return null;
  }
}

  // 撤回消息
  Future<bool> revokeMessage(int messageId, String userEmail) async {
    final url = Uri.parse('${Baseurl.baseUrl}/messages/$messageId/revoke');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: jsonEncode({'userId': userEmail}),
      );
      print('撤回响应: ${response.statusCode} ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      print('撤回消息异常: $e');
      return false;
    }
  }

  // 删除消息
  Future<bool> deleteMessage(int messageId, String userEmail) async {
    final url = Uri.parse('${Baseurl.baseUrl}/messages/$messageId/delete');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: jsonEncode({'userId': userEmail}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('删除消息异常: $e');
      return false;
    }
  }
  
}