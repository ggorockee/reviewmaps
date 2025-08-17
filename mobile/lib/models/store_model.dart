class Store {
  final int id;
  final String platform;
  final String company;
  final String? companyLink;
  final String? offer;
  final double? lat;
  final double? lng;
  final String? imageUrl;
  final DateTime? applyDeadline; // 마감일 표시용 필드
  final DateTime createdAt; // 최신순 정렬을 위한 필수 필드
  double? distance;

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
  });

  factory Store.fromJson(Map<String, dynamic> j) {
    double? toD(v) =>
        (v == null) ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    DateTime? toDt(v) => (v is String) ? DateTime.tryParse(v) : null;

    return Store(
      id: j['id'] as int,
      platform: j['platform'] as String,
      company: j['company'] as String,
      companyLink: j['company_link'] as String?,
      offer: j['offer'] as String?,
      lat: toD(j['lat']),
      lng: toD(j['lng']),
      imageUrl: (j['imageUrl'] as String?) ?? (j['img_url'] as String?),
      createdAt: DateTime.parse(j['created_at'] as String),
      applyDeadline: toDt(j['apply_deadline']),
      distance: (j['distance'] as num?)?.toDouble(),
    );
  }

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

String getLogoPathForPlatform(String platformName) {
  String logoFileName;
  switch (platformName) {
    case '스토리앤미디어':
      logoFileName = 'storymedia.png';
      break;
    case '링블':
      logoFileName = 'ringble.png';
      break;
    case '캐시노트':
      logoFileName = 'cashnote.png';
      break;
    case '놀러와':
      logoFileName = 'noleowa.png'; // mobile/lib/public/image/logo/nollowa.png
      break;
    case '체허미':
      logoFileName = 'chehumi.png';
      break;
    case '링뷰':
      logoFileName = 'ringvue.png';
      break;
    case '미블':
      logoFileName = 'mrble.png';
      break;
    case '체험뷰':
      logoFileName = 'chehumview.png';
      break;
    case '강남맛집':
      logoFileName = 'gannam.png';
      break;
    case '가보자': // 두 플랫폼이 같은 로고를 쓴다면 이렇게 묶을 수 있습니다.
      logoFileName = 'gaboja.png';
      break;
    case '레뷰':
      logoFileName = 'revu.png';
      break;
    case '포블로그':
      logoFileName = '4blog2.png';
      break;
    case '포포몬':
      logoFileName = 'popomon.png';
      break;
    case '리뷰노트':
      logoFileName = 'reviewnote.png';
      break;
    case '리뷰플레이스':
      logoFileName = 'logo_on.png';
      break;
    case '디너의여왕':
      logoFileName = 'dinnerqueen.png';
      break;
    // --- 여기에 필요한 모든 플랫폼 케이스를 추가해주세요 ---

    default:
      // 목록에 없는 플랫폼이거나, 로고가 준비되지 않은 경우 보여줄 기본 이미지
      return '';
  }
  // 최종 경로를 조합하여 반환
  return 'asset/image/logo/$logoFileName';
}


String getbannerPathForPlatform(String platformName) {
  String logoFileName;
  switch (platformName) {
    case '스토리앤미디어':
      logoFileName = 'storymedia.png';
      break;
    case '링블':
      logoFileName = 'ringble.png';
      break;
    case '캐시노트':
      logoFileName = 'cashnote.png';
      break;
    case '놀러와':
      logoFileName = 'noleowa.png';
      break;
    case '체허미':
      logoFileName = 'chehumi.png';
      break;
    case '링뷰':
      logoFileName = 'ringvue.png';
      break;
    case '미블':
      logoFileName = 'mrble.png';
      break;
    case '강남맛집':
      logoFileName = 'gannam.png';
      break;
    case '가보자':
      logoFileName = 'gaboja.png';
      break;
    case '레뷰':
      logoFileName = 'revu.png';
      break;
    case '포블로그':
      logoFileName = 'fourblog.png';
    break;
    case '포포몬':
      logoFileName = 'popomon.png';
      break;
    case '리뷰노트':
      logoFileName = 'reviewnote.png';
      break;
    case '리뷰플레이스':
      logoFileName = 'reviewplace.png';
      break;
    case '디너의여왕':
      logoFileName = 'dinnerqueen.png';
      break;
    case '체험뷰':
      logoFileName = 'chehubview.png';
      break;
    case '아싸뷰':
      logoFileName = 'assaview.png';
      break;


  // --- 여기에 필요한 모든 플랫폼 케이스를 추가해주세요 ---

    default:
    // 목록에 없는 플랫폼이거나, 로고가 준비되지 않은 경우 보여줄 기본 이미지
      return 'asset/image/banner/reviewmaps.png';
  }
  // 최종 경로를 조합하여 반환
  return 'asset/image/banner/$logoFileName';
}
