import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'orb_painter.dart';

enum OrbState { idle, userSpeaking, aiSpeaking }

class VoiceOrbWidget extends StatefulWidget {
  final OrbState state;
  final ValueListenable<double> micLevel;
  final ValueListenable<double> aiLevel;

  const VoiceOrbWidget({
    super.key,
    required this.state,
    required this.micLevel,
    required this.aiLevel,
  });

  @override
  State<VoiceOrbWidget> createState() => _VoiceOrbWidgetState();
}

class _VoiceOrbWidgetState extends State<VoiceOrbWidget>
    with TickerProviderStateMixin {
  late final AnimationController _breathController;
  late final AnimationController _glowController;
  late final AnimationController _rotationController;
  late final AnimationController _scaleController;

  // Smoothed scale target for lerp-based animation
  double _targetScale = 1.0;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();

    _breathController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat(reverse: true);

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 8000),
      vsync: this,
    )..repeat();

    // Drives smooth scale interpolation every frame
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateScale);

    widget.micLevel.addListener(_onAudioLevelChanged);
    widget.aiLevel.addListener(_onAudioLevelChanged);
  }

  void _onAudioLevelChanged() {
    final level = switch (widget.state) {
      OrbState.userSpeaking => widget.micLevel.value,
      OrbState.aiSpeaking => widget.aiLevel.value,
      OrbState.idle => 0.0,
    };
    _targetScale = 1.0 + level * 0.5;

    if (!_scaleController.isAnimating) {
      _scaleController.repeat();
    }
  }

  void _updateScale() {
    // Smooth lerp towards target — 0.15 factor gives responsive but smooth motion
    final newScale = _currentScale + (_targetScale - _currentScale) * 0.15;
    if ((newScale - _currentScale).abs() > 0.0005) {
      _currentScale = newScale;
    } else {
      _currentScale = _targetScale;
      _scaleController.stop();
    }
  }

  @override
  void didUpdateWidget(VoiceOrbWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      if (widget.state == OrbState.idle) {
        _targetScale = 1.0;
        if (!_scaleController.isAnimating) {
          _scaleController.repeat();
        }
      }
    }
  }

  @override
  void dispose() {
    widget.micLevel.removeListener(_onAudioLevelChanged);
    widget.aiLevel.removeListener(_onAudioLevelChanged);
    _breathController.dispose();
    _glowController.dispose();
    _rotationController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _breathController,
        _glowController,
        _rotationController,
        _scaleController,
        widget.micLevel,
        widget.aiLevel,
      ]),
      builder: (_, _) {
        final activeLevel = switch (widget.state) {
          OrbState.userSpeaking => widget.micLevel.value,
          OrbState.aiSpeaking => widget.aiLevel.value,
          OrbState.idle => 0.0,
        };

        const baseSize = 260.0;

        return Transform.scale(
          scale: _currentScale,
          child: SizedBox(
            width: baseSize,
            height: baseSize,
            child: CustomPaint(
              size: const Size(baseSize, baseSize),
              painter: OrbPainter(
                state: widget.state,
                audioLevel: activeLevel,
                breathPhase: _breathController.value,
                rotationPhase: _rotationController.value,
                glowPhase: _glowController.value,
              ),
            ),
          ),
        );
      },
    );
  }
}
