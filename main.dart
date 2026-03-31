import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart'; 

Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);


  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error: $e.code\nError Message: $e.message');
  }

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  // Make cameras nullable or empty list safe
  final List<CameraDescription> cameras;
  
  // Default to empty list if not provided (safety)
  const MyApp({Key? key, this.cameras = const []}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, 
      title: 'Palm Oil Detector',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true, 
      ),
      home: HomeScreen(cameras: cameras), 
    );
  }
}