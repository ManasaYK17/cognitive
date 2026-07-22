import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cognitive_assist_app/widgets/face_scan_camera.dart';

void main() {
  test('resolveInputImageFormatForTesting maps YUV420 frames to the ML Kit input format', () {
    final format = FaceScanCamera.resolveInputImageFormatForTesting(group: ImageFormatGroup.yuv420);

    expect(format, InputImageFormat.nv21);
  });
}
