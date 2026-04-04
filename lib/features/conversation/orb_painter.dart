import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'voice_orb_widget.dart';

class OrbPainter extends CustomPainter {
  final OrbState state;
  final double audioLevel;
  final double breathPhase;
  final double rotationPhase;
  final double glowPhase;

  OrbPainter({
    required this.state,
    required this.audioLevel,
    required this.breathPhase,
    required this.rotationPhase,
    required this.glowPhase,
  });

  static const _pointCount = 64;

  static const _fillColor = Color(0xFFEDE8E3);
  static const _glowColor = Color(0xFF4E3217);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Base radius with breathing
    final breathScale = 1.0 + breathPhase * 0.04;
    final baseRadius = maxRadius * 0.75 * breathScale;

    // Draw glow layers
    _drawGlow(canvas, center, baseRadius);

    // Draw blob body
    _drawBlob(canvas, center, baseRadius);

    // Draw inner highlight
    _drawHighlight(canvas, center, baseRadius);
  }

  void _drawGlow(Canvas canvas, Offset center, double baseRadius) {
    final glowIntensity = switch (state) {
      OrbState.idle => 0.04 + glowPhase * 0.03,
      OrbState.userSpeaking => 0.06 + audioLevel * 0.10,
      OrbState.aiSpeaking => 0.08 + audioLevel * 0.14,
    };

    final glowRadius = switch (state) {
      OrbState.idle => baseRadius * (1.1 + glowPhase * 0.08),
      OrbState.userSpeaking => baseRadius * (1.15 + audioLevel * 0.15),
      OrbState.aiSpeaking => baseRadius * (1.2 + audioLevel * 0.2),
    };

    // Outer glow
    final glowPaint = Paint()
      ..color = _glowColor.withValues(alpha: glowIntensity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 0.4);
    canvas.drawCircle(center, baseRadius, glowPaint);

    // Mid glow
    final midGlowPaint = Paint()
      ..color = _glowColor.withValues(alpha: glowIntensity * 0.6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 0.2);
    canvas.drawCircle(center, baseRadius * 0.95, midGlowPaint);
  }

  void _drawBlob(Canvas canvas, Offset center, double baseRadius) {
    final path = _buildBlobPath(center, baseRadius);

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = _fillColor;

    canvas.drawPath(path, paint);

    // Outer soft glow border
    final idlePulse = glowPhase * 0.08;
    final outerWidth = 4.0 + glowPhase * 4.0 + audioLevel * 8.0;
    final outerBlur = 4.0 + glowPhase * 4.0 + audioLevel * 6.0;
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerWidth
      ..color = _glowColor.withValues(alpha: 0.03 + idlePulse * 0.4 + audioLevel * 0.06)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, outerBlur);
    canvas.drawPath(path, outerPaint);

    // Mid shadow border
    final midWidth = 2.0 + glowPhase * 3.0 + audioLevel * 6.0;
    final midBlur = 2.0 + glowPhase * 3.0 + audioLevel * 5.0;
    final midPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = midWidth
      ..color = _glowColor.withValues(alpha: 0.05 + idlePulse + audioLevel * 0.10)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, midBlur);
    canvas.drawPath(path, midPaint);

    // Crisp inner border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 + glowPhase * 0.5 + audioLevel * 1.5
      ..color = _glowColor.withValues(alpha: 0.08 + idlePulse + audioLevel * 0.15);
    canvas.drawPath(path, borderPaint);
  }

  Path _buildBlobPath(Offset center, double baseRadius) {
    final points = <Offset>[];
    final rotPhase = rotationPhase * 2 * math.pi;

    // Perturbation amount scales with audio level
    final maxPerturbation = switch (state) {
      OrbState.idle => baseRadius * 0.015,
      OrbState.userSpeaking => baseRadius * (0.03 + audioLevel * 0.12),
      OrbState.aiSpeaking => baseRadius * (0.03 + audioLevel * 0.15),
    };

    for (var i = 0; i < _pointCount; i++) {
      final angle = 2 * math.pi * i / _pointCount;

      // Overlapping sine waves at different frequencies for organic shape
      final perturbation = maxPerturbation *
          (0.5 * math.sin(angle * 3 + rotPhase) +
              0.3 * math.sin(angle * 5 + rotPhase * 1.3) +
              0.2 * math.sin(angle * 7 + rotPhase * 0.7));

      final r = baseRadius + perturbation;
      points.add(Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      ));
    }

    // Build smooth path using cubic bezier curves
    return _smoothPath(points);
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path();
    final n = points.length;

    path.moveTo(points[0].dx, points[0].dy);

    for (var i = 0; i < n; i++) {
      final p0 = points[(i - 1 + n) % n];
      final p1 = points[i];
      final p2 = points[(i + 1) % n];
      final p3 = points[(i + 2) % n];

      // Catmull-Rom to cubic bezier control points
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );

      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }

    path.close();
    return path;
  }

  void _drawHighlight(Canvas canvas, Offset center, double baseRadius) {
    // Subtle top-left volumetric highlight
    final highlightCenter = Offset(
      center.dx - baseRadius * 0.15,
      center.dy - baseRadius * 0.15,
    );

    final highlightPaint = Paint()
      ..shader = ui.Gradient.radial(
        highlightCenter,
        baseRadius * 0.6,
        [
          const Color(0x14FFFFFF),
          const Color(0x00FFFFFF),
        ],
      );

    canvas.drawCircle(center, baseRadius, highlightPaint);
  }

  @override
  bool shouldRepaint(OrbPainter oldDelegate) => true;
}
