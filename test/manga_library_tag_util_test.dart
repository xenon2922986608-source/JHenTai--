import 'package:test/test.dart';
import 'package:jhentai/src/utils/manga_library_tag_util.dart';

void main() {
  test('buildEhSearchQueryFromLibraryTitle removes leading numeric ids and noisy language markers', () {
    for (final sample in mangaLibraryTagFillSearchQuerySamples) {
      expect(buildEhSearchQueryFromLibraryTitle(sample.input), sample.output);
    }
  });
}
