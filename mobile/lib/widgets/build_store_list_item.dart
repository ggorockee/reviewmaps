import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/widgets/experience_card.dart';
import 'package:mobile/widgets/title_badge.dart';
import 'package:mobile/widgets/deadline_chips.dart';

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.r),
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: Colors.grey.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 맨 왼쪽: 플랫폼 로고
            _buildPlatformLogo(store.platform),
            SizedBox(width: 12.w),
            
            // 중앙: 제목 + 채널 + NEW + 혜택 + 하단 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // [타이틀][채널][NEW] - 기존 홈 방식 그대로 (폰트 크기 조정)
                  TitleWithBadges(
                    store: store,
                    dense: true, // 맵에서는 항상 dense 모드 사용
                  ),
                  
                  SizedBox(height: 8.h),
                  
                  // 혜택 정보
                  if (store.offer != null && store.offer!.isNotEmpty) ...[
                    Text(
                      store.offer!,
                      style: TextStyle(
                        fontSize: dense ? 11.sp : 13.sp,
                        color: Colors.red[600],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 8.h),
                  ],
                  
                  // 하단: [아이콘]플랫폼 D-day, 거리
                  _buildBottomInfo(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 플랫폼 로고 (asset 이미지)
  Widget _buildPlatformLogo(String platform) {
    final String logoAssetPath = _getLogoPathForPlatform(platform);
    
    return Container(
      width: 48.w,
      height: 48.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        color: Colors.grey[100],
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
            color: Colors.grey[200],
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

  // 하단 정보: [아이콘]플랫폼 D-day, 거리
  Widget _buildBottomInfo() {
    return Row(
      children: [
        // 채널 아이콘들 (9개 사각형 아이콘)
        if (store.campaignChannel != null && store.campaignChannel!.isNotEmpty) ...[
          _buildChannelGridIcon(store.campaignChannel),
          SizedBox(width: 4.w),
        ],
        
        // 플랫폼 이름 (크게)
        Text(
          store.platform,
          style: TextStyle(
            fontSize: dense ? 12.sp : 14.sp, // 플랫폼 폰트 크게
            color: Colors.grey[600],
            fontWeight: FontWeight.w600, // 굵게
          ),
        ),
        
        SizedBox(width: 8.w),
        
        // D-day와 거리 칩들
        Expanded(
          child: DeadlineChips(
            store: store,
            dense: dense,
          ),
        ),
      ],
    );
  }

  // 채널 그리드 아이콘 (9개 사각형 - 모두 같은 회색)
  Widget _buildChannelGridIcon(String? channelStr) {
    if (channelStr == null || channelStr.isEmpty) return const SizedBox.shrink();
    
    final channels = channelStr.split(',').map((c) => c.trim()).toList();
    final validChannels = channels.where((ch) => ch != 'etc' && ch != 'unknown').toList();
    
    if (validChannels.isEmpty) return const SizedBox.shrink();
    
    return Container(
      width: 16.w,
      height: 16.h,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(2.r),
        border: Border.all(color: Colors.grey[300]!, width: 0.5),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        children: List.generate(9, (index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey[400], // 모든 사각형을 같은 회색으로
              borderRadius: BorderRadius.circular(1.r),
            ),
          );
        }),
      ),
    );
  }


  // 플랫폼별 로고 경로 반환
  String _getLogoPathForPlatform(String platform) {
    final Map<String, String> logoMap = {
      '강남맛집': 'asset/image/logo/gannam.png',
      '캐시노트': 'asset/image/logo/cashnote.png',
      '레뷰': 'asset/image/logo/revu.png',
      '체험미': 'asset/image/logo/chehumi.png',
      '체험뷰': 'asset/image/logo/chehumview.png',
      '체리뷰': 'asset/image/logo/cherryview.png',
      '디너퀸': 'asset/image/logo/dinnerqueen.png',
      '가보자': 'asset/image/logo/gaboja.png',
      '미스터블': 'asset/image/logo/mrble.png',
      '놀어와': 'asset/image/logo/noleowa.png',
      '포포몬': 'asset/image/logo/popomon.png',
      '리뷰노트': 'asset/image/logo/reviewnote.png',
      '리뷰플레이스': 'asset/image/logo/reviewplace.png',
      '링블': 'asset/image/logo/ringble.png',
      '링뷰': 'asset/image/logo/ringvue.png',
      '스토리미디어': 'asset/image/logo/storymedia.png',
      '구구다스': 'asset/image/logo/gugudas.png',
      '오마이블로그': 'asset/image/logo/ohmyblog.png',
      '포블로그': 'asset/image/logo/4blog2.png',
      '아사뷰': 'asset/image/logo/assaview.png',
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
              : Colors.grey.withOpacity(0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
