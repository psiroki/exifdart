import "dart:async";
import "dart:typed_data";
import "dart:convert";
import "dart:html";

import "package:exifdart/src/blob_view.dart";
import "package:exifdart/src/log_message_sink.dart";
import "package:exifdart/src/constants.dart";

class Rational {
  Rational(this.numerator, this.denominator);

  double toDouble() => numerator / denominator;

  String toString() => toDouble().toString();

  Map<String, int> toJson() => {
        "numerator": numerator,
        "denominator": denominator,
      };

  final int numerator;
  final int denominator;
}

Future<Map<String, dynamic>> readExifFromBlob(Blob blob, [bool printDebugInfo=false]) {
  return new ExifExtractor(printDebugInfo ? new ConsoleMessageSink() : null)
      .findEXIFinJPEG(new BlobView(blob));
}

class ConsoleMessageSink implements LogMessageSink {
  void log(Object message, [List<Object> additional]) {
    if (message == null) message = "null";
    if (additional != null) message = "${message} ${additional}";
    window.console.log(message);
  }
}

class ExifExtractor {
  ExifExtractor(this.debug);

  Future<Map<String, dynamic>> findEXIFinJPEG(BlobView dataView) async {
    if (debug != null) debug.log("Got file of length ${dataView.byteLength}");
    if ((await dataView.getUint8(0) != 0xFF) ||
        (await dataView.getUint8(1) != 0xD8)) {
      if (debug != null) debug.log("Not a valid JPEG");
      return null; // not a valid jpeg
    }

    int offset = 2;
    int length = dataView.byteLength;
    int marker;

    while (offset < length) {
      int lastValue = await dataView.getUint8(offset);
      if (lastValue != 0xFF) {
        if (debug != null)
          debug.log("Not a valid marker at offset ${offset}, "
              "found: ${lastValue}");
        return null; // not a valid marker, something is wrong
      }

      marker = await dataView.getUint8(offset + 1);
      if (debug != null) debug.log(marker);

      // we could implement handling for other markers here,
      // but we're only looking for 0xFFE1 for EXIF data

      if (marker == 225) {
        if (debug != null) debug.log("Found 0xFFE1 marker");

        return readEXIFData(dataView, offset + 4);

        // offset += 2 + file.getShortAt(offset+2, true);

      } else {
        offset += 2 + await dataView.getUint16(offset + 2);
      }
    }

    return null;
  }

  Future<Object> findIPTCinJPEG(BlobView dataView) async {
    if (debug != null) debug.log("Got file of length ${dataView.byteLength}");
    if ((await dataView.getUint8(0) != 0xFF) ||
        (await dataView.getUint8(1) != 0xD8)) {
      if (debug != null) debug.log("Not a valid JPEG");
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
      int dirStart, Map<int, String> strings, Endianness bigEnd) async {
    int entries = await file.getUint16(dirStart, bigEnd);
    Map<String, dynamic> tags = {};
    int entryOffset;

    for (int i = 0; i < entries; i++) {
      entryOffset = dirStart + i * 12 + 2;
      int tagId = await file.getUint16(entryOffset, bigEnd);
      String tag = strings[tagId];
      if (tag == null && debug != null) debug.log("Unknown tag: ${tagId}");
      if (tag != null) {
        tags[tag] =
            await readTagValue(file, entryOffset, tiffStart, dirStart, bigEnd);
      }
    }
    return tags;
  }

  Future<dynamic> readTagValue(BlobView file, int entryOffset, int tiffStart,
      int dirStart, Endianness bigEnd) async {
    int type = await file.getUint16(entryOffset + 2, bigEnd);
    int numValues = await file.getUint32(entryOffset + 4, bigEnd);
    int valueOffset = await file.getUint32(entryOffset + 8, bigEnd) + tiffStart;

    switch (type) {
      case 1: // byte, 8-bit unsigned int
      case 7: // undefined, 8-bit byte, value depending on field
        if (numValues == 1) {
          return file.getUint8(entryOffset + 8);
        } else {
          int offset = numValues > 4 ? valueOffset : (entryOffset + 8);
          ByteData bytes = await file.getBytes(offset, offset + numValues);
          Uint8List result = new Uint8List(numValues);
          for (int i = 0; i < result.length; ++i) result[i] = bytes.getUint8(i);
          return result;
        }
        break;
      case 2: // ascii, 8-bit byte
        int offset = numValues > 4 ? valueOffset : (entryOffset + 8);
        return getStringFromDB(file, offset, numValues - 1);

      case 3: // short, 16 bit int
        if (numValues == 1) {
          return file.getUint16(entryOffset + 8, bigEnd);
        } else {
          int offset = numValues > 2 ? valueOffset : (entryOffset + 8);
          ByteData bytes = await file.getBytes(offset, offset + 2 * numValues);
          Uint16List result = new Uint16List(numValues);
          for (int i = 0; i < result.length; ++i)
            result[i] = bytes.getUint16(i * 2, bigEnd);
          return result;
        }

        break;

      case 4: // long, 32 bit int
        if (numValues == 1) {
          return file.getUint32(entryOffset + 8, bigEnd);
        } else {
          int offset = valueOffset;
          ByteData bytes = await file.getBytes(offset, offset + 4 * numValues);
          Uint32List result = new Uint32List(numValues);
          for (int i = 0; i < result.length; ++i)
            result[i] = bytes.getUint32(i * 4, bigEnd);
          return result;
        }
        break;
      case 5: // rational = two long values, first is numerator, second is denominator
        if (numValues == 1) {
          int numerator = await file.getUint32(valueOffset, bigEnd);
          int denominator = await file.getUint32(valueOffset + 4, bigEnd);
          return new Rational(numerator, denominator);
        } else {
          int offset = valueOffset;
          ByteData bytes = await file.getBytes(offset, offset + 8 * numValues);
          List<Rational> result = new List(numValues);
          for (int i = 0; i < result.length; ++i) {
            int numerator = bytes.getUint32(i * 8, bigEnd);
            int denominator = bytes.getUint32(i * 8 + 4, bigEnd);
            result[i] = new Rational(numerator, denominator);
          }
          return result;
        }
        break;
      case 9: // slong, 32 bit signed int
        if (numValues == 1) {
          return file.getInt32(entryOffset + 8, bigEnd);
        } else {
          int offset = valueOffset;
          ByteData bytes = await file.getBytes(offset, offset + 4 * numValues);
          Int32List result = new Int32List(numValues);
          for (int i = 0; i < result.length; ++i)
            result[i] = bytes.getInt32(i * 4, bigEnd);
          return result;
        }
        break;
      case 10: // signed rational, two slongs, first is numerator, second is denominator
        if (numValues == 1) {
          int numerator = await file.getInt32(valueOffset, bigEnd);
          int denominator = await file.getInt32(valueOffset + 4, bigEnd);
          return new Rational(numerator, denominator);
        } else {
          int offset = valueOffset;
          ByteData bytes = await file.getBytes(offset, offset + 8 * numValues);
          List<Rational> result = new List(numValues);
          for (int i = 0; i < result.length; ++i) {
            int numerator = bytes.getInt32(i * 8, bigEnd);
            int denominator = bytes.getInt32(i * 8 + 4, bigEnd);
            result[i] = new Rational(numerator, denominator);
          }
          return result;
        }
    }
  }

  Future<String> getStringFromDB(BlobView buffer, int start, int length) async {
    ByteData bytes = await buffer.getBytes(start, start + length);
    return UTF8.decode(new List.generate(length, (int i) => bytes.getUint8(i)),
        allowMalformed: true);
  }

  Future<Map<String, dynamic>> readEXIFData(BlobView file, int start) async {
    String startingString = await getStringFromDB(file, start, 4);
    if (startingString != "Exif") {
      if (debug != null) debug.log("Not valid EXIF data! ${startingString}");
      return null;
    }

    Endianness bigEnd;
    int tiffOffset = start + 6;

    // test for TIFF validity and endianness
    if (await file.getUint16(tiffOffset) == 0x4949) {
      bigEnd = Endianness.LITTLE_ENDIAN;
    } else if (await file.getUint16(tiffOffset) == 0x4D4D) {
      bigEnd = Endianness.BIG_ENDIAN;
    } else {
      if (debug != null)
        debug.log("Not valid TIFF data! (no 0x4949 or 0x4D4D)");
      return null;
    }

    if (await file.getUint16(tiffOffset + 2, bigEnd) != 0x002A) {
      if (debug != null) debug.log("Not valid TIFF data! (no 0x002A)");
      return null;
    }

    int firstIFDOffset = await file.getUint32(tiffOffset + 4, bigEnd);

    if (firstIFDOffset < 0x00000008) {
      if (debug != null)
        debug.log(
            "Not valid TIFF data! (First offset less than 8) ${firstIFDOffset}");
      return null;
    }

    Map<String, dynamic> tags = await readTags(file, tiffOffset,
        tiffOffset + firstIFDOffset, ExifConstants.tiffTags, bigEnd);

    if (tags.containsKey("ExifIFDPointer")) {
      Map<String, dynamic> exifData = await readTags(file, tiffOffset,
          tiffOffset + tags["ExifIFDPointer"], ExifConstants.tags, bigEnd);
      for (String tag in exifData.keys) {
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
            exifData[tag] = ExifConstants.stringValues[tag][exifData[tag]];
            break;

          case "ExifVersion":
          case "FlashpixVersion":
            exifData[tag] =
                UTF8.decode((exifData[tag] as List<int>).sublist(0, 4));
            break;

          case "ComponentsConfiguration":
            exifData[tag] = ExifConstants.stringValues["Components"]
                    [exifData[tag][0]] +
                ExifConstants.stringValues["Components"][exifData[tag][1]] +
                ExifConstants.stringValues["Components"][exifData[tag][2]] +
                ExifConstants.stringValues["Components"][exifData[tag][3]];
            break;
        }
        tags[tag] = exifData[tag];
      }
    }

    if (tags.containsKey("GPSInfoIFDPointer")) {
      Map<String, dynamic> gpsData = await readTags(
          file,
          tiffOffset,
          tiffOffset + tags["GPSInfoIFDPointer"],
          ExifConstants.gpsTags,
          bigEnd);
      for (String tag in gpsData.keys) {
        switch (tag) {
          case "GPSVersionID":
            List version = gpsData[tag] as List;
            gpsData[tag] = version.join(".");
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
          String fieldName = ExifConstants.iptcFieldMap[segmentType];
          String fieldValue =
              await getStringFromDB(dataView, segmentStartPos + 5, dataSize);
          // Check if we already stored a value with this name
          if (data.containsKey(fieldName)) {
            // Value already stored with this name, create multivalue field
            if (data[fieldName] is List) {
              (data[fieldName] as List<String>).add(fieldValue);
            } else {
              data[fieldName] = <String>[data[fieldName], fieldValue];
            }
          } else {
            data[fieldName] = fieldValue;
          }
        }
      }
      segmentStartPos++;
    }
    return data;
  }

  final LogMessageSink debug;
}
