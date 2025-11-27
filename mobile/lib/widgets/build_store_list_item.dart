import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/widgets/experience_card.dart';
import 'package:mobile/widgets/deadline_chips.dart';
import 'package:mobile/screens/home_screen.dart';

/// 스토어 리스트 아이템 위젯
class StoreListItem extends StatelessWidget {
  final Store store;
  final VoidCallback? onTap;
  final bool dense;
  final bool showDistance;

  const StoreListItem({
    super.key,
    required this.store,
    this.onTap,
    this.dense = false,
    this.showDistance = true,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: 80.h), // 최소 높이 설정
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 16.w), // 위아래 같은 여백 + 좌우 패딩
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 가장 왼쪽: 플랫폼 로고 (크게)
            _buildPlatformLogo(store.platform),
            SizedBox(width: 16.w),
            
            // 오른쪽: 텍스트 정보들
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 첫째줄: 타이틀 + 채널 + NEW (2줄까지 가능)
                  _buildTitleRow(isTablet),
                  
                  SizedBox(height: 4.h),
                  
                  // 두번째줄: offer (폰트 작게 붉은색)
                  if (store.offer != null && store.offer!.isNotEmpty)
                    _buildOfferRow(isTablet),
                  
                  SizedBox(height: 8.h),
                  
                  // 세번째줄: 플랫폼명 + D-day + 거리정보
                  _buildMetaRow(isTablet),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }

  // 첫째줄: 타이틀 + 채널 + NEW (2줄까지 가능)
  Widget _buildTitleRow(bool isTablet) {
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          // 제목 텍스트
          TextSpan(
            text: store.title,
            style: TextStyle(
              fontSize: dense ? 13.sp : (isTablet ? 16.sp : 14.sp),
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              height: 1.3,
            ),
          ),
          
          // 채널 아이콘들 (홈화면 참조)
          if (store.campaignChannel != null && store.campaignChannel!.isNotEmpty) ...[
            WidgetSpan(
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: buildChannelIcons(store.campaignChannel),
                ),
              ),
            ),
          ],
          
          // NEW 뱃지
          if (store.isNew == true) ...[
            WidgetSpan(
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: dense ? 4.w : 6.w,
                    vertical: dense ? 1.h : 2.h,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(dense ? 6.r : 8.r),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'NEW',
                    style: TextStyle(
                      fontSize: dense ? 8.sp : (isTablet ? 11.sp : 9.sp),
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 두번째줄: offer (폰트 작게 붉은색)
  Widget _buildOfferRow(bool isTablet) {
    return Text(
      store.offer!,
      style: TextStyle(
        fontSize: dense ? 11.sp : (isTablet ? 13.sp : 11.sp),
        color: Colors.red[600],
        fontWeight: FontWeight.w500,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // 세번째줄: 플랫폼명 + D-day + 거리정보
  Widget _buildMetaRow(bool isTablet) {
    return Row(
      children: [
        // 9개 상자 아이콘
        Icon(
          Icons.apps, // 9개 상자가 있는 더보기 아이콘
          size: 16.sp,
          color: Colors.grey[600],
        ),
        
        SizedBox(width: 4.w),
        
        // 플랫폼 이름
        Text(
          store.platform,
          style: TextStyle(
            fontSize: dense ? 12.sp : (isTablet ? 14.sp : 12.sp),
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        
        SizedBox(width: 8.w),
        
        // D-day와 거리 칩들 (홈화면과 동일)
        Expanded(
          child: DeadlineChips(
            store: store,
            dense: dense,
          ),
        ),
      ],
    );
  }

  // 플랫폼 로고 (asset 이미지) - 크게 표시
  Widget _buildPlatformLogo(String platform) {
    final String logoAssetPath = _getLogoPathForPlatform(platform);
    
    return Container(
      width: 48.w,
      height: 48.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        color: Colors.white,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: Image.asset(
          logoAssetPath,
          width: 48.w,
          height: 48.h,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            width: 48.w,
            height: 48.h,
            color: Colors.white,
            child: Icon(
              Icons.image_not_supported,
              color: Colors.grey[400],
              size: 20.sp,
            ),
          ),
        ),
      ),
    );
  }

  // 플랫폼별 로고 경로 반환
  String _getLogoPathForPlatform(String platform) {
    final Map<String, String> logoMap = {
      '스토리앤미디어': 'asset/image/logo/storymedia.png',
      '링블': 'asset/image/logo/ringble.png',
      '캐시노트': 'asset/image/logo/cashnote.png',
      '놀러와': 'asset/image/logo/noleowa.png',
      '체허미': 'asset/image/logo/chehumi.png',
      '링뷰': 'asset/image/logo/ringvue.png',
      '미블': 'asset/image/logo/mrble.png',
      '강남맛집': 'asset/image/logo/gannam.png',
      '가보자': 'asset/image/logo/gaboja.png',
      '레뷰': 'asset/image/logo/revu.png',
      '포블로그': 'asset/image/logo/4blog2.png',
      '포포몬': 'asset/image/logo/popomon.png',
      '리뷰노트': 'asset/image/logo/reviewnote.png',
      '리뷰플레이스': 'asset/image/logo/reviewplace.png',
      '디너의여왕': 'asset/image/logo/dinnerqueen.png',
      '체험뷰': 'asset/image/logo/chehumview.png',
      '아싸뷰': 'asset/image/logo/assaview.png',
      '체리뷰': 'asset/image/logo/cherryview.png',
      '오마이블로그': 'asset/image/logo/ohmyblog.png',
      '구구다스': 'asset/image/logo/gugudas.png',
      '티블': 'asset/image/logo/tble.png',
      '디노단': 'asset/image/logo/dinodan.png',
      '데일리뷰': 'asset/image/logo/dailiview.png',
      '똑똑체험단': 'asset/image/logo/ddokddok.png',
      '리뷰메이커': 'asset/image/logo/reviewmaker.png',
      '리뷰어랩': 'asset/image/logo/reviewerlab.png',
      '리뷰어스': 'asset/image/logo/reviewus.png',
      '리뷰웨이브': 'asset/image/logo/reviewwave.png',
      '리뷰윙': 'asset/image/logo/reviewwing.png',
      '리뷰퀸': 'asset/image/logo/reviewqueen.png',
      '리얼리뷰': 'asset/image/logo/realreview.png',
      '마녀체험단': 'asset/image/logo/witch_review.png',
      '모두의블로그': 'asset/image/logo/moble.png',
      '모두의체험단': 'asset/image/logo/modan.png',
      '뷰티의여왕': 'asset/image/logo/beauti_queen.png',
      '블로그원정대': 'asset/image/logo/review_one.png',
      '서울오빠': 'asset/image/logo/seoulobba.png',
      '서포터즈픽': 'asset/image/logo/supporterzpick.png',
      '샐러뷰': 'asset/image/logo/celuvu.png',
      '시원뷰': 'asset/image/logo/coolvue.png',
      '와이리': 'asset/image/logo/waili.png',
      '이음체험단': 'asset/image/logo/iumchehum.png',
      '츄블': 'asset/image/logo/chuble.png',
      '클라우드리뷰': 'asset/image/logo/cloudreview.png',
      '키플랫체험단': 'asset/image/logo/keyplat.png',
      '택배의여왕': 'asset/image/logo/taebae_queen.png',
      '파블로체험단': 'asset/image/logo/pablochehum.png',
      '후기업': 'asset/image/logo/whogiup.png',
      '플레이체험단': 'asset/image/logo/playchehum.png',
    };
    
    return logoMap[platform] ?? 'asset/image/logo/default_log.png';
  }


}

/// 간단한 스토어 리스트 아이템 (카드 형태)
class SimpleStoreListItem extends StatelessWidget {
  final Store store;
  final VoidCallback? onTap;

  const SimpleStoreListItem({
    super.key,
    required this.store,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      child: ExperienceCard(
        store: store,
        dense: true,
        compact: false,
        bottomAlignMeta: false,
      ),
    );
  }
}

/// 지도용 스토어 리스트 아이템
class MapStoreListItem extends StatelessWidget {
  final Store store;
  final VoidCallback? onTap;
  final bool isSelected;

  const MapStoreListItem({
    super.key,
    required this.store,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isSelected 
              ? Colors.blue 
              : Colors.grey.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: ExperienceCard(
          store: store,
          dense: true,
          compact: true,
          bottomAlignMeta: true,
        ),
      ),
    );
  }
}

