import 'package:flutter/material.dart';

class AudioWave extends StatefulWidget {
  final bool isPlaying;
  final double size;

  const AudioWave({
    Key? key,
    required this.isPlaying,
    this.size = 24.0,
  }) : super(key: key);

  @override
  _AudioWaveState createState() => _AudioWaveState();
}


class _AudioWaveState extends State<AudioWave> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

@override
void didUpdateWidget(covariant AudioWave oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (widget.isPlaying != oldWidget.isPlaying) {
    if (widget.isPlaying) {
      _controller.repeat(); // 开始循环动画
    } else {
      _controller.stop(); // 停止动画
    }
  }
}
late Animation<double> _curvedAnimation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _curvedAnimation = CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildWaveBar(0.2, 0, 3),
            const SizedBox(width: 2),
            _buildWaveBar(0.4, 1, 3),
            const SizedBox(width: 2),
            _buildWaveBar(0.6, 2, 3),
          ],
        );
      },
    );
  }

  Widget _buildWaveBar(double heightFactor, int index, int totalBars) {
    final double animationOffset = (index / totalBars); // 每个 bar 的动画偏移
    final double animatedValue = (_curvedAnimation.value - animationOffset + 1.0) % 1.0;

    return Container(
      width: 3,
      height: widget.size * (heightFactor + (animatedValue * 0.3)),
     decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.blue.withOpacity(0.5), const Color.fromARGB(255, 217, 230, 240)],
        ),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
} 