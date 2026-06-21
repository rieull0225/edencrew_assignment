// ignore_for_file: unused_element, unused_field

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show setEquals;

import '../../domain/models/watchlist_models.dart';
import '../../domain/repositories/watchlist_repository.dart';
import '../../domain/services/watchlist_sorting.dart';
import '../clients/naver_domestic_stock_client.dart';
import '../clients/naver_stock_logo_url_resolver.dart';
import '../dtos/naver_stock_dtos.dart';
import '../services/api_retry.dart';
import '../services/watchlist_offline_cache.dart';
import 'favorite_ids_local_store.dart';

/// 네이버 금융 API를 사용하는 관심종목 Repository 구현체.
///
/// 구현 방식:
/// - 메타데이터, 일별 시세, 실시간 시세를 조합해 관심종목 데이터 구성
/// - 메모리 캐시로 중복 API 호출 방지 (금융앱 성능 최적화)
/// - SharedPreferences로 즐겨찾기 ID 영속화
///
/// 성능 고려사항 (금융앱):
/// - realtimeCacheTtl: 실시간 시세 캐시 유효 시간 (기본 10초)
/// - 거래일 목록: 로컬 캐시 우선 → 첫 실행 시 병렬 로딩으로 전체 로드
/// - 병렬 배치 요청으로 750+ 페이지도 ~20초 내 로딩 가능
///
/// 안정성 (금융앱):
/// - API 재시도: exponential backoff로 일시적 오류 복구
/// - 오프라인 캐시: 네트워크 실패 시 마지막 성공 데이터 반환
class NaverWatchlistRepository implements WatchlistRepository {
  NaverWatchlistRepository({
    required Dio dio,
    required FavoriteIdsLocalStore favoriteIdsLocalStore,
    WatchlistOfflineCache? offlineCache,
    NaverStockDataClient? client,
    NaverStockLogoUrlResolver? logoUrlResolver,
    this.realtimeCacheTtl = const Duration(seconds: 10),
    this.parallelBatchSize = 10,
  }) : _client = client ?? NaverDomesticStockClient(dio),
       _favoriteIdsLocalStore = favoriteIdsLocalStore,
       _offlineCache = offlineCache,
       _logoUrlResolver = logoUrlResolver ?? const NaverStockLogoUrlResolver();

  static const _historyRowsPerPage = 10;

  final NaverStockDataClient _client;
  final FavoriteIdsLocalStore _favoriteIdsLocalStore;
  final WatchlistOfflineCache? _offlineCache;
  final NaverStockLogoUrlResolver _logoUrlResolver;
  final Duration realtimeCacheTtl;

  /// 병렬 로딩 시 한 번에 요청할 페이지 수.
  /// 너무 크면 rate limiting, 너무 작으면 느림. 10이 적절.
  final int parallelBatchSize;

  final Map<String, NaverChartMetadataDto> _metadataCache = {};
  final Map<String, NaverDailyHistoryPageDto> _dailyHistoryPageCache = {};
  final Map<String, _RealtimeQuoteCacheEntry> _realtimeQuoteCache = {};

  Set<String>? _favoriteIdsCache;
  List<DateTime>? _availableDatesCache;

  /// 관심종목 스냅샷 조회.
  ///
  /// 처리 흐름:
  /// 1. 즐겨찾기 ID 로드 → 종목코드 추출
  /// 2. 메타데이터, 실시간 시세 병렬 로딩
  /// 3. 거래일 목록 로딩 및 asOf 날짜 해석
  /// 4. 각 종목별 WatchlistItem 구성
  ///
  /// 실시간 시세 vs 과거 시세:
  /// - asOf가 최신 거래일이면 실시간 시세 우선 사용
  /// - 과거 날짜면 일별 시세 데이터 사용
  ///
  /// 오프라인 지원:
  /// - 성공 시 오프라인 캐시에 저장
  /// - 네트워크 실패 시 캐시 데이터 반환
  @override
  Future<WatchlistSnapshot> fetchWatchlist({DateTime? asOf}) async {
    try {
      final snapshot = await _fetchWatchlistInternal(asOf: asOf);
      // 성공 시 오프라인 캐시에 저장
      _offlineCache?.saveSnapshot(snapshot);
      return snapshot;
    } catch (e) {
      // 네트워크 오류 시 오프라인 캐시에서 복구 시도
      if (isNetworkError(e)) {
        final cached = _offlineCache?.loadSnapshot();
        if (cached != null) {
          return cached;
        }
      }
      rethrow;
    }
  }

  /// 실제 관심종목 조회 로직 (내부용).
  Future<WatchlistSnapshot> _fetchWatchlistInternal({DateTime? asOf}) async {
    // 1. Load canonical favorite ids
    final favoriteIds = await loadFavoriteIds();

    // 2. Convert each id into a six-digit domestic symbol
    final symbols = <String>[];
    for (final id in favoriteIds) {
      final symbol = domesticSymbolFromFavoriteId(id);
      if (symbol != null) {
        symbols.add(symbol);
      }
    }

    if (symbols.isEmpty) {
      return WatchlistSnapshot(
        asOf: normalizeAsOfDate(asOf ?? DateTime.now()),
        items: [],
        availableDates: [],
      );
    }

    // 3. Load metadata and realtime quotes for those symbols
    final metadataMap = await _loadMetadataBatch(symbols);
    final realtimeQuotes = await _loadRealtimeQuotes(symbols);

    // 4-5. Load available dates and resolve asOf
    final availableDates = await fetchAvailableDates();
    final resolvedAsOf = _resolveAsOf(availableDates, asOf);
    final latestDate = availableDates.isNotEmpty ? availableDates.first : null;

    // 6. Build WatchlistItem for each symbol
    final items = <WatchlistItem>[];
    for (final symbol in symbols) {
      final metadata = metadataMap[symbol];
      if (metadata == null) {
        continue;
      }

      _HistoricalEntry? historicalEntry;

      if (asOf == null) {
        // Use latest historical row
        historicalEntry = await _loadLatestHistoricalEntry(symbol);
      } else {
        // Use historical row for the selected date
        historicalEntry = await _loadHistoricalEntryForDate(
          symbol: symbol,
          availableDates: availableDates,
          asOf: resolvedAsOf,
        );
      }

      if (historicalEntry == null) {
        continue;
      }

      final item = _buildWatchlistItem(
        symbol: symbol,
        metadata: metadata,
        historicalEntry: historicalEntry,
        realtimeQuote: realtimeQuotes[symbol],
        latestDate: latestDate,
      );
      items.add(item);
    }

    return WatchlistSnapshot(
      asOf: resolvedAsOf,
      items: items,
      availableDates: availableDates,
    );
  }

  /// 거래 가능한 날짜 목록 조회 (내림차순 - 최신순).
  ///
  /// 로딩 전략: 로컬 캐시 우선 + 병렬 전체 로딩
  ///
  /// 1. 메모리 캐시 확인 → 있으면 즉시 반환
  /// 2. 로컬 캐시(SharedPreferences) 확인 → 당일 유효하면 즉시 반환
  /// 3. 캐시 없으면 전체 페이지 병렬 로딩 (10개씩 배치)
  ///    - 750페이지 / 10배치 = 75번 × 0.3초 ≈ 22초 (순차 대비 10배 빠름)
  /// 4. 로딩 완료 후 로컬 캐시 저장 (다음 실행 시 즉시 로딩)
  ///
  /// 왜 이렇게 구현했는가:
  /// - 금융앱에서 전체 거래일 접근은 필수 (과거 차트, 분석 등)
  /// - 첫 실행만 오래 걸리고, 이후는 캐시로 즉시 로딩
  /// - 페이지네이션은 UX가 어색함 (날짜 피커에 "더 보기"?)
  @override
  Future<List<DateTime>> fetchAvailableDates() async {
    // 1. 메모리 캐시 확인
    if (_availableDatesCache != null) {
      return _availableDatesCache!;
    }

    // 2. 로컬 캐시 확인 (당일 유효)
    final cachedDates = _offlineCache?.loadAvailableDates();
    if (cachedDates != null && _offlineCache!.isAvailableDatesCacheValid()) {
      _availableDatesCache = cachedDates;
      return cachedDates;
    }

    // 3. 참조할 종목 선택 (첫 번째 즐겨찾기)
    final favoriteIds = await loadFavoriteIds();
    String? referenceSymbol;
    for (final id in favoriteIds) {
      final symbol = domesticSymbolFromFavoriteId(id);
      if (symbol != null) {
        referenceSymbol = symbol;
        break;
      }
    }

    if (referenceSymbol == null) {
      _availableDatesCache = [];
      return [];
    }

    // 4. 첫 페이지 로딩 → 전체 페이지 수 확인
    final firstPage = await _loadDailyHistoryPage(referenceSymbol, 1);
    final totalPages = firstPage.lastPage;

    final allDates = <DateTime>{};
    for (final row in firstPage.priceInfos) {
      allDates.add(normalizeAsOfDate(row.localDate));
    }

    // 5. 나머지 페이지 병렬 로딩 (배치 단위)
    for (var batchStart = 2; batchStart <= totalPages; batchStart += parallelBatchSize) {
      final batchEnd = (batchStart + parallelBatchSize - 1).clamp(1, totalPages);

      final batch = <Future<NaverDailyHistoryPageDto>>[];
      for (var page = batchStart; page <= batchEnd; page++) {
        batch.add(_loadDailyHistoryPage(referenceSymbol, page));
      }

      final results = await Future.wait(batch);
      for (final pageDto in results) {
        for (final row in pageDto.priceInfos) {
          allDates.add(normalizeAsOfDate(row.localDate));
        }
      }
    }

    // 6. 정렬 및 캐시 저장
    final sortedDates = allDates.toList()..sort((a, b) => b.compareTo(a));
    _availableDatesCache = sortedDates;

    // 로컬 캐시에 저장 (다음 앱 실행 시 즉시 로딩)
    _offlineCache?.saveAvailableDates(sortedDates);

    return sortedDates;
  }

  @override
  Future<WatchlistDetail> fetchWatchlistDetail({
    required String symbol,
    required MarketType market,
    DateTime? asOf,
  }) async {
    // Only domestic stocks are supported
    if (market != MarketType.domestic) {
      throw ArgumentError.value(market, 'market', 'Only domestic stocks are supported');
    }

    // Load available dates and resolve asOf
    final availableDates = await fetchAvailableDates();
    final resolvedAsOf = _resolveAsOf(availableDates, asOf);
    final latestDate = availableDates.isNotEmpty ? availableDates.first : null;

    // Find the index of the selected date
    final selectedIndex = _indexOfDate(availableDates, resolvedAsOf);

    // Collect up to 30 trading days (including selected day)
    final windowDatesDescending = <DateTime>[];
    if (selectedIndex != null) {
      for (var i = selectedIndex; i < availableDates.length && windowDatesDescending.length < 30; i++) {
        windowDatesDescending.add(availableDates[i]);
      }
    }

    // Load all required daily history pages for the window
    final rowsByDate = <String, NaverHistoricalPriceDto>{};
    if (windowDatesDescending.isNotEmpty) {
      final pagesToLoad = <int>{};
      for (var i = 0; i < windowDatesDescending.length; i++) {
        pagesToLoad.add(_pageNumberForIndex(selectedIndex! + i));
      }

      for (final page in pagesToLoad) {
        final pageDto = await _loadDailyHistoryPage(symbol, page);
        for (final row in pageDto.priceInfos) {
          rowsByDate[_dateKey(row.localDate)] = row;
        }
      }
    }

    // Get the selected row
    final selectedRow = rowsByDate[_dateKey(resolvedAsOf)];
    if (selectedRow == null) {
      throw StateError('No historical data found for date $resolvedAsOf');
    }

    // Calculate previous close
    double previousClose = selectedRow.openPrice;
    if (selectedIndex != null && selectedIndex + 1 < availableDates.length) {
      final previousRow = rowsByDate[_dateKey(availableDates[selectedIndex + 1])];
      if (previousRow != null) {
        previousClose = previousRow.closePrice;
      }
    }

    // Check if using realtime data (only for latest trading day)
    final isLatest = latestDate != null && normalizeAsOfDate(resolvedAsOf) == latestDate;
    NaverRealtimeQuoteDto? realtimeQuote;
    if (isLatest) {
      final quotes = await _loadRealtimeQuotes([symbol]);
      realtimeQuote = quotes[symbol];
    }

    // Calculate price values
    final currentPrice = isLatest && realtimeQuote != null
        ? realtimeQuote.currentPrice
        : selectedRow.closePrice;
    final changeAmount = currentPrice - previousClose;
    final changeRate = _percentChange(changeAmount, previousClose);
    final tradeVolume = isLatest && realtimeQuote != null
        ? realtimeQuote.accumulatedTradingVolume
        : selectedRow.accumulatedTradingVolume;

    final openPrice = isLatest && realtimeQuote != null
        ? realtimeQuote.openPrice
        : selectedRow.openPrice;
    final highPrice = isLatest && realtimeQuote != null
        ? realtimeQuote.highPrice
        : selectedRow.highPrice;
    final lowPrice = isLatest && realtimeQuote != null
        ? realtimeQuote.lowPrice
        : selectedRow.lowPrice;

    final volumeRatio = _volumeRatio(
      windowDatesDescending: windowDatesDescending,
      rowsByDate: rowsByDate,
    );

    final candles = _candles(
      windowDatesDescending: windowDatesDescending,
      rowsByDate: rowsByDate,
    );

    return WatchlistDetail(
      itemId: canonicalDomesticFavoriteId(symbol),
      symbol: symbol,
      market: market,
      currency: 'KRW',
      currentPrice: currentPrice,
      changeAmount: changeAmount,
      changeRate: changeRate,
      tradeVolume: tradeVolume,
      volumeRatio: volumeRatio,
      openPrice: openPrice,
      openChangeRate: _percentChange(openPrice - previousClose, previousClose),
      highPrice: highPrice,
      highChangeRate: _percentChange(highPrice - previousClose, previousClose),
      lowPrice: lowPrice,
      lowChangeRate: _percentChange(lowPrice - previousClose, previousClose),
      candles: candles,
    );
  }

  @override
  Future<List<StockSearchItem>> searchStocks({required String query}) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return [];
    }

    final searchResults = await _client.searchStocks(trimmedQuery);
    final favoriteIds = await loadFavoriteIds();
    final seenSymbols = <String>{};
    final items = <StockSearchItem>[];

    for (final dto in searchResults) {
      // Only keep domestic 6-digit stock codes
      if (!dto.isDomesticStock) continue;

      // Deduplicate by symbol
      if (seenSymbols.contains(dto.code)) continue;
      seenSymbols.add(dto.code);

      final canonicalId = canonicalDomesticFavoriteId(dto.code);
      items.add(StockSearchItem(
        id: canonicalId,
        market: MarketType.domestic,
        marketLabel: dto.typeName,
        symbol: dto.code,
        name: dto.name,
        isFavorite: favoriteIds.contains(canonicalId),
        logoUrl: _logoUrlResolver.resolveDomesticStockLogoUrl(dto.code),
      ));
    }

    return items;
  }

  /// 즐겨찾기 ID 목록 로드.
  ///
  /// Canonical ID 형식: "domestic:{6자리종목코드}"
  /// - 메모리 캐시 우선 사용
  /// - 저장된 ID가 없거나 레거시 형식이면 기본값 사용
  /// - 변경된 경우 자동으로 저장소에 반영
  @override
  Future<Set<String>> loadFavoriteIds() async {
    if (_favoriteIdsCache != null) {
      return Set<String>.unmodifiable(_favoriteIdsCache!);
    }

    final rawIds = await _favoriteIdsLocalStore.loadRawIds();
    final canonicalIds = rawIds.where(_isCanonicalFavoriteId).toSet();
    final hasLegacyOrInvalidIds =
        rawIds.isNotEmpty && canonicalIds.length != rawIds.length;

    final resolvedIds = !_favoriteIdsLocalStore.hasStoredIds
        ? <String>{...defaultNaverDomesticFavoriteIds}
        : hasLegacyOrInvalidIds
        ? <String>{...defaultNaverDomesticFavoriteIds}
        : canonicalIds;

    _favoriteIdsCache = resolvedIds;

    if (!setEquals(rawIds, resolvedIds)) {
      await _favoriteIdsLocalStore.saveRawIds(resolvedIds);
    }

    return Set<String>.unmodifiable(resolvedIds);
  }

  @override
  Future<void> addFavorite({required String itemId}) async {
    final canonicalId = _requireCanonicalFavoriteId(itemId);
    final favoriteIds = {...await loadFavoriteIds(), canonicalId};
    _favoriteIdsCache = favoriteIds;
    await _favoriteIdsLocalStore.saveRawIds(favoriteIds);
  }

  @override
  Future<void> removeFavorite({required String itemId}) async {
    final canonicalId = _requireCanonicalFavoriteId(itemId);
    final favoriteIds = {...await loadFavoriteIds()}..remove(canonicalId);
    _favoriteIdsCache = favoriteIds;
    await _favoriteIdsLocalStore.saveRawIds(favoriteIds);
  }

  /// 여러 종목의 메타데이터를 배치 로딩.
  /// 개별 종목 실패는 무시하고 성공한 것만 반환.
  Future<Map<String, NaverChartMetadataDto>> _loadMetadataBatch(
    List<String> symbols,
  ) async {
    final results = <String, NaverChartMetadataDto>{};
    for (final symbol in symbols) {
      try {
        results[symbol] = await _loadMetadata(symbol);
      } catch (_) {
        // 개별 종목 메타데이터 실패는 무시 (다른 종목은 계속 로딩)
      }
    }
    return results;
  }

  /// 메타데이터 로딩 (캐시 + 재시도).
  Future<NaverChartMetadataDto> _loadMetadata(String symbol) async {
    final cached = _metadataCache[symbol];
    if (cached != null) {
      return cached;
    }

    // API 호출에 재시도 적용
    final metadata = await apiRetry.execute(
      () => _client.fetchChartMetadata(symbol),
    );
    _metadataCache[symbol] = metadata;
    return metadata;
  }

  /// 일별 시세 페이지 로딩 (캐시 + 재시도).
  Future<NaverDailyHistoryPageDto> _loadDailyHistoryPage(
    String symbol,
    int page,
  ) async {
    final cacheKey = _dailyHistoryPageCacheKey(symbol, page);
    final cached = _dailyHistoryPageCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    // API 호출에 재시도 적용
    final historyPage = await apiRetry.execute(
      () => _client.fetchDailyHistoryPage(symbol: symbol, page: page),
    );
    _dailyHistoryPageCache[cacheKey] = historyPage;
    return historyPage;
  }

  Future<Map<String, NaverRealtimeQuoteDto>> _loadRealtimeQuotes(
    Iterable<String> symbols,
  ) async {
    final requestedSymbols = symbols.toSet();
    final now = DateTime.now();
    final missingSymbols = <String>[];
    final quotes = <String, NaverRealtimeQuoteDto>{};

    for (final symbol in requestedSymbols) {
      final cached = _realtimeQuoteCache[symbol];
      final isFresh =
          cached != null &&
          now.difference(cached.fetchedAt) <= realtimeCacheTtl;
      if (isFresh) {
        quotes[symbol] = cached.quote;
      } else {
        missingSymbols.add(symbol);
      }
    }

    if (missingSymbols.isNotEmpty) {
      try {
        // API 호출에 재시도 적용
        final fetchedQuotes = await apiRetry.execute(
          () => _client.fetchRealtimeQuotes(missingSymbols),
        );
        final fetchedAt = DateTime.now();
        for (final entry in fetchedQuotes.entries) {
          _realtimeQuoteCache[entry.key] = _RealtimeQuoteCacheEntry(
            quote: entry.value,
            fetchedAt: fetchedAt,
          );
          quotes[entry.key] = entry.value;
        }
      } catch (_) {
        // 재시도 후에도 실패 시 과거 시세로 폴백
      }
    }

    return quotes;
  }

  Future<_HistoricalEntry?> _loadHistoricalEntryForDate({
    required String symbol,
    required List<DateTime> availableDates,
    required DateTime asOf,
  }) async {
    final selectedIndex = _indexOfDate(availableDates, asOf);
    if (selectedIndex == null) {
      return null;
    }

    final selectedPageNumber = _pageNumberForIndex(selectedIndex);
    final selectedPage = await _loadDailyHistoryPage(
      symbol,
      selectedPageNumber,
    );
    final selectedRow = _rowForDate(selectedPage.priceInfos, asOf);
    if (selectedRow == null) {
      return null;
    }

    final previousClose = await _resolvePreviousClose(
      symbol: symbol,
      availableDates: availableDates,
      selectedIndex: selectedIndex,
      fallbackOpenPrice: selectedRow.openPrice,
      rowsByDate: {
        for (final row in selectedPage.priceInfos) _dateKey(row.localDate): row,
      },
    );

    return _HistoricalEntry(row: selectedRow, previousClose: previousClose);
  }

  Future<_HistoricalEntry?> _loadLatestHistoricalEntry(String symbol) async {
    final firstPage = await _loadDailyHistoryPage(symbol, 1);
    if (firstPage.priceInfos.isEmpty) {
      return null;
    }

    final selectedRow = firstPage.priceInfos.first;
    double previousClose = selectedRow.openPrice;
    if (firstPage.priceInfos.length > 1) {
      previousClose = firstPage.priceInfos[1].closePrice;
    } else {
      final nextPageRows = (await _loadDailyHistoryPage(symbol, 2)).priceInfos;
      if (nextPageRows.isNotEmpty) {
        previousClose = nextPageRows.first.closePrice;
      }
    }

    return _HistoricalEntry(row: selectedRow, previousClose: previousClose);
  }

  Future<double> _resolvePreviousClose({
    required String symbol,
    required List<DateTime> availableDates,
    required int selectedIndex,
    required double fallbackOpenPrice,
    required Map<String, NaverHistoricalPriceDto> rowsByDate,
  }) async {
    if (selectedIndex >= availableDates.length - 1) {
      return fallbackOpenPrice;
    }

    final previousDate = availableDates[selectedIndex + 1];
    final previousRowFromCache = rowsByDate[_dateKey(previousDate)];
    if (previousRowFromCache != null) {
      return previousRowFromCache.closePrice;
    }

    final page = await _loadDailyHistoryPage(
      symbol,
      _pageNumberForIndex(selectedIndex + 1),
    );
    final previousRow = _rowForDate(page.priceInfos, previousDate);
    return previousRow?.closePrice ?? fallbackOpenPrice;
  }

  WatchlistItem _buildWatchlistItem({
    required String symbol,
    required NaverChartMetadataDto metadata,
    required _HistoricalEntry historicalEntry,
    required NaverRealtimeQuoteDto? realtimeQuote,
    required DateTime? latestDate,
  }) {
    final isLatest =
        latestDate != null &&
        normalizeAsOfDate(historicalEntry.row.localDate) == latestDate;
    final currentPrice = isLatest && realtimeQuote != null
        ? realtimeQuote.currentPrice
        : historicalEntry.row.closePrice;
    final changeRate = isLatest && realtimeQuote != null
        ? realtimeQuote.changeRate
        : _percentChange(
            currentPrice - historicalEntry.previousClose,
            historicalEntry.previousClose,
          );
    final tradeVolume = isLatest && realtimeQuote != null
        ? realtimeQuote.accumulatedTradingVolume
        : historicalEntry.row.accumulatedTradingVolume;
    final marketCap = realtimeQuote == null
        ? 0
        : (realtimeQuote.countOfListedStock * realtimeQuote.currentPrice)
              .round();

    return WatchlistItem(
      id: canonicalDomesticFavoriteId(symbol),
      market: MarketType.domestic,
      symbol: symbol,
      name: metadata.stockName,
      currency: 'KRW',
      currentPrice: currentPrice,
      changeRate: changeRate,
      tradeVolume: tradeVolume,
      marketCap: marketCap,
      logoUrl: _logoUrlResolver.resolveDomesticStockLogoUrl(symbol),
    );
  }

  DateTime _resolveAsOf(
    List<DateTime> availableDates,
    DateTime? requestedAsOf,
  ) {
    if (availableDates.isEmpty) {
      return normalizeAsOfDate(requestedAsOf ?? DateTime.now());
    }

    if (requestedAsOf == null) {
      return availableDates.first;
    }

    final normalizedAsOf = normalizeAsOfDate(requestedAsOf);
    for (final date in availableDates) {
      if (date == normalizedAsOf) {
        return date;
      }
    }

    return availableDates.first;
  }

  int? _indexOfDate(List<DateTime> availableDates, DateTime asOf) {
    final normalizedAsOf = normalizeAsOfDate(asOf);
    for (var index = 0; index < availableDates.length; index += 1) {
      if (availableDates[index] == normalizedAsOf) {
        return index;
      }
    }
    return null;
  }

  int _pageNumberForIndex(int index) {
    return (index ~/ _historyRowsPerPage) + 1;
  }

  NaverHistoricalPriceDto? _rowForDate(
    Iterable<NaverHistoricalPriceDto> rows,
    DateTime date,
  ) {
    final dateKey = _dateKey(date);
    for (final row in rows) {
      if (_dateKey(row.localDate) == dateKey) {
        return row;
      }
    }
    return null;
  }

  double _volumeRatio({
    required List<DateTime> windowDatesDescending,
    required Map<String, NaverHistoricalPriceDto> rowsByDate,
  }) {
    if (windowDatesDescending.isEmpty) {
      return 0;
    }

    final selectedRow = rowsByDate[_dateKey(windowDatesDescending.first)];
    if (selectedRow == null) {
      return 0;
    }

    final previousVolumes = <int>[];
    for (
      var index = 1;
      index < windowDatesDescending.length && previousVolumes.length < 5;
      index += 1
    ) {
      final row = rowsByDate[_dateKey(windowDatesDescending[index])];
      if (row != null) {
        previousVolumes.add(row.accumulatedTradingVolume);
      }
    }

    if (previousVolumes.isEmpty) {
      return 0;
    }

    final averageVolume =
        previousVolumes.reduce((left, right) => left + right) /
        previousVolumes.length;
    if (averageVolume == 0) {
      return 0;
    }

    return double.parse(
      (selectedRow.accumulatedTradingVolume / averageVolume).toStringAsFixed(2),
    );
  }

  List<CandlePoint> _candles({
    required List<DateTime> windowDatesDescending,
    required Map<String, NaverHistoricalPriceDto> rowsByDate,
  }) {
    return windowDatesDescending.reversed
        .map((date) => rowsByDate[_dateKey(date)])
        .whereType<NaverHistoricalPriceDto>()
        .map(
          (item) => CandlePoint(
            time: item.localDate,
            open: item.openPrice,
            high: item.highPrice,
            low: item.lowPrice,
            close: item.closePrice,
            direction: directionFromDelta(item.closePrice - item.openPrice),
          ),
        )
        .toList(growable: false);
  }

  bool _isCanonicalFavoriteId(String itemId) {
    return domesticSymbolFromFavoriteId(itemId) != null;
  }

  String _requireCanonicalFavoriteId(String itemId) {
    final symbol = domesticSymbolFromFavoriteId(itemId);
    if (symbol == null) {
      throw ArgumentError.value(
        itemId,
        'itemId',
        'Naver repository only accepts canonical domestic favorite ids',
      );
    }
    return canonicalDomesticFavoriteId(symbol);
  }

  String _dailyHistoryPageCacheKey(String symbol, int page) => '$symbol::$page';

  String _dateKey(DateTime value) => formatApiDate(value);

  double _percentChange(double delta, double base) {
    if (base == 0) {
      return 0;
    }
    return double.parse(((delta / base) * 100).toStringAsFixed(2));
  }
}

class _RealtimeQuoteCacheEntry {
  const _RealtimeQuoteCacheEntry({
    required this.quote,
    required this.fetchedAt,
  });

  final NaverRealtimeQuoteDto quote;
  final DateTime fetchedAt;
}

class _HistoricalEntry {
  const _HistoricalEntry({required this.row, required this.previousClose});

  final NaverHistoricalPriceDto row;
  final double previousClose;
}
