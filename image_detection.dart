import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img; 
import '../services/hybrid.dart'; 
import '../widgets/image_box.dart'; // <--- NEW IMPORT

class ImageAnalysisScreen extends StatefulWidget {
  final File imageFromFile;

  const ImageAnalysisScreen({Key? key, required this.imageFromFile}) : super(key: key);

  @override
  _ImageAnalysisScreenState createState() => _ImageAnalysisScreenState();
}

class _ImageAnalysisScreenState extends State<ImageAnalysisScreen> {
  final YoloMobileNetService _pipelineService = YoloMobileNetService();
  
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = true;
  String _statusMessage = "Initializing..."; 
  img.Image? _decodedImage; 
  File? _displayImageFile;

  @override
  void initState() {
    super.initState();
    _safeAnalyze();
  }

  Future<void> _safeAnalyze() async {
    try {
      setState(() => _statusMessage = "Loading AI Models...");
      await _pipelineService.loadModels();

      setState(() => _statusMessage = "Processing Image...");
      final bytes = await widget.imageFromFile.readAsBytes();
      final image = await compute(decodeImageInBackground, bytes);

      if (image == null) throw Exception("Could not decode image");

      if (!mounted) return;
      setState(() {
        _decodedImage = image;
        _displayImageFile = widget.imageFromFile;
        _statusMessage = "Running Multi-Stage Analysis...";
      });

      final results = await _pipelineService.runPipeline(image);

      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });

    } catch (e) {
      print("CRITICAL ERROR: $e"); 
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Detailed Analysis")),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(_statusMessage), 
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      double displayWidth = constraints.maxWidth;
                      double displayHeight = displayWidth;
                      if (_decodedImage != null) {
                         displayHeight = (displayWidth * _decodedImage!.height) / _decodedImage!.width;
                      } else {
                          return Container(
                            height: 200,
                            color: Colors.grey[300],
                            child: const Center(child: Text("Fail to Process Image")),
                          );
                        }
                      return SizedBox(
                        width: displayWidth,
                        height: displayHeight,
                        child: Stack(
                          children: [
                            Image.file(
                              _displayImageFile!,
                              width: displayWidth,
                              height: displayHeight,
                              fit: BoxFit.fill, 
                            ),
                            // USES NEW IMAGE BOX
                            ImageBox(
                              results: _results,
                              displayWidth: displayWidth,
                              displayHeight: displayHeight,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Text(
                    _results.isEmpty ? "No FFB Detected" : "Found ${_results.length} Bunches",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  
                  // ..._results.map((res) {
                  //   Color color = Colors.orange;
                  //   if (res['label'] == 'Ripe') color = Colors.green;
                  //   if (res['label'] == 'Unripe') color = Colors.red;
                  //   return ListTile(
                  //     leading: Icon(Icons.circle, color: color),
                  //     title: Text("${res['label']}"),
                  //     subtitle: const Text("Detected via YOLO + MobileNet"),
                  //   );
                  // }),
                ],
              ),
            ),
    );
  }
}

img.Image? decodeImageInBackground(Uint8List bytes) {
  return img.decodeImage(bytes);
}