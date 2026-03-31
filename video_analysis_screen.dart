import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart';
import '../services/hybrid.dart'; // Make sure this matches your file name
import '../widgets/image_box.dart'; 

class VideoAnalysisScreen extends StatefulWidget {
  const VideoAnalysisScreen({Key? key}) : super(key: key);

  @override
  _VideoAnalysisScreenState createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends State<VideoAnalysisScreen> {
  final YoloMobileNetService _pipelineService = YoloMobileNetService();
  final ImagePicker _picker = ImagePicker();

  bool _isProcessing = false;
  String _statusMessage = "Pick a video to start";
  List<Map<String, dynamic>> _analyzedFrames = []; 

  @override
  void initState() {
    super.initState();
    _pipelineService.loadModels();
  }

  // === 1. Pick Video ===
  Future<void> _pickAndProcessVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = "Extracting & Filtering Frames...";
      _analyzedFrames.clear();
    });

    try {
      // Step A: Extract Frames (High Quality)
      List<File> frames = await _extractFrames(File(video.path));

      // Step B: Analyze Frames
      int goodFrames = 0;
      for (int i = 0; i < frames.length; i++) {
        if (!mounted) break;
        
        File frameFile = frames[i];
        final bytes = await frameFile.readAsBytes();
        final image = await compute(decodeImageInBackground, bytes);

        if (image != null) {
          // === COMPUTER VISION CONTRIBUTION: BLUR CHECK ===
          // We calculate the "Sharpness" of the image.
          // If it's too blurry, we SKIP it to avoid bad detection.
          bool isBlurry = await compute(isImageBlurry, image);

          if (isBlurry) {
             print("Skipping Frame $i (Too Blurry)");
             setState(() => _statusMessage = "Skipping Frame $i (Motion Blur)...");
             continue; // <--- SKIP THIS FRAME
          }

          // If clear, run the AI
          setState(() => _statusMessage = "Analyzing Frame $i (Sharp)...");
          final results = await _pipelineService.runPipeline(image);
          
          // Only show if we actually found something (Optional)
          // if (results.isEmpty) continue; 

          goodFrames++;
          _analyzedFrames.add({
            'file': frameFile,
            'image': image, 
            'results': results,
            'timestamp': "${(i * 0.5).toStringAsFixed(1)}s" // 0.5s interval
          });
        }
      }

      setState(() {
        _isProcessing = false;
        _statusMessage = "Complete: Analyzed $goodFrames Sharp Frames";
      });

    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "Error: $e";
      });
      print("Video Error: $e");
    }
  }

  // === 2. Extract High-Quality Frames ===
  Future<List<File>> _extractFrames(File videoFile) async {
    final Directory dir = await getTemporaryDirectory();
    final String path = dir.path;
    List<File> frames = [];
    
    // Check every 0.5 seconds (twice as often as before)
    int intervalMs = 500; 
    int timeMs = 0;

    try {
      while (true) {
        timeMs += intervalMs;

        final uint8list = await VideoThumbnail.thumbnailData(
          video: videoFile.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 1280, 
          quality: 100,   
          timeMs: timeMs, 
        );

        if (uint8list == null) break; 

        final file = File('$path/frame_$timeMs.jpg');
        await file.writeAsBytes(uint8list);
        frames.add(file);

        // Safety: Stop after 30 frames (15 seconds) to prevent crashing
        if (frames.length >= 30) break; 
      }
    } catch (e) {
      print("Error extracting frame: $e");
    }
    return frames;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Video Analysis")),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.green.shade50,
            width: double.infinity,
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _pickAndProcessVideo,
                  icon: const Icon(Icons.video_library),
                  label: const Text("Upload Video"),
                ),
                const SizedBox(height: 10),
                Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (_isProcessing) const LinearProgressIndicator(),
              ],
            ),
          ),
          Expanded(
            child: _analyzedFrames.isEmpty
                ? const Center(child: Text("Upload a video to analyze frames"))
                : ListView.builder(
                    itemCount: _analyzedFrames.length,
                    itemBuilder: (context, index) {
                      final frameData = _analyzedFrames[index];
                      final File file = frameData['file'];
                      final img.Image image = frameData['image'];
                      final List<Map<String, dynamic>> results = frameData['results'];
                      final String timestamp = frameData['timestamp'];

                      return Card(
                        margin: const EdgeInsets.all(10),
                        elevation: 4,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Time: $timestamp", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(results.isEmpty ? "No Detection" : "Found ${results.length}", 
                                       style: TextStyle(color: results.isEmpty ? Colors.grey : Colors.green, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                double displayWidth = constraints.maxWidth;
                                double displayHeight = (displayWidth * image.height) / image.width;
                                return SizedBox(
                                  width: displayWidth,
                                  height: displayHeight,
                                  child: Stack(
                                    children: [
                                      Image.file(file, width: displayWidth, height: displayHeight, fit: BoxFit.fill),
                                      ImageBox(
                                        results: results,
                                        displayWidth: displayWidth,
                                        displayHeight: displayHeight,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

img.Image? decodeImageInBackground(Uint8List bytes) {
  return img.decodeImage(bytes);
}

// 🧠 Simple Blur Detection (Laplacian Variance Lite)
// If the image is too smooth (no edges), it is blurry.
bool isImageBlurry(img.Image image) {
  // 1. Convert to Grayscale (Luminance) to save CPU
  final grayscale = img.grayscale(image);
  
  // 2. Simplified Edge Detection Check
  // Sharp images have HIGH difference (Edges).
  // Blurry images have LOW difference (Smooth).
  
  double totalEdgeIntensity = 0;
  int count = 0;

  // Scan the center of the image (where the fruit likely is)
  int startX = (image.width * 0.25).toInt();
  int endX = (image.width * 0.75).toInt();
  int startY = (image.height * 0.25).toInt();
  int endY = (image.height * 0.75).toInt();

  for (int y = startY; y < endY; y += 2) {
    for (int x = startX; x < endX; x += 2) {
      var pixel = grayscale.getPixel(x, y);
      var right = grayscale.getPixel(x + 1, y);
      var down = grayscale.getPixel(x, y + 1);
      
      // Calculate difference (edge strength)
      num diff = (pixel.r - right.r).abs() + (pixel.r - down.r).abs();
      totalEdgeIntensity += diff;
      count++;
    }
  }

  double averageEdge = totalEdgeIntensity / count;
  
  // Threshold: If average edge strength is < 5, it's very blurry.
  // Adjust this number if it skips too many frames.
  return averageEdge < 5.0; 
}