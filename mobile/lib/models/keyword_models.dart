/// 키워드 알람 관련 모델 클래스들
/// - API 요청/응답 데이터 구조 정의
/// - JSON 직렬화/역직렬화 지원

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
  final String? campaignOffer;
  final String? campaignAddress;
  final double? campaignLat;
  final double? campaignLng;
  final String? campaignImgUrl;
  final String matchedField;
  final bool isRead;
  final String createdAt;
  final double? distance; // 거리 (km)

  AlertInfo({
    required this.id,
    required this.keyword,
    required this.campaignId,
    required this.campaignTitle,
    this.campaignOffer,
    this.campaignAddress,
    this.campaignLat,
    this.campaignLng,
    this.campaignImgUrl,
    required this.matchedField,
    required this.isRead,
    required this.createdAt,
    this.distance,
  });

  factory AlertInfo.fromJson(Map<String, dynamic> json) {
    return AlertInfo(
      id: json['id'] as int,
      keyword: json['keyword'] as String,
      campaignId: json['campaign_id'] as int,
      campaignTitle: json['campaign_title'] as String,
      campaignOffer: json['campaign_offer'] as String?,
      campaignAddress: json['campaign_address'] as String?,
      campaignLat: json['campaign_lat'] != null
          ? (json['campaign_lat'] as num).toDouble()
          : null,
      campaignLng: json['campaign_lng'] != null
          ? (json['campaign_lng'] as num).toDouble()
          : null,
      campaignImgUrl: json['campaign_img_url'] as String?,
      matchedField: json['matched_field'] as String,
      isRead: json['is_read'] as bool,
      createdAt: json['created_at'] as String,
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
    'campaign_offer': campaignOffer,
    'campaign_address': campaignAddress,
    'campaign_lat': campaignLat,
    'campaign_lng': campaignLng,
    'campaign_img_url': campaignImgUrl,
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
}

/// 알람 목록 응답 데이터
class AlertListResponse {
  final List<AlertInfo> alerts;
  final int unreadCount;

  AlertListResponse({
    required this.alerts,
    required this.unreadCount,
  });

  factory AlertListResponse.fromJson(Map<String, dynamic> json) {
    final alertsList = json['alerts'] as List<dynamic>;
    return AlertListResponse(
      alerts: alertsList
          .map((item) => AlertInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
      unreadCount: json['unread_count'] as int,
    );
  }
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
