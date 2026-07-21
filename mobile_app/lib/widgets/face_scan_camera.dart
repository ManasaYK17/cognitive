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

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _scanController.repeat(reverse: true);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (kIsWeb) {
      if (!mounted) return;
      Navigator.of(context).pop(const FaceScanCaptureResult(cancelled: true, message: 'Camera is not available on web.'));
      return;
    }

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      Navigator.of(context).pop(const FaceScanCaptureResult(cancelled: true, message: 'Camera permission is required.'));
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (!mounted) return;
      Navigator.of(context).pop(const FaceScanCaptureResult(cancelled: true, message: 'No camera is available.'));
      return;
    }

    final camera = cameras.firstWhere((item) => item.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    _controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    await _controller!.startImageStream(_processCameraImage);

    _timeoutTimer = Timer(Duration(seconds: widget.timeoutSeconds), () {
      if (_didCapture || !mounted) return;
      _closeWithResult(const FaceScanCaptureResult(cancelled: true, message: "Couldn't find a face — try again"));
    });

    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isCapturing || _didCapture || !_isScanning) return;

    _isCapturing = true;
    try {
      final inputImage = _createInputImage(image);
      if (inputImage == null) {
        return;
      }
      final faces = await _faceDetector.processImage(inputImage);
      final bestFace = _selectBestFace(faces, image.width, image.height);
      if (bestFace != null) {
        await _captureAndClose();
      }
    } catch (_) {
      // Ignore transient detection failures and keep scanning.
    } finally {
      if (!_didCapture) {
        _isCapturing = false;
      }
    }
  }

  InputImage? _createInputImage(CameraImage image) {
    try {
      final format = _inputImageFormatFromCameraImage(image);
      if (format == null) return null;

      final bytes = Uint8List.fromList(image.planes.expand((plane) => plane.bytes).toList());
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      );
      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (_) {
      return null;
    }
  }

  InputImageFormat? _inputImageFormatFromCameraImage(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
      case ImageFormatGroup.nv21:
        return InputImageFormat.nv21;
      case ImageFormatGroup.bgra8888:
        return InputImageFormat.bgra8888;
      default:
        return null;
    }
  }

  Face? _selectBestFace(List<Face> faces, int width, int height) {
    if (faces.isEmpty) return null;

    final safeFaces = faces.where((face) {
      final box = face.boundingBox;
      final boxArea = box.width * box.height;
      final frameArea = width * height.toDouble();
      final isLargeEnough = boxArea / frameArea > 0.08;
      final isCentered = box.left > width * 0.08 && box.right < width * 0.92 && box.top > height * 0.08 && box.bottom < height * 0.92;
      return isLargeEnough && isCentered;
    }).toList();

    if (safeFaces.isEmpty) return null;
    safeFaces.sort((a, b) {
      final aArea = a.boundingBox.width * a.boundingBox.height;
      final bArea = b.boundingBox.width * b.boundingBox.height;
      return bArea.compareTo(aArea);
    });
    return safeFaces.first;
  }

  Future<void> _captureAndClose() async {
    if (_didCapture || _controller == null || !_controller!.value.isInitialized) return;
    _didCapture = true;
    _isScanning = false;
    _timeoutTimer?.cancel();

    try {
      final imageFile = await _controller!.takePicture();
      if (!mounted) return;
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _closeWithResult(FaceScanCaptureResult(image: imageFile));
    } catch (_) {
      if (!mounted) return;
      _closeWithResult(const FaceScanCaptureResult(cancelled: true, message: 'Unable to capture the image.'));
    }
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
