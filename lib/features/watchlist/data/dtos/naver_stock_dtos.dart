// ignore_for_file: unused_element

import '../../domain/services/watchlist_sorting.dart';

/// 검색 자동완성 결과 DTO.
///
/// 파싱 규칙:
/// - 모든 필드를 문자열로 안전하게 파싱 (_readString)
/// - isDomesticStock: 국내 주식만 필터링하기 위한 조건
///   - category == 'stock': 주식만
///   - nationCode == 'KOR': 한국만
///   - code가 6자리 숫자: 국내 종목코드 형식
///   - url에 '/domestic/stock/' 포함: 국내 주식 URL 패턴
class NaverAutocompleteItemDto {
  const NaverAutocompleteItemDto({
    required this.code,
    required this.name,
    required this.typeCode,
    required this.typeName,
    required this.url,
    required this.nationCode,
    required this.category,
  });

  factory NaverAutocompleteItemDto.fromJson(Map<String, dynamic> json) {
    return NaverAutocompleteItemDto(
      code: _readString(json['code']),
      name: _readString(json['name']),
      typeCode: _readString(json['typeCode']),
      typeName: _readString(json['typeName']),
      url: _readString(json['url']),
      nationCode: _readString(json['nationCode']),
      category: _readString(json['category']),
    );
  }

  final String code;
  final String name;
  final String typeCode;
  final String typeName;
  final String url;
  final String nationCode;
  final String category;

  /// 국내 6자리 주식 종목인지 판별.
  /// 과제 요구사항: 국내 주식만 필터링, 6자리 종목코드만 통과.
  bool get isDomesticStock =>
      category == 'stock' &&
      nationCode == 'KOR' &&
      RegExp(r'^\d{6}$').hasMatch(code) &&
      url.contains('/domestic/stock/');
}

/// 실시간 시세 DTO.
///
/// 파싱 규칙:
/// - API 응답 필드명이 축약형(cd, nv, pcv 등)이므로 의미있는 이름으로 매핑
/// - 숫자는 num 타입이면 직접 변환, 문자열이면 콤마 제거 후 파싱
/// - countOfListedStock은 nullable이므로 기본값 0 사용
class NaverRealtimeQuoteDto {
  const NaverRealtimeQuoteDto({
    required this.symbol,
    required this.currentPrice,
    required this.previousClose,
    required this.openPrice,
    required this.highPrice,
    required this.lowPrice,
    required this.accumulatedTradingVolume,
    required this.countOfListedStock,
  });

  factory NaverRealtimeQuoteDto.fromJson(Map<String, dynamic> json) {
    return NaverRealtimeQuoteDto(
      symbol: _readString(json['cd']),
      currentPrice: _readDouble(json['nv']),
      previousClose: _readDouble(json['pcv']),
      openPrice: _readDouble(json['ov']),
      highPrice: _readDouble(json['hv']),
      lowPrice: _readDouble(json['lv']),
      accumulatedTradingVolume: _readInt(json['aq']),
      countOfListedStock: _readNullableInt(json['countOfListedStock']) ?? 0,
    );
  }

  final String symbol;
  final double currentPrice;
  final double previousClose;
  final double openPrice;
  final double highPrice;
  final double lowPrice;
  final int accumulatedTradingVolume;
  final int countOfListedStock;

  double get changeAmount => currentPrice - previousClose;

  /// 등락률 계산. 소수점 2자리까지.
  double get changeRate {
    if (previousClose == 0) {
      return 0;
    }
    return double.parse(
      (((currentPrice - previousClose) / previousClose) * 100).toStringAsFixed(
        2,
      ),
    );
  }
}

/// 종목 메타데이터 DTO.
class NaverChartMetadataDto {
  const NaverChartMetadataDto({
    required this.symbol,
    required this.stockName,
    required this.stockExchangeNameKor,
  });

  factory NaverChartMetadataDto.fromJson(Map<String, dynamic> json) {
    return NaverChartMetadataDto(
      symbol: _readString(json['symbolCode']),
      stockName: _readString(json['stockName']),
      stockExchangeNameKor: _readString(json['stockExchangeNameKor']),
    );
  }

  final String symbol;
  final String stockName;
  final String stockExchangeNameKor;
}

/// 일별 시세 DTO.
///
/// 파싱 규칙:
/// - localDate는 'yyyyMMdd' 형식 문자열을 DateTime으로 변환
/// - normalizeAsOfDate로 시간 정보 제거하여 날짜 비교 용이하게 함
class NaverHistoricalPriceDto {
  const NaverHistoricalPriceDto({
    required this.localDate,
    required this.closePrice,
    required this.openPrice,
    required this.highPrice,
    required this.lowPrice,
    required this.accumulatedTradingVolume,
  });

  factory NaverHistoricalPriceDto.fromJson(Map<String, dynamic> json) {
    return NaverHistoricalPriceDto(
      localDate: _readLocalDate(json['localDate']),
      closePrice: _readDouble(json['closePrice']),
      openPrice: _readDouble(json['openPrice']),
      highPrice: _readDouble(json['highPrice']),
      lowPrice: _readDouble(json['lowPrice']),
      accumulatedTradingVolume: _readInt(json['accumulatedTradingVolume']),
    );
  }

  final DateTime localDate;
  final double closePrice;
  final double openPrice;
  final double highPrice;
  final double lowPrice;
  final int accumulatedTradingVolume;
}

class NaverHistoricalChartDto {
  const NaverHistoricalChartDto({
    required this.symbol,
    required this.periodType,
    required this.priceInfos,
  });

  factory NaverHistoricalChartDto.fromJson(Map<String, dynamic> json) {
    final priceInfosList = json['priceInfos'] as List<dynamic>? ?? [];
    return NaverHistoricalChartDto(
      symbol: _readString(json['code']),
      periodType: _readString(json['periodType']),
      priceInfos: priceInfosList
          .map((e) => NaverHistoricalPriceDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String symbol;
  final String periodType;
  final List<NaverHistoricalPriceDto> priceInfos;
}

/// 일별 시세 페이지 DTO.
/// HTML 파싱 결과를 담음.
class NaverDailyHistoryPageDto {
  const NaverDailyHistoryPageDto({
    required this.symbol,
    required this.page,
    required this.lastPage,
    required this.priceInfos,
  });

  final String symbol;
  final int page;
  final int lastPage;
  final List<NaverHistoricalPriceDto> priceInfos;
}

/// yyyyMMdd 형식 문자열을 DateTime으로 파싱.
DateTime _readLocalDate(Object? value) {
  final text = _readString(value);
  if (text.length != 8) {
    throw FormatException('Invalid Naver localDate "$text"');
  }

  return normalizeAsOfDate(
    DateTime(
      int.parse(text.substring(0, 4)),
      int.parse(text.substring(4, 6)),
      int.parse(text.substring(6, 8)),
    ),
  );
}

/// null이나 빈 문자열이면 예외 발생.
String _readString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    throw FormatException('Missing string value for "$value"');
  }
  return text;
}

/// 숫자 파싱. num이면 직접 변환, 문자열이면 콤마 제거 후 파싱.
double _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.parse(_readString(value).replaceAll(',', ''));
}

/// 정수 파싱. 콤마 구분자 지원.
int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.parse(_readString(value).replaceAll(',', ''));
}

int? _readNullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  return _readInt(value);
}
