import 'package:flutter/material.dart';

import 'orb_painter.dart';

enum OrbState { idle, userSpeaking, aiSpeaking }

class VoiceOrbWidget extends StatefulWidget {
  final OrbState state;
  final ValueNotifier<double> micLevel;
  final ValueNotifier<double> aiLevel;

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
  late final AnimationController _stateTransitionController;

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

    _stateTransitionController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(VoiceOrbWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _stateTransitionController.forward(from: 0);

      // Adjust breath speed based on state
      _breathController.duration = switch (widget.state) {
        OrbState.idle => const Duration(milliseconds: 3000),
        OrbState.userSpeaking => const Duration(milliseconds: 1500),
        OrbState.aiSpeaking => const Duration(milliseconds: 2000),
      };
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    _glowController.dispose();
    _rotationController.dispose();
    _stateTransitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.micLevel,
      builder: (_, micLevel, _) {
        return ValueListenableBuilder<double>(
          valueListenable: widget.aiLevel,
          builder: (_, aiLevel, _) {
            return AnimatedBuilder(
              animation: Listenable.merge([
                _breathController,
                _glowController,
                _rotationController,
                _stateTransitionController,
              ]),
              builder: (_, _) {
                final activeLevel = switch (widget.state) {
                  OrbState.userSpeaking => micLevel,
                  OrbState.aiSpeaking => aiLevel,
                  OrbState.idle => 0.0,
                };

                // Animated size based on state
                final baseSize = switch (widget.state) {
                  OrbState.idle => 200.0,
                  OrbState.userSpeaking => 200.0,
                  OrbState.aiSpeaking => 220.0,
                };

                return SizedBox(
                  width: baseSize,
                  height: baseSize,
                  child: CustomPaint(
                    size: Size(baseSize, baseSize),
                    painter: OrbPainter(
                      state: widget.state,
                      audioLevel: activeLevel,
                      breathPhase: _breathController.value,
                      rotationPhase: _rotationController.value,
                      glowPhase: _glowController.value,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
