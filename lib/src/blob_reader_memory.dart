import "dart:async";
import "dart:typed_data";

import "abstract_reader.dart";
import "exif_extractor.dart";

/// Reads the EXIF info from an image already loaded into memory
Future<Map<String, dynamic>> readExifFromBytes(Uint8List bytes) {
  return readExif(new MemoryBlobReader(bytes));
}
