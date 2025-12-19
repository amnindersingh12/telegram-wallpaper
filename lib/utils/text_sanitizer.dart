String sanitizeText(String? text) {
  if (text == null || text.isEmpty) return '';

  final codeUnits = text.codeUnits;
  final buffer = StringBuffer();

  for (int i = 0; i < codeUnits.length; i++) {
    final unit = codeUnits[i];

    // High surrogate
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 < codeUnits.length) {
        final next = codeUnits[i + 1];
        // Valid low surrogate follows
        if (next >= 0xDC00 && next <= 0xDFFF) {
          buffer.writeCharCode(unit);
          buffer.writeCharCode(next);
          i++; // Skip the low surrogate
          continue;
        }
      }

      // Unpaired high surrogate: drop it
      continue;
    }

    // Unpaired low surrogate: drop it
    if (unit >= 0xDC00 && unit <= 0xDFFF) {
      continue;
    }

    buffer.writeCharCode(unit);
  }

  return buffer.toString();
}
