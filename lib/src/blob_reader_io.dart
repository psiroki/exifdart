import "dart:io";
import "dart:async";
import "dart:typed_data";

import "abstract_reader.dart";
import "exif_extractor.dart";

Future<Map<String, dynamic>> readExifFromFile(File file, {bool printDebugInfo = false}) {
  return readExif(new FileReader(file));
}

class FileReader extends AbstractBlobReader {
  FileReader(this.file);

  @override
  FutureOr<int> get byteLength {
    if (_length != null) return _length;
    return file.length().then((len) => _length = len);
  }

  @override
  Future<ByteData> readSlice(int start, int end) async {
    int size = await byteLength;
    if (start >= size) return new ByteData(0);
    if (end > size) end = size;
    List<List<int>> blocks = await file.openRead(start, end).toList();
    if (blocks.length > 0) {
      int overallSize = blocks.fold(0, (sum, block) => sum + block.length);
      Uint8List bytes = new Uint8List(overallSize);
      int offset = 0;
      for (List<int> block in blocks) {
        bytes.setRange(offset, block.length, block);
        offset += block.length;
      }
      return bytes.buffer.asByteData();
    } else {
      if (blocks.isEmpty) return new ByteData(0);
      List<int> block = blocks.first;
      if (block is! TypedData) block = new Uint8List.fromList(block);
      TypedData b = block as TypedData;
      return b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes);
    }
  }

  final File file;
  int _length;
}
