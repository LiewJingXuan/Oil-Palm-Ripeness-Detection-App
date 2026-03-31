import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

class IsolateUtils {

  static Future<img.Image?> convertCameraImageInBackground(CameraImage cameraImage) async {
    //Extract data
    final int width = cameraImage.width;
    final int height = cameraImage.height;
    final int uvRowStride = cameraImage.planes[1].bytesPerRow;
    final int? uvPixelStride = cameraImage.planes[1].bytesPerPixel;
    
    //Copy the bytes so can pass them to the isolate
    final Uint8List yPlane = cameraImage.planes[0].bytes;
    final Uint8List uPlane = cameraImage.planes[1].bytes;
    final Uint8List vPlane = cameraImage.planes[2].bytes;

    //Pack data into a Map
    final Map<String, dynamic> isolateData = {
      'width': width,
      'height': height,
      'uvRowStride': uvRowStride,
      'uvPixelStride': uvPixelStride,
      'yPlane': yPlane,
      'uPlane': uPlane,
      'vPlane': vPlane,
    };
    return await compute(convertYUVtoRGB, isolateData);
  }

  //run in the background
  static img.Image convertYUVtoRGB(Map<String, dynamic> data) {
    final int width = data['width'];
    final int height = data['height'];
    final int uvRowStride = data['uvRowStride'];
    final int? uvPixelStride = data['uvPixelStride'] ?? 1;
    final Uint8List yPlane = data['yPlane'];
    final Uint8List uPlane = data['uPlane'];
    final Uint8List vPlane = data['vPlane'];

    //Create target image
    final img.Image image = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = (uvPixelStride! * (x / 2).floor()) + (uvRowStride * (y / 2).floor());
        final int index = y * width + x;

        final yp = yPlane[index];
        final up = uPlane[uvIndex];
        final vp = vPlane[uvIndex];

        //Standard YUV conversion formula
        int r = (yp + (vp - 128) * 1.402).toInt();
        int g = (yp - (up - 128) * 0.34414 - (vp - 128) * 0.71414).toInt();
        int b = (yp + (up - 128) * 1.772).toInt();

        //Clamp values 0-255
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return img.copyRotate(image, angle: 90);
  }
}