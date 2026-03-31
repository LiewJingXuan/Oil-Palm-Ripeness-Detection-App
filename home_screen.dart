import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fyp_second/screens/image_detection.dart';
import 'package:fyp_second/screens/real_detection_screen.dart';
import 'video_analysis_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomeScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  //LOCK VARIABLE: Prevents double-tapping
  bool _isPickerActive = false; 

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.storage, Permission.photos].request();
  }

  Future<void> _pickImageFromGallery() async {
    // 1. If already opening, stop here.
    if (_isPickerActive) return;

    setState(() {
      _isPickerActive = true; // Lock the button
    });

    try {
      final ImagePicker picker = ImagePicker();
      // 2. Open Gallery
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageAnalysisScreen(
              imageFromFile: File(image.path),
            ),
          ),
        );
      }
    } catch (e) {
      print("Error picking image: $e");
    } finally {
      // 3. Unlock the button safely when done (or if user cancels)
      if (mounted) {
        setState(() {
          _isPickerActive = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Oil Palm Ripeness Detection App")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/FYP_Logo.png', 
              height: 200,              
              width: 200,
            ),
            const SizedBox(height: 20),
            // BUTTON 1: GO TO CAMERA PAGE
            _buildCard(
              context,
              "Live Detection",
              Icons.camera_alt,
              Colors.black,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LiveDetectionScreen(cameras: widget.cameras),
                ),
              ),
            ),

            const SizedBox(height: 20),

            _buildCard(
              context,
              _isPickerActive ? "Opening Gallery..." : "Upload Image Analysis", // Change text if loading
              Icons.image,
              _isPickerActive ? Colors.grey : Colors.black, // Grey out if loading
              _pickImageFromGallery, 
            ),

            const SizedBox(height: 20,),

            // BUTTON 3: UPLOAD VIDEO
            _buildCard(
              context,
              "Upload Video Analysis",
              Icons.video_collection,
              Colors.black, 
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const VideoAnalysisScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 5,
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        leading: Icon(icon, size: 40, color: color),
        title: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        onTap: onTap,
      ),
    );
  }
}