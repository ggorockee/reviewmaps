import 'package:flutter/material.dart';

/// 앱 공통 메인 컬러
/// - 브랜드 아이덴티티 컬러 (#22A45D)
/// - MaterialApp의 primaryColor, SeedColor 등에 활용됨
const primaryColor = Color(0xFF22A45D);

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
    case '체허미': return const Color(0xFFe27062);          // 코랄
    case '체험뷰': return const Color(0xFFc76284);          // 와인핑크
    case '체리뷰': return const Color(0xFFd34540);          // 오렌지
    case '디너의여왕': return const Color(0xFFda5f9d);      // 핑크
    case '가보자': return const Color(0xFF9fc162);          // 올리브그린
    case '강남맛집': return const Color(0xFFe3763f);        // 오렌지
    case '구구다스': return const Color(0xFFd34540);
    case '미블': return const Color(0xFF80bd92);            // 민트그린
    case '놀러와': return const Color(0xFFbb7138);          // 브라운톤
    case '오마이블로그': return const Color(0xFF80a1bd); // 색상확인인     // 그레이블루
    case '포포몬': return const Color(0xFF7d6fef);          // 바이올렛
    case '리뷰노트': return const Color(0xFF3195d3);       //
    case '리뷰플레이스': return const Color(0xFF6355f2);    // 블루퍼플
    case '레뷰': return const Color(0xFF9038ee);            // 퍼플
    case '링뷰': return const Color(0xFF80a1bd);            // 그레이블루
    case '포블로그': return const Color(0xFFb49fc4);        // 라벤더
    case '아싸뷰': return const Color(0xFF5ac6d9);          // 시원한 블루
    case '티블': return const Color(0xFF9854a7);           // 색상확인 // 라벤더
    case '디노단': return const Color(0xFF55754d);          // 초록
    case '데일리뷰': return const Color(0xFF669759);          // 라이트그린
    case '똑똑체험단': return const Color(0xFF729287);          // 톤다운 그린
    case '리뷰메이커': return const Color(0xFFfb4884);          // 톤다운 그린
    case '리뷰어랩': return const Color(0xFFda1a42);
    case '리뷰어스': return const Color(0xFF2f52a0);
    case '리뷰웨이브': return const Color(0xFF0f5fff);
    case '리뷰윙': return const Color(0xFF559e9d);
    case '리뷰퀸': return const Color(0xFFeea6ce);
    case '리얼리뷰': return const Color(0xFFe30221);
    case '마녀체험단': return const Color(0xFF18ce5f);
    case '모두의블로그': return const Color(0xFF1c8bf9);
    case '모두의체험단': return const Color(0xFF39b54a);
    case '뷰티의여왕': return const Color(0xFFcf83d9);
    case '블로그원정대': return const Color(0xFF6e77f2);
    case '서울오빠': return const Color(0xFF6292ff);
    case '서포터즈픽': return const Color(0xFFff5929);
    case '샐러뷰': return const Color(0xFFe93f98);
    case '시원뷰': return const Color(0xFF1187cf);
    case '와이리': return const Color(0xFF2ec8c8);
    case '이음체험단': return const Color(0xFF4646f2);
    case '츄블': return const Color(0xFFf2651c);
    case '클라우드리뷰': return const Color(0xFF00aeef);
    case '키플랫체험단': return const Color(0xFFf76918);
    case '택배의여왕': return const Color(0xFF142f64);
    case '파블로체험단': return const Color(0xFF85ccc9);
    case '후기업': return const Color(0xFFff2cb6);
    case '플레이체험단': return const Color(0xFF576179);
    case '태그바이': return const Color(0xFF005ff0);
    default: return Colors.black54; // 기본값: 매칭 없는 경우 회색톤
  }
}
