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

  @override
  Future<WatchlistSnapshot> build() {
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
    return _repository.fetchWatchlist(asOf: _selectedDate);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => _repository.fetchWatchlist(asOf: _selectedDate),
    );
  }

  Future<void> setAsOf(DateTime value) async {
    ref.read(watchlistSelectedDateProvider.notifier).state = normalizeAsOfDate(
      value,
    );
    await refresh();
  }
}
