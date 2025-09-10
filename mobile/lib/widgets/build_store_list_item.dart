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
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: 80.h), // 최소 높이 설정
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 16.w), // 위아래 같은 여백 + 좌우 패딩
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 첫째줄: 타이틀 + 채널 + NEW (2줄까지 가능)
            _buildTitleRow(),
            
            SizedBox(height: 4.h),
            
            // 두번째줄: offer (폰트 작게 붉은색)
            if (store.offer != null && store.offer!.isNotEmpty)
              _buildOfferRow(),
            
            SizedBox(height: 8.h),
            
            // 세번째줄: 플랫폼 + D-day + 거리정보
            _buildMetaRow(),
          ],
        ),
      ),
    );
  }

  // 첫째줄: 타이틀 + 채널 + NEW (2줄까지 가능)
  Widget _buildTitleRow() {
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          // 제목 텍스트
          TextSpan(
            text: store.title,
            style: TextStyle(
              fontSize: dense ? 16.sp : 18.sp,
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
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(dense ? 6.r : 8.r),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'NEW',
                    style: TextStyle(
                      fontSize: dense ? 8.sp : 9.sp,
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
  Widget _buildOfferRow() {
    return Text(
      store.offer!,
      style: TextStyle(
        fontSize: dense ? 11.sp : 13.sp,
        color: Colors.red[600],
        fontWeight: FontWeight.w500,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // 세번째줄: 플랫폼 + D-day + 거리정보
  Widget _buildMetaRow() {
    return Row(
      children: [
        // 플랫폼 로고 (3x3 그리드 아이콘 사용)
        Container(
          width: 20.w,
          height: 20.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4.r),
            color: Colors.grey[200],
          ),
          child: Icon(
            Icons.grid_view,
            size: 12.sp,
            color: Colors.grey[600],
          ),
        ),
        
        SizedBox(width: 8.w),
        
        // 플랫폼 이름
        Text(
          store.platform,
          style: TextStyle(
            fontSize: dense ? 12.sp : 14.sp,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
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
        
        // 거리 정보가 없으면 "거리정보없음" 표시
        if (store.distance == null)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 6.w : 8.w,
              vertical: dense ? 2.h : 3.h,
            ),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(dense ? 8.r : 10.r),
              border: Border.all(
                color: Colors.grey.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Text(
              '거리정보없음',
              style: TextStyle(
                fontSize: dense ? 9.sp : 10.sp,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
      ],
    );
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

