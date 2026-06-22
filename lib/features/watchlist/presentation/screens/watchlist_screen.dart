import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/watchlist_models.dart';
import '../../domain/services/watchlist_formatters.dart';
import '../../domain/services/watchlist_sorting.dart';
import '../../data/providers/watchlist_repository_provider.dart';
import '../layout/watchlist_layout_spec.dart';
import '../providers/favorite_ids_controller.dart';
import '../providers/watchlist_controller.dart';
import '../providers/watchlist_detail_controller.dart';
import '../widgets/watchlist_date_bottom_sheet.dart';
import '../widgets/watchlist_collapsed_row.dart';
import '../widgets/watchlist_expanded_row.dart';
import '../widgets/watchlist_sort_bottom_sheet.dart';
import '../widgets/watchlist_states.dart';
import '../widgets/watchlist_top_filter.dart';
import '../../../../theme/app_theme.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  late final AppLifecycleListener _appLifecycleListener;
  late final ScrollController _scrollController;
  List<DateTime>? _availableDatesCache;
  Future<List<DateTime>>? _availableDatesFuture;

  /// 백그라운드 진입 시간 (생명주기 관리용).
  DateTime? _pausedAt;

  /// 현재 표시 중인 아이템 수 (페이지네이션).
  int _displayCount = _pageSize;

  /// 페이지네이션 단위.
  ///
  /// 20개 선택 이유:
  /// - 일반적인 모바일 화면에서 스크롤 없이 5~7개 표시
  /// - 20개면 2~3번 스크롤로 전체 확인 가능 (적당한 청크)
  /// - 너무 적으면 빈번한 로딩, 너무 많으면 초기 로딩 지연
  static const _pageSize = 20;

  /// 스크롤 끝에서 이 거리 이내로 오면 다음 페이지 로드.
  ///
  /// 200px 선택 이유:
  /// - 행 높이 약 60px 기준, 3~4개 행 미리 로드
  /// - 사용자가 끝에 도달하기 전에 자연스럽게 로딩
  /// - 너무 크면 불필요한 로딩, 너무 작으면 끊김 느낌
  static const _loadMoreThreshold = 200.0;

  /// 금융앱: 백그라운드에서 30초 이상 경과 시에만 새로고침.
  /// 짧은 앱 전환(알림 확인 등)에서는 불필요한 API 호출 방지.
  static const _staleThreshold = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _appLifecycleListener = AppLifecycleListener(
      onResume: _handleResume,
      onPause: _handlePause,
      onHide: _handlePause,
      onInactive: _handlePause,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _appLifecycleListener.dispose();
    super.dispose();
  }

  /// 스크롤 이벤트 핸들러 - 무한 스크롤 구현.
  ///
  /// 무한 스크롤 선택 이유:
  /// - "더 보기" 버튼 대비 사용자 경험 향상 (끊김 없는 탐색)
  /// - 금융앱에서 종목 리스트는 빠른 스캔이 중요
  /// - 별도 페이지 번호 UI 불필요 (단순함 유지)
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // 스크롤이 끝에 가까워지면 더 로드
    if (maxScroll - currentScroll <= _loadMoreThreshold) {
      _loadMore();
    }
  }

  void _loadMore() {
    final snapshot = ref.read(watchlistControllerProvider).valueOrNull;
    if (snapshot == null) return;

    final totalItems = snapshot.items.length;
    if (_displayCount >= totalItems) return;

    setState(() {
      _displayCount = (_displayCount + _pageSize).clamp(0, totalItems);
    });
  }

  /// 새로고침 시 페이지네이션 리셋.
  ///
  /// 리셋 이유:
  /// - 새로고침은 "처음부터 다시 보기" 의도
  /// - 데이터 변경 시 기존 위치 유지보다 최신 상위 항목이 중요
  void _resetPagination() {
    _displayCount = _pageSize;
  }

  void _handlePause() {
    _pausedAt = DateTime.now();
  }

  void _handleResume() {
    final pausedAt = _pausedAt;
    _pausedAt = null;

    // 백그라운드에서 staleThreshold 이상 경과했을 때만 새로고침
    if (pausedAt == null) {
      // 처음 앱 시작 시에는 새로고침 안 함 (이미 로딩됨)
      return;
    }

    final elapsed = DateTime.now().difference(pausedAt);
    if (elapsed >= _staleThreshold) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    _clearAvailableDatesCache();
    _resetPagination();
    await ref.read(watchlistControllerProvider.notifier).refresh();
    await _syncSelectedDetailWithSnapshot();
  }

  void _clearAvailableDatesCache() {
    _availableDatesCache = null;
    _availableDatesFuture = null;
  }

  Future<List<DateTime>> _loadAvailableDates() {
    final cached = _availableDatesCache;
    if (cached != null) {
      return Future<List<DateTime>>.value(cached);
    }

    return _availableDatesFuture ??= ref
        .read(watchlistRepositoryProvider)
        .fetchAvailableDates()
        .then((dates) {
          _availableDatesCache = dates;
          return dates;
        });
  }

  Future<void> _syncSelectedDetailWithSnapshot() async {
    final snapshot = ref.read(watchlistControllerProvider).valueOrNull;
    final detailController = ref.read(
      watchlistDetailControllerProvider.notifier,
    );

    if (snapshot == null) {
      detailController.clearAll();
      return;
    }

    await detailController.invalidateCacheAndReselect(snapshot.items);
  }

  Future<void> _showSortBottomSheet(WatchlistSortMode currentSortMode) async {
    final selectedMode = await showModalBottomSheet<WatchlistSortMode>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppDerivedColors.modalScrim,
      builder: (context) {
        return WatchlistSortBottomSheet(currentSortMode: currentSortMode);
      },
    );

    if (selectedMode == null || !mounted) {
      return;
    }

    ref.read(watchlistSortModeProvider.notifier).state = selectedMode;
  }

  Future<void> _showDateBottomSheet(WatchlistSnapshot snapshot) async {
    final selectedDate = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppDerivedColors.modalScrim,
      builder: (context) {
        return _LazyWatchlistDateBottomSheet(
          loadAvailableDates: _loadAvailableDates,
          initialDate: snapshot.asOf,
        );
      },
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    final normalizedDate = normalizeAsOfDate(selectedDate);
    if (formatApiDate(normalizedDate) == formatApiDate(snapshot.asOf)) {
      return;
    }

    // Apply the selected trading day to the watchlist controller
    await ref.read(watchlistControllerProvider.notifier).setAsOf(normalizedDate);
    // Refresh the selected detail so list/detail stay in sync
    await _syncSelectedDetailWithSnapshot();
  }

  Future<void> _handleActionTap(WatchlistItem item, String action) async {
    if (action == '삭제') {
      await ref.read(favoriteIdsControllerProvider.notifier).remove(item.id);
      _clearAvailableDatesCache();
      await ref.read(watchlistControllerProvider.notifier).refresh();
      await _syncSelectedDetailWithSnapshot();
      if (!mounted) {
        return;
      }
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$action 기능은 준비 중입니다. ${item.name}에 연결될 예정입니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<WatchlistSnapshot>>(watchlistControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasValue) {
        unawaited(_syncSelectedDetailWithSnapshot());
      }
    });

    final snapshotAsync = ref.watch(watchlistControllerProvider);
    final sortMode = ref.watch(watchlistSortModeProvider);
    final detailUiState = ref.watch(watchlistDetailControllerProvider);
    final snapshot = snapshotAsync.valueOrNull;
    final allItems = snapshot == null
        ? const <WatchlistItem>[]
        : sortWatchlistItems(snapshot.items, sortMode);
    // 페이지네이션: _displayCount만큼만 표시
    final items = allItems.take(_displayCount).toList();
    final hasMore = items.length < allItems.length;
    final selectedItemId = detailUiState.selectedItemId;

    return ColoredBox(
      color: AppColors.bg.bg_121212,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = WatchlistLayoutSpec.fromWidth(constraints.maxWidth);

            return Column(
              key: const Key('watchlist-screen'),
              children: [
                _WatchlistHeader(layout: layout),
                const SizedBox(height: WatchlistLayoutSpec.headerToFilterGap),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: layout.horizontalPadding,
                  ),
                  child: WatchlistTopFilter(
                    currentSortMode: sortMode,
                    asOfLabel: snapshot == null
                        ? '--.--.--'
                        : formatAsOfDate(snapshot.asOf),
                    enabled: snapshot != null,
                    onSortTap: () => _showSortBottomSheet(sortMode),
                    onDateTap: snapshot == null
                        ? () {}
                        : () => _showDateBottomSheet(snapshot),
                  ),
                ),
                const SizedBox(height: WatchlistLayoutSpec.filterToListGap),
                Expanded(
                  child: snapshotAsync.when(
                    data: (data) {
                      if (data.items.isEmpty) {
                        return WatchlistEmptyState(onRefresh: _refresh);
                      }

                      return RefreshIndicator.adaptive(
                        color: AppColors.mainAndAccent.primary_ff8a00,
                        backgroundColor: AppColors.bg.bg_2_212121,
                        onRefresh: _refresh,
                        child: ListView.builder(
                          key: const Key('watchlist-list'),
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.only(bottom: 16),
                          // 더 로드할 항목이 있으면 로딩 인디케이터용 +1
                          itemCount: items.length + (hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            // 마지막 항목: 로딩 인디케이터
                            //
                            // 로딩 인디케이터 UI 선택 이유:
                            // - 작은 크기(24x24): 리스트 흐름 방해 최소화
                            // - 중앙 정렬: 시선 자연스럽게 유도
                            // - 앱 브랜드 컬러: 일관된 디자인 언어
                            // - 텍스트 없음: "로딩 중" 등 불필요 (맥락상 명확)
                            if (index >= items.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.mainAndAccent.primary_ff8a00,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final item = items[index];
                            final isSelected = item.id == selectedItemId;
                            final detailState = detailUiState.detailFor(
                              item.id,
                            );
                            final detailController = ref.read(
                              watchlistDetailControllerProvider.notifier,
                            );

                            if (isSelected) {
                              return WatchlistExpandedRow(
                                item: item,
                                detailState: detailState,
                                layout: layout,
                                onHeaderTap: () {
                                  unawaited(
                                    detailController.toggleSelection(item),
                                  );
                                },
                                onRetry: () {
                                  unawaited(
                                    detailController.fetchDetail(
                                      item,
                                      force: true,
                                    ),
                                  );
                                },
                                onActionTap: (action) {
                                  unawaited(_handleActionTap(item, action));
                                },
                              );
                            }

                            return WatchlistCollapsedRow(
                              item: item,
                              sortMode: sortMode,
                              layout: layout,
                              onTap: () {
                                unawaited(
                                  detailController.toggleSelection(item),
                                );
                              },
                            );
                          },
                        ),
                      );
                    },
                    loading: WatchlistSkeleton.new,
                    error: (error, stackTrace) {
                      return WatchlistErrorState(onRetry: _refresh);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LazyWatchlistDateBottomSheet extends StatefulWidget {
  const _LazyWatchlistDateBottomSheet({
    required this.loadAvailableDates,
    required this.initialDate,
  });

  final Future<List<DateTime>> Function() loadAvailableDates;
  final DateTime initialDate;

  @override
  State<_LazyWatchlistDateBottomSheet> createState() =>
      _LazyWatchlistDateBottomSheetState();
}

class _LazyWatchlistDateBottomSheetState
    extends State<_LazyWatchlistDateBottomSheet> {
  late Future<List<DateTime>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadAvailableDates();
  }

  void _retry() {
    setState(() {
      _future = widget.loadAvailableDates();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DateTime>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _DateBottomSheetLoading();
        }

        if (snapshot.hasError) {
          return _DateBottomSheetError(onRetry: _retry);
        }

        final availableDates = snapshot.data;
        return WatchlistDateBottomSheet(
          availableDates: availableDates == null || availableDates.isEmpty
              ? [widget.initialDate]
              : availableDates,
          initialDate: widget.initialDate,
        );
      },
    );
  }
}

class _DateBottomSheetLoading extends StatelessWidget {
  const _DateBottomSheetLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg.bg_2_212121,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: AppColors.mainAndAccent.primary_ff8a00,
            ),
            const SizedBox(height: 16),
            Text('거래일 목록을 불러오는 중입니다.', style: AppTypography.searchMeta),
          ],
        ),
      ),
    );
  }
}

class _DateBottomSheetError extends StatelessWidget {
  const _DateBottomSheetError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg.bg_2_212121,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '거래일 목록을 불러오지 못했습니다.',
              style: AppTypography.searchEmptyTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '잠시 후 다시 시도해 주세요.',
              style: AppTypography.searchMeta.copyWith(
                color: AppColors.text.text_3_9e9e9e,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mainAndAccent.primary_ff8a00,
                ),
                child: const Text('다시 시도'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchlistHeader extends StatelessWidget {
  const _WatchlistHeader({required this.layout});

  final WatchlistLayoutSpec layout;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: WatchlistLayoutSpec.headerHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border.border_333333),
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: layout.horizontalPadding),
            child: Text(
              '관심',
              key: const Key('watchlist-header-title'),
              style: AppTypography.header,
            ),
          ),
        ),
      ),
    );
  }
}
