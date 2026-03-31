import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:permission_handler/permission_handler.dart'; 
import '../services/efficientdet.dart'; 
import '../widgets/real_time_bounding_box.dart';
import 'package:fyp_second/screens/image_detection.dart'; 
import '../utils/isolate_utils.dart';
import '../utils/cv_logic.dart'; 

class LiveDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const LiveDetectionScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _LiveDetectionScreenState createState() => _LiveDetectionScreenState();
}

class _LiveDetectionScreenState extends State<LiveDetectionScreen> with WidgetsBindingObserver {
  CameraController? _controller; 
  
  final Efficientdet _modelService = Efficientdet();
  
  bool _isDetecting = false;
  List<Map<String, dynamic>> _results = [];
  int _lastFrameTime = 0; 
  bool _isPermissionDenied = false;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _modelService.loadModels();
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose(); 
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  void _initializeCamera() async { 
    var status = await Permission.camera.status;

    if (status.isDenied || status.isPermanentlyDenied) {
      status = await Permission.camera.request();
    }

    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _isPermissionDenied = true;
          _isCameraInitialized = false;
        });
      }
      return; 
    }

    _controller = CameraController(widget.cameras[0], ResolutionPreset.veryHigh, enableAudio: false);

    try {
      await _controller!.initialize(); 
      
      if (!mounted) return;
      setState(() {
        _isPermissionDenied = false;
        _isCameraInitialized = true;
      }); 
      _startLiveStream();
      
    } on CameraException catch (e) {
      if (e.code == 'CameraAccessDenied' || e.code == 'permission_denied') {
        if (mounted) {
          setState(() {
            _isPermissionDenied = true;
          });
        }
      }
      print("Camera Error: $e");
    } catch (e) {
       print("Other Error: $e");
    }
  }

  void _startLiveStream() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _controller!.startImageStream((image) {
      int currentTime = DateTime.now().millisecondsSinceEpoch;
      if (currentTime - _lastFrameTime > 1000) { 
        if (!_isDetecting) {
          _isDetecting = true;
          _lastFrameTime = currentTime;
          _runInference(image);
        }
      }
    });
  }

  Future<void> _runInference(CameraImage cameraImage) async {
    try {
      final image = await IsolateUtils.convertCameraImageInBackground(cameraImage);
      if (image == null) {
        _isDetecting = false;
        return;
      }      

      final results = await _modelService.runInference(image);

      List<Map<String, dynamic>> filteredResults = [];
      for (var result in results) {
         List<dynamic> box = result['box'];
         double h = box[2] - box[0];
         double w = box[3] - box[1];

         if (CVLogic.isValidObject(w, h)) {
            filteredResults.add(result);
         }
      }

      if (mounted) {
        setState(() {
          _results = filteredResults; 
          _isDetecting = false;
        });
      }
    } catch (e) {
      print("Inference error: $e");
      _isDetecting = false; 
    }
  }

  Future<void> _captureAndAnalyze() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) return;
      
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      final XFile photo = await _controller!.takePicture();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageAnalysisScreen(
              imageFromFile: File(photo.path),
            ),
          ),
        ).then((_) {
          _initializeCamera();
        });
      }
    } catch (e) {
      print("Error taking picture: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPermissionDenied) {
      return Scaffold(
        appBar: AppBar(title: const Text("Permission Required")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography, size: 50, color: Colors.grey),
              const SizedBox(height: 20),
              const Text("Camera permission is required."),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => openAppSettings(),
                child: const Text("Open Settings"),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Live Detection")),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: CameraPreview(_controller!), 
              );
            }
          ),
          RealTimeBox(
            results: _results,
            screenWidth: MediaQuery.of(context).size.width,
            screenHeight: MediaQuery.of(context).size.height,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 50.0),
              child: FloatingActionButton.large(
                heroTag: "capture",
                backgroundColor: Colors.white,
                onPressed: _captureAndAnalyze,
                child: const Icon(Icons.camera_alt, color: Colors.green, size: 50),
              ),
            ),
          ),
        ],
      ),
    );
  }
}