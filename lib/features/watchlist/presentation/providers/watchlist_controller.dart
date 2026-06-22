import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/watchlist_repository_provider.dart';
import '../../domain/models/watchlist_models.dart';
import '../../domain/repositories/watchlist_repository.dart';
import '../../domain/services/watchlist_sorting.dart';
import 'favorite_ids_controller.dart';

final watchlistSortModeProvider = StateProvider<WatchlistSortMode>(
  (ref) => WatchlistSortMode.alphabetical,
);

final watchlistSelectedDateProvider = StateProvider<DateTime?>((ref) => null);

final watchlistControllerProvider =
    AsyncNotifierProvider<WatchlistController, WatchlistSnapshot>(
      WatchlistController.new,
    );

class WatchlistController extends AsyncNotifier<WatchlistSnapshot> {
  WatchlistRepository get _repository => ref.read(watchlistRepositoryProvider);

  DateTime? get _selectedDate => ref.read(watchlistSelectedDateProvider);

  /// 페이지네이션 단위
  static const _pageSize = 20;

  /// 추가 로딩 중 여부 (중복 호출 방지)
  bool _isLoadingMore = false;

  @override
  Future<WatchlistSnapshot> build() async {
    // 즐겨찾기 변경 시 관심종목 새로고침
    ref.listen<AsyncValue<Set<String>>>(
      favoriteIdsControllerProvider,
      (previous, next) {
        final prevIds = previous?.valueOrNull;
        final nextIds = next.valueOrNull;
        // 실제 변경이 있을 때만 새로고침 (초기 로딩 제외)
        if (prevIds != null && nextIds != null && prevIds != nextIds) {
          refresh();
        }
      },
    );

    final initialSnapshot = await _repository.fetchWatchlist(
      asOf: _selectedDate,
      offset: 0,
      limit: _pageSize,
    );

    // 초기 로딩 후 나머지 항목은 백그라운드에서 자동 로드
    if (initialSnapshot.hasMore) {
      _loadRemainingInBackground();
    }

    return initialSnapshot;
  }

  Future<void> refresh() async {
    _isLoadingMore = false;
    state = await AsyncValue.guard(
      () => _repository.fetchWatchlist(
        asOf: _selectedDate,
        offset: 0,
        limit: _pageSize,
      ),
    );

    // 새로고침 후에도 나머지 항목 백그라운드 로드
    final snapshot = state.valueOrNull;
    if (snapshot != null && snapshot.hasMore) {
      _loadRemainingInBackground();
    }
  }

  /// 나머지 항목을 백그라운드에서 자동 로드.
  ///
  /// 초기 20개 로드 후 정렬이 제대로 동작하도록
  /// 전체 데이터를 백그라운드에서 가져옴.
  Future<void> _loadRemainingInBackground() async {
    while (true) {
      final loaded = await loadMore();
      if (!loaded) break;
    }
  }

  /// 다음 페이지 로드 (무한 스크롤용).
  ///
  /// 반환값: 로딩 성공 여부.
  /// - true: 새 항목이 추가됨
  /// - false: 더 이상 항목 없음 또는 이미 로딩 중
  Future<bool> loadMore() async {
    final currentSnapshot = state.valueOrNull;
    if (currentSnapshot == null) return false;
    if (!currentSnapshot.hasMore) return false;
    if (_isLoadingMore) return false;

    _isLoadingMore = true;

    try {
      final nextPage = await _repository.fetchWatchlist(
        asOf: _selectedDate,
        offset: currentSnapshot.items.length,
        limit: _pageSize,
      );

      // 새 아이템을 기존 스냅샷에 추가
      state = AsyncValue.data(
        currentSnapshot.appendItems(nextPage.items, nextPage.totalCount),
      );

      return nextPage.items.isNotEmpty;
    } catch (_) {
      // 추가 로딩 실패 시 기존 데이터 유지
      // (전체 state를 error로 바꾸지 않음)
      return false;
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> setAsOf(DateTime value) async {
    ref.read(watchlistSelectedDateProvider.notifier).state = normalizeAsOfDate(
      value,
    );
    await refresh();
  }
}
