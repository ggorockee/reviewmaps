import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/widgets/experience_card.dart';
import 'package:mobile/widgets/meta_bar.dart';

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 플랫폼 및 제목
            Row(
              children: [
                if (store.platform != null) ...[
                  _buildPlatformChip(store.platform!),
                  SizedBox(width: 8.w),
                ],
                Expanded(
                  child: Text(
                    store.company,
                    style: TextStyle(
                      fontSize: dense ? 13.sp : 15.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 8.h),
            
            // 혜택 정보
            if (store.offer != null && store.offer!.isNotEmpty) ...[
              Text(
                store.offer!,
                style: TextStyle(
                  fontSize: dense ? 11.sp : 13.sp,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 8.h),
            ],
            
            // 메타 정보 (마감일, 거리 등)
            MetaBar(
              store: store,
              dense: dense,
              showDistance: showDistance,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformChip(String platform) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 6.w,
        vertical: 2.h,
      ),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(
          color: Colors.orange.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        platform,
        style: TextStyle(
          fontSize: 9.sp,
          fontWeight: FontWeight.w500,
          color: Colors.orange[700],
        ),
      ),
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
