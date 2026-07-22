import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

class FaceScanCaptureResult {
  const FaceScanCaptureResult({this.image, this.cancelled = false, this.message});

  final XFile? image;
  final bool cancelled;
  final String? message;
}

class FaceScanCamera extends StatefulWidget {
  const FaceScanCamera({super.key, this.timeoutSeconds = 18});

  final int timeoutSeconds;

  static InputImageFormat? resolveInputImageFormatForTesting({required ImageFormatGroup group}) {
    switch (group) {
      case ImageFormatGroup.yuv420:
        return InputImageFormat.nv21;
      case ImageFormatGroup.nv21:
        return InputImageFormat.nv21;
      case ImageFormatGroup.bgra8888:
        return InputImageFormat.bgra8888;
      default:
        return null;
    }
  }

  @override
  State<FaceScanCamera> createState() => _FaceScanCameraState();
}

class _FaceScanCameraState extends State<FaceScanCamera> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  bool _isInitializing = true;
  bool _isScanning = true;
  bool _isCapturing = false;
  bool _didCapture = false;
  late final AnimationController _scanController;
  Timer? _timeoutTimer;
  Timer? _captureTimer;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _scanController.repeat(reverse: true);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    debugPrint('[face_scan] initializing camera');
    if (kIsWeb) {
      debugPrint('[face_scan] camera unavailable on web');
      if (!mounted) return;
      Navigator.of(context).pop(const FaceScanCaptureResult(cancelled: true, message: 'Camera is not available on web.'));
      return;
    }

    final status = await Permission.camera.request();
    debugPrint('[face_scan] camera permission status: ${status.toString()}');
    if (!status.isGranted) {
      debugPrint('[face_scan] camera permission denied');
      if (!mounted) return;
      Navigator.of(context).pop(const FaceScanCaptureResult(cancelled: true, message: 'Camera permission is required.'));
      return;
    }

    final cameras = await availableCameras();
    debugPrint('[face_scan] available cameras: ${cameras.length}');
    if (cameras.isEmpty) {
      debugPrint('[face_scan] no camera available');
      if (!mounted) return;
      Navigator.of(context).pop(const FaceScanCaptureResult(cancelled: true, message: 'No camera is available.'));
      return;
    }

    final camera = cameras.firstWhere((item) => item.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    debugPrint('[face_scan] using camera: ${camera.name} (${camera.lensDirection.name})');
    _controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();

    _timeoutTimer = Timer(Duration(seconds: widget.timeoutSeconds), () {
      if (_didCapture || !mounted) return;
      debugPrint('[face_scan] timeout reached without capture');
      _closeWithResult(const FaceScanCaptureResult(cancelled: true, message: "Couldn't find a face — try again"));
    });

    _captureTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      unawaited(_attemptStillCaptureAndDetect());
    });
    unawaited(_attemptStillCaptureAndDetect());

    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _attemptStillCaptureAndDetect() async {
    if (_isCapturing || _didCapture || !_isScanning || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    _isCapturing = true;
    try {
      debugPrint('[face_scan] attempting still-image capture for detection');
      final imageFile = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);
      debugPrint('[face_scan] still-image detection completed with ${faces.length} face(s)');
      final bestFace = _selectBestFace(faces);
      if (bestFace != null) {
        debugPrint('[face_scan] face detected from still image; capturing and closing');
        _captureTimer?.cancel();
        _timeoutTimer?.cancel();
        _didCapture = true;
        _isScanning = false;
        if (!mounted) return;
        setState(() {});
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        _closeWithResult(FaceScanCaptureResult(image: imageFile));
        return;
      }
      debugPrint('[face_scan] no face found in still image; continuing scan');
    } catch (error, stackTrace) {
      debugPrint('[face_scan] still-image detection exception: $error');
      debugPrint(stackTrace.toString());
    } finally {
      if (!_didCapture) {
        _isCapturing = false;
      }
    }
  }

  Face? _selectBestFace(List<Face> faces) {
    if (faces.isEmpty) return null;

    // ML Kit returns bounds in the rotated image coordinate space. Avoid
    // comparing them with the raw camera frame dimensions, which can reject
    // valid faces on front cameras. The largest detected face is the subject.
    final sortedFaces = List<Face>.of(faces);
    sortedFaces.sort((a, b) {
      final aArea = a.boundingBox.width * a.boundingBox.height;
      final bArea = b.boundingBox.width * b.boundingBox.height;
      return bArea.compareTo(aArea);
    });
    return sortedFaces.first;
  }

  void _closeWithResult(FaceScanCaptureResult result) {
    if (!mounted) return;
    _timeoutTimer?.cancel();
    _scanController.stop();
    _controller?.dispose();
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _captureTimer?.cancel();
    _scanController.dispose();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_isInitializing)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_controller != null && _controller!.value.isInitialized)
              Positioned.fill(child: CameraPreview(_controller!))
            else
              const Center(child: Text('Unable to start camera', style: TextStyle(color: Colors.white))),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(_didCapture ? 160 : 0),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => _closeWithResult(const FaceScanCaptureResult(cancelled: true, message: 'Canceled')),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                          Text(
                            _didCapture ? 'Captured' : 'Scanning for face...',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.82,
                          height: MediaQuery.of(context).size.height * 0.62,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.9), width: 2),
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              AnimatedBuilder(
                                animation: _scanController,
                                builder: (context, child) {
                                  final top = 0.08 + (0.84 * _scanController.value);
                                  return Positioned(
                                    top: MediaQuery.of(context).size.height * top * 0.62 / 1.4,
                                    child: Container(
                                      width: MediaQuery.of(context).size.width * 0.72,
                                      height: 2,
                                      color: const Color.fromRGBO(255, 255, 255, 0.95),
                                    ),
                                  );
                                },
                              ),
                              if (_didCapture)
                                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 72)
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text('Face guide', style: TextStyle(color: Colors.white)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_didCapture)
                      const SizedBox(height: 18)
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Text(
                          _isScanning ? 'Keep your face centered in the guide.' : 'Capturing...',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
