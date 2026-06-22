import '../models/watchlist_models.dart';

abstract interface class WatchlistRepository {
  /// 관심종목 스냅샷 조회 (페이지네이션 지원).
  ///
  /// [offset]: 시작 인덱스 (기본값 0)
  /// [limit]: 가져올 항목 수 (기본값 20)
  Future<WatchlistSnapshot> fetchWatchlist({
    DateTime? asOf,
    int offset = 0,
    int limit = 20,
  });

  /// 거래 가능한 날짜 목록 조회 (내림차순 - 최신순).
  ///
  /// 구현 전략:
  /// - 첫 실행: 전체 페이지 병렬 로딩 → 로컬 캐시 저장
  /// - 이후 실행: 캐시에서 즉시 반환 → 백그라운드에서 새 거래일 확인
  Future<List<DateTime>> fetchAvailableDates();

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
