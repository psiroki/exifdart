import "dart:async";
import "dart:typed_data";
import "dart:convert";

import "abstract_reader.dart";
import "log_message_sink.dart";
import "constants.dart";
import "blob_view.dart";

/// Represents a rational number: the fraction of two integers
class Rational {
  /// Initializes the rational number with the given numerator
  /// and denominator
  Rational(this.numerator, this.denominator);

  /// Converts the rational number to `double`
  double toDouble() => numerator / denominator;

  @override
  String toString() => toDouble().toString();

  /// Converts the object to a JSON encodable map
  Map<String, int> toJson() => {
        "numerator": numerator,
        "denominator": denominator,
      };

  /// The numerator part of the fraction
  final int numerator;

  /// The denominator part of the fraction
  final int denominator;
}

/// Reads the EXIF info from the given [blob] reader.
Future<Map<String, dynamic>?> readExif(AbstractBlobReader blob,
    {bool printDebugInfo = false}) async {
  return ExifExtractor(printDebugInfo ? ConsoleMessageSink() : null)
      .findEXIFinJPEG(await BlobView.create(blob));
}

class ConsoleMessageSink implements LogMessageSink {
  @override
  void log(Object? message, [List<Object>? additional]) {
    if (message == null) message = "null";
    if (additional != null) message = "${message} ${additional}";
    print(message);
  }
}

class ExifExtractor {
  ExifExtractor(this.debug);

  Future<Map<String, dynamic>?> findEXIFinJPEG(BlobView dataView) async {
    debug?.log("Got file of length ${dataView.byteLength}");
    if ((await dataView.getUint8(0) != 0xFF) ||
        (await dataView.getUint8(1) != 0xD8)) {
      debug?.log("Not a valid JPEG");
      return null; // not a valid jpeg
    }

    int offset = 2;
    int length = dataView.byteLength;
    int marker;

    while (offset < length) {
      int lastValue = await dataView.getUint8(offset);
      if (lastValue != 0xFF) {
        debug?.log("Not a valid marker at offset ${offset}, "
            "found: ${lastValue}");
        return null; // not a valid marker, something is wrong
      }

      marker = await dataView.getUint8(offset + 1);
      debug?.log(marker);

      // we could implement handling for other markers here,
      // but we're only looking for 0xFFE1 for EXIF data

      if (marker == 225) {
        debug?.log("Found 0xFFE1 marker");

        return readEXIFData(dataView, offset + 4);

        // offset += 2 + file.getShortAt(offset+2, true);

      } else {
        offset += 2 + await dataView.getUint16(offset + 2);
      }
    }

    return null;
  }

  Future<Object?> findIPTCinJPEG(BlobView dataView) async {
    debug?.log("Got file of length ${dataView.byteLength}");
    if ((await dataView.getUint8(0) != 0xFF) ||
        (await dataView.getUint8(1) != 0xD8)) {
      debug?.log("Not a valid JPEG");
      return null; // not a valid jpeg
    }

    int offset = 2, length = dataView.byteLength;

    const List<int> segmentStartBytes = const [
      0x38,
      0x42,
      0x49,
      0x4D,
      0x04,
      0x04
    ];

    Future<bool> isFieldSegmentStart(BlobView dataView, int offset) async {
      ByteData data = await dataView.getBytes(offset, offset + 6);
      for (int i = 0; i < 6; ++i) {
        if (data.getUint8(i) != segmentStartBytes[i]) return false;
      }
      return true;
    }

    while (offset < length) {
      if (await isFieldSegmentStart(dataView, offset)) {
        // Get the length of the name header (which is padded to an even number of bytes)
        int nameHeaderLength = await dataView.getUint8(offset + 7);
        if (nameHeaderLength % 2 != 0) nameHeaderLength += 1;
        // Check for pre photoshop 6 format
        if (nameHeaderLength == 0) {
          // Always 4
          nameHeaderLength = 4;
        }

        int startOffset = offset + 8 + nameHeaderLength;
        int sectionLength =
            await dataView.getUint16(offset + 6 + nameHeaderLength);

        return readIPTCData(dataView, startOffset, sectionLength);
      }

      // Not the marker, continue searching
      offset++;
    }

    return null;
  }

  Future<Map<String, dynamic>> readTags(BlobView file, int tiffStart,
      int dirStart, Map<int, String> strings, Endian bigEnd) async {
    int entries = await file.getUint16(dirStart, bigEnd);
    Map<String, dynamic> tags = {};
    int entryOffset;

    for (int i = 0; i < entries; i++) {
      entryOffset = dirStart + i * 12 + 2;
      int tagId = await file.getUint16(entryOffset, bigEnd);
      String? tag = strings[tagId];
      if (tag == null) debug?.log("Unknown tag: ${tagId}");
      if (tag != null) {
        tags[tag] =
            await readTagValue(file, entryOffset, tiffStart, dirStart, bigEnd);
      }
    }
    return tags;
  }

  Future<dynamic> readTagValue(BlobView file, int entryOffset, int tiffStart,
      int dirStart, Endian bigEnd) async {
    int type = await file.getUint16(entryOffset + 2, bigEnd);
    int numValues = await file.getUint32(entryOffset + 4, bigEnd);
    int valueOffset = await file.getUint32(entryOffset + 8, bigEnd) + tiffStart;

    switch (type) {
      case 1: // byte, 8-bit unsigned int
      case 7: // undefined, 8-bit byte, value depending on field
        if (numValues == 1) {
          return file.getUint8(entryOffset + 8);
        }

        int offset = numValues > 4 ? valueOffset : (entryOffset + 8);
        ByteData bytes = await file.getBytes(offset, offset + numValues);
        Uint8List result = Uint8List(numValues);
        for (int i = 0; i < result.length; ++i) result[i] = bytes.getUint8(i);
        return result;

      case 2: // ascii, 8-bit byte
        int offset = numValues > 4 ? valueOffset : (entryOffset + 8);
        return getStringFromDB(file, offset, numValues - 1);

      case 3: // short, 16 bit int
        if (numValues == 1) {
          return file.getUint16(entryOffset + 8, bigEnd);
        }

        int offset = numValues > 2 ? valueOffset : (entryOffset + 8);
        ByteData bytes = await file.getBytes(offset, offset + 2 * numValues);
        Uint16List result = Uint16List(numValues);
        for (int i = 0; i < result.length; ++i)
          result[i] = bytes.getUint16(i * 2, bigEnd);
        return result;

      case 4: // long, 32 bit int
        if (numValues == 1) {
          return file.getUint32(entryOffset + 8, bigEnd);
        }

        int offset = valueOffset;
        ByteData bytes = await file.getBytes(offset, offset + 4 * numValues);
        Uint32List result = Uint32List(numValues);
        for (int i = 0; i < result.length; ++i)
          result[i] = bytes.getUint32(i * 4, bigEnd);
        return result;

      case 5: // rational = two long values, first is numerator, second is denominator
        if (numValues == 1) {
          int numerator = await file.getUint32(valueOffset, bigEnd);
          int denominator = await file.getUint32(valueOffset + 4, bigEnd);
          return Rational(numerator, denominator);
        }

        int offset = valueOffset;
        ByteData bytes = await file.getBytes(offset, offset + 8 * numValues);
        List<Rational?> result = List.filled(numValues, null);
        for (int i = 0; i < result.length; ++i) {
          int numerator = bytes.getUint32(i * 8, bigEnd);
          int denominator = bytes.getUint32(i * 8 + 4, bigEnd);
          result[i] = Rational(numerator, denominator);
        }
        return result;

      case 9: // slong, 32 bit signed int
        if (numValues == 1) {
          return file.getInt32(entryOffset + 8, bigEnd);
        }

        int offset = valueOffset;
        ByteData bytes = await file.getBytes(offset, offset + 4 * numValues);
        Int32List result = Int32List(numValues);
        for (int i = 0; i < result.length; ++i)
          result[i] = bytes.getInt32(i * 4, bigEnd);
        return result;

      case 10: // signed rational, two slongs, first is numerator, second is denominator
        if (numValues == 1) {
          int numerator = await file.getInt32(valueOffset, bigEnd);
          int denominator = await file.getInt32(valueOffset + 4, bigEnd);
          return Rational(numerator, denominator);
        }

        int offset = valueOffset;
        ByteData bytes = await file.getBytes(offset, offset + 8 * numValues);
        List<Rational?> result = List.filled(numValues, null);
        for (int i = 0; i < result.length; ++i) {
          int numerator = bytes.getInt32(i * 8, bigEnd);
          int denominator = bytes.getInt32(i * 8 + 4, bigEnd);
          result[i] = Rational(numerator, denominator);
        }
        return result;

      case 11: // single float, 32 bit float
        if (numValues == 1) {
          return file.getFloat32(entryOffset + 8, bigEnd);
        }

        int offset = valueOffset;
        ByteData bytes = await file.getBytes(offset, offset + 4 * numValues);
        Float32List result = Float32List(numValues);
        for (int i = 0; i < result.length; ++i)
          result[i] = bytes.getFloat32(i * 4, bigEnd);
        return result;

      case 12: // double float, 64 bit float
        if (numValues == 1) {
          return file.getFloat64(entryOffset + 8, bigEnd);
        }

        int offset = valueOffset;
        ByteData bytes = await file.getBytes(offset, offset + 8 * numValues);
        Float64List result = Float64List(numValues);
        for (int i = 0; i < result.length; ++i)
          result[i] = bytes.getFloat64(i * 8, bigEnd);
        return result;
    }
  }

  Future<String> getStringFromDB(BlobView buffer, int start, int length) async {
    ByteData bytes = await buffer.getBytes(start, start + length);
    return utf8.decode(List.generate(length, (int i) => bytes.getUint8(i)),
        allowMalformed: true);
  }

  Future<Map<String, dynamic>?> readEXIFData(BlobView file, int start) async {
    String startingString = await getStringFromDB(file, start, 4);
    if (startingString != "Exif") {
      debug?.log("Not valid EXIF data! ${startingString}");
      return null;
    }

    Endian bigEnd;
    int tiffOffset = start + 6;

    // test for TIFF validity and endianness
    if (await file.getUint16(tiffOffset) == 0x4949) {
      bigEnd = Endian.little;
    } else if (await file.getUint16(tiffOffset) == 0x4D4D) {
      bigEnd = Endian.big;
    } else {
      debug?.log("Not valid TIFF data! (no 0x4949 or 0x4D4D)");
      return null;
    }

    if (await file.getUint16(tiffOffset + 2, bigEnd) != 0x002A) {
      debug?.log("Not valid TIFF data! (no 0x002A)");
      return null;
    }

    int firstIFDOffset = await file.getUint32(tiffOffset + 4, bigEnd);

    if (firstIFDOffset < 0x00000008) {
      debug?.log(
          "Not valid TIFF data! (First offset less than 8) ${firstIFDOffset}");
      return null;
    }

    Map<String, dynamic> tags = await readTags(file, tiffOffset,
        tiffOffset + firstIFDOffset, ExifConstants.tiffTags, bigEnd);

    if (tags.containsKey("ExifIFDPointer")) {
      Map<String, dynamic> exifData = await readTags(
          file,
          tiffOffset,
          (tiffOffset + tags["ExifIFDPointer"]).toInt(),
          ExifConstants.tags,
          bigEnd);
      for (String tag in exifData.keys) {
        dynamic value = exifData[tag];
        switch (tag) {
          case "LightSource":
          case "Flash":
          case "MeteringMode":
          case "ExposureProgram":
          case "SensingMethod":
          case "SceneCaptureType":
          case "SceneType":
          case "CustomRendered":
          case "WhiteBalance":
          case "GainControl":
          case "Contrast":
          case "Saturation":
          case "Sharpness":
          case "SubjectDistanceRange":
          case "FileSource":
            exifData[tag] = ExifConstants.stringValues[tag]![value];
            break;

          case "ExifVersion":
          case "FlashpixVersion":
            if (value is List<int> && value.length >= 4) {
              exifData[tag] = utf8.decode((value).sublist(0, 4));
            }
            break;

          case "ComponentsConfiguration":
            exifData[tag] = Iterable.generate(4, (i) => value[i])
                .map((index) =>
                    ExifConstants.stringValues["Components"]![index] ?? "")
                .join("");
            break;
        }
        tags[tag] = exifData[tag];
      }
    }

    if (tags.containsKey("GPSInfoIFDPointer")) {
      Map<String, dynamic> gpsData = await readTags(
          file,
          tiffOffset,
          (tiffOffset + tags["GPSInfoIFDPointer"]).toInt(),
          ExifConstants.gpsTags,
          bigEnd);
      for (String tag in gpsData.keys) {
        switch (tag) {
          case "GPSVersionID":
            var data = gpsData[tag];
            if (data is List) {
              gpsData[tag] = data.join(".");
            } else {
              gpsData[tag] = data?.toString();
            }
            break;
        }
        tags[tag] = gpsData[tag];
      }
    }

    return tags;
  }

  Future<Map<String, dynamic>> readIPTCData(
      BlobView dataView, int startOffset, int sectionLength) async {
    Map<String, dynamic> data = {};
    int segmentStartPos = startOffset;
    while (segmentStartPos < startOffset + sectionLength) {
      ByteData bytes =
          await dataView.getBytes(segmentStartPos, segmentStartPos + 5);
      if (bytes.getUint8(0) == 0x1C && bytes.getUint8(1) == 0x02) {
        int segmentType = bytes.getUint8(2);
        if (ExifConstants.iptcFieldMap.containsKey(segmentType)) {
          int dataSize = bytes.getInt16(3);
          String? fieldName = ExifConstants.iptcFieldMap[segmentType];
          String fieldValue =
              await getStringFromDB(dataView, segmentStartPos + 5, dataSize);
          // Check if we already stored a value with this name
          if (data.containsKey(fieldName)) {
            // Value already stored with this name, create multivalue field
            if (data[fieldName] is List) {
              (data[fieldName] as List<String>).add(fieldValue);
            } else {
              data[fieldName!] = <String>[data[fieldName], fieldValue];
            }
          } else {
            if (fieldName != null) data[fieldName] = fieldValue;
          }
        }
      }
      segmentStartPos++;
    }
    return data;
  }

  final LogMessageSink? debug;
}
