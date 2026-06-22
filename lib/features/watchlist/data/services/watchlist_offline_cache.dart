import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/watchlist_models.dart';
import '../../domain/services/watchlist_sorting.dart';

/// 오프라인 캐시 키.
const _watchlistCacheKey = 'watchlist_offline_cache';
const _cacheTsKey = 'watchlist_cache_timestamp';
const _availableDatesCacheKey = 'available_dates_cache';
const _availableDatesTsKey = 'available_dates_timestamp';

/// 관심종목 오프라인 캐시 서비스.
///
/// 금융앱 UX를 위한 오프라인 지원:
/// - 마지막 성공한 관심종목 데이터를 SharedPreferences에 저장
/// - 네트워크 실패 시 캐시된 데이터 반환
/// - 캐시 데이터 사용 시 isStale 플래그로 구분
///
/// 캐시 유효성:
/// - 캐시 타임스탬프 저장
/// - 오래된 캐시도 오프라인에서는 유효 (없는 것보다 나음)
class WatchlistOfflineCache {
  const WatchlistOfflineCache(this._sharedPreferences);

  final SharedPreferences? _sharedPreferences;

  /// 캐시된 스냅샷 저장.
  Future<void> saveSnapshot(WatchlistSnapshot snapshot) async {
    final prefs = _sharedPreferences;
    if (prefs == null) return;

    try {
      final json = _serializeSnapshot(snapshot);
      await prefs.setString(_watchlistCacheKey, jsonEncode(json));
      await prefs.setInt(_cacheTsKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // 캐시 저장 실패는 무시 (필수 기능 아님)
    }
  }

  /// 캐시된 스냅샷 로드.
  /// 캐시가 없거나 파싱 실패 시 null 반환.
  WatchlistSnapshot? loadSnapshot() {
    final prefs = _sharedPreferences;
    if (prefs == null) return null;

    try {
      final jsonString = prefs.getString(_watchlistCacheKey);
      if (jsonString == null) return null;

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return _deserializeSnapshot(json);
    } catch (_) {
      return null;
    }
  }

  /// 캐시 타임스탬프 조회.
  DateTime? getCacheTimestamp() {
    final prefs = _sharedPreferences;
    if (prefs == null) return null;

    final ts = prefs.getInt(_cacheTsKey);
    if (ts == null) return null;

    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  /// 캐시 삭제.
  Future<void> clearCache() async {
    final prefs = _sharedPreferences;
    if (prefs == null) return;

    await prefs.remove(_watchlistCacheKey);
    await prefs.remove(_cacheTsKey);
    await prefs.remove(_availableDatesCacheKey);
    await prefs.remove(_availableDatesTsKey);
  }

  // ─────────────────────────────────────────────────────────────────
  // 거래일 목록 캐시
  // ─────────────────────────────────────────────────────────────────

  /// 거래일 목록 캐시 저장.
  Future<void> saveAvailableDates(List<DateTime> dates) async {
    final prefs = _sharedPreferences;
    if (prefs == null) return;

    try {
      final jsonList = dates.map(formatApiDate).toList();
      await prefs.setString(_availableDatesCacheKey, jsonEncode(jsonList));
      await prefs.setInt(
        _availableDatesTsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // 캐시 저장 실패는 무시
    }
  }

  /// 거래일 목록 캐시 로드.
  List<DateTime>? loadAvailableDates() {
    final prefs = _sharedPreferences;
    if (prefs == null) return null;

    try {
      final jsonString = prefs.getString(_availableDatesCacheKey);
      if (jsonString == null) return null;

      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((e) => _parseDate(e as String)).toList();
    } catch (_) {
      return null;
    }
  }

  /// 거래일 캐시 타임스탬프 조회.
  DateTime? getAvailableDatesCacheTimestamp() {
    final prefs = _sharedPreferences;
    if (prefs == null) return null;

    final ts = prefs.getInt(_availableDatesTsKey);
    if (ts == null) return null;

    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  /// 거래일 캐시가 유효한지 (오늘 이미 로딩했는지) 확인.
  bool isAvailableDatesCacheValid() {
    final cacheTime = getAvailableDatesCacheTimestamp();
    if (cacheTime == null) return false;

    final now = DateTime.now();
    // 같은 날이면 유효 (당일 중 거래일이 바뀌진 않음)
    return cacheTime.year == now.year &&
        cacheTime.month == now.month &&
        cacheTime.day == now.day;
  }

  /// WatchlistSnapshot → JSON 직렬화.
  Map<String, dynamic> _serializeSnapshot(WatchlistSnapshot snapshot) {
    return {
      'asOf': formatApiDate(snapshot.asOf),
      'items': snapshot.items.map(_serializeItem).toList(),
      'availableDates': snapshot.availableDates.map(formatApiDate).toList(),
    };
  }

  Map<String, dynamic> _serializeItem(WatchlistItem item) {
    return {
      'id': item.id,
      'market': item.market.apiValue,
      'symbol': item.symbol,
      'name': item.name,
      'currency': item.currency,
      'currentPrice': item.currentPrice,
      'changeRate': item.changeRate,
      'tradeVolume': item.tradeVolume,
      'marketCap': item.marketCap,
      'logoUrl': item.logoUrl,
    };
  }

  /// JSON → WatchlistSnapshot 역직렬화.
  WatchlistSnapshot _deserializeSnapshot(Map<String, dynamic> json) {
    final asOfStr = json['asOf'] as String;
    final itemsJson = json['items'] as List<dynamic>;
    final datesJson = json['availableDates'] as List<dynamic>? ?? [];

    return WatchlistSnapshot(
      asOf: _parseDate(asOfStr),
      items: itemsJson
          .map((e) => _deserializeItem(e as Map<String, dynamic>))
          .toList(),
      availableDates: datesJson.map((e) => _parseDate(e as String)).toList(),
    );
  }

  WatchlistItem _deserializeItem(Map<String, dynamic> json) {
    return WatchlistItem(
      id: json['id'] as String,
      market: _parseMarketType(json['market'] as String),
      symbol: json['symbol'] as String,
      name: json['name'] as String,
      currency: json['currency'] as String,
      currentPrice: (json['currentPrice'] as num?)?.toDouble(),
      changeRate: (json['changeRate'] as num?)?.toDouble(),
      tradeVolume: json['tradeVolume'] as int?,
      marketCap: json['marketCap'] as int?,
      logoUrl: json['logoUrl'] as String?,
    );
  }

  DateTime _parseDate(String dateStr) {
    // yyyyMMdd 형식
    if (dateStr.length == 8) {
      return normalizeAsOfDate(DateTime(
        int.parse(dateStr.substring(0, 4)),
        int.parse(dateStr.substring(4, 6)),
        int.parse(dateStr.substring(6, 8)),
      ));
    }
    // ISO 형식 fallback
    return normalizeAsOfDate(DateTime.parse(dateStr));
  }

  MarketType _parseMarketType(String value) {
    switch (value) {
      case 'overseas':
        return MarketType.overseas;
      default:
        return MarketType.domestic;
    }
  }
}

/// 오프라인 캐시 결과.
/// [isStale]이 true면 캐시 데이터임을 표시.
class CachedWatchlistResult {
  const CachedWatchlistResult({
    required this.snapshot,
    required this.isStale,
    this.cacheTime,
  });

  final WatchlistSnapshot snapshot;
  final bool isStale;
  final DateTime? cacheTime;
}
