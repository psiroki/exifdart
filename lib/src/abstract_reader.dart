import "dart:async";
import "dart:typed_data";

abstract class AbstractBlobReader {
  FutureOr<int> get byteLength;

  FutureOr<ByteData> readSlice(int start, int end);
}

class MemoryBlobReader extends AbstractBlobReader {
  MemoryBlobReader(List<int> bytes)
      : _bytes = bytes is Uint8List ? bytes : new Uint8List.fromList(bytes);

  int get byteLength => _bytes.lengthInBytes;

  ByteData readSlice(int start, int end) {
    if (start >= _bytes.lengthInBytes) return _bytes.buffer.asByteData(_bytes.offsetInBytes, 0);
    if (end > _bytes.lengthInBytes) end = _bytes.lengthInBytes;
    return _bytes.buffer.asByteData(start + _bytes.offsetInBytes, end - start);
  }

  final Uint8List _bytes;
}
