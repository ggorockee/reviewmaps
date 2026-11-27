import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/utils/stay_availability.dart';

/// 실제 숙박 체험단 제공 내역(2026-11-27 운영 API·리뷰노트 수집분)으로 검증
void main() {
  StayAvailability? p(String s) => StayAvailability.parse(s);

  group('이용 가능 요일', () {
    test('평일 + 괄호 범위', () {
      final r = p('평일(일-목) 1박 숙박권 (최대 2인가능)')!;
      expect(r.availableText, '평일(일~목)');
      expect(r.availableDays, {7, 1, 2, 3, 4});
      expect(r.excludedText, isNull);
    });

    test('평일 가능 (월~목)', () {
      final r = p('1박 숙박권(영유아 포함 최대 4인, 38만원 상당),  평일 가능 (월~목), 바베큐 신청시(3만원)')!;
      expect(r.availableText, '평일(월~목)');
      expect(r.availableDays, {1, 2, 3, 4});
    });

    test('평일 월~목요일 이용권', () {
      expect(p('평일 월~목요일 이용권 (약 60~70만원) A동 B동은 랜덤배정')!.availableText, '평일(월~목)');
    });

    test('범위만: (일~목)', () {
      final r = p('2인 기준 / 1일 숙박권 (일~목) / 객실 랜덤 제공')!;
      expect(r.availableText, '일~목');
      expect(r.weekdaysOnly, isFalse);
    });

    test('본문 중간 범위: 일~목 중 협의', () {
      final r = p('감포라온 독채 숙소 평일 1박 숙박권 제공 (기준 3인, 정상가 250,000원) - 일~목 중 협의된 날짜 이용 - 숙소 내 기본 편의시설 이용')!;
      expect(r.availableText, '평일(일~목)');
    });

    test('평일만 쓴 경우', () {
      expect(p('평일 1일 숙박 체험권 (2인 기준)')!.availableText, '평일만');
      expect(p('평일1박숙박권')!.availableText, '평일만');
      expect(p('50만원 상당의 평일 1박 숙박 체험권 (4인 기준)')!.availableText, '평일만');
      expect(p('평일 1박 숙박권 (4인 기준)')!.dayState(6), isNull);
    });

    test('붙여 쓴 요일·나열', () {
      expect(p('월화수목 이용 가능 숙박권')!.availableText, '월~목');
      expect(p('월,수 숙박 가능')!.availableText, '월·수');
    });

    test('일요일만', () {
      final r = p('일요일만 숙박 가능 2인')!;
      expect(r.availableText, '일');
      expect(r.availableDays, {7});
    });

    test('지정일', () {
      expect(p('12월5일 숙박권,무료인원4인(인원초과시 비용 별도)')!.availableText, '12/5');
    });
  });

  group('이용 불가', () {
    test('(토요일제외)', () {
      final r = p('베스트필드 1박2일 숙박권 (토요일제외) (추가금액 없으며 드실것만 따로 사오시면 됩니다)')!;
      expect(r.excludedText, '토');
      expect(r.excludedDays, {6});
      expect(r.availableText, isNull);
      expect(r.dayState(6), isFalse);
    });

    test('토요일 및 공휴일제외', () {
      expect(p('오션뷰풀빌라 2인숙박권 + 불멍 (토요일 및 공휴일제외)')!.excludedText, '토·공휴일');
    });

    test('특정 휴일 제외', () {
      expect(p('카라반1박 및 바베큐/ 20만원상당 / 특정 휴일 제외')!.excludedText, '특정 휴일');
    });

    test('금,토 불가 / 금토 불가', () {
      expect(p('1박 숙박권 (금,토 불가)')!.excludedText, '금·토');
      expect(p('1박 숙박권 금토 불가')!.excludedText, '금·토');
    });

    test('가능 + 불가 함께', () {
      final r = p('평일(일~목) 1박 숙박권 / 공휴일 및 성수기 제외')!;
      expect(r.availableText, '평일(일~목)');
      expect(r.excludedText, '공휴일·성수기');
    });

    test('주말 불가는 글로만 표시', () {
      final r = p('1박 숙박권 (주말 불가)')!;
      expect(r.excludedText, '주말');
      expect(r.excludedDays, isEmpty);
    });
  });

  group('표시하지 않아야 하는 경우 (오탐 방지)', () {
    for (final s in [
      '한옥스테이 숙박권제공 (평일 45만원 상당)',
      '① 이용료 무료 (주말기준 42만원) + ② 자쿠지 무료 (3만원)',
      '인제주 게스트하우스 1박 숙박권 (평일 기준 / 80,000원 상당)',
      '1일 무료숙박제공 (1일 평일 18만원 이상 숙박료) 독채 (2팀모집) 최대인원2명',
      '호텔 1일 숙박-501호 디럭스 최대 3인 평일 10만원',
      '1박 2일 독채펜션 30만 원 상당 제공! 기준 2인, 추가 1인당 2만 원. 애견 동반 불가.',
      '독채펜션 숙박권(3인 기준/🚨인원 추가 불가, 애견 동반은 예약 시 확인)',
      '1인 침대 한자리 2박(조식 포함) 1박만 이용 및 1인실 업글 불가',
      '1박 숙박이용권 자쿠지 가능  바베큐x',
      '(숙박x)당일치기 글램핑 + 웨버그릴제공 (148,500원 상당)',
      '목살 2인분 + 고구마 + 버섯 + 한강라면 2개 + 불멍(밤에 제공)',
      '수목원 인근 펜션 1박 숙박권',
      '5박 6일 숙박 무료 지원(2인 1실)',
      '1박2일 숙박권 - 목포 시내 위치',
      '평일, 주말 모두 가능 1박 숙박권',
      '평일 또는 주말 선택 1박',
      '요일 무관 1박 숙박권',
      '4월~6월 1박 숙박권',
      '',
    ]) {
      test(s.isEmpty ? '(빈 문자열)' : s, () => expect(p(s), isNull));
    }

    test('주말 추가요금은 제한 아님', () {
      expect(p('평일 1박 숙박권 (주말 추가요금 3만원)')!.availableText, '평일만');
    });
  });

  group('숙박 체험단 판별', () {
    test('숙박 카테고리', () {
      expect(isLodgingCampaign(categoryId: kLodgingCategoryId, title: '아무개', offer: '체험권'), isTrue);
    });
    test('여행 카테고리여도 글에 숙박 말이 있으면', () {
      expect(isLodgingCampaign(categoryId: 12, title: '스테이수채화', offer: '1박 숙박권'), isTrue);
      expect(isLodgingCampaign(title: '포천 글램포레 글램핑', offer: '바베큐 제공'), isTrue);
    });
    test('맛집은 제외', () {
      expect(isLodgingCampaign(categoryId: 1, title: '꽁크 압구정본점', offer: '평일 디너 5만원 이용권'), isFalse);
      expect(stayAvailabilityFor(categoryId: 1, title: '꽁크 압구정본점', offer: '평일 디너 이용권'), isNull);
    });
  });

  group('문구', () {
    test('낭독기 문장', () {
      expect(p('평일(일~목) 1박 / 공휴일 제외')!.semanticsLabel, '평일(일~목) 이용 가능, 공휴일 이용 불가');
    });
  });

  // 2026-11-27 리뷰노트 여행 상세 수집(possible_days / impossible_days) 실제 값 형태
  group('상세 페이지 정보 우선 (fromDetail / stayAvailabilityFor)', () {
    test('일요일을 넘어가는 범위는 "일~목"으로', () {
      final r = StayAvailability.fromDetail(possibleDays: '월 / 화 / 수 / 목 / 일')!;
      expect(r.availableText, '일~목');
      expect(r.availableDays, {1, 2, 3, 4, 7});
      expect(r.dayState(5), isFalse);
      expect(r.dayState(7), isTrue);
      expect(r.hasExplicitDays, isTrue);
    });

    test('하루만 가능', () {
      expect(StayAvailability.fromDetail(possibleDays: '금')!.availableText, '금');
    });

    test('이어지지 않는 요일은 나열', () {
      expect(StayAvailability.fromDetail(possibleDays: '월 / 수 / 금')!.availableText, '월·수·금');
    });

    test('7일 모두 가능하고 불가 정보가 없으면 표시 안 함', () {
      expect(StayAvailability.fromDetail(possibleDays: '월 / 화 / 수 / 목 / 금 / 토 / 일'), isNull);
      expect(StayAvailability.fromDetail(possibleDays: '매일'), isNull);
    });

    test('불가 요일·공휴일', () {
      final r = StayAvailability.fromDetail(
        possibleDays: '월 / 화 / 수 / 목 / 금 / 토 / 일',
        impossibleDays: '토 / 공휴일',
      )!;
      expect(r.availableText, '일~금'); // 7일 중 불가(토)를 뺀 나머지
      expect(r.excludedText, '토·공휴일');
      expect(r.dayState(6), isFalse);
    });

    test('상세에 "평일"만 적혀 있으면 이용 가능은 표시 안 함', () {
      expect(StayAvailability.fromDetail(possibleDays: '평일'), isNull);
    });

    test('상세 정보가 있으면 제공 내역 글보다 우선', () {
      final r = stayAvailabilityFor(
        categoryId: kLodgingCategoryId,
        title: '푸른바다스파펜션',
        offer: '평일 1박 숙박권 (4인 기준)',
        possibleDays: '월 / 화 / 수 / 목 / 일',
      )!;
      expect(r.availableText, '일~목');
      expect(r.weekdaysOnly, isFalse);
    });

    test('숙박이 아니어도 상세 요일이 있으면 표시 (공연 등)', () {
      final r = stayAvailabilityFor(title: '원테이블 매직', offer: '2인 공연 초대권', possibleDays: '금');
      expect(r?.availableText, '금');
    });

    test('상세 정보가 없으면 애매한 "평일만"은 표시하지 않음', () {
      expect(stayAvailabilityFor(categoryId: kLodgingCategoryId, title: '펜션', offer: '평일 1박 숙박권 (4인 기준)'), isNull);
      expect(stayAvailabilityFor(title: '라벤더온천텔', offer: '평일 숙박 or 대실 체험권 (2인 기준)'), isNull);
    });

    test('상세 정보가 없어도 요일이 분명한 문구는 표시', () {
      expect(stayAvailabilityFor(title: '펜션', offer: '평일(일-목) 1박 숙박권')!.availableText, '평일(일~목)');
      final r = stayAvailabilityFor(title: '펜션', offer: '평일 1박 숙박권 (토요일 및 공휴일제외)')!;
      expect(r.availableText, isNull);
      expect(r.excludedText, '토·공휴일');
    });
  });
}
