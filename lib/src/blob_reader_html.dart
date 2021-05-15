// ignore_for_file: prefer_single_quotes

import "dart:html";
import "dart:async";
import "dart:typed_data";

import "abstract_reader.dart";
import "exif_extractor.dart";

/// Reads the EXIF info from a DOM `Blob` object including a `File` object.
Future<Map<String, dynamic>?> readExifFromBlob(Blob blob,
    {bool printDebugInfo = false}) {
  return readExif(BlobReader(blob));
}

/// Reads sections from a (`dart:html`) `Blob` using (`dart:html`) `FileReader`.
class BlobReader extends AbstractBlobReader {
  /// Creates the `BlobReader` with the given `Blob`.
  BlobReader(this.blob);

  @override
  int get byteLength => blob.size;

  @override
  Future<ByteData> readSlice(int start, int end) {
    if (start >= blob.size) return Future.value(ByteData(0));
    if (end > blob.size) end = blob.size;
    final completer = Completer<ByteData>();
    final reader = FileReader();
    reader.onLoad.listen((_) {
      final bytes = (reader.result as Uint8List).buffer.asByteData();
      completer.complete(bytes);
    });
    reader.onLoadEnd.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError("Couldn't fetch blob section");
      }
    });
    reader.readAsArrayBuffer(blob.slice(start, end));
    return completer.future;
  }

  /// The DOM `Blob`
  final Blob blob;
}
