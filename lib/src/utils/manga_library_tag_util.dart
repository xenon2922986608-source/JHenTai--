import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/enum/eh_namespace.dart';


const Map<String, String> mangaLibraryChineseNamespaceAliases = {
  '语言': 'language',
  '語言': 'language',
  '女性': 'female',
  '男性': 'male',
  '角色': 'character',
  '原作': 'parody',
  '作者': 'artist',
  '团体': 'group',
  '團體': 'group',
  '社团': 'group',
  '社團': 'group',
  '其他': 'other',
  '混杂': 'misc',
  '混雜': 'misc',
  '杂项': 'misc',
  '雜項': 'misc',
};

const List<({String input, String output})> mangaLibraryTagFillSearchQuerySamples = [
  (
    input: '979293 [五識細工 (愛子八千代)] セクシャルディーヴィエントモード (グランブルーファンタジー) [中国 ]',
    output: '[五識細工 (愛子八千代)] セクシャルディーヴィエントモード (グランブルーファンタジー)',
  ),
  (
    input: '3745937-(C107) [フラットプラーク(かぐーら)] 交接条件下、影と生存 (アークナイツ) [中国翻訳]',
    output: '(C107) [フラットプラーク(かぐーら)] 交接条件下、影と生存 (アークナイツ)',
  ),
  (input: '3745937 - [作者] 标题 [Chinese]', output: '[作者] 标题'),
  (input: '3745937_[作者] 标题 [Digital]', output: '[作者] 标题'),
  (input: '3745937【作者】标题 [AI Generated]', output: '【作者】标题'),
];

String buildEhSearchQueryFromLibraryTitle(String title) {
  return cleanMangaLibraryTitleForTagFill(title);
}

String cleanMangaLibraryTitleForTagFill(String title) {
  return _cleanupMangaLibraryTitle(title, keepSearchPunctuation: true);
}

String normalizeMangaLibraryTitleForExactMatch(String title) {
  return _cleanupMangaLibraryTitle(title, keepSearchPunctuation: false)
      .toLowerCase()
      .replaceAll(RegExp(r'^[\s\-＿_.,，。!！?？:：;；/\\|·・~～]+|[\s\-＿_.,，。!！?？:：;；/\\|·・~～]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool isExactMangaLibraryTitleMatch(String localTitle, String candidateTitle) {
  String local = normalizeMangaLibraryTitleForExactMatch(localTitle);
  String candidate = normalizeMangaLibraryTitleForExactMatch(candidateTitle);
  return local.isNotEmpty && local == candidate;
}

String _cleanupMangaLibraryTitle(String title, {required bool keepSearchPunctuation}) {
  String value = title.replaceAll('　', ' ').trim();
  value = _removeLeadingNumericId(value);
  value = value
      .replaceAll(
        RegExp(
          r'[\[【]\s*(?:中国|中國|中国語|中國語|中国翻訳|中國翻譯|中文|無修正|无修正|chinese|digital|uncensored|ai generated|english|japanese|korean|translated|translation)\s*[\]】]',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'[\(（]\s*(?:中国|中國|中国語|中國語|中国翻訳|中國翻譯|中文|無修正|无修正|chinese|digital|uncensored|ai generated|english|japanese|korean|translated|translation)\s*[\)）]',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'漢化|汉化|中文|無修正|无修正|中国語|中國語|中国翻訳|中國翻譯|翻訳|翻译|DL版|電子版', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\[[^\]]*(?:汉化组|漢化組|翻译组|翻訳組)[^\]]*\]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\([^\)]*(?:汉化组|漢化組|翻译组|翻訳組)[^\)]*\)', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\[\s*\]|\(\s*\)|（\s*）|【\s*】'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (!keepSearchPunctuation) {
    value = value.replaceAll(RegExp(r'[【】「」『』]'), ' ');
  }

  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _removeLeadingNumericId(String title) {
  RegExpMatch? match = RegExp(r'^\s*\d{3,}\s*(?:[-_]+\s*)?').firstMatch(title);
  if (match == null) {
    return title.trim();
  }

  String rest = title.substring(match.end).trimLeft();
  if (rest.isEmpty) {
    return title.trim();
  }

  int firstMeaningful = rest.indexOf(RegExp(r'[\[【\(（]'));
  if (firstMeaningful > 0 && RegExp(r'^[\s_\-]+$').hasMatch(rest.substring(0, firstMeaningful))) {
    return rest.substring(firstMeaningful).trimLeft();
  }
  return rest;
}


bool mangaLibraryTagsContainChineseLanguage(Iterable<TagData> tags) {
  return tags.any((tag) => isMangaLibraryChineseLanguageTag(namespace: tag.namespace, key: tag.key) ||
      isMangaLibraryChineseLanguageTag(namespace: tag.translatedNamespace ?? '', key: tag.tagName ?? ''));
}

bool mangaLibraryTagStringContainsChineseLanguage(String tags) {
  if (mangaLibraryTitleContainsChineseLanguage(tags)) {
    return true;
  }
  return tags.split(',').any((rawTag) {
    List<String> parts = rawTag.split(RegExp(r'[:：]'));
    if (parts.length < 2) {
      return false;
    }
    return isMangaLibraryChineseLanguageTag(namespace: parts.first, key: parts.sublist(1).join(':'));
  });
}

bool isMangaLibraryChineseLanguageTag({required String namespace, required String key}) {
  String normalizedNamespace = normalizeMangaLibraryTagNamespace(namespace).trim().toLowerCase();
  String normalizedKey = key.trim().toLowerCase().replaceAll('　', ' ');
  return normalizedNamespace == 'language' && (normalizedKey == 'chinese' || normalizedKey == '汉语' || normalizedKey == '漢語' || normalizedKey == '中文');
}

String normalizeMangaLibraryTagNamespace(String namespace) {
  String value = namespace.trim();
  if (value.isEmpty) {
    return value;
  }
  String? mapped = mangaLibraryChineseNamespaceAliases[value];
  if (mapped != null) {
    return mapped;
  }
  return EHNamespace.findNameSpaceFromDescOrAbbr(value)?.desc ?? value.toLowerCase();
}

String mangaLibraryTagText(TagData tag) {
  String namespace = tag.translatedNamespace?.isNotEmpty == true ? tag.translatedNamespace! : tag.namespace;
  String key = tag.tagName?.isNotEmpty == true ? tag.tagName! : tag.key;
  return '$namespace:$key';
}

String mangaLibraryTagSearchText(TagData tag) {
  String translatedNamespace = mangaLibraryNamespaceText(tag.namespace, sampleTag: tag);
  String translatedTagName = tag.tagName?.isNotEmpty == true ? tag.tagName! : tag.key;
  return [
    '${tag.namespace}:${tag.key}',
    tag.namespace,
    tag.key,
    translatedNamespace,
    translatedTagName,
    '$translatedNamespace:$translatedTagName',
  ].join(' ');
}


String mangaLibraryNamespaceText(String namespace, {TagData? sampleTag}) {
  if (sampleTag?.translatedNamespace?.isNotEmpty == true) {
    return sampleTag!.translatedNamespace!;
  }

  return EHNamespace.findNameSpaceFromDescOrAbbr(namespace)?.chineseDesc ?? namespace;
}

LinkedHashMap<String, List<TagData>> groupMangaLibraryTagsByNamespace(List<TagData> tags) {
  const namespaceOrder = ['language', 'parody', 'character', 'female', 'male', 'mixed', 'artist', 'group', 'cosplayer', 'misc', 'other'];
  Map<String, List<TagData>> grouped = tags.groupListsBy((tag) => tag.namespace);
  LinkedHashMap<String, List<TagData>> result = LinkedHashMap();

  for (String namespace in namespaceOrder) {
    List<TagData>? namespaceTags = grouped.remove(namespace);
    if (namespaceTags != null && namespaceTags.isNotEmpty) {
      result[namespace] = namespaceTags;
    }
  }

  List<String> restNamespaces = grouped.keys.toList()..sort();
  for (String namespace in restNamespaces) {
    result[namespace] = grouped[namespace]!;
  }

  return result;
}

enum MangaLibraryTagFillStrictness {
  strict,
  balanced,
  loose,
}

extension MangaLibraryTagFillStrictnessText on MangaLibraryTagFillStrictness {
  String get code {
    switch (this) {
      case MangaLibraryTagFillStrictness.strict:
        return 'strict';
      case MangaLibraryTagFillStrictness.balanced:
        return 'balanced';
      case MangaLibraryTagFillStrictness.loose:
        return 'loose';
    }
  }
}

class MangaLibraryTagFillCandidateInfo {
  final String title;
  final bool hasChineseLanguage;
  final int? pageCount;

  const MangaLibraryTagFillCandidateInfo({required this.title, required this.hasChineseLanguage, this.pageCount});
}

class MangaLibraryTagFillMatchDecision {
  final int? selectedIndex;
  final String status;
  final String matchLevel;
  final int score;
  final String candidateTitle;
  final List<String> reasons;

  const MangaLibraryTagFillMatchDecision({
    required this.selectedIndex,
    required this.status,
    required this.matchLevel,
    required this.score,
    required this.candidateTitle,
    required this.reasons,
  });

  bool get isSuccess => selectedIndex != null && status.startsWith('success_');

  String get reasonText => reasons.join('; ');
}

class MangaLibraryStructuredTitleParts {
  final String original;
  final String? leadingId;
  final String? event;
  final String? circle;
  final String? artist;
  final String mainTitle;
  final String? parody;
  final bool hasChineseMarker;
  final String? date;
  final int? season;
  final int? chapter;
  final int? chapterRangeStart;
  final int? chapterRangeEnd;
  final int? volume;

  const MangaLibraryStructuredTitleParts({
    required this.original,
    required this.leadingId,
    required this.event,
    required this.circle,
    required this.artist,
    required this.mainTitle,
    required this.parody,
    required this.hasChineseMarker,
    required this.date,
    required this.season,
    required this.chapter,
    required this.chapterRangeStart,
    required this.chapterRangeEnd,
    required this.volume,
  });
}

MangaLibraryStructuredTitleParts extractMangaLibraryStructuredTitleParts(String title) {
  String value = title.replaceAll('　', ' ').trim();
  String? leadingId = RegExp(r'^\s*(\d{3,})').firstMatch(value)?.group(1);
  bool hasChineseMarker = mangaLibraryTitleContainsChineseLanguage(value);
  String? event = RegExp(r'\b(C\d{2,3})\b', caseSensitive: false).firstMatch(value)?.group(1)?.toUpperCase();
  String? date = _extractMangaLibraryDate(value);
  int? season = _extractMangaLibrarySeason(value);
  ({int? chapter, int? start, int? end}) chapterInfo = _extractMangaLibraryChapter(value);

  String withoutId = _removeLeadingNumericId(value);
  String? circle;
  String? artist;
  RegExpMatch? bracketMatch = RegExp(r'[\[【]\s*([^\]】]+?)\s*[\]】]').firstMatch(withoutId);
  if (bracketMatch != null) {
    String bracket = bracketMatch.group(1)!.trim();
    RegExpMatch? circleArtist = RegExp(r'^(.+?)\s*[\(（]\s*(.+?)\s*[\)）]\s*$').firstMatch(bracket);
    if (circleArtist != null) {
      circle = circleArtist.group(1)?.trim();
      artist = circleArtist.group(2)?.trim();
    } else if (!_isMangaLibraryNoiseMarker(bracket)) {
      circle = bracket;
    }
  }

  String? parody;
  Iterable<RegExpMatch> parenMatches = RegExp(r'[\(（]\s*([^\)）]+?)\s*[\)）]').allMatches(withoutId);
  for (RegExpMatch match in parenMatches) {
    String content = match.group(1)!.trim();
    if (content.isEmpty || _isMangaLibraryNoiseMarker(content) || RegExp(r'^C\d{2,3}$', caseSensitive: false).hasMatch(content)) {
      continue;
    }
    if (artist != null && _normalizeMangaLibraryAnchor(content) == _normalizeMangaLibraryAnchor(artist)) {
      continue;
    }
    parody = content;
  }

  String mainTitle = _extractMangaLibraryMainTitle(withoutId, circle: circle, artist: artist, parody: parody);
  int? volume = _extractMangaLibraryVolume(mainTitle);

  return MangaLibraryStructuredTitleParts(
    original: title,
    leadingId: leadingId,
    event: event,
    circle: circle,
    artist: artist,
    mainTitle: mainTitle,
    parody: parody,
    hasChineseMarker: hasChineseMarker,
    date: date,
    season: season,
    chapter: chapterInfo.chapter,
    chapterRangeStart: chapterInfo.start,
    chapterRangeEnd: chapterInfo.end,
    volume: volume,
  );
}

MangaLibraryTagFillMatchDecision selectMangaLibraryTagFillCandidate({
  required String localTitle,
  required List<MangaLibraryTagFillCandidateInfo> candidates,
  MangaLibraryTagFillStrictness strictness = MangaLibraryTagFillStrictness.balanced,
}) {
  if (candidates.isEmpty) {
    return const MangaLibraryTagFillMatchDecision(selectedIndex: null, status: 'skipped_low_score', matchLevel: 'none', score: 0, candidateTitle: '', reasons: ['no_candidates']);
  }

  List<int> exactIndexes = [];
  for (int i = 0; i < candidates.length; i++) {
    if (isExactMangaLibraryTitleMatch(localTitle, candidates[i].title)) {
      exactIndexes.add(i);
    }
  }
  if (exactIndexes.length == 1) {
    int index = exactIndexes.single;
    return MangaLibraryTagFillMatchDecision(selectedIndex: index, status: 'success_exact_single', matchLevel: 'exact', score: 100, candidateTitle: candidates[index].title, reasons: const ['exact_title_match']);
  }
  if (exactIndexes.length > 1) {
    List<int> chineseExact = exactIndexes.where((index) => candidates[index].hasChineseLanguage).toList();
    if (chineseExact.length == 1) {
      int index = chineseExact.single;
      return MangaLibraryTagFillMatchDecision(selectedIndex: index, status: 'success_exact_chinese_preferred', matchLevel: 'exact', score: 100, candidateTitle: candidates[index].title, reasons: const ['exact_title_match', 'unique_chinese_candidate']);
    }
    return MangaLibraryTagFillMatchDecision(
      selectedIndex: null,
      status: chineseExact.length > 1 ? 'skipped_multiple_chinese' : 'skipped_no_chinese',
      matchLevel: 'exact',
      score: 100,
      candidateTitle: '',
      reasons: [chineseExact.length > 1 ? 'multiple_chinese_exact_candidates' : 'no_chinese_exact_candidate'],
    );
  }

  MangaLibraryStructuredTitleParts local = extractMangaLibraryStructuredTitleParts(localTitle);
  List<_MangaLibraryCandidateScore> scores = [
    for (int i = 0; i < candidates.length; i++) _scoreMangaLibraryCandidate(local: local, candidate: candidates[i], index: i),
  ]..sort((a, b) => b.score.compareTo(a.score));

  if (_hasAmbiguousVolumeSeries(local, scores)) {
    return MangaLibraryTagFillMatchDecision(selectedIndex: null, status: 'skipped_volume_conflict', matchLevel: 'structured', score: scores.first.score, candidateTitle: scores.first.info.title, reasons: const ['multiple_volume_or_chapter_candidates']);
  }

  _MangaLibraryCandidateScore best = scores.first;
  if (best.volumeConflict) {
    return MangaLibraryTagFillMatchDecision(selectedIndex: null, status: 'skipped_volume_conflict', matchLevel: 'structured', score: best.score, candidateTitle: best.info.title, reasons: best.reasons);
  }

  List<_MangaLibraryCandidateScore> highConfidence = scores.where((score) => score.isHighConfidence).toList();
  List<_MangaLibraryCandidateScore> chineseHighConfidence = highConfidence.where((score) => score.info.hasChineseLanguage).toList();
  if (chineseHighConfidence.length > 1) {
    return MangaLibraryTagFillMatchDecision(selectedIndex: null, status: 'skipped_multiple_high_confidence', matchLevel: 'structured', score: chineseHighConfidence.first.score, candidateTitle: chineseHighConfidence.first.info.title, reasons: const ['multiple_chinese_high_confidence_candidates']);
  }
  if (chineseHighConfidence.length == 1) {
    _MangaLibraryCandidateScore selected = chineseHighConfidence.single;
    int secondScore = scores.length > 1 ? scores[1].score : 0;
    if (scores.length > 1 && selected.score - secondScore < 12) {
      return MangaLibraryTagFillMatchDecision(selectedIndex: null, status: 'skipped_multiple_high_confidence', matchLevel: 'structured', score: selected.score, candidateTitle: selected.info.title, reasons: [...selected.reasons, 'score_margin_too_small']);
    }
    return MangaLibraryTagFillMatchDecision(selectedIndex: selected.index, status: 'success_high_confidence_chinese', matchLevel: 'structured_high_confidence', score: selected.score, candidateTitle: selected.info.title, reasons: selected.reasons);
  }

  if (candidates.length == 1) {
    if (strictness == MangaLibraryTagFillStrictness.strict) {
      return MangaLibraryTagFillMatchDecision(selectedIndex: null, status: best.info.hasChineseLanguage ? 'skipped_low_score' : 'skipped_no_chinese', matchLevel: 'single_result', score: best.score, candidateTitle: best.info.title, reasons: best.reasons);
    }
    bool hasAnchor = best.strongAnchorCount > 0 || best.hasCoreEnglishContainment;
    bool looseAllowed = strictness == MangaLibraryTagFillStrictness.loose && (best.weakAnchorCount > 0 || best.info.hasChineseLanguage);
    if (best.info.hasChineseLanguage || hasAnchor || looseAllowed) {
      String status = best.info.hasChineseLanguage && !hasAnchor ? 'success_single_result_chinese' : 'success_single_result_anchor';
      List<String> reasons = [...best.reasons];
      if (best.score < 75 || best.strongAnchorCount < 2) {
        reasons.add('low_confidence_single_result');
      }
      return MangaLibraryTagFillMatchDecision(selectedIndex: best.index, status: status, matchLevel: reasons.contains('low_confidence_single_result') ? 'low_confidence_single_result' : 'single_result', score: best.score, candidateTitle: best.info.title, reasons: reasons);
    }
    return MangaLibraryTagFillMatchDecision(selectedIndex: null, status: 'skipped_single_result_no_anchor', matchLevel: 'single_result', score: best.score, candidateTitle: best.info.title, reasons: [...best.reasons, 'no_chinese_or_anchor']);
  }

  if (strictness != MangaLibraryTagFillStrictness.strict) {
    List<_MangaLibraryCandidateScore> sameWork = scores.where((score) => score.isSameWorkCandidate).toList();
    List<_MangaLibraryCandidateScore> chineseSameWork = sameWork.where((score) => score.info.hasChineseLanguage).toList();
    if (chineseSameWork.length == 1) {
      _MangaLibraryCandidateScore selected = chineseSameWork.single;
      return MangaLibraryTagFillMatchDecision(selectedIndex: selected.index, status: 'success_same_work_chinese_preferred', matchLevel: 'same_work_group', score: selected.score, candidateTitle: selected.info.title, reasons: selected.reasons);
    }
    if (chineseSameWork.length > 1) {
      return MangaLibraryTagFillMatchDecision(selectedIndex: null, status: 'skipped_multiple_chinese', matchLevel: 'same_work_group', score: chineseSameWork.first.score, candidateTitle: chineseSameWork.first.info.title, reasons: const ['multiple_chinese_same_work_candidates']);
    }
  }

  if (scores.where((score) => score.info.hasChineseLanguage).length > 1 && best.strongAnchorCount == 0) {
    return MangaLibraryTagFillMatchDecision(selectedIndex: null, status: 'skipped_multiple_chinese', matchLevel: 'structured', score: best.score, candidateTitle: best.info.title, reasons: const ['multiple_chinese_candidates_without_unique_work_anchor']);
  }
  return MangaLibraryTagFillMatchDecision(selectedIndex: null, status: best.titleConflict ? 'skipped_title_conflict' : (best.info.hasChineseLanguage ? 'skipped_low_score' : 'skipped_no_chinese'), matchLevel: 'structured', score: best.score, candidateTitle: best.info.title, reasons: best.reasons);
}

bool mangaLibraryTitleContainsChineseLanguage(String title) {
  return RegExp(r'(?:language\s*[:：]\s*chinese|语言\s*[:：]\s*汉语|語言\s*[:：]\s*漢語|[\[【]\s*(?:Chinese|中国翻訳|中國翻譯|中国語|中國語|中国|中國)\s*[\]】])', caseSensitive: false).hasMatch(title);
}

class _MangaLibraryCandidateScore {
  final int index;
  final MangaLibraryTagFillCandidateInfo info;
  final MangaLibraryStructuredTitleParts parts;
  final int score;
  final int strongAnchorCount;
  final int weakAnchorCount;
  final bool titleConflict;
  final bool volumeConflict;
  final bool hasCoreEnglishContainment;
  final List<String> reasons;

  const _MangaLibraryCandidateScore({required this.index, required this.info, required this.parts, required this.score, required this.strongAnchorCount, required this.weakAnchorCount, required this.titleConflict, required this.volumeConflict, required this.hasCoreEnglishContainment, required this.reasons});

  bool get isHighConfidence => score >= 75 && strongAnchorCount >= 2 && info.hasChineseLanguage && !titleConflict && !volumeConflict;

  bool get isSameWorkCandidate => score >= 60 && info.hasChineseLanguage && !titleConflict && !volumeConflict && strongAnchorCount >= 2 && (reasons.any((reason) => reason.startsWith('main_title_') || reason.startsWith('parody_') || reason == 'date_match' || reason == 'chapter_or_season_match'));
}

_MangaLibraryCandidateScore _scoreMangaLibraryCandidate({required MangaLibraryStructuredTitleParts local, required MangaLibraryTagFillCandidateInfo candidate, required int index}) {
  MangaLibraryStructuredTitleParts parts = extractMangaLibraryStructuredTitleParts(candidate.title);
  int score = 0;
  int strong = 0;
  int weak = 0;
  bool titleConflict = false;
  bool volumeConflict = false;
  List<String> reasons = [];

  if (_anchorMatches(local.circle, parts.circle)) {
    score += 30;
    strong++;
    reasons.add('circle_match');
  }
  if (_anchorMatches(local.artist, parts.artist)) {
    score += 20;
    strong++;
    reasons.add('artist_match');
  }

  double mainSimilarity = _mangaLibraryTitleSimilarity(local.mainTitle, parts.mainTitle);
  bool coreContainment = _hasCoreEnglishTitleContainment(local.mainTitle, parts.mainTitle);
  if (mainSimilarity >= 0.72 || coreContainment) {
    score += 30;
    strong++;
    reasons.add('main_title_match');
  } else if (mainSimilarity >= 0.38) {
    score += 12;
    weak++;
    reasons.add('main_title_partial');
  } else if (_hasSubstantialText(local.mainTitle) && _hasSubstantialText(parts.mainTitle)) {
    titleConflict = true;
    reasons.add('main_title_conflict');
  }

  if (_anchorMatches(local.parody, parts.parody) || _parodyCoreMatches(local.parody, parts.parody)) {
    score += 15;
    strong++;
    reasons.add('parody_match');
  }

  bool eventMatch = local.event != null && parts.event != null && local.event == parts.event;
  bool dateMatch = local.date != null && parts.date != null && local.date == parts.date;
  if (eventMatch || dateMatch) {
    score += 5;
    strong++;
    reasons.add(dateMatch ? 'date_match' : 'event_match');
  } else if (local.event != null && parts.event != null && local.event != parts.event) {
    reasons.add('event_conflict');
  }

  if (_chapterOrSeasonCompatible(local, parts)) {
    score += 5;
    strong++;
    reasons.add('chapter_or_season_match');
  }

  if (candidate.pageCount != null) {
    // Page count is kept as an extension point for callers that compare a local page count.
    weak++;
  }

  if (candidate.hasChineseLanguage || parts.hasChineseMarker) {
    score += 10;
    reasons.add('chinese_language');
  }

  if (_volumeConflicts(local, parts)) {
    score -= 20;
    volumeConflict = local.volume != null && parts.volume != null && local.volume != parts.volume;
    reasons.add(volumeConflict ? 'volume_conflict' : 'volume_mismatch_penalty');
  }

  return _MangaLibraryCandidateScore(index: index, info: candidate, parts: parts, score: score.clamp(0, 100).toInt(), strongAnchorCount: strong, weakAnchorCount: weak, titleConflict: titleConflict, volumeConflict: volumeConflict, hasCoreEnglishContainment: coreContainment, reasons: reasons);
}

bool _hasAmbiguousVolumeSeries(MangaLibraryStructuredTitleParts local, List<_MangaLibraryCandidateScore> scores) {
  Map<String, Set<int>> volumesByBase = {};
  for (final score in scores.where((score) => score.info.hasChineseLanguage && score.parts.volume != null)) {
    String base = _stripTrailingVolume(_normalizeMangaLibraryAnchor(score.parts.mainTitle));
    if (base.isEmpty) {
      continue;
    }
    volumesByBase.putIfAbsent(base, () => {}).add(score.parts.volume!);
  }
  return volumesByBase.values.any((volumes) => volumes.length > 1 && (local.volume == null || !volumes.contains(local.volume)));
}

String _extractMangaLibraryMainTitle(String title, {String? circle, String? artist, String? parody}) {
  String value = title;
  value = value.replaceAll(RegExp(r'^\s*[-_\s]*\(?(?:C\d{2,3})\)?\s*[-_\s]*', caseSensitive: false), ' ');
  value = value.replaceFirst(RegExp(r'^\s*[\[【][^\]】]+[\]】]\s*'), ' ');
  if (parody != null && parody.isNotEmpty) {
    value = value.replaceAll(RegExp('[\\(（]\\s*${RegExp.escape(parody)}\\s*[\\)）]'), ' ');
  }
  value = value.replaceAll(RegExp(r'[\[【][^\]】]*[\]】]'), ' ');
  value = value.replaceAll(RegExp(r'\b(?:Digital|DL版|Chinese|中国翻訳|中國翻譯)\b', caseSensitive: false), ' ');
  value = value.split('|').first;
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  value = value.replaceAll(RegExp(r'^[\s\-＿_.,，。!！?？:：;；/\\|·・~～]+|[\s\-＿_.,，。!！?？:：;；/\\|·・~～]+$'), '').trim();
  return value.isEmpty ? cleanMangaLibraryTitleForTagFill(title) : value;
}

bool _isMangaLibraryNoiseMarker(String value) {
  return RegExp(r'^(?:中国|中國|中国語|中國語|中国翻訳|中國翻譯|中文|Chinese|Digital|DL版|AI Generated|English|Japanese|Korean)$', caseSensitive: false).hasMatch(value.trim()) || RegExp(r'(?:汉化组|漢化組|翻译组|翻訳組)').hasMatch(value);
}

String? _extractMangaLibraryDate(String value) {
  RegExpMatch? iso = RegExp(r'\b(\d{4})[-./](\d{1,2})[-./](\d{1,2})\b').firstMatch(value);
  if (iso != null) {
    return '${iso.group(1)!}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}';
  }
  RegExpMatch? jp = RegExp(r'(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日').firstMatch(value);
  if (jp != null) {
    return '${jp.group(1)!}-${jp.group(2)!.padLeft(2, '0')}-${jp.group(3)!.padLeft(2, '0')}';
  }
  return null;
}

int? _extractMangaLibrarySeason(String value) {
  RegExpMatch? match = RegExp(r'(?:Season\s*|\b[Ss])([0-9]{1,2})\b|第\s*([0-9０-９一二三四五六七八九十]{1,3})\s*季', caseSensitive: false).firstMatch(value);
  return match == null ? null : _parseMangaLibraryInt(match.group(1) ?? match.group(2));
}

({int? chapter, int? start, int? end}) _extractMangaLibraryChapter(String value) {
  RegExpMatch? range = RegExp(r'\bch\.?\s*(\d{1,4})\s*[-~～]\s*(\d{1,4})\b', caseSensitive: false).firstMatch(value);
  if (range != null) {
    return (chapter: null, start: int.parse(range.group(1)!), end: int.parse(range.group(2)!));
  }
  RegExpMatch? chapter = RegExp(r'\bch\.?\s*(\d{1,4})\b|第\s*(\d{1,4})\s*话', caseSensitive: false).firstMatch(value);
  if (chapter != null) {
    return (chapter: int.parse(chapter.group(1) ?? chapter.group(2)!), start: null, end: null);
  }
  RegExpMatch? trailing = RegExp(r'(?:\s|^)(\d{1,3})(?=\s*[\(（])').firstMatch(value);
  if (trailing != null) {
    return (chapter: int.parse(trailing.group(1)!), start: null, end: null);
  }
  return (chapter: null, start: null, end: null);
}

int? _extractMangaLibraryVolume(String value) {
  RegExpMatch? match = RegExp(r'(?:\bVol\.?\s*|第\s*)(\d{1,3})(?:\s*巻|\s*卷)?\b|(?:^|\s)(\d{1,3})$', caseSensitive: false).firstMatch(value.trim());
  return match == null ? null : int.tryParse(match.group(1) ?? match.group(2)!);
}

int? _parseMangaLibraryInt(String? value) {
  if (value == null) {
    return null;
  }
  const map = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10};
  String normalized = value.replaceAll('０', '0').replaceAll('１', '1').replaceAll('２', '2').replaceAll('３', '3').replaceAll('４', '4').replaceAll('５', '5').replaceAll('６', '6').replaceAll('７', '7').replaceAll('８', '8').replaceAll('９', '9');
  return int.tryParse(normalized) ?? map[normalized];
}

bool _anchorMatches(String? left, String? right) {
  if (left == null || right == null || left.trim().isEmpty || right.trim().isEmpty) {
    return false;
  }
  String a = _normalizeMangaLibraryAnchor(left);
  String b = _normalizeMangaLibraryAnchor(right);
  return a.isNotEmpty && (a == b || a.contains(b) || b.contains(a));
}

bool _parodyCoreMatches(String? left, String? right) {
  if (left == null || right == null) {
    return false;
  }
  Set<String> a = _coreTokens(left);
  Set<String> b = _coreTokens(right);
  return a.isNotEmpty && b.isNotEmpty && a.intersection(b).length >= 2;
}

double _mangaLibraryTitleSimilarity(String left, String right) {
  if (_anchorMatches(left, right)) {
    return 1;
  }
  Set<String> a = _coreTokens(left);
  Set<String> b = _coreTokens(right);
  if (a.isEmpty || b.isEmpty) {
    return 0;
  }
  return a.intersection(b).length / a.union(b).length;
}

bool _hasCoreEnglishTitleContainment(String left, String right) {
  String a = _coreEnglishTitle(left);
  String b = _coreEnglishTitle(right);
  return a.length >= 6 && b.length >= 6 && (a.contains(b) || b.contains(a));
}

String _coreEnglishTitle(String value) {
  return _coreTokens(value).where((token) => RegExp(r'[a-z]').hasMatch(token)).join(' ');
}

Set<String> _coreTokens(String value) {
  return _normalizeMangaLibraryAnchor(value).split(' ').where((token) => token.length > 1 && !_stopMangaLibraryTokens.contains(token)).toSet();
}

bool _hasSubstantialText(String value) {
  return _coreTokens(value).isNotEmpty || RegExp(r'[\u3040-\u30ff\u3400-\u9fff]{3,}').hasMatch(value);
}

String _normalizeMangaLibraryAnchor(String value) {
  String normalized = value.toLowerCase().replaceAll('é', 'e').replaceAll('：', ':').replaceAll('　', ' ');
  const aliases = {
    '白ネギ屋': 'shironegiya',
    'すがいし': 'sugaishi',
    'にえあ': 'niea',
    '黒犬獣': 'kuroinu juu',
    'イケニエネイビー': 'ikenie navy',
    'ヒスイ転生録': 'hisui tensei roku',
    'pokemon legends アルセウス': 'pokemon legends arceus',
    'pokémon legends アルセウス': 'pokemon legends arceus',
    'スクールランブル': 'school rumble',
    '吸烟洗脑': 'smoking hypnosis',
    '催眠烟': 'smoking hypnosis',
    '綺麗にしてもらえますか': 'kirei ni shite moraemasu ka',
  };
  aliases.forEach((from, to) {
    normalized = normalized.replaceAll(from.toLowerCase(), to);
  });
  normalized = normalized
      .replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return normalized;
}

bool _chapterOrSeasonCompatible(MangaLibraryStructuredTitleParts local, MangaLibraryStructuredTitleParts candidate) {
  bool season = local.season != null && candidate.season != null && local.season == candidate.season;
  bool chapter = false;
  if (local.chapter != null && candidate.chapter != null) {
    chapter = local.chapter == candidate.chapter;
  } else if (local.chapter != null && candidate.chapterRangeStart != null && candidate.chapterRangeEnd != null) {
    chapter = local.chapter! >= candidate.chapterRangeStart! && local.chapter! <= candidate.chapterRangeEnd!;
  } else if (candidate.chapter != null && local.chapterRangeStart != null && local.chapterRangeEnd != null) {
    chapter = candidate.chapter! >= local.chapterRangeStart! && candidate.chapter! <= local.chapterRangeEnd!;
  }
  return season || chapter;
}

bool _volumeConflicts(MangaLibraryStructuredTitleParts local, MangaLibraryStructuredTitleParts candidate) {
  if (local.volume != null && candidate.volume != null) {
    return local.volume != candidate.volume;
  }
  return local.volume == null && candidate.volume != null;
}

String _stripTrailingVolume(String value) {
  return value.replaceAll(RegExp(r'\s+\d{1,3}$'), '').trim();
}

const Set<String> _stopMangaLibraryTokens = {
  'the',
  'and',
  'for',
  'with',
  'digital',
  'chinese',
  'translation',
  'translated',
  'route',
  'ban',
};
