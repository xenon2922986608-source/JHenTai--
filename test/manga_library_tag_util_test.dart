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
    expect(mangaLibraryTagStringContainsChineseLanguage('[Chinese]'), isTrue);
    expect(mangaLibraryTagStringContainsChineseLanguage('[中国翻訳]'), isTrue);
  });
}

group('structured batch tag fill candidate matching', () {
  MangaLibraryTagFillCandidateInfo chinese(String title) => MangaLibraryTagFillCandidateInfo(title: title, hasChineseLanguage: true);

  test('sample 1 extracts full local title anchors for a short Chinese candidate', () {
    final parts = extractMangaLibraryStructuredTitleParts(
      '1631155-(C97) [slice slime (108 Gou)] Legend of SicoRiesZ (Seiken Densetsu 3) [Chinese] [佚名机翻]',
    );
    expect(parts.leadingId, '1631155');
    expect(parts.event, 'C97');
    expect(parts.circle, 'slice slime');
    expect(parts.artist, '108 Gou');
    expect(parts.mainTitle, 'Legend of SicoRiesZ');
    expect(parts.parody, 'Seiken Densetsu 3');

    final decision = selectMangaLibraryTagFillCandidate(
      localTitle: parts.original,
      candidates: [chinese('Legend of SicoRiesZ')],
    );
    expect(decision.isSuccess, isTrue);
    expect(decision.status, 'success_single_result_anchor');
  });

  test('sample 2 matches circle with equivalent Chinese/Digital markers', () {
    final decision = selectMangaLibraryTagFillCandidate(
      localTitle: '1508201-[Maniac Street (すがいし)] イケニエネイビー [中国翻訳] [DL版]',
      candidates: [chinese('[Maniac Street (Sugaishi)] Ikenie Navy | 犧牲的海軍藍 [Chinese] [禁漫漢化組] [Digital]')],
    );
    expect(decision.isSuccess, isTrue);
    expect(decision.score, greaterThanOrEqualTo(75));
    expect(decision.reasons, contains('circle_match'));
  });

  test('sample 3 matches artist and Pokémon Legends parody aliases', () {
    final decision = selectMangaLibraryTagFillCandidate(
      localTitle: '2299805-[白ネギ屋 (miya9)] ヒスイ転生録 (Pokémon LEGENDS アルセウス) [中国翻訳] [DL版]',
      candidates: [chinese('[Shironegiya (miya9)] Hisui Tensei-roku (Pokémon Legends: Arceus) [Chinese] [绅士仓库汉化] [Digital]')],
    );
    expect(decision.isSuccess, isTrue);
    expect(decision.status, 'success_high_confidence_chinese');
    expect(decision.reasons, contains('artist_match'));
    expect(decision.reasons, contains('parody_match'));
  });

  test('sample 4 matches Salt Peanuts and Clean Me Softly', () {
    final decision = selectMangaLibraryTagFillCandidate(
      localTitle: '3838522-[Salt Peanuts (にえあ)] Clean Me Softly (綺麗にしてもらえますか。) [Chinese] [XX漢化]',
      candidates: [chinese('[Salt Peanuts (Niea)] Clean Me Softly (Kirei ni Shite moraemasu ka.) [Chinese] [暴碧汉化组] [Digital]')],
    );
    expect(decision.isSuccess, isTrue);
    expect(decision.reasons, contains('circle_match'));
    expect(decision.reasons, contains('main_title_match'));
  });

  test('sample 5 matches BLACK DOG, ATUM, and normalized dates', () {
    final decision = selectMangaLibraryTagFillCandidate(
      localTitle: '1038494-[BLACK DOG (黒犬獣)] ATUM (スクールランブル) [中国翻訳] [2005年6月21日]',
      candidates: [chinese('[BLACK DOG (Kuroinu Juu)] ATUM (School Rumble) [Chinese] [2005-06-21]')],
    );
    expect(decision.isSuccess, isTrue);
    expect(decision.reasons, contains('date_match'));
  });

  test('sample 6 matches English core title and season/chapter ranges', () {
    final decision = selectMangaLibraryTagFillCandidate(
      localTitle: '3888593 - [Dr  Stein] 吸烟洗脑 s2 19(Smoking Hypnosis)(催眠烟)',
      candidates: [chinese('Smoking Hypnosis Season 2 ch.1-19 【Chinese】')],
    );
    expect(decision.isSuccess, isTrue);
    expect(decision.reasons, contains('chapter_or_season_match'));
  });

  test('sample 7 allows risky circle/artist-only match only for a single result', () {
    final local = '3541440 - (C106) [Dokudami (Okita Ababa)] Manadeshi ga Touzoku ni Netorareta Hanashi + Paper C1';
    final candidate = chinese('(C103) [Dokudami (Okita Ababa)] Boku no Shishou ga Kanemochi no Ijimekko ni NTRreta Hanashi [Chinese] [流木个人汉化]');
    final single = selectMangaLibraryTagFillCandidate(localTitle: local, candidates: [candidate]);
    expect(single.isSuccess, isTrue);
    expect(single.matchLevel, 'low_confidence_single_result');

    final multi = selectMangaLibraryTagFillCandidate(localTitle: local, candidates: [candidate, chinese('[Dokudami (Okita Ababa)] Another Title [Chinese]')]);
    expect(multi.isSuccess, isFalse);
    expect(multi.status, anyOf('skipped_title_conflict', 'skipped_multiple_chinese', 'skipped_low_score'));
  });

  test('sample 8 penalizes missing volume and skips ambiguous 1/2/3 Chinese series', () {
    final local = '2299805-[白ネギ屋 (miya9)] ヒスイ転生録 (Pokémon LEGENDS アルセウス) [中国翻訳] [DL版]';
    final single = selectMangaLibraryTagFillCandidate(
      localTitle: local,
      candidates: [chinese('[Shironegiya (miya9)] Hisui Tensei-roku 3 (Pokémon Legends: Arceus) [Chinese] [绅士仓库汉化] [Digital]')],
    );
    expect(single.isSuccess, isTrue);
    expect(single.reasons, contains('volume_mismatch_penalty'));

    final multi = selectMangaLibraryTagFillCandidate(
      localTitle: local,
      candidates: [
        chinese('[Shironegiya (miya9)] Hisui Tensei-roku 1 (Pokémon Legends: Arceus) [Chinese]'),
        chinese('[Shironegiya (miya9)] Hisui Tensei-roku 2 (Pokémon Legends: Arceus) [Chinese]'),
        chinese('[Shironegiya (miya9)] Hisui Tensei-roku 3 (Pokémon Legends: Arceus) [Chinese]'),
      ],
    );
    expect(multi.isSuccess, isFalse);
    expect(multi.status, 'skipped_volume_conflict');
  });

  test('sample 9 does not match multi-result Jury candidates by author and Chinese marker only', () {
    final local = '3035652 - [Jury] Meushi ni Sarechau Madoushi-chan [Chinese] [AKwoL汉化组]';
    final candidate = chinese('[Jury] Haraiya-san wa Haramibukuro ni Nanka Sarenai + Haraiya-san wa Haramibukuro ni Nanka Sarenai Haiboku Route Ban [Chinese] [AKwoL烤肉组]');
    final single = selectMangaLibraryTagFillCandidate(localTitle: local, candidates: [candidate]);
    expect(single.isSuccess, isTrue);
    expect(single.matchLevel, 'low_confidence_single_result');

    final multi = selectMangaLibraryTagFillCandidate(localTitle: local, candidates: [candidate, chinese('[Jury] Different Title [Chinese]')]);
    expect(multi.isSuccess, isFalse);
    expect(multi.status, anyOf('skipped_title_conflict', 'skipped_multiple_chinese', 'skipped_low_score'));
  });
});
