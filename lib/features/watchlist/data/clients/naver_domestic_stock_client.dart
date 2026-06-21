// ignore_for_file: unused_element, unused_field

import 'dart:convert';

import 'package:dio/dio.dart';

import '../dtos/naver_stock_dtos.dart';

abstract interface class NaverStockDataClient {
  Future<List<NaverAutocompleteItemDto>> searchStocks(String query);

  Future<Map<String, NaverRealtimeQuoteDto>> fetchRealtimeQuotes(
    Iterable<String> symbols,
  );

  Future<NaverChartMetadataDto> fetchChartMetadata(String symbol);

  Future<NaverDailyHistoryPageDto> fetchDailyHistoryPage({
    required String symbol,
    required int page,
  });
}

/// 네이버 금융 API 클라이언트 구현체.
///
/// 구현 방식:
/// - Dio를 사용해 네이버 금융 API 호출
/// - 브라우저처럼 보이도록 User-Agent, Referer 헤더 설정
/// - JSON API는 plain text로 받아 직접 파싱 (Dio의 자동 파싱 대신)
/// - HTML 응답은 bytes로 받아 latin1(EUC-KR 호환)으로 디코딩
///
/// 이렇게 구현한 이유:
/// - 네이버 API는 브라우저 요청만 허용하므로 적절한 헤더 필요
/// - 응답 형식이 다양해서 수동 파싱이 더 안정적
class NaverDomesticStockClient implements NaverStockDataClient {
  const NaverDomesticStockClient(this._dio);

  final Dio _dio;

  /// 네이버 웹 브라우저처럼 보이기 위한 기본 헤더.
  /// Referer를 m.stock.naver.com으로 설정해 API 접근 허용받음.
  static const Map<String, String> _defaultHeaders = {
    'accept': 'application/json, text/plain, */*',
    'referer': 'https://m.stock.naver.com/',
    'accept-language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
    'user-agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/123.0.0.0 Safari/537.36',
  };

  static Map<String, dynamic> _decodeJsonObjectBody(
    Object? data,
    String contextLabel,
  ) {
    if (data == null) {
      throw FormatException('$contextLabel response body is empty');
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw FormatException('$contextLabel response is not a JSON object');
    }

    if (data is List<int>) {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw FormatException('$contextLabel response is not a JSON object');
    }

    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }

    throw FormatException('$contextLabel response body has unsupported shape');
  }

  static Map<String, dynamic> _asStringKeyedMap(
    Object? value,
    String contextLabel,
  ) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    throw FormatException('$contextLabel is not a JSON object');
  }

  /// 검색어로 종목 후보를 조회.
  /// ac.stock.naver.com/ac 엔드포인트 사용.
  @override
  Future<List<NaverAutocompleteItemDto>> searchStocks(String query) async {
    final response = await _dio.get<dynamic>(
      'https://ac.stock.naver.com/ac',
      queryParameters: {
        'q': query,
        'target': 'stock,ipo,index,marketindicator',
      },
      options: Options(
        headers: _defaultHeaders,
        responseType: ResponseType.plain,
      ),
    );

    final data = _decodeJsonObjectBody(response.data, 'searchStocks');
    final items = data['items'] as List<dynamic>? ?? [];

    return items
        .map((e) => NaverAutocompleteItemDto.fromJson(
            _asStringKeyedMap(e, 'searchStocks item')))
        .toList();
  }

  /// 실시간 시세 조회. 여러 종목을 한 번에 요청 가능.
  ///
  /// 구현 방식:
  /// - query 파라미터에 "SERVICE_ITEM:005930,000660" 형식으로 종목 코드 전달
  /// - 응답의 result.areas[].datas[] 구조에서 각 종목 데이터 추출
  /// - symbol을 key로 하는 Map 반환하여 빠른 조회 지원
  @override
  Future<Map<String, NaverRealtimeQuoteDto>> fetchRealtimeQuotes(
    Iterable<String> symbols,
  ) async {
    final uniqueSymbols = symbols.toSet().toList();
    if (uniqueSymbols.isEmpty) {
      return {};
    }

    final queryPayload = 'SERVICE_ITEM:${uniqueSymbols.join(',')}';

    final response = await _dio.get<dynamic>(
      'https://polling.finance.naver.com/api/realtime',
      queryParameters: {'query': queryPayload},
      options: Options(
        headers: _defaultHeaders,
        responseType: ResponseType.plain,
      ),
    );

    final data = _decodeJsonObjectBody(response.data, 'fetchRealtimeQuotes');
    final result = <String, NaverRealtimeQuoteDto>{};

    final resultMap = data['result'] as Map<String, dynamic>?;
    if (resultMap == null) return result;

    final areas = resultMap['areas'] as List<dynamic>?;
    if (areas == null || areas.isEmpty) return result;

    for (final area in areas) {
      final areaMap = _asStringKeyedMap(area, 'fetchRealtimeQuotes area');
      final datas = areaMap['datas'] as List<dynamic>?;
      if (datas == null) continue;

      for (final row in datas) {
        final rowMap = _asStringKeyedMap(row, 'fetchRealtimeQuotes row');
        final quote = NaverRealtimeQuoteDto.fromJson(rowMap);
        result[quote.symbol] = quote;
      }
    }

    return result;
  }

  /// 종목 메타데이터(이름, 거래소명) 조회.
  @override
  Future<NaverChartMetadataDto> fetchChartMetadata(String symbol) async {
    final response = await _dio.get<dynamic>(
      'https://stock.naver.com/api/securityFe/api/fchart/domestic/stock/$symbol',
      options: Options(
        headers: _defaultHeaders,
        responseType: ResponseType.plain,
      ),
    );

    final data = _decodeJsonObjectBody(response.data, 'fetchChartMetadata');
    return NaverChartMetadataDto.fromJson(data);
  }

  /// 일별 시세 HTML 페이지 파싱.
  ///
  /// 파싱 규칙:
  /// - HTML은 EUC-KR 인코딩이므로 latin1로 디코딩 (호환됨)
  /// - <tr onMouseOver=...> 패턴으로 데이터 행 식별
  /// - 각 행에서 날짜(YYYY.MM.DD)와 숫자값(종가, 시가, 고가, 저가, 거래량) 추출
  /// - <span class="tah..."> 태그 내 숫자만 추출, 전일비(index 1)는 건너뜀
  /// - lastPage는 페이지네이션 링크에서 최대값 추출
  ///
  /// 주의: 테이블 숫자 순서는 [종가, 전일비, 시가, 고가, 저가, 거래량]
  @override
  Future<NaverDailyHistoryPageDto> fetchDailyHistoryPage({
    required String symbol,
    required int page,
  }) async {
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'must be >= 1');
    }

    final response = await _dio.get<List<int>>(
      'https://finance.naver.com/item/sise_day.naver',
      queryParameters: {
        'code': symbol,
        'page': page,
      },
      options: Options(
        headers: _defaultHeaders,
        responseType: ResponseType.bytes,
      ),
    );

    // EUC-KR 인코딩 HTML을 latin1로 디코딩 (ASCII 확장 호환)
    final html = latin1.decode(response.data ?? []);

    final priceInfos = <NaverHistoricalPriceDto>[];

    // 데이터 행 패턴: onMouseOver 속성을 가진 tr 태그
    final rowPattern = RegExp(
      r'<tr\s+onMouseOver[^>]*>.*?</tr>',
      multiLine: true,
      dotAll: true,
    );

    for (final rowMatch in rowPattern.allMatches(html)) {
      final row = rowMatch.group(0) ?? '';

      // 날짜 추출: >YYYY.MM.DD< 패턴
      final dateMatch = RegExp(r'>(\d{4})\.(\d{2})\.(\d{2})<').firstMatch(row);
      if (dateMatch == null) continue;

      final localDateStr =
          '${dateMatch.group(1)}${dateMatch.group(2)}${dateMatch.group(3)}';

      // 숫자값 추출: <span class="tah...">숫자</span> 패턴
      // 숫자 주변 공백 허용 (\s*)
      final numberPattern =
          RegExp(r'<span[^>]*class="tah[^"]*"[^>]*>\s*([0-9,]+)\s*</span>');
      final numbers = numberPattern
          .allMatches(row)
          .map((m) => m.group(1) ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      // 최소 6개 값 필요: 종가, 전일비, 시가, 고가, 저가, 거래량
      if (numbers.length < 6) continue;

      try {
        priceInfos.add(NaverHistoricalPriceDto.fromJson({
          'localDate': localDateStr,
          'closePrice': _parseDouble(numbers[0]),
          // numbers[1]은 전일비 - 사용하지 않음
          'openPrice': _parseDouble(numbers[2]),
          'highPrice': _parseDouble(numbers[3]),
          'lowPrice': _parseDouble(numbers[4]),
          'accumulatedTradingVolume': _parseInt(numbers[5]),
        }));
      } catch (_) {
        continue;
      }
    }

    // 페이지네이션에서 lastPage 추출
    int lastPage = page;
    final pagePattern = RegExp(r'page=(\d+)');
    for (final match in pagePattern.allMatches(html)) {
      final pageNum = int.tryParse(match.group(1) ?? '');
      if (pageNum != null && pageNum > lastPage) {
        lastPage = pageNum;
      }
    }

    return NaverDailyHistoryPageDto(
      symbol: symbol,
      page: page,
      lastPage: lastPage,
      priceInfos: priceInfos,
    );
  }
}

double _parseDouble(String value) {
  return double.parse(value.replaceAll(',', ''));
}

int _parseInt(String value) {
  return int.parse(value.replaceAll(',', ''));
}

Map<String, String> naverDesktopLikeHeaders() =>
    Map<String, String>.unmodifiable(NaverDomesticStockClient._defaultHeaders);
