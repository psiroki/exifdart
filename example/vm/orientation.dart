import "dart:async";
import "dart:io";
import "package:exifdart/exifdart_io.dart";

const Map<int, String> orienationNames = {
  1: "The 0th row is at the visual top of the image, "
      "and the 0th column is the visual left-hand side.",
  2: "The 0th row is at the visual top of the image, "
      "and the 0th column is the visual right-hand side.",
  3: "The 0th row is at the visual bottom of the image, "
      "and the 0th column is the visual right-hand side.",
  4: "The 0th row is at the visual bottom of the image, "
      "and the 0th column is the visual left-hand side.",
  5: "The 0th row is the visual left-hand side of the image, "
      "and the 0th column is the visual top.",
  6: "The 0th row is the visual right-hand side of the image, "
      "and the 0th column is the visual top.",
  7: "The 0th row is the visual right-hand side of the image, "
      "and the 0th column is the visual bottom.",
  8: "The 0th row is the visual left-hand side of the image, "
      "and the 0th column is the visual bottom.",
};

Future main(List<String> args) async {
  if (args.isEmpty || args.contains("-h") || args.contains("--help")) {
    stderr.writeln("Usage:");
    stderr.writeln("  orientation.dart <filename.jpg>");
  }
  Map<String, dynamic> result = await readExifFromFile(File(args[0]));
  int orientation = result == null ? null : result["Orientation"];
  if (orientation == null) {
    print("Orientation is missing");
  } else {
    print(orienationNames[orientation] ?? "Reserved");
  }
}
