// ============================================================
// camera_service.dart — Inisialisasi kamera & face detection gimmick
// ============================================================

import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraService {
  CameraService._();

  static CameraController? _controller;
  static FaceDetector? _faceDetector;
  static bool _isProcessing = false;
  static Timer? _detectionTimer;

  // ── Inisialisasi kamera depan ────────────────────────────────
  static Future<CameraController?> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return null;

      // Pilih kamera depan
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.low, // Low untuk hemat resource
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await controller.initialize();
      _controller = controller;

      // Inisialisasi face detector
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableClassification: false,
          enableLandmarks: false,
          enableTracking: false,
        ),
      );

      debugPrint('[CameraService] Kamera berhasil diinisialisasi.');
      return controller;
    } catch (e) {
      debugPrint('[CameraService] Gagal inisialisasi kamera: $e');
      return null;
    }
  }

  // ── Mulai deteksi wajah periodik ────────────────────────────
  static void startFaceDetection(Function(bool) onResult) {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_isProcessing || _controller == null || _faceDetector == null) return;
      if (!_controller!.value.isInitialized) return;

      _isProcessing = true;
      try {
        final image = await _controller!.takePicture();
        final inputImage = InputImage.fromFilePath(image.path);
        final faces = await _faceDetector!.processImage(inputImage);
        onResult(faces.isNotEmpty);
      } catch (e) {
        debugPrint('[CameraService] Deteksi wajah error: $e');
        onResult(false);
      } finally {
        _isProcessing = false;
      }
    });
  }

  // ── Hentikan & bersihkan resource ───────────────────────────
  static Future<void> dispose() async {
    _detectionTimer?.cancel();
    _detectionTimer = null;
    try {
      await _faceDetector?.close();
      _faceDetector = null;
      await _controller?.dispose();
      _controller = null;
    } catch (e) {
      debugPrint('[CameraService] Dispose error: $e');
    }
  }
}
