// ignore_for_file: prefer_single_quotes

import "dart:io";
import "dart:async";
import "dart:typed_data";

import "abstract_reader.dart";
import "exif_extractor.dart";

/// Reads the EXIF info from a `dart:io` `File` object.
Future<Map<String, dynamic>?> readExifFromFile(File file,
    {bool printDebugInfo = false}) {
  return readExif(FileReader(file));
}

/// Reads sections from a `dart:io` `File`.
class FileReader extends AbstractBlobReader {
  /// Creates a `FileReader` with the given `File`.
  FileReader(this.file);

  @override
  FutureOr<int> get byteLength {
    if (_length != null) return _length!;
    return file.length().then((len) => _length = len);
  }

  @override
  Future<ByteData> readSlice(int start, int end) async {
    final size = await byteLength;
    if (start >= size) return ByteData(0);
    if (end > size) end = size;
    final blocks = await file.openRead(start, end).toList();
    if (blocks.isNotEmpty) {
      final overallSize =
          blocks.fold<int>(0, (sum, block) => sum + block.length);
      final bytes = Uint8List(overallSize);
      var offset = 0;
      for (var block in blocks) {
        bytes.setRange(offset, block.length, block);
        offset += block.length;
      }
      return bytes.buffer.asByteData();
    } else {
      if (blocks.isEmpty) return ByteData(0);
      var block = blocks.first;
      if (block is! TypedData) block = Uint8List.fromList(block);
      final b = block as TypedData;
      return b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes);
    }
  }

  final File file;
  int? _length;
}
