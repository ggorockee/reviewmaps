/// Store
/// --------------------------------------------
/// 단일 캠페인/업체 정보를 담는 도메인 모델.
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
  final double? distance;

  /// 신규 여부
  final bool isNew;

  /// 캠페인 채널(예: "blog,instagram,youtube")
  final String? campaignChannel;

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
    this.campaignChannel,
  });

  /// etc/unknown 제외한 채널 리스트 (소문자, trim 완료)
  List<String> get channels {
    if (campaignChannel == null || campaignChannel!.trim().isEmpty) return const [];
    return campaignChannel!
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty && e != 'etc' && e != 'unknown')
        .toList(growable: false);
  }

  /// JSON → Store 안전 파싱
  factory Store.fromJson(Map<String, dynamic> j) {
    double? toD(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    DateTime? toDt(dynamic v) {
      if (v == null) return null;
      final dt = DateTime.tryParse('$v');
      return dt?.toLocal(); // ✅ 로컬 변환
    }
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      final p = int.tryParse('$v');
      if (p == null) throw FormatException('Invalid id in Store.fromJson: $v');
      return p;
    }
    String? normChannel(dynamic v) {
      if (v == null) return null;
      if (v is List) {
        return v.map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .join(',');
      }
      return v.toString()
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .join(',');
    }

    final createdRaw = j['created_at'] ?? j['createdAt'];
    if (createdRaw == null) {
      throw FormatException('Missing required field: created_at/createdAt');
    }
    final created = toDt(createdRaw)!;

    final img = (j['imageUrl'] as String?) ??
        (j['img_url'] as String?) ??
        (j['image_url'] as String?);

    final isNewServer = (j['is_new'] == true) || (j['isNew'] == true);
    final isNewAuto = DateTime.now().difference(created).inHours < 72;

    return Store(
      id: toInt(j['id']),
      platform: (j['platform'] ?? '').toString().trim(),
      company: (j['company'] ?? '').toString().trim(),
      companyLink: (j['company_link'] ?? j['companyLink'])?.toString().trim(),
      offer: (j['offer'] as String?)?.trim(),
      lat: toD(j['lat']),
      lng: toD(j['lng']),
      imageUrl: img?.trim(),
      createdAt: created,
      applyDeadline: toDt(j['apply_deadline'] ?? j['applyDeadline']),
      distance: toD(j['distance'] ?? j['distance_km'] ?? j['distanceKm']),
      isNew: isNewServer || isNewAuto, // ✅ 서버 플래그 없으면 72h 규칙
      campaignChannel: normChannel(
        j['campaign_channel'] ?? j['campaignChannel'] ?? j['channels'] ?? j['channel'],
      ),
    );
  }


  /// 얕은 복사 (필요 필드 갱신)
  Store copyWith({
    int? id,
    String? platform,
    String? company,
    String? companyLink,
    String? offer,
    double? lat,
    double? lng,
    String? imageUrl,
    DateTime? applyDeadline,
    DateTime? createdAt,
    double? distance,
    bool? isNew,
    String? campaignChannel,
  }) {
    return Store(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      company: company ?? this.company,
      companyLink: companyLink ?? this.companyLink,
      offer: offer ?? this.offer,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      applyDeadline: applyDeadline ?? this.applyDeadline,
      distance: distance ?? this.distance,
      isNew: isNew ?? this.isNew,
      campaignChannel: campaignChannel ?? this.campaignChannel,
    );
  }
}

/// -------------------------------
/// 로고/배너 이미지 경로 유틸
/// -------------------------------

/// 플랫폼별 로고 파일명 매핑
const Map<String, String> _platformLogoFile = {
  '스토리앤미디어': 'storymedia.png',
  '링블': 'ringble.png',
  '캐시노트': 'cashnote.png',
  '놀러와': 'noleowa.png', // 프로젝트 내 실제 파일명 확인
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
  '리뷰플레이스': 'reviewplace.png',
  '디너의여왕': 'dinnerqueen.png',
  '아싸뷰': 'assaview.png',
  '체리뷰': 'cherryview.png',
  '오마이블로그': 'ohmyblog.png',
  '구구다스': 'gugudas.png',
  '티블': 'tble.png',
  // ------
  '디노단': 'dinodan.png',
  '데일리뷰': 'dailiview.png',
  '똑똑체험단': 'ddokddok.png',
  '리뷰메이커': 'reviewmaker.png',
  '리뷰어랩': 'reviewerlab.png',
  '리뷰어스': 'reviewus.png',
  '리뷰웨이브': 'reviewwave.png',
  '리뷰윙': 'reviewwing.png',
  '리뷰퀸': 'reviewqueen.png',
  '리얼리뷰': 'realreview.png',
  '마녀체험단': 'witch_review.png',
  '모두의블로그': 'moble.png',
  '모두의체험단': 'modan.png',
  '뷰티의여왕': 'beauti_queen.png',
  '블로그원정대': 'review_one.png',
  '서울오빠': 'seoulobba.png',
  '서포터즈픽': 'supporterzpick.png',
  '샐러뷰': 'celuvu.png',
  '시원뷰': 'coolvue.png',
  '와이리': 'waili.png',
  '이음체험단': 'iumchehum.png',
  '츄블': 'chuble.png',
  '클라우드리뷰': 'cloudreview.png',
  '키플랫체험단': 'keyplat.png',
  '택배의여왕': 'taebae_queen.png',
  '파블로체험단': 'pablochehum.png',
  '후기업': 'whogiup.png',
  '플레이체험단': 'playchehum.png',
  '태그바이': 'tagby.png',

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
  '포블로그': 'fourblog.png', // 로고와 파일명 다름 → 실제 파일 확인
  '포포몬': 'popomon.png',
  '리뷰노트': 'reviewnote.png',
  '리뷰플레이스': 'reviewplace.png',
  '디너의여왕': 'dinnerqueen.png',
  '체험뷰': 'chehubview.png', // 철자 확인 필요
  '아싸뷰': 'assaview.png',
  '체리뷰': 'cherryview.png',
  '오마이블로그': 'ohmyblog.png',
  '구구다스': 'gugudas.png',
  '티블': 'tble.png',
};

String _logoPath(String fileName) => 'asset/image/logo/$fileName';
String _bannerPath(String fileName) => 'asset/image/banner/$fileName';

/// 플랫폼명 → 로고 경로 (없으면 빈 문자열)
String getLogoPathForPlatform(String platformName) {
  final key = platformName.trim();
  final file = _platformLogoFile[key];
  if (file == null || file.isEmpty) return '';
  return _logoPath(file);
}

/// 플랫폼명 → 배너 경로 (없으면 기본)
String getBannerPathForPlatform(String platformName) {
  final key = platformName.trim();
  final file = _platformBannerFile[key];
  if (file == null || file.isEmpty) {
    return 'asset/image/banner/reviewmaps.png';
  }
  return _bannerPath(file);
}
