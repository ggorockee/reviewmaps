import 'package:flutter/material.dart';

/// Store
/// --------------------------------------------
/// 단일 캠페인/업체 정보를 담는 도메인 모델.
/// - 서버 JSON을 안전하게 파싱(factory fromJson)
/// - 거리(distance) 계산 후 상태 업데이트를 위한 copyWith 제공
/// - lat/lng, imageUrl, offer 등은 nullable로 정의(백엔드별 스키마 편차 대응)
class Store {
  /// 고유 식별자 (필수)
  final int id;

  /// 유입 플랫폼명(예: '가보자', '레뷰' 등) (필수)
  final String platform;

  /// 업체명/캠페인명 (필수)
  final String company;

  /// 상세 링크 (선택)
  final String? companyLink;

  /// 제공 혜택/오퍼 (선택)
  final String? offer;

  /// 위도/경도 (선택)
  final double? lat;
  final double? lng;

  /// 이미지 URL (선택)
  final String? imageUrl;

  /// 신청 마감일 (선택)
  final DateTime? applyDeadline;

  /// 생성 시각(정렬 기준, 필수)
  final DateTime createdAt;

  /// 현재 위치로부터의 거리(m 단위 등, 클라이언트 계산 필드 → 선택)
  double? distance;

  final bool isNew; //  isNew 필드


  Store({
    required this.id,
    required this.platform,
    required this.company,
    required this.createdAt,
    this.companyLink,
    this.offer,
    this.lat,
    this.lng,
    this.imageUrl,
    this.applyDeadline,
    this.distance,
    this.isNew = false,
  });

  /// JSON → Store 안전 파싱
  /// --------------------------------------------
  /// - 숫자/문자 혼용 대응(toD)
  /// - 날짜 문자열 안전 파싱(toDt) : 실패 시 null
  /// - imageUrl 키 편차 대응: `imageUrl` 또는 `img_url`를 우선순위로 조회
  /// - created_at은 반드시 존재해야 하므로 `DateTime.parse` 사용 (없으면 런타임 에러로 즉시 감지)
  factory Store.fromJson(Map<String, dynamic> j) {
    double? toD(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

    DateTime? toDt(dynamic v) => v is String ? DateTime.tryParse(v) : null;

    // id는 서버마다 int 또는 string일 수 있으므로 유연하게 처리
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      final parsed = int.tryParse('$v');
      if (parsed == null) {
        throw FormatException('Invalid id in Store.fromJson: $v');
      }
      return parsed;
    }

    final createdAtRaw = j['created_at'];
    if (createdAtRaw == null) {
      // 필수 값 누락은 명확히 실패시켜 문제를 조기에 드러냄
      throw FormatException('Missing required field: created_at');
    }

    // imageUrl은 여러 키 중 하나를 사용
    final img = (j['imageUrl'] as String?) ??
        (j['img_url'] as String?) ??
        (j['image_url'] as String?); // 혹시 다른 백엔드 변형도 고려

    return Store(
      id: toInt(j['id']),
      platform: j['platform'] as String,
      company: j['company'] as String,
      companyLink: j['company_link'] as String?,
      offer: j['offer'] as String?,
      lat: toD(j['lat']),
      lng: toD(j['lng']),
      imageUrl: img,
      createdAt: DateTime.parse(createdAtRaw as String),
      applyDeadline: toDt(j['apply_deadline']),
      distance: (j['distance'] as num?)?.toDouble(),
      isNew: j['is_new'] as bool? ?? false,
    );
  }

  /// 거리만 갱신(또는 향후 다른 필드 확장)할 때 사용하는 샬로우 카피
  Store copyWith({double? distance}) {
    return Store(
      id: id,
      platform: platform,
      company: company,
      companyLink: companyLink,
      offer: offer,
      lat: lat,
      lng: lng,
      imageUrl: imageUrl,
      createdAt: createdAt,
      applyDeadline: applyDeadline,
      distance: distance ?? this.distance,
    );
  }
}

/// -------------------------------
/// 로고/배너 이미지 경로 유틸
/// -------------------------------
/// - 중복된 switch 문을 없애고 Map 기반으로 정리
/// - 미스스펠/파일명 불일치가 있을 수 있어, 현재 네이밍은
///   기존 코드를 최대한 보수적으로 유지함(파일 시스템과 맞춰 사용)
///
/// 경로 규칙:
///  - 로고:  'asset/image/logo/<파일명>'
///  - 배너:  'asset/image/banner/<파일명>'
///
/// 기본값:
///  - 로고:  빈 문자열("") 반환 → 호출부에서 placeholder 판단
///  - 배너:  'asset/image/banner/reviewmaps.png'

/// 플랫폼별 로고 파일명 매핑
const Map<String, String> _platformLogoFile = {
  '스토리앤미디어': 'storymedia.png',
  '링블': 'ringble.png',
  '캐시노트': 'cashnote.png',
  '놀러와': 'noleowa.png', // (주석 참고) 프로젝트 내 실제 파일명 확인 필요
  '체허미': 'chehumi.png',
  '링뷰': 'ringvue.png',
  '미블': 'mrble.png',
  '체험뷰': 'chehumview.png',
  '강남맛집': 'gannam.png',
  '가보자': 'gaboja.png',
  '레뷰': 'revu.png',
  '포블로그': '4blog2.png',
  '포포몬': 'popomon.png',
  '리뷰노트': 'reviewnote.png',
  '리뷰플레이스': 'logo_on.png',
  '디너의여왕': 'dinnerqueen.png',
  '아싸뷰': 'assaview.png',
  '체리뷰': 'cherryview.png',
  '오마이블로그': 'ohmyblog.png',
  '구구다스': 'gugudas.png',
  // ⚠️ 필요한 경우 여기에 계속 추가
};

/// 플랫폼별 배너 파일명 매핑
const Map<String, String> _platformBannerFile = {
  '스토리앤미디어': 'storymedia.png',
  '링블': 'ringble.png',
  '캐시노트': 'cashnote.png',
  '놀러와': 'noleowa.png',
  '체허미': 'chehumi.png',
  '링뷰': 'ringvue.png',
  '미블': 'mrble.png',
  '강남맛집': 'gannam.png',
  '가보자': 'gaboja.png',
  '레뷰': 'revu.png',
  '포블로그': 'fourblog.png', // 로고와 다름(4blog2 vs fourblog) → 파일 존재 확인 필요
  '포포몬': 'popomon.png',
  '리뷰노트': 'reviewnote.png',
  '리뷰플레이스': 'reviewplace.png',
  '디너의여왕': 'dinnerqueen.png',
  '체험뷰': 'chehubview.png', // 로고의 chehumview와 철자 다름 → 파일 존재 확인 필요
  '아싸뷰': 'assaview.png',
  '체리뷰': 'cherryview.png',
  '오마이블로그': 'ohmyblog.png',
  '구구다스': 'gugudas.png',
  // ⚠️ 필요한 경우 여기에 계속 추가
};

/// 내부 공통: 로고 경로 생성기
String _logoPath(String fileName) => 'asset/image/logo/$fileName';

/// 내부 공통: 배너 경로 생성기
String _bannerPath(String fileName) => 'asset/image/banner/$fileName';

/// 플랫폼명 → 로고 경로
/// - 매핑 없으면 빈 문자열 반환(호출부에서 placeholder 처리)
String getLogoPathForPlatform(String platformName) {
  final file = _platformLogoFile[platformName];
  if (file == null || file.isEmpty) return '';
  return _logoPath(file);
}

/// 플랫폼명 → 배너 경로
/// - 매핑 없으면 기본 배너 이미지 경로 반환
String getbannerPathForPlatform(String platformName) {
  final file = _platformBannerFile[platformName];
  if (file == null || file.isEmpty) {
    return 'asset/image/banner/reviewmaps.png';
  }
  return _bannerPath(file);
}
