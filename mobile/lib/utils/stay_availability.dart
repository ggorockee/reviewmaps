/// 숙박(숙소·캠핑장·펜션 등) 체험단의 이용 가능/불가 요일
/// --------------------------------------------
/// 체험단 사이트는 이용 요일을 별도 칸 없이 제공 내역 글에 섞어 씁니다.
///   예) "평일(일-목) 1박 숙박권", "1박2일 숙박권 (토요일제외)",
///       "오션뷰풀빌라 2인숙박권 (토요일 및 공휴일제외)", "평일 월~목요일 이용권"
/// 사용자가 공고마다 들어가 확인하지 않도록, 제공 내역에서 요일 정보를 뽑아
/// 목록 카드에 바로 보여주기 위한 파서입니다. 서버·DB 변경 없이 앱에서만 계산합니다.
///
/// 원칙: 애매하면 표시하지 않습니다 (잘못된 요일 안내가 표시 안 함보다 나쁨).
///   - "평일 45만원 상당", "주말기준 42만원", "평일 기준 / 8만원"처럼
///     요금 기준을 말하는 경우는 이용 제한으로 보지 않습니다.
///   - "애견 동반 불가", "인원 추가 불가"처럼 요일과 무관한 불가는 무시합니다.
library;

/// 요일 번호: DateTime.monday(1) ~ DateTime.sunday(7)
const List<String> kWeekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

const Map<String, int> _dayIndex = {
  '월': 1, '화': 2, '수': 3, '목': 4, '금': 5, '토': 6, '일': 7,
};

/// 숙박 카테고리 ID (서버 categories 테이블 기준)
const int kLodgingCategoryId = 3;

class StayAvailability {
  const StayAvailability({
    this.availableLabels = const [],
    this.availableDays = const {},
    this.weekdaysOnly = false,
    this.weekendOnly = false,
    this.excludedLabels = const [],
    this.excludedDays = const {},
  });

  /// 이용 가능 표시용 조각 (예: "일~목", "월·수", "12/5")
  final List<String> availableLabels;

  /// 이용 가능 요일 (요일을 명시한 경우만. "평일"만 쓴 경우는 비어 있음)
  final Set<int> availableDays;

  /// "평일", "주중" 이용
  final bool weekdaysOnly;

  /// "주말 이용", "주말만"
  final bool weekendOnly;

  /// 이용 불가 표시용 조각 (예: "토", "공휴일", "특정 휴일", "주말")
  final List<String> excludedLabels;

  /// 이용 불가 요일
  final Set<int> excludedDays;

  bool get isEmpty =>
      availableLabels.isEmpty &&
      !weekdaysOnly &&
      !weekendOnly &&
      excludedLabels.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// 요일 띠(월~일)로 그릴 수 있을 만큼 요일이 명시되었는지
  bool get hasExplicitDays => availableDays.isNotEmpty || excludedDays.isNotEmpty;

  /// 이용 가능 문구 (예: "평일(일~목)", "평일만", "주말만", "월~목")
  String? get availableText {
    if (availableLabels.isNotEmpty) {
      final joined = availableLabels.join(', ');
      if (weekdaysOnly) return '평일($joined)';
      if (weekendOnly) return '주말($joined)';
      return joined;
    }
    if (weekdaysOnly) return '평일만';
    if (weekendOnly) return '주말만';
    return null;
  }

  /// 이용 불가 문구 (예: "토·공휴일")
  String? get excludedText =>
      excludedLabels.isEmpty ? null : excludedLabels.join('·');

  /// 화면 낭독기용 문장
  String get semanticsLabel {
    final parts = <String>[];
    final a = availableText;
    final e = excludedText;
    if (a != null) parts.add('$a 이용 가능');
    if (e != null) parts.add('$e 이용 불가');
    return parts.join(', ');
  }

  /// 요일별 상태: true=가능, false=불가, null=알 수 없음
  bool? dayState(int day) {
    if (excludedDays.contains(day)) return false;
    if (availableDays.isNotEmpty) return availableDays.contains(day);
    if (weekdaysOnly && day >= 6) return null; // "평일"의 금·일 포함 여부는 숙소마다 다름
    return null;
  }

  @override
  String toString() =>
      'StayAvailability(available: $availableText, excluded: $excludedText, days: $availableDays, excludedDays: $excludedDays)';

  // ------------------------------------------------------------------
  // 파싱
  // ------------------------------------------------------------------

  /// 제공 내역 글에서 이용 요일 정보를 뽑습니다. 정보가 없으면 null.
  static StayAvailability? parse(String? offer) {
    if (offer == null) return null;
    final text = _normalize(offer);
    if (text.trim().isEmpty) return null;

    // "평일/주말 모두 가능", "요일 무관"이면 제한 없음
    if (_noRestriction.hasMatch(text)) return null;

    final consumed = <_Span>[];
    bool overlaps(int s, int e) => consumed.any((c) => s < c.end && e > c.start);

    final availableLabels = <String>[];
    final availableDays = <int>{};
    final excludedLabels = <String>[];
    final excludedDays = <int>{};
    var weekdaysOnly = false;
    var weekendOnly = false;

    void addAvail(String label, Iterable<int> days) {
      if (!availableLabels.contains(label)) availableLabels.add(label);
      availableDays.addAll(days);
    }

    void addExcluded(String label, Iterable<int> days) {
      if (!excludedLabels.contains(label)) excludedLabels.add(label);
      excludedDays.addAll(days);
    }

    // 1) 날짜 지정: "12월5일 숙박권", "12월 24일 제외"
    for (final m in _datePattern.allMatches(text)) {
      final rest = text.substring(m.end);
      final label = '${int.parse(m.group(1)!)}/${int.parse(m.group(2)!)}';
      if (_isNegated(rest)) {
        addExcluded(label, const []);
      } else if (_dateUsage.hasMatch(rest)) {
        addAvail(label, const []);
      } else {
        continue;
      }
      consumed.add(_Span(m.start, m.end));
    }

    // 2) 요일 범위: "월~목", "일-목", "월~목요일"
    for (final m in _rangePattern.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      if (!_validDayPrefix(text, m.start)) continue;
      final a = _dayIndex[m.group(1)]!;
      final b = _dayIndex[m.group(2)]!;
      if (a == b) continue;
      final days = _expandRange(a, b);
      final label = '${m.group(1)}~${m.group(2)}';
      if (_isNegated(text.substring(m.end))) {
        addExcluded(label, days);
      } else {
        addAvail(label, days);
      }
      consumed.add(_Span(m.start, m.end));
    }

    // 3) 요일 나열: "금,토 불가", "월·화·수", "금/토"
    for (final m in _listPattern.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      if (!_validDayPrefix(text, m.start)) continue;
      final rest = text.substring(m.end);
      if (!_validDaySuffix(rest)) continue;
      final days = _daysIn(m.group(0)!);
      if (days.length < 2) continue;
      final label = _labelForDays(days);
      if (_isNegated(rest)) {
        addExcluded(label, days);
      } else {
        addAvail(label, days);
      }
      consumed.add(_Span(m.start, m.end));
    }

    // 4) 붙여 쓴 요일: "월화수목 가능", "금토 불가" (수목원·화목한 같은 낱말은 제외)
    for (final m in _joinedPattern.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      if (!_validDayPrefix(text, m.start)) continue;
      final rest = text.substring(m.end);
      if (!_validDaySuffix(rest)) continue;
      final chars = m.group(1)!.split('');
      if (chars.toSet().length != chars.length) continue;
      final days = chars.map((c) => _dayIndex[c]!).toList();
      final label = _labelForDays(days);
      if (_isNegated(rest)) {
        addExcluded(label, days);
      } else {
        addAvail(label, days);
      }
      consumed.add(_Span(m.start, m.end));
    }

    // 5) 요일 하나: "토요일 제외", "일요일만", "(토 불가)"
    for (final m in _singlePattern.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      final hasYoil = m.group(2) != null;
      if (!hasYoil && !_validDayPrefix(text, m.start)) continue;
      final day = _dayIndex[m.group(1)]!;
      final rest = text.substring(m.end);
      if (_isNegated(rest)) {
        addExcluded(m.group(1)!, [day]);
      } else if (hasYoil && _singlePositive.hasMatch(rest)) {
        addAvail(m.group(1)!, [day]);
      } else {
        continue;
      }
      consumed.add(_Span(m.start, m.end));
    }

    // 6) 평일·주중 / 주말
    for (final m in _weekPartPattern.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      final word = m.group(1)!;
      final rest = text.substring(m.end);
      if (_priceBasis.hasMatch(rest)) continue; // "평일 45만원 상당", "주말기준 42만원"
      final isWeekend = word == '주말';
      if (_isNegated(rest)) {
        // "주말 불가"는 숙소마다 금·토 밤 / 토·일을 뜻해 요일 띠에는 표시하지 않음
        addExcluded(isWeekend ? '주말' : '평일', const []);
      } else if (isWeekend) {
        if (_weekendPositive.hasMatch(rest)) weekendOnly = true;
      } else {
        weekdaysOnly = true;
      }
      consumed.add(_Span(m.start, m.end));
    }

    // 7) 공휴일·연휴·성수기 등은 "제외/불가"일 때만 표시
    for (final m in _holidayPattern.allMatches(text)) {
      if (overlaps(m.start, m.end)) continue;
      if (!_isNegated(text.substring(m.end))) continue;
      addExcluded(_holidayLabel(m.group(0)!), const []);
      consumed.add(_Span(m.start, m.end));
    }

    final result = StayAvailability(
      availableLabels: List.unmodifiable(availableLabels),
      availableDays: Set.unmodifiable(availableDays),
      weekdaysOnly: weekdaysOnly,
      weekendOnly: weekendOnly && !weekdaysOnly,
      excludedLabels: List.unmodifiable(excludedLabels),
      excludedDays: Set.unmodifiable(excludedDays),
    );
    return result.isEmpty ? null : result;
  }

  // ------------------------------------------------------------------
  // 내부 도우미
  // ------------------------------------------------------------------

  static String _normalize(String s) => s
      .replaceAll(RegExp(r'[～〜∼～－–—]'), '~')
      .replaceAll(RegExp(r'[，、]'), ',')
      .replaceAll('ㆍ', '·')
      .replaceAll(RegExp(r'[（]'), '(')
      .replaceAll(RegExp(r'[）]'), ')')
      .replaceAll(RegExp(r'\s+'), ' ');

  static const _d = '[월화수목금토일]';

  static final RegExp _datePattern = RegExp(r'(?<![0-9])(\d{1,2})\s*월\s*(\d{1,2})\s*일');
  static final RegExp _dateUsage =
      RegExp(r'^\s*(에\s*)?(숙박|이용|입실|체크인|1박|투숙|하루|당일|사용)');

  static final RegExp _rangePattern =
      RegExp('($_d)(?:요일)?\\s*[~\\-]\\s*($_d)(?:요일)?');

  static final RegExp _listPattern =
      RegExp('$_d(?:요일)?(?:\\s*[,·/]\\s*$_d(?:요일)?)+');

  static final RegExp _joinedPattern = RegExp('($_d{2,7})(?:요일)?');

  static final RegExp _singlePattern = RegExp('($_d)(요일)?');

  static final RegExp _singlePositive =
      RegExp(r'^\s*(만|에만|전용|이용|가능|숙박|투숙|입실|1박)');

  static final RegExp _weekPartPattern = RegExp(r'(평일|주중|주말)');

  static final RegExp _weekendPositive =
      RegExp(r'^\s*(\(|만|에만|전용|이용|가능|숙박|투숙|입실|1박)');

  /// 요금 기준 표현: "45만원", "기준", "요금", "정상가", "추가금", "할증"
  static final RegExp _priceBasis = RegExp(
      r'^\s*(기준|요금|가격|정상가|추가|할증|[:)]?\s*\(?\s*[\d,.]+\s*(만|천)?\s*원)');

  static final RegExp _noRestriction = RegExp(
      r'(요일\s*(무관|상관\s*없)|(평일|주중)\s*[,/·및]?\s*주말\s*(모두|상관|무관|전부)|주말\s*[,/·및]?\s*평일\s*(모두|상관|무관|전부)|(평일|주말)\s*(또는|or|OR|/|,|·)\s*(평일|주말))');

  static final RegExp _holidayPattern = RegExp(
      r'(특정\s*)?(극성수기|성수기|법정\s*공휴일|공휴일\s*전날|공휴일|휴일\s*전날|휴일|연휴|명절|크리스마스|연말연시|연말)');

  /// 요일 표현 뒤에 이어 붙는 "및 공휴일", "숙박" 같은 연결어를 건너뛰고
  /// 바로 "제외/불가"가 오면 부정으로 판단합니다.
  static final RegExp _connector = RegExp(
      r'^(\s|및|와|과|,|·|/|요일|은|는|에는|엔|에|숙박|이용|사용|입실|투숙|체크인|예약|특정|법정|공휴일|휴일|전날|연휴|성수기|극성수기|명절|[월화수목금토일])+');
  static final RegExp _negation =
      RegExp(r'^(제외|불가|안\s*됨|안돼|안됩니다|이용\s*불가|어려|휴무|미운영|x(?![a-z])|X(?![A-Z]))');

  static bool _isNegated(String rest) {
    final stripped = rest.replaceFirst(_connector, '');
    return _negation.hasMatch(stripped);
  }

  /// "12월", "2일-목포", "수목원" 같은 오탐을 막기 위한 앞 글자 검사
  static bool _validDayPrefix(String text, int start) {
    if (start == 0) return true;
    final prev = text[start - 1];
    if (RegExp(r'[0-9]').hasMatch(prev)) return false;
    if (RegExp(r'[가-힣]').hasMatch(prev)) {
      // "평일월~목", "주중월~금"처럼 붙여 쓴 경우만 허용
      return prev == '일' || prev == '중';
    }
    return true;
  }

  /// 붙여 쓴 요일 뒤 글자 검사: 낱말 일부("수목원", "화목한")가 아닌지
  static bool _validDaySuffix(String rest) {
    if (rest.isEmpty) return true;
    if (!RegExp(r'^[가-힣]').hasMatch(rest)) return true;
    return RegExp(r'^(요일|만|중|에만|은|는|에는|이용|가능|불가|제외|숙박|사용|투숙|입실|1박)').hasMatch(rest);
  }

  static List<int> _expandRange(int a, int b) {
    final days = <int>[];
    var d = a;
    for (var i = 0; i < 7; i++) {
      days.add(d);
      if (d == b) break;
      d = d % 7 + 1;
    }
    return days;
  }

  static List<int> _daysIn(String s) {
    final days = <int>[];
    for (final ch in s.split('')) {
      final d = _dayIndex[ch];
      if (d != null && !days.contains(d)) days.add(d);
    }
    return days;
  }

  /// 연속된 요일 3개 이상이면 범위("월~목"), 아니면 나열("금·토")
  static String _labelForDays(List<int> days) {
    if (days.length >= 3) {
      var contiguous = true;
      for (var i = 1; i < days.length; i++) {
        if (days[i] != days[i - 1] % 7 + 1) {
          contiguous = false;
          break;
        }
      }
      if (contiguous) {
        return '${kWeekdayLabels[days.first - 1]}~${kWeekdayLabels[days.last - 1]}';
      }
    }
    return days.map((d) => kWeekdayLabels[d - 1]).join('·');
  }

  static String _holidayLabel(String raw) {
    final s = raw.replaceAll(RegExp(r'\s+'), '');
    switch (s) {
      case '특정휴일':
        return '특정 휴일';
      case '특정공휴일':
        return '특정 공휴일';
      case '공휴일전날':
        return '공휴일 전날';
      case '휴일전날':
        return '휴일 전날';
      case '법정공휴일':
        return '공휴일';
      default:
        return s.startsWith('특정') ? '특정 ${s.substring(2)}' : s;
    }
  }
}

class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
}

/// 숙박 체험단인지: 숙박 카테고리이거나 제목·제공 내역에 숙박 관련 말이 있으면 true
/// (리뷰노트 등은 숙소를 "여행"으로 분류하는 경우가 많아 글로도 판단)
bool isLodgingCampaign({int? categoryId, String? title, String? offer}) {
  if (categoryId == kLodgingCategoryId) return true;
  final text = '${title ?? ''} ${offer ?? ''}';
  return _lodgingWords.hasMatch(text);
}

final RegExp _lodgingWords = RegExp(
    r'(숙박|객실|투숙|입실|체크인|\d\s*박|펜션|호텔|모텔|리조트|글램핑|캠핑|카라반|게스트\s*하우스|풀빌라|스테이|민박|한옥|독채|콘도|레지던스|호스텔|빌라|오토캠핑|차박)');

/// 숙박 체험단이면 이용 요일 정보를, 아니면 null을 돌려줍니다.
StayAvailability? stayAvailabilityFor({int? categoryId, String? title, String? offer}) {
  if (!isLodgingCampaign(categoryId: categoryId, title: title, offer: offer)) {
    return null;
  }
  return StayAvailability.parse(offer);
}
