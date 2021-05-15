import "dart:async";
import "dart:typed_data";

/// An interface to randomly read a blob.
abstract class AbstractBlobReader {
  /// Returns the size of the blob.
  FutureOr<int> get byteLength;

  /// Returns the bytes as `ByteData` in the given section.
  /// The [start] is inclusive, the [end] is exclusive.
  FutureOr<ByteData> readSlice(int start, int end);
}

/// Uses a byte buffer to read the blob data from.
class MemoryBlobReader extends AbstractBlobReader {
  /// Use this constructor to create a memory blob reader with the given list of bytes.
  /// The [bytes] aren't copied if the type is `Uint8List`.
  MemoryBlobReader(List<int> bytes)
      : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  @override
  int get byteLength => _bytes.lengthInBytes;

  @override
  ByteData readSlice(int start, int end) {
    if (start >= _bytes.lengthInBytes) {
      return _bytes.buffer.asByteData(_bytes.offsetInBytes, 0);
    }
    if (end > _bytes.lengthInBytes) end = _bytes.lengthInBytes;
    return _bytes.buffer.asByteData(start + _bytes.offsetInBytes, end - start);
  }

  final Uint8List _bytes;
}
