import "dart:async";
import "dart:typed_data";
import "abstract_reader.dart";

abstract class CacheView {
  factory CacheView(int start, ByteData? bytes) {
    return bytes == null ? DummyCacheView() : RealCacheView(start, bytes);
  }

  bool contains(int absPosition);

  bool containsRange(int absStart, int absEnd);

  int getUint8(int offset);
  int getUint16(int offset, Endian endianness);
  int getUint32(int offset, Endian endianness);
  int getInt32(int offset, Endian endianness);
  double getFloat32(int offset, Endian endianness);
  double getFloat64(int offset, Endian endianness);

  ByteData getBytes(int absStart, int absEnd);
}

class DummyCacheView implements CacheView {
  const DummyCacheView();

  @override
  bool contains(int absPosition) => false;

  @override
  bool containsRange(int absStart, int absEnd) => false;

  @override
  int getUint8(int offset) => throw UnsupportedError("Cache is empty");
  @override
  int getUint16(int offset, Endian endianness) =>
      throw UnsupportedError("Cache is empty");
  @override
  int getUint32(int offset, Endian endianness) =>
      throw UnsupportedError("Cache is empty");
  @override
  int getInt32(int offset, Endian endianness) =>
      throw UnsupportedError("Cache is empty");
  @override
  double getFloat32(int offset, Endian endianness) =>
      throw UnsupportedError("Cache is empty");
  @override
  double getFloat64(int offset, Endian endianness) =>
      throw UnsupportedError("Cache is empty");

  @override
  ByteData getBytes(int absStart, int absEnd) =>
      throw UnsupportedError("Cache is empty");
}

class RealCacheView implements CacheView {
  RealCacheView(this.start, this.bytes);

  @override
  bool contains(int absPosition) =>
      start <= absPosition && absPosition - start < bytes.lengthInBytes;

  @override
  bool containsRange(int absStart, int absEnd) =>
      start <= absStart && absEnd <= start + bytes.lengthInBytes;

  @override
  int getUint8(int offset) => bytes.getUint8(offset - start);
  @override
  int getUint16(int offset, Endian endianness) =>
      bytes.getUint16(offset - start, endianness);
  @override
  int getUint32(int offset, Endian endianness) =>
      bytes.getUint32(offset - start, endianness);
  @override
  int getInt32(int offset, Endian endianness) =>
      bytes.getInt32(offset - start, endianness);
  @override
  double getFloat32(int offset, Endian endianness) =>
      bytes.getFloat32(offset - start, endianness);
  @override
  double getFloat64(int offset, Endian endianness) =>
      bytes.getFloat64(offset - start, endianness);

  @override
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
          .then((actualLength) => BlobView._(blob, actualLength));
    return BlobView._(blob, length);
  }

  BlobView._(this.blob, this.byteLength);

  final int byteLength;

  Future<ByteData> getBytes(int start, int end) async {
    if (_lastCacheView.containsRange(start, end))
      return Future.value(_lastCacheView.getBytes(start, end));
    int realEnd = end;
    if (start + _pageSize > realEnd) realEnd = start + _pageSize;
    CacheView view = await _retrieve(start, realEnd);
    return view.getBytes(start, end);
  }

  Future<int> getInt32(int offset, [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 4))
      return Future.value(_lastCacheView.getInt32(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getInt32(offset, endianness);
  }

  Future<int> getUint32(int offset, [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 4))
      return Future.value(_lastCacheView.getUint32(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getUint32(offset, endianness);
  }

  Future<int> getUint16(int offset, [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 2))
      return Future.value(_lastCacheView.getUint16(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getUint16(offset, endianness);
  }

  Future<int> getUint8(int offset) async {
    if (_lastCacheView.contains(offset))
      return Future.value(_lastCacheView.getUint8(offset));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getUint8(offset);
  }

  Future<double> getFloat32(int offset,
      [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 4))
      return Future.value(_lastCacheView.getFloat32(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getFloat32(offset, endianness);
  }

  Future<double> getFloat64(int offset,
      [Endian endianness = Endian.big]) async {
    if (_lastCacheView.containsRange(offset, offset + 8))
      return Future.value(_lastCacheView.getFloat64(offset, endianness));
    CacheView view = await _retrieve(offset, offset + _pageSize);
    return view.getFloat64(offset, endianness);
  }

  FutureOr<CacheView> _retrieve(int start, int end) {
    FutureOr<ByteData> bytes = blob.readSlice(start, end);
    if (bytes is Future<ByteData>) {
      Future<ByteData> bytesFuture = bytes;
      return bytesFuture.then((actualBytes) => CacheView(start, actualBytes));
    }
    return CacheView(start, bytes);
  }

  final AbstractBlobReader blob;
  CacheView _lastCacheView = CacheView(0, null);

  static const int _pageSize = 4096;
}
