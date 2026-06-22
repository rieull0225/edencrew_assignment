import 'package:flutter/foundation.dart';

enum WatchlistSortMode {
  price('현재가순'),
  changeRate('등락률순'),
  alphabetical('가나다순'),
  marketCap('시총순');

  const WatchlistSortMode(this.label);

  final String label;
}

enum MarketType { domestic, overseas }

extension MarketTypeX on MarketType {
  String get apiValue {
    switch (this) {
      case MarketType.domestic:
        return 'domestic';
      case MarketType.overseas:
        return 'overseas';
    }
  }
}

enum PriceChangeDirection { up, down, flat }

@immutable
class WatchlistItem {
  const WatchlistItem({
    required this.id,
    required this.market,
    required this.symbol,
    required this.name,
    required this.currency,
    this.currentPrice,
    this.changeRate,
    this.tradeVolume,
    this.marketCap,
    this.logoUrl,
  });

  final String id;
  final MarketType market;
  final String symbol;
  final String name;
  final String currency;
  /// 현재가. null이면 데이터 없음 (상장 전 또는 해당 날짜 데이터 미존재).
  final double? currentPrice;
  /// 등락률. null이면 데이터 없음.
  final double? changeRate;
  /// 거래량. null이면 데이터 없음.
  final int? tradeVolume;
  /// 시가총액. null이면 데이터 없음.
  final int? marketCap;
  final String? logoUrl;

  /// 데이터가 있는지 여부.
  bool get hasData => currentPrice != null;

  PriceChangeDirection get direction => directionFromDelta(changeRate ?? 0);
}

@immutable
class StockSearchItem {
  const StockSearchItem({
    required this.id,
    required this.market,
    required this.marketLabel,
    required this.symbol,
    required this.name,
    required this.isFavorite,
    this.logoUrl,
  });

  final String id;
  final MarketType market;
  final String marketLabel;
  final String symbol;
  final String name;
  final bool isFavorite;
  final String? logoUrl;

  StockSearchItem copyWith({
    String? id,
    MarketType? market,
    String? marketLabel,
    String? symbol,
    String? name,
    bool? isFavorite,
    Object? logoUrl = _sentinel,
  }) {
    return StockSearchItem(
      id: id ?? this.id,
      market: market ?? this.market,
      marketLabel: marketLabel ?? this.marketLabel,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      isFavorite: isFavorite ?? this.isFavorite,
      logoUrl: logoUrl == _sentinel ? this.logoUrl : logoUrl as String?,
    );
  }
}

@immutable
class CandlePoint {
  const CandlePoint({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.direction,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final PriceChangeDirection direction;
}

@immutable
class WatchlistDetail {
  const WatchlistDetail({
    required this.itemId,
    required this.symbol,
    required this.market,
    required this.currency,
    required this.currentPrice,
    required this.changeAmount,
    required this.changeRate,
    required this.tradeVolume,
    required this.volumeRatio,
    required this.openPrice,
    required this.openChangeRate,
    required this.highPrice,
    required this.highChangeRate,
    required this.lowPrice,
    required this.lowChangeRate,
    required this.candles,
  });

  final String itemId;
  final String symbol;
  final MarketType market;
  final String currency;
  final double currentPrice;
  final double changeAmount;
  final double changeRate;
  final int tradeVolume;
  final double volumeRatio;
  final double openPrice;
  final double openChangeRate;
  final double highPrice;
  final double highChangeRate;
  final double lowPrice;
  final double lowChangeRate;
  final List<CandlePoint> candles;

  PriceChangeDirection get direction => directionFromDelta(changeAmount);
}

@immutable
class WatchlistSnapshot {
  const WatchlistSnapshot({
    required this.asOf,
    required this.items,
    required this.totalCount,
    this.availableDates = const [],
  });

  final DateTime asOf;
  final List<WatchlistItem> items;
  /// 전체 즐겨찾기 수 (페이지네이션용).
  final int totalCount;
  final List<DateTime> availableDates;

  /// 더 로드할 항목이 있는지 여부.
  bool get hasMore => items.length < totalCount;

  /// 현재 로드된 아이템에 더 추가하여 새 스냅샷 생성.
  WatchlistSnapshot appendItems(List<WatchlistItem> newItems, int newTotalCount) {
    return WatchlistSnapshot(
      asOf: asOf,
      items: [...items, ...newItems],
      totalCount: newTotalCount,
      availableDates: availableDates,
    );
  }
}

PriceChangeDirection directionFromDelta(double value) {
  if (value > 0) {
    return PriceChangeDirection.up;
  }
  if (value < 0) {
    return PriceChangeDirection.down;
  }
  return PriceChangeDirection.flat;
}

const _sentinel = Object();
