/// 키워드 알람 관련 모델 클래스들
/// - API 요청/응답 데이터 구조 정의
/// - JSON 직렬화/역직렬화 지원
library;

/// 키워드 등록 요청 데이터
class KeywordRegisterRequest {
  final String keyword;

  KeywordRegisterRequest({
    required this.keyword,
  });

  Map<String, dynamic> toJson() => {
    'keyword': keyword,
  };
}

/// 키워드 정보
class KeywordInfo {
  final int id;
  final String keyword;
  final bool isActive;
  final String createdAt;

  KeywordInfo({
    required this.id,
    required this.keyword,
    required this.isActive,
    required this.createdAt,
  });

  factory KeywordInfo.fromJson(Map<String, dynamic> json) {
    return KeywordInfo(
      id: json['id'] as int,
      keyword: json['keyword'] as String,
      isActive: json['is_active'] as bool,
      createdAt: json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'keyword': keyword,
    'is_active': isActive,
    'created_at': createdAt,
  };
}

/// 키워드 목록 응답 데이터
class KeywordListResponse {
  final List<KeywordInfo> keywords;

  KeywordListResponse({
    required this.keywords,
  });

  factory KeywordListResponse.fromJson(Map<String, dynamic> json) {
    final keywordsList = json['keywords'] as List<dynamic>;
    return KeywordListResponse(
      keywords: keywordsList
          .map((item) => KeywordInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 알람 정보
class AlertInfo {
  final int id;
  final String keyword;
  final int campaignId;
  final String campaignTitle;
  final String? campaignCompany; // 업체명
  final String? campaignOffer;
  final String? campaignAddress;
  final double? campaignLat;
  final double? campaignLng;
  final String? campaignImgUrl;
  final String? campaignPlatform; // 플랫폼
  final DateTime? campaignApplyDeadline; // 신청 마감일
  final String? campaignContentLink; // 콘텐츠 링크
  final String? campaignChannel; // 캠페인 채널
  final String matchedField;
  final bool isRead;
  final String createdAt;
  final double? distance; // 거리 (km)

  AlertInfo({
    required this.id,
    required this.keyword,
    required this.campaignId,
    required this.campaignTitle,
    this.campaignCompany,
    this.campaignOffer,
    this.campaignAddress,
    this.campaignLat,
    this.campaignLng,
    this.campaignImgUrl,
    this.campaignPlatform,
    this.campaignApplyDeadline,
    this.campaignContentLink,
    this.campaignChannel,
    required this.matchedField,
    required this.isRead,
    required this.createdAt,
    this.distance,
  });

  factory AlertInfo.fromJson(Map<String, dynamic> json) {
    // 서버 응답: 중첩된 keyword/campaign 객체 구조
    final keywordObj = json['keyword'] as Map<String, dynamic>?;
    final campaignObj = json['campaign'] as Map<String, dynamic>?;

    return AlertInfo(
      id: json['id'] as int,
      keyword: keywordObj?['keyword'] as String? ?? '',
      campaignId: json['campaign_id'] as int? ?? campaignObj?['id'] as int? ?? 0,
      campaignTitle: campaignObj?['title'] as String? ?? '',
      campaignCompany: campaignObj?['company'] as String?,
      campaignOffer: campaignObj?['offer'] as String?,
      campaignAddress: campaignObj?['address'] as String?,
      campaignLat: campaignObj?['lat'] != null
          ? (campaignObj!['lat'] as num).toDouble()
          : null,
      campaignLng: campaignObj?['lng'] != null
          ? (campaignObj!['lng'] as num).toDouble()
          : null,
      campaignImgUrl: campaignObj?['img_url'] as String?,
      campaignPlatform: campaignObj?['platform'] as String?,
      campaignApplyDeadline: campaignObj?['apply_deadline'] != null
          ? DateTime.tryParse(campaignObj!['apply_deadline'] as String)
          : null,
      campaignContentLink: campaignObj?['content_link'] as String?,
      campaignChannel: campaignObj?['campaign_channel'] as String?,
      matchedField: json['matched_field'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      distance: json['distance'] != null
          ? (json['distance'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'keyword': keyword,
    'campaign_id': campaignId,
    'campaign_title': campaignTitle,
    'campaign_company': campaignCompany,
    'campaign_offer': campaignOffer,
    'campaign_address': campaignAddress,
    'campaign_lat': campaignLat,
    'campaign_lng': campaignLng,
    'campaign_img_url': campaignImgUrl,
    'campaign_platform': campaignPlatform,
    'campaign_apply_deadline': campaignApplyDeadline?.toIso8601String(),
    'campaign_content_link': campaignContentLink,
    'campaign_channel': campaignChannel,
    'matched_field': matchedField,
    'is_read': isRead,
    'created_at': createdAt,
    'distance': distance,
  };

  /// 거리 표시 문자열 (예: "1.5km", "500m")
  String get distanceText {
    if (distance == null) return '';
    if (distance! < 1) {
      return '${(distance! * 1000).round()}m';
    }
    return '${distance!.toStringAsFixed(1)}km';
  }

  /// D-day 계산 (음수: 지남, 양수: 남음)
  int? get dDay {
    if (campaignApplyDeadline == null) return null;
    final now = DateTime.now();
    final deadline = campaignApplyDeadline!;
    return deadline.difference(now).inDays;
  }

  /// D-day 표시 문자열
  String get dDayText {
    final d = dDay;
    if (d == null) return '';
    if (d == 0) return 'D-Day';
    if (d > 0) return 'D-$d';
    return '마감';
  }
}

/// 알람 목록 응답 데이터
class AlertListResponse {
  final List<AlertInfo> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  AlertListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory AlertListResponse.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>? ?? [];
    return AlertListResponse(
      items: itemsList
          .map((item) => AlertInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
      totalPages: json['total_pages'] as int? ?? 0,
    );
  }

  /// 하위 호환성을 위한 getter
  List<AlertInfo> get alerts => items;
  int get unreadCount => items.where((a) => !a.isRead).length;
}

/// 알람 읽음 처리 요청 데이터
class MarkAlertsReadRequest {
  final List<int> alertIds;

  MarkAlertsReadRequest({
    required this.alertIds,
  });

  Map<String, dynamic> toJson() => {
    'alert_ids': alertIds,
  };
}
