import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads standard textual PNG chunks without decoding the image pixels.
class PngMetadataReader {
  const PngMetadataReader();

  Future<Map<String, dynamic>> read(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < 8 ||
        bytes[0] != 0x89 ||
        ascii.decode(bytes.sublist(1, 4), allowInvalid: true) != 'PNG') {
      return const {};
    }

    final result = <String, dynamic>{};
    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getUint32(0, Endian.big);
      final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      if (dataEnd + 4 > bytes.length) break;
      final data = bytes.sublist(dataStart, dataEnd);

      try {
        switch (type) {
          case 'tEXt':
            _readText(data, result);
            break;
          case 'zTXt':
            _readCompressedText(data, result);
            break;
          case 'iTXt':
            _readInternationalText(data, result);
            break;
        }
      } on Exception {
        // A malformed optional metadata chunk must not hide a valid image.
      }
      offset = dataEnd + 4;
      if (type == 'IEND') break;
    }
    return result;
  }

  void _readText(Uint8List data, Map<String, dynamic> result) {
    final separator = data.indexOf(0);
    if (separator < 1) return;
    _store(
      latin1.decode(data.sublist(0, separator)),
      utf8.decode(data.sublist(separator + 1), allowMalformed: true),
      result,
    );
  }

  void _readCompressedText(Uint8List data, Map<String, dynamic> result) {
    final separator = data.indexOf(0);
    if (separator < 1 || separator + 2 > data.length) return;
    final decoded = zlib.decode(data.sublist(separator + 2));
    _store(
      latin1.decode(data.sublist(0, separator)),
      utf8.decode(decoded, allowMalformed: true),
      result,
    );
  }

  void _readInternationalText(Uint8List data, Map<String, dynamic> result) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd < 1 || keywordEnd + 3 >= data.length) return;
    final compressed = data[keywordEnd + 1] == 1;
    var cursor = keywordEnd + 3;
    final languageEnd = data.indexOf(0, cursor);
    if (languageEnd < 0) return;
    cursor = languageEnd + 1;
    final translatedEnd = data.indexOf(0, cursor);
    if (translatedEnd < 0) return;
    cursor = translatedEnd + 1;
    final raw = data.sublist(cursor);
    final decoded = compressed ? zlib.decode(raw) : raw;
    _store(
      utf8.decode(data.sublist(0, keywordEnd), allowMalformed: true),
      utf8.decode(decoded, allowMalformed: true),
      result,
    );
  }

  void _store(String key, String value, Map<String, dynamic> result) {
    result[key] = value;
    if (key.toLowerCase() != 'comment') return;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) result.addAll(decoded);
    } on FormatException {
      // Keep the raw Comment string when it is not JSON.
    }
  }
}
