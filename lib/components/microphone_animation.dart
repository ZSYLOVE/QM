import 'package:flutter/material.dart';

class MicrophoneAnimation extends StatefulWidget {
  final int recordingSeconds;
  final bool showCancel;
  final double? volume; // 音量值 0.0-1.0

  const MicrophoneAnimation({
    Key? key, 
    required this.recordingSeconds,
    this.showCancel = false,
    this.volume,
  }) : super(key: key);

  @override
  State<MicrophoneAnimation> createState() => _MicrophoneAnimationState();
}

class _MicrophoneAnimationState extends State<MicrophoneAnimation>
    with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late AnimationController _waveController;
  late AnimationController _cancelController;
  late Animation<double> _breathingAnimation;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    
    // 呼吸动画控制器
    _breathingController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    // 波形动画控制器
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    // 取消动画控制器
    _cancelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 呼吸动画
    _breathingAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _breathingController,
      curve: Curves.easeInOut,
    ));

    // 波形动画
    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveController,
      curve: Curves.easeInOut,
    ));

    // 取消动画

    // 开始动画
    _breathingController.repeat(reverse: true);
    _waveController.repeat();
  }

  @override
  void didUpdateWidget(MicrophoneAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 当显示取消状态改变时，播放取消动画
    if (widget.showCancel != oldWidget.showCancel) {
      if (widget.showCancel) {
        _cancelController.forward();
      } else {
        _cancelController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _waveController.dispose();
    _cancelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _breathingController,
        _waveController,
        _cancelController,
      ]),
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 麦克风图标和波形
              Stack(
                alignment: Alignment.center,
                children: [
                  // 背景圆圈
                  Transform.scale(
                    scale: _breathingAnimation.value,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.showCancel 
                            ? Colors.red.withOpacity(0.3)
                            : Colors.blue.withOpacity(0.3),
                      ),
                    ),
                  ),

                  // 麦克风图标
                  Transform.scale(
                    scale: _breathingAnimation.value,
                    child: Icon(
                      widget.showCancel ? Icons.close:null,
                      size: 48,
                      color: widget.showCancel ? Colors.red : Colors.white,
                    ),
                  ),

                  // 音量波形
                  if (!widget.showCancel && widget.volume != null)
                    _buildVolumeWaves(),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // 文字提示
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  widget.showCancel 
                      ? '松开手指，取消发送'
                      : '录音时长: ${widget.recordingSeconds} 秒\n上滑取消发送',
                  key: ValueKey(widget.showCancel),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVolumeWaves() {
    final volume = widget.volume ?? 0.5;
    final waveCount = 8;
    final List<Widget> waves = [];

    for (int i = 0; i < waveCount; i++) {
      final delay = i * 0.1;
      final waveValue = (_waveAnimation.value + delay) % 1.0;
      final height = (0.3 + waveValue * 0.7) * volume * 40;
      
      waves.add(
        AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 3,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
      
      if (i < waveCount - 1) {
        waves.add(const SizedBox(width: 2));
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: waves,
    );
  }
}

