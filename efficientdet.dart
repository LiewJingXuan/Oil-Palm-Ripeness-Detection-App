import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class Efficientdet {
  Interpreter? _interpreter;
  List<String> _labels = [];

  Future<void> loadModels() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/oilpalm_efficientdet_local.tflite');
      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelData.split('\n');
      print("EfficientDet (Real-Time) Loaded.");
    } catch (e) {
      print("Error loading EfficientDet: $e");
    }
  }

  Future<List<Map<String, dynamic>>> runInference(img.Image image) async {
    if (_interpreter == null) return [];

    //rotate for Android, then SQUASH to 384x384. 
    //This matches the screen scaling logic perfectly.
    img.Image fixedImage = image;
    const int inputSize = 384; 
    final img.Image resizedImage = img.copyResize(fixedImage, width: inputSize, height: inputSize);

    //ENHANCE
    img.Image enhancedImage = img.adjustColor(resizedImage, contrast: 1.4, saturation: 1.1, brightness: 1.3);
    
    //CONVERT TO BYTES
    var input = _imageToByteListUint8(enhancedImage, inputSize);

    //PREPARE OUTPUTS
    Map<int, Object> outputs = {};
    var outputTensors = _interpreter!.getOutputTensors();
    for (int i = 0; i < outputTensors.length; i++) {
      outputs[i] = List.filled(outputTensors[i].numElements(), 0.0).reshape(outputTensors[i].shape);
    }

    //run it
    _interpreter!.runForMultipleInputs([input], outputs);

    //Parse it (Auto-detect Boxes vs Scores)
    List<dynamic>? outputBoxes;
    List<dynamic>? outputScores;
    List<dynamic>? outputClasses;

    outputs.forEach((index, value) {
      var shape = outputTensors[index].shape;
      if (shape.last == 4) outputBoxes = value as List;
      else if (shape.last == 25) {
        if (outputScores == null) outputScores = value as List;
        else outputClasses = value as List;
      }
    });

    //format the result
    List<Map<String, dynamic>> results = [];
    if (outputScores != null && outputBoxes != null) {
      for (int i = 0; i < 20; i++) { 
        double score = (outputScores![0][i] as num).toDouble();
        if (score > 0.2) { 
          String label = "Oil Palm";
          if (outputClasses != null) {
             int clsIdx = (outputClasses![0][i] as num).toInt();
             if (clsIdx < _labels.length) label = _labels[clsIdx];
          }
          
          var box = outputBoxes![0][i];
          //EFFICIENTDET OUTPUT: [ymin, xmin, ymax, xmax] (Normalized 0-1)
          results.add({
            'label': label,
            'confidence': score,
            'box': [box[0], box[1], box[2], box[3]], // [ymin, xmin, ymax, xmax]
          });
        }
      }
    }
    return results;
  }

  Uint8List _imageToByteListUint8(img.Image image, int inputSize) {
    var convertedBytes = Uint8List(1 * inputSize * inputSize * 3);
    var buffer = convertedBytes.buffer;
    var bd = buffer.asByteData();
    int pixelIndex = 0;
    for (var i = 0; i < inputSize; i++) {
      for (var j = 0; j < inputSize; j++) {
        var pixel = image.getPixel(j, i);
        bd.setUint8(pixelIndex++, pixel.r.toInt());
        bd.setUint8(pixelIndex++, pixel.g.toInt());
        bd.setUint8(pixelIndex++, pixel.b.toInt());
      }
    }
    return convertedBytes;
  }
}