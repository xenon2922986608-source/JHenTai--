import 'package:test/test.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/utils/manga_library_tag_util.dart';

void main() {
  test('buildEhSearchQueryFromLibraryTitle removes leading numeric ids and noisy language markers', () {
    for (final sample in mangaLibraryTagFillSearchQuerySamples) {
      expect(buildEhSearchQueryFromLibraryTitle(sample.input), sample.output);
    }
  });

  test('normalizes exact title matches after stripping ids and language markers', () {
    expect(
      isExactMangaLibraryTitleMatch(
        '979293 [五識細工 (愛子八千代)] セクシャルディーヴィエントモード (グランブルーファンタジー) [中国 ]',
        '[五識細工 (愛子八千代)] セクシャルディーヴィエントモード (グランブルーファンタジー)',
      ),
      isTrue,
    );
    expect(
      isExactMangaLibraryTitleMatch(
        '3745937-(C107) [フラットプラーク(かぐーら)] 交接条件下、影と生存 (アークナイツ) [中国翻訳]',
        '(C107) [フラットプラーク(かぐーら)] 交接条件下、影と生存 (アークナイツ)',
      ),
      isTrue,
    );
  });

  test('does not treat title containment as exact match', () {
    expect(isExactMangaLibraryTitleMatch('[作者] 标题', '[作者] 标题 extra'), isFalse);
    expect(isExactMangaLibraryTitleMatch('[作者] 标题 extra', '[作者] 标题'), isFalse);
  });

  test('detects Chinese language tags from TagData and string forms', () {
    expect(mangaLibraryTagsContainChineseLanguage([TagData(namespace: 'language', key: 'chinese')]), isTrue);
    expect(mangaLibraryTagsContainChineseLanguage([TagData(namespace: '语言', key: '汉语')]), isTrue);
    expect(mangaLibraryTagsContainChineseLanguage([TagData(namespace: 'language', key: 'translated')]), isFalse);
    expect(mangaLibraryTagStringContainsChineseLanguage('artist:abc,language：chinese'), isTrue);
    expect(mangaLibraryTagStringContainsChineseLanguage('语言：汉语'), isTrue);
  });
}
