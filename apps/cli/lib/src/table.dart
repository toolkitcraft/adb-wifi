/// Formats rows as aligned columns, two spaces apart, for the terminal.
String table(List<String> headers, List<List<String>> rows) {
  final widths = [
    for (var c = 0; c < headers.length; c++)
      [
        headers[c],
        for (final r in rows) r[c],
      ].map((cell) => cell.length).reduce((a, b) => a > b ? a : b),
  ];
  String line(List<String> cells) => [
    for (var c = 0; c < cells.length; c++)
      c == cells.length - 1
          ? cells[c]
          : cells[c] + ' ' * (widths[c] - displayWidth(cells[c])),
  ].join('  ').trimRight();
  return [line(headers), for (final r in rows) line(r)].join('\n');
}

/// Terminal columns used by [text]: emoji take two, the emoji variation
/// selector takes none, everything else one.
int displayWidth(String text) {
  var width = 0;
  for (final rune in text.runes) {
    if (rune == 0xFE0F) continue;
    width += rune >= 0x1F300 || (rune >= 0x2600 && rune <= 0x27BF) ? 2 : 1;
  }
  return width;
}
