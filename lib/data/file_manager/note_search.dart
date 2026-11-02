/// Finding notes by title and listing the most recently edited notes,
/// for the search and latest views of the browse page.
abstract final class NoteSearch {
  /// How many notes the latest view shows.
  static const latestLimit = 60;

  static const _diacritics = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'ą': 'a',
    'ć': 'c',
    'č': 'c',
    'ç': 'c',
    'ď': 'd',
    'đ': 'd',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'ě': 'e',
    'ę': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ł': 'l',
    'ľ': 'l',
    'ñ': 'n',
    'ń': 'n',
    'ň': 'n',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ø': 'o',
    'ő': 'o',
    'ř': 'r',
    'ś': 's',
    'š': 's',
    'ß': 'ss',
    'ť': 't',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ů': 'u',
    'ű': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'ź': 'z',
    'ż': 'z',
    'ž': 'z',
  };

  /// Lower-cases [text] and strips common diacritics,
  /// so that "cas" finds "Čas".
  static String normalize(String text) {
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (final char in lower.split('')) {
      buffer.write(_diacritics[char] ?? char);
    }
    return buffer.toString();
  }

  /// The title of the note at [filePath], i.e. its file name.
  static String title(String filePath) =>
      filePath.substring(filePath.lastIndexOf('/') + 1);

  /// Whether the title of [filePath] contains every word of [query],
  /// ignoring case and diacritics.
  static bool matches(String filePath, String query) {
    final words = normalize(query)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    if (words.isEmpty) return false;
    final normalizedTitle = normalize(title(filePath));
    return words.every(normalizedTitle.contains);
  }

  /// The notes in [filePaths] whose title matches [query],
  /// in the order of [filePaths].
  ///
  /// The browse page passes the notes newest first,
  /// so the results are sorted by the edit time too.
  static List<String> search(Iterable<String> filePaths, String query) =>
      filePaths.where((path) => matches(path, query)).toList();

  /// [filePaths] sorted by the edit time, newest first.
  static List<String> newestFirst(
    Iterable<String> filePaths,
    DateTime Function(String filePath) lastModified,
  ) {
    final dated = [for (final path in filePaths) (path, lastModified(path))];
    dated.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (path, _) in dated) path];
  }
}
