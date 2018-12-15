import "dart:async";
import "dart:typed_data";
import "abstract_reader.dart";

class CacheView {
  CacheView(this.start, this.bytes);

  bool contains(int absPosition) =>
      bytes != null &&
      start <= absPosition &&
      absPosition - start < bytes.lengthInBytes;

  bool containsRange(int absStart, int absEnd) =>
      bytes != null &&
      start <= absStart &&
      absEnd <= start + bytes.lengthInBytes;

  int getUint8(int offset) => bytes.getUint8(offset - start);
  int getUint16(int offset, Endian endianness) =>
      bytes.getUint16(offset - start, endianness);
  int getUint32(int offset, Endian endianness) =>
      bytes.getUint32(offset - start, endianness);
  int getInt32(int offset, Endian endianness) =>
      bytes.getInt32(offset - start, endianness);
  double getFloat32(int offset, Endian endianness) =>
      bytes.getFloat32(offset - start, endianness);
  double getFloat64(int offset, Endian endianness) =>
      bytes.getFloat64(offset - start, endianness);

  ByteData getBytes(int absStart, int absEnd) => bytes.buffer
      .asByteData(bytes.offsetInBytes + absStart - start, absEnd - absStart);

  final int start;
  final ByteData bytes;
}

class BlobView {
  static FutureOr<BlobView> create(AbstractBlobReader blob) {
    FutureOr<int> length = blob.byteLength;
    if (length is Future)
      return (length as Future)
          .then((actualLength) => new BlobView._(blob, actualLength));
    return new BlobView._(blob, length);
  }

  BlobView._(this.blob, this.byteLength);

  final int byteLength;

  Future<ByteData> getBytes(int start, int end) async {
    if (_lastCacheView.containsRange(start, end))
      return new Future.value(_lastCacheView.getBytes(start, end));
    int realEnd = end;
    if (start + _pageSize > realEnd) realEnd = start + _pageSize;
    CacheView view = await _retrieve(start, realEnd);
    return view.getBytes(start, end);
  }

  Future<int> getInt32(int offset, [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 4))
      return new Future.value(_lastCacheView.getInt32(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getInt32(offset, endianness);
  }

  Future<int> getUint32(int offset, [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 4))
      return new Future.value(_lastCacheView.getUint32(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getUint32(offset, endianness);
  }

  Future<int> getUint16(int offset, [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 2))
      return new Future.value(_lastCacheView.getUint16(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getUint16(offset, endianness);
  }

  Future<int> getUint8(int offset) async {
    if (_lastCacheView.contains(offset))
      return new Future.value(_lastCacheView.getUint8(offset));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getUint8(offset);
  }

  Future<double> getFloat32(int offset,
      [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 4))
      return new Future.value(_lastCacheView.getFloat32(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getFloat32(offset, endianness);
  }

  Future<double> getFloat64(int offset,
      [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 8))
      return new Future.value(_lastCacheView.getFloat64(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getFloat64(offset, endianness);
  }

  FutureOr<CacheView> _retrieve(int start, int end) {
    FutureOr<ByteData> bytes = blob.readSlice(start, end);
    if (bytes is Future) {
      Future<ByteData> bytesFuture = bytes;
      return bytesFuture
          .then((actualBytes) => new CacheView(start, actualBytes));
    }
    return new CacheView(start, bytes);
  }

  final AbstractBlobReader blob;
  CacheView _lastCacheView = new CacheView(0, null);

  static const int _pageSize = 4096;
}
