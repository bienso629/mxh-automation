import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class SlideToVerify extends StatefulWidget {
  final bool isVerified;
  final ValueChanged<bool> onVerifiedChanged;
  final VoidCallback? onReset;

  const SlideToVerify({
    super.key,
    required this.isVerified,
    required this.onVerifiedChanged,
    this.onReset,
  });

  @override
  State<SlideToVerify> createState() => _SlideToVerifyState();
}

class _SlideToVerifyState extends State<SlideToVerify> with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SlideToVerify oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isVerified && oldWidget.isVerified) {
      setState(() {
        _dragPosition = 0.0;
      });
    }
  }

  void _resetSlider() {
    setState(() {
      _dragPosition = 0.0;
    });
    widget.onVerifiedChanged(false);
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    const double barHeight = 48.0;
    const double knobSize = 40.0;
    const double knobPadding = 4.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxDrag = constraints.maxWidth - knobSize - (knobPadding * 2);
        final double progress = maxDrag > 0 ? (_dragPosition / maxDrag).clamp(0.0, 1.0) : 0.0;

        return Container(
          height: barHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF070B14),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: widget.isVerified
                  ? AppColors.primary
                  : (progress > 0 ? AppColors.primaryLight.withValues(alpha: 0.6) : const Color(0xFF1E293B)),
              width: 1.2,
            ),
            boxShadow: [
              if (widget.isVerified)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 1. Dải màu tiến trình kéo từ trái qua (Màu vàng sang trọng)
                FractionallySizedBox(
                  widthFactor: widget.isVerified ? 1.0 : (knobSize + (knobPadding * 2) + _dragPosition) / constraints.maxWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.isVerified
                            ? [
                                const Color(0xFFCA8A04),
                                const Color(0xFFEAB308),
                              ]
                            : [
                                const Color(0xFF713F12).withValues(alpha: 0.6),
                                AppColors.primary.withValues(alpha: 0.4),
                              ],
                      ),
                    ),
                  ),
                ),

                // 2. Chữ hướng dẫn kèm Shimmer ánh sáng chạy ngang
                Center(
                  child: widget.isVerified
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Color(0xFF070B14), size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Đã xác minh bảo mật',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF070B14),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        )
                      : AnimatedBuilder(
                          animation: _shimmerAnimation,
                          builder: (context, child) {
                            return ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: const [
                                    Color(0xFF64748B),
                                    Color(0xFFFDE047), // Ánh vàng lấp lánh
                                    Color(0xFF64748B),
                                  ],
                                  stops: [
                                    (_shimmerAnimation.value - 0.25).clamp(0.0, 1.0),
                                    _shimmerAnimation.value.clamp(0.0, 1.0),
                                    (_shimmerAnimation.value + 0.25).clamp(0.0, 1.0),
                                  ],
                                ).createShader(bounds);
                              },
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Trượt sang phải để xác minh',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.keyboard_double_arrow_right_rounded, size: 16),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // 3. Nút tròn trượt (Vàng rực rỡ)
                if (!widget.isVerified)
                  Positioned(
                    left: knobPadding + _dragPosition,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, maxDrag);
                        });
                      },
                      onHorizontalDragEnd: (details) {
                        if (_dragPosition >= maxDrag * 0.88) {
                          setState(() {
                            _dragPosition = maxDrag;
                          });
                          HapticFeedback.mediumImpact();
                          widget.onVerifiedChanged(true);
                        } else {
                          setState(() {
                            _dragPosition = 0.0;
                          });
                        }
                      },
                      child: Container(
                        width: knobSize,
                        height: knobSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFDE047), // Vàng sáng
                              Color(0xFFEAB308), // Vàng Amber
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF070B14), // Mũi tên đen nổi trên nền vàng
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                // 4. Nút bấm hoàn tác xác minh / Reset
                if (widget.isVerified)
                  Positioned(
                    right: 6,
                    child: IconButton(
                      tooltip: 'Xác minh lại',
                      icon: const Icon(Icons.refresh_rounded, color: Color(0xFF070B14), size: 18),
                      onPressed: _resetSlider,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
