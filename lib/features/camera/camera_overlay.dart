// ============================================================
// camera_overlay.dart — Widget overlay kamera kecil di sudut layar
// ============================================================

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class CameraOverlay extends StatelessWidget {
  const CameraOverlay({
    super.key,
    required this.controller,
    required this.isFaceDetected,
  });

  final CameraController controller;
  final bool isFaceDetected;

  @override
  Widget build(BuildContext context) {
    final borderColor = isFaceDetected
        ? const Color(0xFF01A507)
        : Colors.redAccent;

    return Container(
      width: AppConstants.cameraWidth,
      height: AppConstants.cameraHeight,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 6,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Preview kamera
            CameraPreview(controller),

            // Indikator status (dot kecil pojok kanan atas)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: borderColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: borderColor.withOpacity(0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),

            // Label "LIVE" kecil di pojok kiri bawah
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
