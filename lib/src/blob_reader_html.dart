import "dart:html";
import "dart:async";
import "dart:typed_data";

import "abstract_reader.dart";
import "exif_extractor.dart";

Future<Map<String, dynamic>> readExifFromBlob(Blob blob, {bool printDebugInfo=false}) {
  return readExif(new BlobReader(blob));
}

class BlobReader extends AbstractBlobReader {
  BlobReader(this.blob);

  @override
  int get byteLength => blob.size;

  @override
  Future<ByteData> readSlice(int start, int end) {
    if (start >= blob.size) return new Future.value(new ByteData(0));
    if (end > blob.size) end = blob.size;
    Completer<ByteData> completer = new Completer();
    FileReader reader = new FileReader();
    reader.onLoad.listen((_) {
      ByteData bytes = (reader.result as Uint8List).buffer.asByteData();
      completer.complete(bytes);
    });
    reader.onLoadEnd.listen((_) {
      if (!completer.isCompleted)
        completer.completeError("Couldn't fetch blob section");
    });
    reader.readAsArrayBuffer(blob.slice(start, end));
    return completer.future;
  }

  final Blob blob;
}
