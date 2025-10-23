import 'package:flutter/material.dart';

class UploadProgressDialog extends StatefulWidget {
  final String title;
  final String fileName;
  final String? fileSize;
  final Future<Map<String, dynamic>> uploadFuture;
  final Function(Map<String, dynamic>) onSuccess;
  final Function(String) onError;

  const UploadProgressDialog({
    Key? key,
    required this.title,
    required this.fileName,
    this.fileSize,
    required this.uploadFuture,
    required this.onSuccess,
    required this.onError,
  }) : super(key: key);

  @override
  State<UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<UploadProgressDialog>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isUploading = true;
  String _status = '准备发送...';
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat();
    _startUpload();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startUpload() async {
    try {
      setState(() {
        _status = '正在发送...';
        _retryCount = 0;
      });

      final result = await widget.uploadFuture;

      if (mounted) {
        if (result['success'] == true) {
          setState(() {
            _status = '发送成功！';
            _isUploading = false;
          });
          
          // 延迟关闭对话框，让用户看到成功状态
          await Future.delayed(Duration(milliseconds: 500));
          
          if (mounted) {
            Navigator.of(context).pop();
            widget.onSuccess(result);
          }
        } else {
          setState(() {
            _status = '发送失败';
            _isUploading = false;
          });
          
          await Future.delayed(Duration(milliseconds: 1000));
          
          if (mounted) {
            Navigator.of(context).pop();
            widget.onError(result['error'] ?? '发送失败');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '发送异常';
          _isUploading = false;
        });
        
        await Future.delayed(Duration(milliseconds: 1000));
        
        if (mounted) {
          Navigator.of(context).pop();
          widget.onError('发送异常: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(
            _isUploading ? Icons.cloud_upload : 
            (_status.contains('成功') ? Icons.check_circle : Icons.error),
            color: _isUploading ? Colors.blue : 
                   (_status.contains('成功') ? Colors.green : Colors.red),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isUploading) ...[
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _animation.value * 2 * 3.14159,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                );
              },
            ),
            SizedBox(height: 16),
          ] else ...[
            Icon(
              _status.contains('成功') ? Icons.check_circle : Icons.error,
              size: 48,
              color: _status.contains('成功') ? Colors.green : Colors.red,
            ),
            SizedBox(height: 16),
          ],
          Text(
            widget.fileName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.fileSize != null) ...[
            SizedBox(height: 4),
            Text(
              '大小: ${widget.fileSize}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
          SizedBox(height: 16),
          Text(
            _status,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _isUploading ? Colors.blue : 
                     (_status.contains('成功') ? Colors.green : Colors.red),
            ),
          ),
          if (_isUploading) ...[
            SizedBox(height: 8),
            Text(
              '请耐心等待，大文件发送可能需要较长时间',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            if (_retryCount > 0) ...[
              SizedBox(height: 4),
              Text(
                '正在重试 (${_retryCount}/3)...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ],
      ),
      actions: _isUploading ? null : [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('确定'),
        ),
      ],
    );
  }
} 