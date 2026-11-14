/// Makes text from a device safe to show and store.
///
/// Device output is untrusted: it can hold terminal control codes (which
/// could rewrite the screen) or be very long. Control characters are
/// removed and the text is cut to [maxLength] characters.
String cleanDeviceText(String text, {int maxLength = 120}) {
  final clean = text.replaceAll(_control, '').trim();
  return clean.length <= maxLength ? clean : clean.substring(0, maxLength);
}

final _control = RegExp(r'[\u0000-\u001F\u007F-\u009F]');
