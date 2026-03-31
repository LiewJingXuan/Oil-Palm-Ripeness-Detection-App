import 'package:image/image.dart' as img;

class CVLogic {
  
  //Geometric Noise Filter
  //Returns true if the box looks like a fruit (Square-ish), false if noise (Line/Dot)
  static bool isValidObject(double width, double height) {
    double area = width * height;
    double aspectRatio = width / height;

    // Rule A: Ignore tiny specks (< 5% of screen)
    if (area < 0.02) return false;

    // Rule B: Ignore flat lines (Branches/Leaves)
    if (aspectRatio > 2.5 || aspectRatio < 0.4) return false;

    return true;
  }
  
  // "Normalizes" the image histogram to make texture visible in bad lighting
  static void enhanceImage(img.Image image) {
    img.normalize(image, min: 0, max:255); 
  }
}