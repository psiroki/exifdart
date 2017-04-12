import "dart:html";
import "dart:async";
import "dart:typed_data";

class CacheView {
  CacheView(this.start, this.bytes);

  bool contains(int absPosition) => bytes != null &&
    start <= absPosition && absPosition-start < bytes.lengthInBytes;

  bool containsRange(int absStart, int absEnd) => bytes != null &&
    start <= absStart && absEnd <= absStart + bytes.lengthInBytes;

  int getUint8(int offset) => bytes.getUint8(offset-start);
  int getUint16(int offset, Endianness endianness) => bytes.getUint16(offset-start, endianness);
  int getUint32(int offset, Endianness endianness) => bytes.getUint32(offset-start, endianness);
  int getInt32(int offset, Endianness endianness) => bytes.getInt32(offset-start, endianness);

  ByteData getBytes(int absStart, int absEnd) =>
    bytes.buffer.asByteData(bytes.offsetInBytes + absStart - start, absEnd-absStart);

  final int start;
  final ByteData bytes;
}

class BlobView {
    BlobView(this.blob);

    int get byteLength => blob.size;

    Future<ByteData> getBytes(int start, int end) async {
      if (_lastCacheView.containsRange(start, end))
        return new Future.value(_lastCacheView.getBytes(start, end));
      int realEnd = end;
      if (start + _pageSize > realEnd)
        realEnd = start + _pageSize;
      CacheView view = await _retrieve(start, realEnd);
      return view.getBytes(start, end);
    }

    Future<int> getInt32(int offset, [Endianness endianness = Endianness.BIG_ENDIAN]) async {
      if (_lastCacheView.containsRange(offset, offset+4))
        return new Future.value(_lastCacheView.getInt32(offset, endianness));
      CacheView view = await _retrieve(offset, offset+_pageSize);
      return view.getInt32(offset, endianness);
    }

    Future<int> getUint32(int offset, [Endianness endianness = Endianness.BIG_ENDIAN]) async {
      if (_lastCacheView.containsRange(offset, offset+4))
        return new Future.value(_lastCacheView.getUint32(offset, endianness));
      CacheView view = await _retrieve(offset, offset+_pageSize);
      return view.getUint32(offset, endianness);
    }

    Future<int> getUint16(int offset, [Endianness endianness = Endianness.BIG_ENDIAN]) async {
      if (_lastCacheView.containsRange(offset, offset+2))
        return new Future.value(_lastCacheView.getUint16(offset, endianness));
      CacheView view = await _retrieve(offset, offset+_pageSize);
      return view.getUint16(offset, endianness);
    }

    Future<int> getUint8(int offset) async {
      if (_lastCacheView.contains(offset))
        return new Future.value(_lastCacheView.getUint8(offset));
      CacheView view = await _retrieve(offset, offset+_pageSize);
      return view.getUint8(offset);
    }

    Future<CacheView> _retrieve(int start, int end) {
      Completer<Null> completer = new Completer();
      FileReader reader = new FileReader();
      reader.onLoad.listen((_) {
        ByteData bytes = (reader.result as Uint8List).buffer.asByteData();
        CacheView view = new CacheView(start, bytes);
        _lastCacheView = view;
        completer.complete(view);
      });
      reader.onLoadEnd.listen((_) {
        if (!completer.isCompleted)
          completer.completeError("Couldn't fetch blob section");
      });
      reader.readAsArrayBuffer(blob.slice(start, end));
      return completer.future;
    }

    final Blob blob;
    CacheView _lastCacheView = new CacheView(0, null);

    static const int _pageSize = 4096;
}
