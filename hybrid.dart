import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../utils/cv_logic.dart';


class YoloMobileNetService {
  Interpreter? _yoloInterpreter;
  Interpreter? _mobileNetInterpreter;
  final List<String> _mobileNetLabels = ['Overripe', 'Ripe', 'Unripe'];

  Future<void> loadModels() async {
    try {
      _yoloInterpreter = await Interpreter.fromAsset('assets/best_float32.tflite');
      _mobileNetInterpreter = await Interpreter.fromAsset('assets/mobilenet.tflite');
      print("Models Loaded: YOLO & MobileNet");
    } catch (e) {
      print("Error loading models: $e");
    }
  }

  Future<List<Map<String, dynamic>>> runPipeline(img.Image originalImage) async {
    if (_yoloInterpreter == null) return [];

    //FIX ROTATION
    img.Image fixedImage = img.bakeOrientation(originalImage);

    //LETTERBOXING (Crucial for correct detection)
    var letterboxResult = _letterboxImage(fixedImage, 640);
    img.Image yoloInput = letterboxResult['image'];
    double paddingX = letterboxResult['paddingX'];
    double paddingY = letterboxResult['paddingY'];
    
    //run YOLO
    var yoloBytes = _imageToFloat32List(yoloInput, 640);
    var yoloOutput = List.filled(1 * 5 * 8400, 0.0).reshape([1, 5, 8400]);
    _yoloInterpreter!.run(yoloBytes, yoloOutput);

    //PARSE *ALL* BOXES (Not just the best one)
    List<List<double>> detectedBoxes = _parseAllBoxes(yoloOutput[0], paddingX, paddingY);
    
    //REMOVE DUPLICATES (NMS)
    List<List<double>> finalBoxes = _nonMaxSuppression(detectedBoxes, 0.45);

    print("🔎 Found ${finalBoxes.length} potential fruits. Running classification...");

    //CLASSIFY EACH BOX INDIVIDUALLY
    List<Map<String, dynamic>> finalResults = [];

    for (var box in finalBoxes) {
      // Check for valid box size
      if (box[3] - box[1] > 0.005) { 
        // Convert Normalized -> Pixels for Cropping
        int x = (box[1] * fixedImage.width).toInt();
        int y = (box[0] * fixedImage.height).toInt();
        int w = ((box[3] - box[1]) * fixedImage.width).toInt();
        int h = ((box[2] - box[0]) * fixedImage.height).toInt();

        // Safety Clamp
        x = x.clamp(0, fixedImage.width - 1);
        y = y.clamp(0, fixedImage.height - 1);
        if (x + w > fixedImage.width) w = fixedImage.width - x;
        if (y + h > fixedImage.height) h = fixedImage.height - y;

        // Crop & Classify
        img.Image crop = img.copyCrop(fixedImage, x: x, y: y, width: w, height: h);
         CVLogic.enhanceImage(crop); // Preprocessing
        Map<String, dynamic> classification = _runMobileNet(crop);

        finalResults.add({
          'label': classification['label'],
          'confidence': classification['confidence'], 
          'box': box, // [ymin, xmin, ymax, xmax]
        });
      }
    }

    return finalResults;
  }

  List<List<double>> _parseAllBoxes(List<dynamic> data, double padX, double padY) {
    int numAnchors = 8400; 
    List<List<double>> candidates = [];

    for (int i = 0; i < numAnchors; i++) {
      double confidence = data[4][i]; 
      
      if (confidence > 0.35) { 
          double xCenter = data[0][i];
          double yCenter = data[1][i];
          double width   = data[2][i];
          double height  = data[3][i];

          // Auto-fix pixels vs normalized
          if (xCenter > 1.0) { xCenter/=640; yCenter/=640; width/=640; height/=640; }

          // Convert to Pixels on 640x640
          double xPx = xCenter * 640;
          double yPx = yCenter * 640;
          double wPx = width * 640;
          double hPx = height * 640;

          // Remove Padding & Normalize to Original Image
          double actualW = 640 - (padX * 2);
          double actualH = 640 - (padY * 2);

          double xmin = ((xPx - padX) / actualW) - ((wPx / actualW) / 2);
          double ymin = ((yPx - padY) / actualH) - ((hPx / actualH) / 2);
          double xmax = ((xPx - padX) / actualW) + ((wPx / actualW) / 2);
          double ymax = ((yPx - padY) / actualH) + ((hPx / actualH) / 2);

          // Store: [ymin, xmin, ymax, xmax, confidence]
          candidates.add([ymin, xmin, ymax, xmax, confidence]);
      }
    }
    return candidates;
  }


  // Removes Overlapping Boxes(NMS)
  List<List<double>> _nonMaxSuppression(List<List<double>> boxes, double iouThreshold) {
    //Sort by confidence (descending)
    boxes.sort((a, b) => b[4].compareTo(a[4]));

    List<List<double>> selected = [];
    List<bool> active = List.filled(boxes.length, true);

    for (int i = 0; i < boxes.length; i++) {
      if (active[i]) {
        List<double> boxA = boxes[i];
        selected.add(boxA); // Keep the winner

        for (int j = i + 1; j < boxes.length; j++) {
          if (active[j]) {
            List<double> boxB = boxes[j];
            
            // Calculate IoU (Intersection over Union)
            double iou = _calculateIoU(boxA, boxB);
            if (iou > iouThreshold) {
              active[j] = false; 
            }
          }
        }
      }
    }
    return selected;
  }

  double _calculateIoU(List<double> boxA, List<double> boxB) {
    // Box: [ymin, xmin, ymax, xmax]
    double yA = math.max(boxA[0], boxB[0]);
    double xA = math.max(boxA[1], boxB[1]);
    double yB = math.min(boxA[2], boxB[2]);
    double xB = math.min(boxA[3], boxB[3]);

    double interArea = math.max(0, xB - xA) * math.max(0, yB - yA);

    double boxAArea = (boxA[2] - boxA[0]) * (boxA[3] - boxA[1]);
    double boxBArea = (boxB[2] - boxB[0]) * (boxB[3] - boxB[1]);

    return interArea / (boxAArea + boxBArea - interArea);
  }


  //CLASSIFIER HELPER
  Map<String, dynamic> _runMobileNet(img.Image crop) {
    const int mnSize = 224;
    final img.Image mnInput = img.copyResize(crop, width: mnSize, height: mnSize);
    
    // MobileNet Normalization: -1 to 1
    var mnBytes = _imageToFloat32List(mnInput, mnSize, mean: 127.5, std: 127.5);
    var mnOutput = List.filled(3, 0.0).reshape([1, 3]);
    
    if (_mobileNetInterpreter != null) {
      _mobileNetInterpreter!.run(mnBytes, mnOutput);
    }

    List<double> probs = List<double>.from(mnOutput[0]);
    int maxIdx = 0;
    double maxProb = probs[0];
    for(int i=1; i<probs.length; i++) {
      if(probs[i] > maxProb) { maxProb = probs[i]; maxIdx = i; }
    }
    
    return {'label': _mobileNetLabels[maxIdx], 'confidence': maxProb};
  }

  //utillities
  Uint8List _imageToFloat32List(img.Image image, int inputSize, {double mean = 0.0, double std = 255.0}) {
    var convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;
    for (var i = 0; i < inputSize; i++) {
      for (var j = 0; j < inputSize; j++) {
        var pixel = image.getPixel(j, i);
        buffer[pixelIndex++] = (pixel.r.toDouble() - mean) / std;
        buffer[pixelIndex++] = (pixel.g.toDouble() - mean) / std;
        buffer[pixelIndex++] = (pixel.b.toDouble() - mean) / std;
      }
    }
    return convertedBytes.buffer.asUint8List();
  }

  Map<String, dynamic> _letterboxImage(img.Image src, int targetSize) {
    double scale = targetSize / (src.width > src.height ? src.width : src.height);
    int newW = (src.width * scale).toInt();
    int newH = (src.height * scale).toInt();
    var resized = img.copyResize(src, width: newW, height: newH);
    var canvas = img.Image(width: targetSize, height: targetSize);
    img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
    int dx = (targetSize - newW) ~/ 2;
    int dy = (targetSize - newH) ~/ 2;
    img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
    return {'image': canvas, 'paddingX': dx.toDouble(), 'paddingY': dy.toDouble()};
  }
}