import 'package:flutter/material.dart';

const PRIMARY_COLOR = Color(0xFF22A45D);

Color platformBadgeColor(String platform) {
  switch (platform) {
    case '스토리앤미디어': return Color(0xFFa83828);
    case '링블': return Color(0xFF2d62cd);
    case '캐시노트': return Color(0xFF1d2d79);
    case '놀러와': return Color(0xFFbb7138);
    case '체허미': return Color(0xFFe27062);
    case '링뷰': return Color(0xFF80a1bd);
    case '미블': return Color(0xFF80bd92);
    case '강남맛집': return Color(0xFFe3763f);
    case '가보자': return Color(0xFF9fc162);
    case '레뷰': return Color(0xFF9038ee);
    case '포블로그': return Color(0xFFb49fc4);
    case '포포몬': return Color(0xFF7d6fef);
    case '리뷰노트': return Color(0xFF729287);
    case '리뷰플레이스': return Color(0xFF6355f2);
    case '디너의여왕': return Color(0xFFda5f9d);
    case '체험뷰': return Color(0xFFc76284);
    case '아싸뷰': return Color(0xFF5ac6d9);
    default: return Colors.black54;
  }
}