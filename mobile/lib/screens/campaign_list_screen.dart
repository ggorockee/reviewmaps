import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../const/colors.dart';
import '../models/store_model.dart';
import '../services/campaign_service.dart';

class CampaignListScreen extends StatefulWidget {
  final String title;
  final List<Store> initialStores;
  final Position? userPosition;

  const CampaignListScreen({
    super.key,
    required this.title,
    required this.initialStores,
    this.userPosition, // Null일 수 있음 (예: 추천 체험단)
  });

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  // --- 상태 변수 ---
  final _scrollController = ScrollController();
  final _campaignService = CampaignService(
    'https://api.review-maps.com/v1',
    apiKey: '9e53ccafd6e993152e01e9e7a8ca66d1c2224bb5b21c78cf076f6e45dcbc0d12',
  );

  final List<Store> _stores = [];
  bool _isLoading = false;
  bool _hasMore = true;
  final int _limit = 20;
  int _offset = 0;

  @override
  void initState() {
    super.initState();

    // 1. 초기 데이터로 리스트를 채웁니다.
    _stores.addAll(widget.initialStores);
    _offset = _stores.length;

    // 2. 위치 정보가 없으면 (예: 추천 체험단), 더보기 기능을 비활성화합니다.
    if (widget.userPosition == null) {
      setState(() {
        _hasMore = false;
      });
    }

    // 3. 스크롤 리스너를 설정하여 사용자가 끝까지 스크롤했는지 감지합니다.
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  /// 스크롤 위치를 감지하여 추가 데이터를 로드할지 결정합니다.
  void _scrollListener() {
    if (_scrollController.position.extentAfter < 300 && !_isLoading && _hasMore) {
      _loadMore();
    }
  }

  /// API를 통해 다음 페이지의 데이터를 비동기적으로 불러옵니다.
  Future<void> _loadMore() async {
    // 위치 정보가 없으면 로드하지 않습니다.
    if (widget.userPosition == null) return;

    setState(() {
      _isLoading = true;
    });

    final newStores = await _campaignService.fetchNearest(
      lat: widget.userPosition!.latitude,
      lng: widget.userPosition!.longitude,
      limit: _limit,
      offset: _offset,
    );

    if (mounted) {
      setState(() {
        if (newStores.isNotEmpty) {
          _stores.addAll(newStores);
          _offset += newStores.length;
        } else {
          // 받아온 데이터가 없으면 더 이상 페이지가 없는 것이므로 더보기 중단
          _hasMore = false;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 0,
                mainAxisSpacing: 0,
                mainAxisExtent: 170, // 아이템의 고정 높이
              ),
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  return _buildGridItemWithBorders(_stores[index], index);
                },
                childCount: _stores.length,
              ),
            ),
          ),
          // 로딩 중일 때 하단에 표시될 인디케이터
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
    );
  }

  /// 그리드 아이템에 경계선을 추가하여 렌더링하는 위젯입니다.
  Widget _buildGridItemWithBorders(Store store, int index) {
    final gridLineColor = Colors.grey.shade300;
    const gridLineWidth = 0.7;
    const cols = 2;

    final isRightCol = (index % cols) == cols - 1;
    // 마지막 줄인지 계산
    final rowCount = (_stores.length / cols).ceil();
    final currentRow = (index / cols).floor();
    final isLastRow = currentRow == rowCount - 1;

    final boxBorder = Border(
      right: isRightCol
          ? BorderSide.none
          : BorderSide(color: gridLineColor, width: gridLineWidth),
      // 마지막 줄이고 더이상 불러올 데이터가 없을 때만 아래쪽 경계선을 제거합니다.
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

  /// 실제 캠페인 카드 UI를 구성하는 위젯입니다.
  Widget _buildGridItemCard(Store store) {
    final platformColor = platformBadgeColor(store.platform);

    return InkWell(
      onTap: () => _openLink(store.companyLink),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // --- 상단 콘텐츠 (플랫폼, 상호명, 오퍼) ---
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: platformColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    store.platform,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
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
            // --- 하단 메타 정보 (날짜, 거리) ---
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                if (store.applyDeadline != null)
                  Text(
                    '~${DateFormat('MM.dd').format(store.applyDeadline!)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.0),
                  ),
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

  /// 외부 링크를 실행하는 함수입니다.
  Future<void> _openLink(String? rawLink) async {
    if (rawLink == null || rawLink.isEmpty) return;
    try {
      String s = rawLink.trim();
      if (!s.startsWith('http://') && !s.startsWith('https://')) {
        s = 'https://$s';
      }
      final uri = Uri.parse(Uri.encodeFull(s));
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('Could not launch $rawLink: $e');
    }
  }
}