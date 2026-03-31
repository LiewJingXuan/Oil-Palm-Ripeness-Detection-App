import 'package:flutter/material.dart';

class RealTimeBox extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final double screenWidth;
  final double screenHeight;

  const RealTimeBox({
    Key? key,
    required this.results,
    required this.screenWidth,
    required this.screenHeight,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: results.map((result) {
        List<dynamic> box = result['box'];
        
        // EFFICIENTDET STANDARD: [ymin, xmin, ymax, xmax]
        double ymin = box[0] * 1.0;
        double xmin = box[1] * 1.0;
        double ymax = box[2] * 1.0;
        double xmax = box[3] * 1.0;

        // Convert to Screen Pixels
        double left = xmin * screenWidth;
        double top = ymin * screenHeight;
        double width = (xmax - xmin) * screenWidth;
        double height = (ymax - ymin) * screenHeight;

        Color color = Colors.orange;
        String label = result['label'] ?? "Unknown";
        if (label.toLowerCase().contains('ripe')) color = Colors.green;
        if (label.toLowerCase().contains('unripe')) color = Colors.red;
        if (label.toLowerCase().contains('overripe')) color = Colors.purple;

        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
            ),
            child: Text(
              "$label ${(result['confidence']*100).toStringAsFixed(0)}%",
              style: TextStyle(
                backgroundColor: color, 
                color: Colors.white, 
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}