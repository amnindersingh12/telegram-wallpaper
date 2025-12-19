import 'dart:io';
import 'package:image/image.dart' as img;

Future<void> main() async {
  final ppmFile = File('assets/icons/app_icon.ppm');
  if (!await ppmFile.exists()) {
    stderr.writeln('Missing assets/icons/app_icon.ppm');
    exit(1);
  }

  final bytes = await ppmFile.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    stderr.writeln('Failed to decode PPM.');
    exit(1);
  }

  final resized = img.copyResize(decoded, width: 1024, height: 1024, interpolation: img.Interpolation.cubic);
  final outPng = File('assets/icons/app_icon.png');
  await outPng.create(recursive: true);
  await outPng.writeAsBytes(img.encodePng(resized));

  stdout.writeln('Wrote assets/icons/app_icon.png');
}
