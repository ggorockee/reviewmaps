import 'package:flutter/material.dart';

import '../models/release_note.dart';

/// 카드를 언제 띄우는지. 버튼 구성과 닫기 가능 여부가 달라진다.
enum ReleaseCardType {
  /// 업데이트한 뒤 "새로워진 점"
  afterUpdate('after'),

  /// 새 버전이 있음. "나중에" 가능
  optionalUpdate('optional'),

  /// 업데이트해야 계속 쓸 수 있음. 닫을 수 없음
  forceUpdate('force');

  const ReleaseCardType(this.analyticsName);

  final String analyticsName;
}

/// 사용자가 카드에서 한 일
enum ReleaseCardAction { confirm, update, later, close }

/// 카드를 닫을 때의 결과. [lastPage]는 가장 멀리 본 장(1부터).
class ReleaseCardResult {
  const ReleaseCardResult(this.action, this.lastPage);

  final ReleaseCardAction action;
  final int lastPage;
}

/// 화면 대부분을 덮는 카드. 안내를 한 장씩 넘겨 본다.
class ReleaseNoteCard extends StatefulWidget {
  const ReleaseNoteCard({
    super.key,
    required this.note,
    required this.type,
    this.onOpenStore,
  });

  /// 화면 대비 카드 크기
  static const double widthFactor = 0.9;
  static const double heightFactor = 0.8;

  static const Map<String, IconData> _icons = {
    'bell': Icons.notifications_active_outlined,
    'calendar': Icons.event_available_outlined,
    'map': Icons.map_outlined,
    'new': Icons.auto_awesome_outlined,
    'star': Icons.star_outline,
    'text': Icons.text_fields,
    'update': Icons.system_update,
  };

  final ReleaseNote note;
  final ReleaseCardType type;

  /// 스토어를 연다. 열지 못하면 false.
  final Future<bool> Function()? onOpenStore;

  /// 카드를 띄운다. 강제 업데이트면 반환되지 않는다.
  static Future<ReleaseCardResult?> show(
    BuildContext context, {
    required ReleaseNote note,
    required ReleaseCardType type,
    Future<bool> Function()? onOpenStore,
  }) => showDialog<ReleaseCardResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ReleaseNoteCard(note: note, type: type, onOpenStore: onOpenStore),
  );

  @override
  State<ReleaseNoteCard> createState() => _ReleaseNoteCardState();
}

class _ReleaseNoteCardState extends State<ReleaseNoteCard> {
  final _pages = PageController();
  int _page = 0;
  int _furthest = 0;
  bool _storeFailed = false;

  bool get _forced => widget.type == ReleaseCardType.forceUpdate;
  bool get _isLast => _page == widget.note.pages.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _close(ReleaseCardAction action) =>
      Navigator.of(context).pop(ReleaseCardResult(action, _furthest + 1));

  Future<void> _update() async {
    final opened = await widget.onOpenStore?.call() ?? false;
    if (!mounted) return;
    if (!opened) {
      setState(() => _storeFailed = true);
      return;
    }
    // 강제 업데이트는 스토어에 다녀와도 카드가 남아야 한다
    if (!_forced) _close(ReleaseCardAction.update);
  }

  void _next() => _pages.nextPage(
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // 태블릿은 카드가 커서 글자·버튼·그림을 키운다
    final isTablet = size.shortestSide >= 600;
    final scale = isTablet ? 1.5 : 1.0;
    final version = widget.note.version;
    final hasVersion = version != '0.0.0';
    final label = switch (widget.type) {
      ReleaseCardType.afterUpdate => '새로워진 점 · v$version',
      _ => hasVersion ? '새 버전 v$version' : '업데이트 안내',
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_forced) _close(ReleaseCardAction.close);
      },
      child: Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SizedBox(
          width: size.width * ReleaseNoteCard.widthFactor,
          height: size.height * ReleaseNoteCard.heightFactor,
          child: Column(
            children: [
              _header(label, scale),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: widget.note.pages.length,
                  onPageChanged: (i) => setState(() {
                    _page = i;
                    if (i > _furthest) _furthest = i;
                  }),
                  itemBuilder: (_, i) => _PageContent(
                    page: widget.note.pages[i],
                    scale: scale,
                    visualFraction: isTablet ? 0.65 : 0.55,
                  ),
                ),
              ),
              if (widget.note.pages.length > 1) _dots(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _buttons(scale),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String label, double scale) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
    child: SizedBox(
      height: 48 * scale,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13 * scale,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
          if (!_forced)
            IconButton(
              tooltip: '닫기',
              icon: Icon(Icons.close, size: 24 * scale, color: Colors.black54),
              onPressed: () => _close(ReleaseCardAction.close),
            ),
        ],
      ),
    ),
  );

  Widget _dots() => Semantics(
    label: '${widget.note.pages.length}장 중 ${_page + 1}장',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.note.pages.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == _page ? Theme.of(context).primaryColor : Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buttons(double scale) {
    final isAfter = widget.type == ReleaseCardType.afterUpdate;
    final String primaryLabel = isAfter ? (_isLast ? '확인했어요' : '다음') : '업데이트 하기';
    final VoidCallback onPrimary = isAfter
        ? (_isLast ? () => _close(ReleaseCardAction.confirm) : _next)
        : _update;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_storeFailed)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('스토어를 열 수 없어요', style: TextStyle(color: Colors.red)),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                minimumSize: Size.fromHeight(48 * scale),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                primaryLabel,
                style: TextStyle(fontSize: 15 * scale, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (widget.type == ReleaseCardType.optionalUpdate)
            TextButton(
              onPressed: () => _close(ReleaseCardAction.later),
              style: TextButton.styleFrom(foregroundColor: Colors.black54),
              child: Text('나중에', style: TextStyle(fontSize: 14 * scale)),
            ),
        ],
      ),
    );
  }
}

class _PageContent extends StatelessWidget {
  const _PageContent({required this.page, required this.scale, required this.visualFraction});

  final ReleaseNotePage page;
  final double scale;

  /// 장 높이에서 그림이 차지하는 비율
  final double visualFraction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // 가로 화면이나 큰 글자에서도 잘리지 않게 장마다 세로 스크롤
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: constraints.maxHeight * visualFraction,
              width: double.infinity,
              child: _visual(context),
            ),
            const SizedBox(height: 20),
            Text(
              page.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20 * scale,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
                height: 1.35,
              ),
            ),
            if (page.body.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                page.body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15 * scale, color: Colors.black54, height: 1.55),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );

  /// 그림. 없거나 불러오지 못하면 아이콘.
  Widget _visual(BuildContext context) {
    final image = page.image;
    final fallback = Center(
      child: LayoutBuilder(
        builder: (context, c) {
          final diameter = (c.biggest.shortestSide * 0.6).clamp(0.0, 144.0 * scale);
          return Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              ReleaseNoteCard._icons[page.icon] ?? Icons.auto_awesome_outlined,
              size: diameter * 0.5,
              color: Theme.of(context).primaryColor,
            ),
          );
        },
      ),
    );
    if (image == null) return fallback;
    if (image.startsWith('asset/')) {
      return Image.asset(image, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback);
    }
    return Image.network(
      image,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : const Center(child: CircularProgressIndicator()),
    );
  }
}
