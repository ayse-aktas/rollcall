import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../../core/services/person_detector_service.dart';
import '../../../core/utils/theme/colors/app_colors.dart';
import 'dart:io';

class VerificationCameraPage extends StatefulWidget {
  const VerificationCameraPage({super.key});

  @override
  State<VerificationCameraPage> createState() => _VerificationCameraPageState();
}

class _VerificationCameraPageState extends State<VerificationCameraPage>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _isCapturing = false;
  String? _errorMessage;

  late AnimationController _pulseController;
  late AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _initCamera();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMessage = 'Kamera bulunamadı');
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() => _isCameraReady = true);
    } catch (e) {
      setState(() => _errorMessage = 'Kamera başlatılamadı: $e');
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (_isCapturing || _isProcessing || _cameraController == null) return;

    setState(() {
      _isCapturing = true;
      _isProcessing = true;
    });

    File? fileToDelete;
    try {
      final XFile imageFile = await _cameraController!.takePicture();
      fileToDelete = File(imageFile.path);
      
      if (!await fileToDelete.exists()) throw Exception('Fotoğraf dosyası oluşturulamadı');

      final inputImage = InputImage.fromFilePath(imageFile.path);
      final result = await PersonDetectorService.instance.detectPersons(inputImage);

      // Algılama bittikten sonra geçici dosyayı siliyoruz
      if (await fileToDelete.exists()) {
        await fileToDelete.delete();
        debugPrint('🗑️ Geçici fotoğraf dosyası başarıyla silindi.');
      }

      if (!mounted) return;

      if (result.hasError) {
        _showErrorSnackBar('Algılama hatası: ${result.error}');
        setState(() {
          _isCapturing = false;
          _isProcessing = false;
        });
        return;
      }

      Navigator.pop(context, result);
    } catch (e) {
      // Hata oluşsa bile geçici dosyayı temizlemeye çalışıyoruz
      if (fileToDelete != null && await fileToDelete.exists()) {
        try {
          await fileToDelete.delete();
          debugPrint('🗑️ Hata sonrası geçici fotoğraf dosyası silindi.');
        } catch (deleteError) {
          debugPrint('⚠️ Hata sonrası dosya silinirken hata oluştu: $deleteError');
        }
      }

      if (mounted) {
        _showErrorSnackBar('Hata: $e');
        setState(() {
          _isCapturing = false;
          _isProcessing = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _pulseController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isCameraReady && _cameraController != null)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            )
          else if (_errorMessage != null)
            _buildErrorState()
          else
            _buildLoadingState(),

          // Üst Kaplama
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withAlpha(178), Colors.transparent],
                ),
              ),
            ),
          ),

          // Alt Kaplama
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withAlpha(204), Colors.transparent],
                ),
              ),
            ),
          ),

          if (_isProcessing) _buildScanOverlay(),

          // Üst Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildCircleButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(230),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('AI Yoklama', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
            ),
          ),

          // Kontroller
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(38),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withAlpha(51)),
                      ),
                      child: Row(
                        children: [
                          Icon(_isProcessing ? Icons.psychology_rounded : Icons.info_outline, color: Colors.white70, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isProcessing ? 'AI kişi sayıyor...' : 'Kamerayı tüm sınıfa doğrultun',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildCaptureButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _isProcessing ? null : _captureAndAnalyze,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: _isProcessing ? 0.85 + (_pulseController.value * 0.1) : 1.0,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isProcessing ? AppColors.primary : Colors.white,
                ),
                child: _isProcessing
                    ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 28),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildScanOverlay() {
    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, child) {
        return Positioned(
          top: MediaQuery.of(context).size.height * _scanController.value,
          left: 0,
          right: 0,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: AppColors.primary.withAlpha(153), blurRadius: 10, spreadRadius: 2)],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCircleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withAlpha(128)),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildLoadingState() => const Center(child: CircularProgressIndicator());

  Widget _buildErrorState() => Center(child: Text(_errorMessage ?? 'Hata', style: const TextStyle(color: Colors.white)));
}
