import 'package:flutter/material.dart';

/// 앱 공통 메인 컬러
/// - 브랜드 아이덴티티 컬러 (#22A45D)
/// - MaterialApp의 primaryColor, SeedColor 등에 활용됨
const PRIMARY_COLOR = Color(0xFF22A45D);

/// 플랫폼별 뱃지 색상 매핑 함수
/// --------------------------------------------
/// [platform] 문자열 값에 따라 지정된 Color를 반환.
/// UI에서 각 플랫폼의 아이덴티티 컬러를 표현할 때 사용됨.
///
/// 예시:
/// ```dart
/// Container(
///   color: platformBadgeColor(store.platform),
///   child: Text(store.platform),
/// )
/// ```
///
/// ⚠️ 매핑되지 않은 플랫폼 이름이 들어올 경우 `Colors.black54` 반환.
Color platformBadgeColor(String platform) {
  switch (platform) {
    case '스토리앤미디어': return const Color(0xFFa83828); // 레드톤
    case '링블': return const Color(0xFF2d62cd);            // 블루
    case '캐시노트': return const Color(0xFF1d2d79);        // 네이비
    case '놀러와': return const Color(0xFFbb7138);          // 브라운톤
    case '체허미': return const Color(0xFFe27062);          // 코랄
    case '링뷰': return const Color(0xFF80a1bd);            // 그레이블루
    case '미블': return const Color(0xFF80bd92);            // 민트그린
    case '강남맛집': return const Color(0xFFe3763f);        // 오렌지
    case '가보자': return const Color(0xFF9fc162);          // 올리브그린
    case '레뷰': return const Color(0xFF9038ee);            // 퍼플
    case '포블로그': return const Color(0xFFb49fc4);        // 라벤더
    case '포포몬': return const Color(0xFF7d6fef);          // 바이올렛
    case '리뷰노트': return const Color(0xFF729287);        // 톤다운 그린
    case '리뷰플레이스': return const Color(0xFF6355f2);    // 블루퍼플
    case '디너의여왕': return const Color(0xFFda5f9d);      // 핑크
    case '체험뷰': return const Color(0xFFc76284);          // 와인핑크
    case '아싸뷰': return const Color(0xFF5ac6d9);          // 시원한 블루
    case '구구다스': return const Color(0xFFd34540);
    default: return Colors.black54; // 기본값: 매칭 없는 경우 회색톤
  }
}
