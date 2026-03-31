import 'package:flutter/material.dart';

class ImageBox extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final double displayWidth;
  final double displayHeight;

  const ImageBox({
    Key? key,
    required this.results,
    required this.displayWidth,
    required this.displayHeight,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: results.map((result) {
        List<dynamic> box = result['box'];
        
        // 1. Coordinates
        double ymin = box[0] * 1.0;
        double xmin = box[1] * 1.0;
        double ymax = box[2] * 1.0;
        double xmax = box[3] * 1.0;

        // 2. Screen Mapping
        double left = xmin * displayWidth;
        double top = ymin * displayHeight;
        double width = (xmax - xmin) * displayWidth;
        double height = (ymax - ymin) * displayHeight;

        // 3. Color Logic (For the Border Line)
        Color borderColor = Colors.blue; 
        String label = result['label'] ?? "Unknown";
        if (label.toLowerCase().contains('ripe')) borderColor = Colors.green;
        if (label.toLowerCase().contains('unripe')) borderColor = Colors.red;
        if (label.toLowerCase().contains('overripe')) borderColor = Colors.purple;
        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: Container(
            // --- THE BOX BORDER (Colored Red/Green) ---
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 3),
              color: Colors.transparent, // Inside is empty
            ),
            
            // --- THE LABEL (White Text on Black Background) ---
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                color: Colors.black, // <--- SMALL BLACK BACKGROUND
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                margin: const EdgeInsets.only(top: 0, left: 0), // Sticks to corner
                child: Text(
                  // Note: Removed the *100 if you fixed it in UI previously. 
                  // If you still see 1000%, remove the *100 below.
                  "$label",
                  style: const TextStyle(
                    color: Colors.white, // <--- TEXT ALWAYS WHITE
                    fontWeight: FontWeight.bold, 
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}