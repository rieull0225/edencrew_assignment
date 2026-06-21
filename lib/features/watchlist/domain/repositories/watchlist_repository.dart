import '../models/watchlist_models.dart';

abstract interface class WatchlistRepository {
  Future<WatchlistSnapshot> fetchWatchlist({DateTime? asOf});

  Future<List<DateTime>> fetchAvailableDates();

  /// 추가 거래일 로딩 (페이지네이션).
  Future<List<DateTime>> loadMoreDates();

  /// 추가 로딩 가능 여부.
  bool get hasMoreDates;

  Future<WatchlistDetail> fetchWatchlistDetail({
    required String symbol,
    required MarketType market,
    DateTime? asOf,
  });

  Future<List<StockSearchItem>> searchStocks({required String query});

  Future<Set<String>> loadFavoriteIds();

  Future<void> addFavorite({required String itemId});

  Future<void> removeFavorite({required String itemId});
}
