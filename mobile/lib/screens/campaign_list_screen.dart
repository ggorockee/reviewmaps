import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:mobile/config/config.dart';
import 'package:url_launcher/url_launcher.dart';

import '../const/colors.dart';
import '../models/store_model.dart';
import '../services/campaign_service.dart';
import '../widgets/friendly.dart';

/// 캠페인 리스트 화면
/// ------------------------------------------------------------
/// 진입 케이스:
///  - 추천 목록: initialStores만 주어지고 userPosition은 null → 무한스크롤 비활성화(더 불러올 기준 없음)
///  - 가까운 목록: initialStores + userPosition 제공 → fetchNearest로 페이지네이션
///
/// 배포 포인트:
///  - 불필요 로그 제거, 사용자 피드백은 스낵바/조용한 폴백으로 처리
///  - 텍스트 스케일 대응(가독성 + 레이아웃 안정)
class CampaignListScreen extends StatefulWidget {
  final String title;
  final List<Store> initialStores;
  final Position? userPosition;

  const CampaignListScreen({
    super.key,
    required this.title,
    required this.initialStores,
    this.userPosition, // 추천 목록 등 위치 없는 경우 null
  });

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  // ---------------- State & Services ----------------
  final _scrollController = ScrollController();

  // 근처 목록(위치 기반) 무한스크롤 시 사용
  final _campaignService = CampaignService(
    AppConfig.ReviewMapbaseUrl,
    apiKey: AppConfig.ReviewMapApiKey,
  );

  final List<Store> _stores = []; // 화면에 보여줄 누적 리스트
  bool _isLoading = false;        // 서버 페치 중 플래그
  bool _hasMore = true;           // 추가 페이지 유무
  final int _limit = 20;          // 서버 페이지 크기
  int _offset = 0;                // 서버 오프셋

  @override
  void initState() {
    super.initState();

    // 1) 초기 데이터 채우기
    _stores.addAll(widget.initialStores);
    _offset = _stores.length;

    // 2) 위치가 없으면 더보기(무한스크롤) 비활성화
    if (widget.userPosition == null) {
      _hasMore = false;
    }

    // 3) 스크롤 끝 근처 감지하여 자동 로드
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------- Infinite Scroll ----------------
  /// 스크롤 잔여 길이가 임계치 이하일 때 다음 페이지 로드
  void _scrollListener() {
    if (_scrollController.position.extentAfter < 300 && !_isLoading && _hasMore) {
      _loadMore();
    }
  }

  /// 위치가 있을 때만(=근처 목록일 때만) 다음 페이지를 서버에서 페치
  Future<void> _loadMore() async {
    if (widget.userPosition == null) return; // 추천 목록일 땐 종료

    setState(() => _isLoading = true);

    try {
      final newStores = await _campaignService.fetchNearest(
        lat: widget.userPosition!.latitude,
        lng: widget.userPosition!.longitude,
        limit: _limit,
        offset: _offset,
      );

      if (!mounted) return;

      setState(() {
        if (newStores.isNotEmpty) {
          _stores.addAll(newStores);
          _offset += newStores.length;
        } else {
          // 더 이상 가져올 페이지 없음
          _hasMore = false;
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFriendlySnack(context, '목록을 더 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  // ---------------- Build ----------------
  @override
  Widget build(BuildContext context) {
    // 텍스트 확대 시 카드 높이도 살짝 키워 주어 오버플로우 방지
    final scale = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.3);
    final itemExtent = 170 * scale;

    return ClampTextScale(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        backgroundColor: Colors.white,
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // 2열 고정 그리드
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 0,
                  mainAxisSpacing: 0,
                  mainAxisExtent: itemExtent, // 텍스트 스케일 반영된 높이
                ),
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildGridItemWithBorders(_stores[index], index),
                  childCount: _stores.length,
                ),
              ),
            ),

            // 하단 로딩 인디케이터(추가 페이지 로딩 중에만 노출)
            SliverToBoxAdapter(
              child: _isLoading
                  ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(child: CircularProgressIndicator()),
              )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Grid Item ----------------
  /// 그리드 셀 외곽선(테이블 격자 느낌) 포함 빌더
  Widget _buildGridItemWithBorders(Store store, int index) {
    final gridLineColor = Colors.grey.shade300;
    const gridLineWidth = 0.7;
    const cols = 2;

    final isRightCol = (index % cols) == cols - 1;
    final rowCount = (_stores.length / cols).ceil();
    final currentRow = (index / cols).floor();
    final isLastRow = currentRow == rowCount - 1;

    final boxBorder = Border(
      right: isRightCol
          ? BorderSide.none
          : BorderSide(color: gridLineColor, width: gridLineWidth),
      // 마지막 줄이고 더이상 불러올 데이터가 없을 때만 아래 경계선 제거
      bottom: isLastRow && !_hasMore
          ? BorderSide.none
          : BorderSide(color: gridLineColor, width: gridLineWidth),
    );

    return DecoratedBox(
      decoration: BoxDecoration(border: boxBorder),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: _buildGridItemCard(store),
      ),
    );
  }

  /// 실제 카드 UI (플랫폼 뱃지 / 상호 / 오퍼 / 메타)
  Widget _buildGridItemCard(Store store) {
    final platformColor = platformBadgeColor(store.platform);

    return InkWell(
      onTap: () => _openLink(store.companyLink),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // 상단/하단 분리 배치
          children: [
            // ---------- 상단: 플랫폼, 상호, 오퍼 ----------
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // 내용만큼만 높이
              children: [
                // 플랫폼 뱃지
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: platformColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    // 플랫폼명은 길지 않으므로 폰트 고정 (가독 우선)
                    // 필요 시 ScreenUtil로 .sp 적용 가능
                    '플랫폼', // 접근성 리더에서 store.platform을 그대로 읽게 하려면 아래 Text로 교체
                    // Text(store.platform, ... )
                  ),
                ),
                const SizedBox(height: 6),

                // 상호명
                Text(
                  store.company,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    height: 1.15,
                  ),
                ),

                // 오퍼(있을 때만)
                if ((store.offer ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    store.offer!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.15,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ],
            ),

            // ---------- 하단: 메타(마감일/거리) ----------
            Row(
              children: [
                // 마감일 있을 때만 달력 아이콘 + 날짜 표기
                if (store.applyDeadline != null) ...[
                  Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '~${DateFormat('MM.dd').format(store.applyDeadline!)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.0),
                  ),
                ],
                const Spacer(),
                if (store.distance != null)
                  Text(
                    '${store.distance!.toStringAsFixed(1)}km',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.0),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Link Helper ----------------
  /// 외부 링크 실행(https 보정 + 외부 브라우저 우선)
  Future<void> _openLink(String? rawLink) async {
    if (rawLink == null || rawLink.isEmpty) return;
    try {
      String s = rawLink.trim();
      if (!s.startsWith('http://') && !s.startsWith('https://')) {
        s = 'https://$s';
      }
      final uri = Uri.parse(Uri.encodeFull(s));
      // 외부 브라우저 우선
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        // 실패 시 인앱 시도
        await launchUrl(uri);
      }
    } catch (_) {
      if (!mounted) return;
      showFriendlySnack(context, '링크를 열 수 없어요.');
    }
  }
}
