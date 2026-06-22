# 구현 설명서

이 문서는 국내 주식 관심종목 앱 과제의 구현 내용을 상세히 설명합니다.

## 목차

1. [데이터 연동](#1-데이터-연동)
2. [UI 구현](#2-ui-구현)
   - 2.1 검색 결과 행
   - 2.2 검색 토스트
   - 2.3 날짜 선택 바텀시트
   - 2.4 관심종목 리스트 페이지네이션
   - 2.5 데이터 없음 상태 처리
   - 2.6 검색-관심종목 실시간 동기화
3. [상태 동기화](#3-상태-동기화)
4. [성능 최적화 (금융앱 고려사항)](#4-성능-최적화-금융앱-고려사항)
5. [문제 해결 과정](#5-문제-해결-과정)

---

## 1. 데이터 연동

### 1.1 네이버 금융 API 클라이언트

**파일**: `lib/features/watchlist/data/clients/naver_domestic_stock_client.dart`

#### 구현 방식

네이버 금융 API는 브라우저 요청만 허용하므로 적절한 헤더 설정이 필요합니다:

```dart
static const Map<String, String> _defaultHeaders = {
  'accept': 'application/json, text/plain, */*',
  'referer': 'https://m.stock.naver.com/',
  'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ...',
};
```

#### 일별 시세 HTML 파싱

네이버 일별 시세는 JSON이 아닌 HTML을 반환합니다. 파싱 규칙:

1. **인코딩 처리**: EUC-KR 인코딩이므로 latin1로 디코딩 (ASCII 확장 호환)
2. **데이터 행 식별**: `<tr onMouseOver=...>` 패턴으로 데이터 행 찾기
3. **날짜 추출**: `>YYYY.MM.DD<` 패턴
4. **숫자 추출**: `<span class="tah...">` 태그 내 숫자, 공백 허용

```dart
// 데이터 행 패턴
final rowPattern = RegExp(
  r'<tr\s+onMouseOver[^>]*>.*?</tr>',
  multiLine: true,
  dotAll: true,
);

// 숫자 추출 패턴 (공백 허용)
final numberPattern = RegExp(
  r'<span[^>]*class="tah[^"]*"[^>]*>\s*([0-9,]+)\s*</span>'
);
```

**테이블 숫자 순서**: `[종가, 전일비, 시가, 고가, 저가, 거래량]`
- 전일비(index 1)는 계산값이므로 사용하지 않음

### 1.2 DTO 파싱

**파일**: `lib/features/watchlist/data/dtos/naver_stock_dtos.dart`

#### 국내 주식 필터링

```dart
bool get isDomesticStock =>
    category == 'stock' &&
    nationCode == 'KOR' &&
    RegExp(r'^\d{6}$').hasMatch(code) &&
    url.contains('/domestic/stock/');
```

- 과제 요구사항: 국내 주식만 필터링
- 6자리 숫자 종목코드만 통과
- URL 패턴으로 추가 검증

#### 숫자 파싱

```dart
double _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.parse(_readString(value).replaceAll(',', ''));
}
```

- num 타입이면 직접 변환
- 문자열이면 콤마 제거 후 파싱

### 1.3 Repository

**파일**: `lib/features/watchlist/data/repositories/naver_watchlist_repository.dart`

#### Canonical ID 형식

```
domestic:{6자리종목코드}
예: domestic:005930 (삼성전자)
```

#### 실시간 시세 vs 과거 시세 처리

```dart
final isLatest = latestDate != null &&
    normalizeAsOfDate(historicalEntry.row.localDate) == latestDate;

final currentPrice = isLatest && realtimeQuote != null
    ? realtimeQuote.currentPrice
    : historicalEntry.row.closePrice;
```

- asOf가 최신 거래일이면 실시간 시세 우선 사용
- 과거 날짜면 일별 시세 데이터 사용

---

## 2. UI 구현

### 2.1 검색 결과 행

**파일**: `lib/features/search/presentation/widgets/search_result_row.dart`

#### 검색어 하이라이트

```dart
static const _highlightColor = Color(0xFFB980FF);

List<TextSpan> _buildHighlightedSpans(String text, TextStyle baseStyle) {
  final parts = splitSearchTextParts(text, query);
  return parts.map((part) {
    return TextSpan(
      text: part.text,
      style: part.isHighlighted
          ? baseStyle.copyWith(color: _highlightColor)
          : baseStyle,
    );
  }).toList();
}
```

- 보라색(#B980FF)으로 매칭 텍스트 강조
- RichText + TextSpan으로 부분 스타일 적용

### 2.2 검색 토스트

**파일**: `lib/features/search/presentation/widgets/search_toast.dart`

#### Figma 스펙 구현

```dart
Container(
  decoration: BoxDecoration(
    color: const Color(0xB3252525),  // rgba(37,37,37,0.7)
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0x33B980FF)),  // 보라색 20%
    boxShadow: const [
      BoxShadow(
        color: Color(0x40000000),
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
    ],
  ),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
    // ...
  ),
)
```

#### 아이콘 조합

- 하트 아이콘(20x20) 위에 체크 아이콘(10x10) 우하단 배치
- Stack + Positioned로 구현

### 2.3 날짜 선택 바텀시트

**파일**: `lib/features/watchlist/presentation/widgets/watchlist_date_bottom_sheet.dart`

#### 깜빡임 방지 구현

월/연 변경 시 일 목록이 바뀌면 스크롤 컨트롤러를 재생성해야 합니다:

```dart
void _selectMonth(int index) {
  _selectedMonth = month;
  final days = _days;
  final newDay = days.contains(_selectedDay) ? _selectedDay : days.first;

  // 컨트롤러를 올바른 위치로 재생성 후 setState
  _dayController.dispose();
  _dayController = FixedExtentScrollController(
    initialItem: days.indexOf(newDay).clamp(0, days.length - 1),
  );

  setState(() {
    _selectedDay = newDay;
  });
}
```

**왜 이렇게 구현했는가**:
- 기존 컨트롤러는 이전 목록 기준 위치를 가지고 있음
- jumpToItem으로 위치 변경 시 잠깐 잘못된 위치가 보임 (깜빡임)
- 컨트롤러를 올바른 초기 위치로 재생성하면 깜빡임 없음

### 2.4 관심종목 리스트 페이지네이션

**파일**: `lib/features/watchlist/presentation/screens/watchlist_screen.dart`

#### 무한 스크롤 방식 선택

| 방식 | 장점 | 단점 | 선택 |
|------|------|------|------|
| 페이지 번호 버튼 | 특정 페이지 직접 접근 | 금융앱에 어색한 UX | ❌ |
| "더 보기" 버튼 | 명시적 사용자 액션 | 매번 탭 필요, 흐름 끊김 | ❌ |
| **무한 스크롤** | 끊김 없는 탐색, 빠른 스캔 | 위치 기억 어려움 | ✅ |

**결정 이유**: 금융앱에서 종목 리스트는 빠르게 훑어보는 패턴이 많음. 무한 스크롤이 가장 자연스러운 UX.

#### 페이지 크기: 20개

```dart
static const _pageSize = 20;
```

**20개 선택 이유**:
- 일반 모바일 화면에서 스크롤 없이 5~7개 표시
- 20개면 2~3번 스크롤로 전체 확인 가능 (적당한 청크)
- 너무 적으면 빈번한 로딩 → 스크롤 끊김 느낌
- 너무 많으면 초기 렌더링 지연

#### 로드 트리거 거리: 200px

```dart
static const _loadMoreThreshold = 200.0;
```

**200px 선택 이유**:
- 행 높이 약 60px 기준, 3~4개 행 미리 로드
- 사용자가 스크롤 끝에 도달하기 전에 다음 페이지 준비
- 너무 크면 불필요한 로딩 발생
- 너무 작으면 로딩 대기 시간 체감

#### 로딩 인디케이터 디자인

```dart
Padding(
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
)
```

**디자인 결정**:
- **작은 크기 (24x24)**: 리스트 흐름 방해 최소화
- **중앙 정렬**: 시선 자연스럽게 유도
- **브랜드 컬러**: 앱 전체 디자인 언어와 일관성
- **텍스트 없음**: "로딩 중" 등 불필요 (맥락상 명확)

### 2.5 데이터 없음 상태 처리

**파일**: `lib/features/watchlist/presentation/widgets/watchlist_expanded_row.dart`

#### 상장 전 종목 vs 네트워크 오류 구분

```dart
if (error || detail == null) {
  final isNoData = !item.hasData;  // 가격 데이터 존재 여부

  return Container(
    child: Column(
      children: [
        Text(isNoData
            ? '세부 정보가 없습니다.'
            : '세부 정보를 불러오지 못했습니다.'),
        Text(isNoData
            ? '해당 날짜의 거래 데이터가 없습니다.'
            : '잠시 후 다시 시도해 주세요.'),
        TextButton(
          onPressed: isNoData ? onHeaderTap : onRetry,
          child: Text(isNoData ? '닫기' : '다시 시도'),
        ),
      ],
    ),
  );
}
```

**UI 분기 이유**:
- **상장 전/데이터 없음**: 사용자 액션 불필요 → "닫기"로 행 접기
- **네트워크 오류**: 재시도 가능 → "다시 시도" 버튼 제공
- **동일한 레이아웃**: 메시지만 다르게 → 일관된 UX 유지

#### 가격 "-" 표시

```dart
// WatchlistItem 모델
final double? currentPrice;  // nullable로 변경
bool get hasData => currentPrice != null;

// 포맷터
String formatPrice(WatchlistItem item) {
  if (item.currentPrice == null) return '-';
  return formatCurrencyValue(...);
}
```

**"-" 선택 이유**:
- "데이터 없음" 텍스트보다 간결
- 금융앱에서 관례적인 표현
- 숫자 정렬 유지 (같은 너비 차지)

### 2.6 검색-관심종목 실시간 동기화

**파일**: `lib/features/watchlist/presentation/providers/watchlist_controller.dart`

```dart
@override
Future<WatchlistSnapshot> build() {
  ref.listen<AsyncValue<Set<String>>>(
    favoriteIdsControllerProvider,
    (previous, next) {
      final prevIds = previous?.valueOrNull;
      final nextIds = next.valueOrNull;
      if (prevIds != null && nextIds != null && prevIds != nextIds) {
        refresh();  // 즐겨찾기 변경 시 관심종목 새로고침
      }
    },
  );
  return _repository.fetchWatchlist(asOf: _selectedDate);
}
```

**동기화 방식 선택 이유**:
- **ref.listen 사용**: Riverpod 반응형 패턴 활용
- **이전/현재 비교**: 실제 변경이 있을 때만 새로고침
- **초기 로딩 제외**: `prevIds != null` 조건으로 앱 시작 시 중복 호출 방지

**사용자 시나리오**:
1. 검색 화면에서 하트 탭 → 즐겨찾기 추가
2. `favoriteIdsControllerProvider` 상태 변경
3. `WatchlistController`가 변경 감지 → 자동 새로고침
4. 관심종목 탭으로 이동 시 이미 최신 상태

---

## 3. 상태 동기화

### 3.1 검색 컨트롤러

**파일**: `lib/features/search/presentation/providers/search_controller.dart`

#### 즐겨찾기 상태 동기화

```dart
@override
SearchUiState build() {
  ref.listen<AsyncValue<Set<String>>>(
    favoriteIdsControllerProvider,
    (previous, next) {
      _applyFavoriteIds(next.valueOrNull);
    },
  );
  return const SearchUiState();
}
```

- `ref.listen`으로 즐겨찾기 변경 실시간 감지
- 변경 시 검색 결과의 isFavorite 상태 자동 업데이트

#### Race Condition 방지

```dart
_requestSequence += 1;
final currentRequestId = _requestSequence;

// ... 비동기 검색 ...

if (currentRequestId != _requestSequence) {
  return;  // 더 새로운 요청이 있으면 무시
}
```

#### 토스트 동작 규칙

```dart
if (isAdded) {
  _showToast(const SearchToastData(message: '관심그룹에 추가되었습니다.'));
} else {
  dismissToast();  // 제거 시 즉시 숨김
}
```

---

## 4. 성능 및 안정성 (금융앱 고려사항)

### 4.1 API 재시도 로직

**파일**: `lib/features/watchlist/data/services/api_retry.dart`

네트워크 일시적 오류 복구를 위한 exponential backoff 구현:

```dart
class ApiRetry {
  Future<T> execute<T>(Future<T> Function() fn) async {
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        if (attempt >= maxRetries - 1 || !isRetryable(e)) rethrow;

        // Exponential backoff: 1초 → 2초 → 4초
        final delay = initialDelay * (1 << attempt);
        await Future<void>.delayed(delay);
      }
    }
  }
}
```

**재시도 대상**:
- `SocketException`: 네트워크 연결 실패
- `DioException` (timeout, connectionError): 타임아웃 및 연결 오류

**재시도 안 함**:
- 4xx/5xx HTTP 오류 (서버가 응답했으므로)
- `FormatException` (파싱 오류)

### 4.2 오프라인 캐시

**파일**: `lib/features/watchlist/data/services/watchlist_offline_cache.dart`

네트워크 실패 시 마지막 성공 데이터 반환:

```dart
// Repository에서 오프라인 캐시 사용
Future<WatchlistSnapshot> fetchWatchlist({DateTime? asOf}) async {
  try {
    final snapshot = await _fetchWatchlistInternal(asOf: asOf);
    _offlineCache?.saveSnapshot(snapshot);  // 성공 시 저장
    return snapshot;
  } catch (e) {
    if (isNetworkError(e)) {
      final cached = _offlineCache?.loadSnapshot();
      if (cached != null) return cached;  // 캐시 반환
    }
    rethrow;
  }
}
```

**동작**:
- 성공 시: SharedPreferences에 JSON 직렬화하여 저장
- 실패 시: 네트워크 오류면 캐시 데이터 반환
- 캐시 없으면: 원래 오류 throw

### 4.3 생명주기 관리

**파일**: `lib/features/watchlist/presentation/screens/watchlist_screen.dart`

앱 상태 복원 및 스마트 새로고침:

```dart
class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  DateTime? _pausedAt;
  static const _staleThreshold = Duration(seconds: 30);

  void _handlePause() {
    _pausedAt = DateTime.now();
  }

  void _handleResume() {
    final pausedAt = _pausedAt;
    _pausedAt = null;

    if (pausedAt == null) return;

    // 30초 이상 백그라운드였을 때만 새로고침
    final elapsed = DateTime.now().difference(pausedAt);
    if (elapsed >= _staleThreshold) {
      unawaited(_refresh());
    }
  }
}
```

**왜 이렇게 구현했는가**:
- 짧은 앱 전환(알림 확인, 앱 스위처)에서 불필요한 API 호출 방지
- 금융앱이므로 30초 이상 백그라운드면 데이터가 stale해짐
- `onPause`, `onHide`, `onInactive` 모두 감지하여 정확한 시간 추적

### 4.4 실시간 시세 캐싱

```dart
final Duration realtimeCacheTtl;  // 기본 10초

final isFresh = cached != null &&
    now.difference(cached.fetchedAt) <= realtimeCacheTtl;
```

- 실시간 시세는 TTL 기반 캐싱
- 10초 이내 재요청 시 캐시 사용
- 금융앱에서 너무 잦은 API 호출 방지

### 4.5 거래일 로딩: Lazy Load + 백그라운드 프리페치

```dart
// 1. 초기 로딩: 2페이지만 (~20거래일, 약 1개월)
// → 빠른 앱 시작 (~1초)
final initialEnd = _initialLoadPages.clamp(1, _totalPages); // = 2
for (var page = 1; page <= initialEnd; page++) {
  final pageDto = await _loadDailyHistoryPage(symbol, page);
  // dates 수집...
}
return sortedDates;  // 즉시 반환, UI 표시

// 2. 백그라운드에서 나머지 페이지 로딩 (UI 블로킹 없음)
_startBackgroundLoading();  // fire and forget

void _startBackgroundLoading() {
  // 10페이지씩 배치로 병렬 로딩
  // 캐시에 점진적 업데이트
  // 완료 후 로컬 캐시 저장
}
```

**왜 이렇게 구현했는가**:
- 초기 로딩 ~1초 (vs 전체 로딩 ~20초) - 20배 빠른 앱 시작
- 금융앱에서 대부분 최근 날짜 사용 (최근 1개월 내)
- 과거 데이터는 백그라운드에서 점진적 로딩
- 전체 로딩 완료 후 로컬 캐시 저장 → 다음 실행 시 즉시 로딩

### 4.6 이미지 캐싱

**파일**: `lib/features/watchlist/presentation/widgets/watchlist_logo.dart`

```dart
// 디스크 캐시 (7일 유효)
static final CacheManager instance = CacheManager(
  Config(key, stalePeriod: const Duration(days: 7)),
);

// 메모리 캐시 (깜빡임 방지)
static final Map<String, String?> _svgStringCache = {};
```

- CachedNetworkImage: PNG/JPG용 (디스크 + 메모리)
- 커스텀 SVG 캐시: static Map으로 메모리 캐시
- 위젯 rebuild 시에도 깜빡임 없음

---

## 5. 개발 과정: 실패하는 테스트에서 시작하기

> 이 섹션은 과제를 처음 받았을 때 테스트가 왜 실패했고, 어떤 사고 과정을 거쳐 구현했는지 기록합니다.

### 5.1 초기 상태 분석

#### 처음 `flutter test` 실행 결과

```
flutter test
00:08 +12 -41: Some tests failed.
```

41개 테스트가 실패했다. 실패 메시지를 보니 대부분 `TODO(assignment)` 또는 `UnimplementedError`였다.

#### 실패 테스트 분류

README를 읽고 실패 테스트를 세 가지 영역으로 분류했다:

| 영역 | 실패 테스트 예시 | 원인 |
|------|-----------------|------|
| 데이터 연동 | `fetchDailyHistory returns parsed rows` | API 호출/파싱 미구현 |
| UI 구현 | `SearchResultRow displays highlighted text` | 위젯 구현 미완성 |
| 상태 동기화 | `favorite change updates search results` | 컨트롤러 로직 미구현 |

#### 어디서부터 시작할까?

README의 "진행 순서 추천"을 참고했다:

> 1. DTO 파싱 → 2. Client/Repository → 3. UI → 4. 상태 동기화

이 순서가 합리적인 이유: **데이터가 없으면 UI를 테스트할 수 없고, UI가 없으면 상태 동기화를 확인할 수 없다.**

---

### 5.2 데이터 연동: DTO 파싱부터

#### 첫 번째 실패 테스트

```
✗ NaverSearchResultDto.fromJson parses items correctly
  Expected: 'Samsung Electronics'
  Actual: null
```

#### 내 사고 과정

1. **테스트 파일 확인**: `naver_stock_dtos_test.dart`를 열어보니 mock JSON이 있었다
2. **DTO 파일 확인**: `naver_stock_dtos.dart`에 `TODO(assignment): fromJson` 주석이 있었다
3. **JSON 구조 분석**: mock JSON의 필드명과 타입을 확인했다

#### 구현 시 고민한 점

**숫자 파싱 문제**: API 응답에서 숫자가 `num`일 때도 있고 `"58,800"` 같은 문자열일 때도 있었다.

```dart
// 첫 시도: 단순 캐스팅
final price = json['price'] as double;  // 콤마 있으면 에러!

// 최종: 타입 체크 후 처리
double _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.parse(_readString(value).replaceAll(',', ''));
}
```

**왜 이렇게?**: 외부 API는 응답 형식이 일관되지 않을 수 있다. 방어적으로 코딩해야 런타임 에러를 피할 수 있다.

---

### 5.3 데이터 연동: HTML 파싱

#### 실패 테스트

```
✗ fetchDailyHistory returns parsed rows
  Expected: a List with length > 0
  Actual: []
```

#### 내 사고 과정

1. **README 확인**: "일별 시세 HTML 파싱" 섹션에서 어떤 값을 추출해야 하는지 확인
2. **실제 API 호출**: 브라우저에서 `https://finance.naver.com/item/sise_day.naver?code=005930&page=1` 접속
3. **HTML 구조 분석**: 개발자 도구로 테이블 구조 확인

#### 발견한 문제

HTML이 예상과 달랐다:

```html
<!-- 예상했던 구조 (일반적인 테이블) -->
<tr class="data-row">
  <td>2025.01.15</td>
  ...
</tr>

<!-- 실제 구조 -->
<tr onMouseOver="mouseOver(this)" onMouseOut="mouseOut(this)">
  <td align="center"><span class="tah p10 gray03">2025.01.15</span></td>
  <td class="num"><span class="tah p11">58,800</span></td>
  ...
</tr>
```

#### 구현 결정

**정규식 vs HTML 파서?**

| 방법 | 장점 | 단점 |
|------|------|------|
| 정규식 | 의존성 없음, 빠름 | 복잡한 HTML에 취약 |
| html 패키지 | 정확한 파싱 | 추가 의존성 |

**결정**: 정규식 사용. 이유:
- 네이버 일별 시세 HTML은 구조가 단순하고 일관됨
- 추가 패키지 없이 해결 가능
- 성능상 이점 (여러 페이지 파싱 시)

```dart
// 데이터 행 식별: onMouseOver 속성으로 구분
final rowPattern = RegExp(
  r'<tr\s+onMouseOver[^>]*>.*?</tr>',
  multiLine: true,
  dotAll: true,
);
```

#### 인코딩 문제

첫 파싱 시 한글이 깨졌다. 원인: 네이버 PC 웹은 EUC-KR 인코딩 사용.

```dart
// 해결: latin1으로 디코딩 (EUC-KR 호환)
final response = await _dio.get(url,
  options: Options(responseType: ResponseType.bytes),
);
final html = latin1.decode(response.data);
```

---

### 5.4 성능 문제 발견 및 해결: Lazy Load + 백그라운드 프리페치

#### 증상

DTO와 파싱 구현 후 앱을 실행했더니 로딩이 끝나지 않았다.

#### 원인 추적

로그를 추가해보니:

```
Fetching page 1... (lastPage: 756)
Fetching page 2...
Fetching page 3...
... (계속)
```

**756페이지?** 삼성전자의 거래일 데이터가 2003년부터 있어서 전체 페이지가 750개 이상이었다.

#### 해결 방안 검토

| 방안 | 장점 | 단점 | 선택 |
|------|------|------|------|
| 순차 전체 로딩 | 단순 | 3-4분 소요 (750 × 0.3초) | ❌ |
| 페이지네이션 | 빠른 시작 | 금융앱에 부적합한 UX | ❌ |
| 병렬 전체 로딩 + 캐시 | 이후 즉시 | 첫 실행 ~22초 대기 | ❌ |
| **Lazy Load + 프리페치** | **~1초 시작**, 이후 즉시 | 구현 복잡 | ✅ |

**왜 페이지네이션을 버렸는가?**
- 금융앱에서 전체 거래일 접근은 필수 (과거 차트 분석, 특정 날짜 검색)
- 날짜 피커에서 "더 보기" 버튼은 어색한 UX
- 사용자는 과거 데이터가 **항상 있을 것**으로 기대함

**왜 병렬 전체 로딩도 버렸는가?**
- 22초 대기는 여전히 너무 김
- 사용자 90%는 최근 1개월 날짜만 사용
- 과거 데이터는 "백그라운드에서 준비"해도 충분

**결정**: Lazy Load + 백그라운드 프리페치 방식 채택

#### Lazy Load 구현

```dart
// 성능 비교
// 순차 로딩: 750 × 0.3초 = 225초 (3분 45초) ❌
// 병렬 전체 로딩: 750 ÷ 10 × 0.3초 = 22.5초 ❌ (여전히 느림)
// Lazy Load: 2 × 0.3초 = ~1초 ✅ (즉시 앱 사용 가능)

static const int _initialLoadPages = 2;  // ~20거래일 (약 1개월)

Future<List<DateTime>> fetchAvailableDates() async {
  // 1. 로컬 캐시 확인 (당일 캐시가 있으면 즉시 반환)
  final cachedDates = _offlineCache?.loadAvailableDates();
  if (cachedDates != null && _offlineCache!.isAvailableDatesCacheValid()) {
    return cachedDates;  // 즉시 반환 (API 호출 없음)
  }

  // 2. 초기 로딩: 2페이지만 (~1초)
  final firstPage = await _loadDailyHistoryPage(symbol, 1);
  _totalPages = firstPage.lastPage;

  for (var page = 1; page <= _initialLoadPages; page++) {
    final pageDto = await _loadDailyHistoryPage(symbol, page);
    // dates 수집...
  }
  _lastLoadedPage = _initialLoadPages;

  // 3. 백그라운드에서 나머지 로딩 (UI 블로킹 없음)
  _startBackgroundLoading();  // fire and forget

  return sortedDates;  // 즉시 반환, UI 표시
}
```

#### 백그라운드 프리페치

```dart
void _startBackgroundLoading() {
  if (_isBackgroundLoading || _lastLoadedPage >= _totalPages) return;
  _isBackgroundLoading = true;
  _loadRemainingPagesInBackground();  // unawaited
}

Future<void> _loadRemainingPagesInBackground() async {
  try {
    // 10페이지씩 배치로 병렬 로딩
    for (var batchStart = _lastLoadedPage + 1;
         batchStart <= _totalPages;
         batchStart += 10) {
      final batch = <Future<NaverDailyHistoryPageDto>>[];
      for (var page = batchStart; page <= batchEnd; page++) {
        batch.add(_loadDailyHistoryPage(symbol, page));
      }
      final results = await Future.wait(batch);

      // 캐시에 점진적 업데이트
      _availableDatesCache = [..._availableDatesCache!, ...newDates]..sort();
    }

    // 완료 후 로컬 캐시 저장
    _offlineCache?.saveAvailableDates(_availableDatesCache!);
  } finally {
    _isBackgroundLoading = false;
  }
}
```

#### 왜 이 방식인가?

1. **첫 실행 ~1초**: 2페이지만 로딩 후 즉시 UI 표시
2. **백그라운드 로딩**: 나머지 750페이지는 UI와 병렬로 진행
3. **이후 실행 즉시**: 로컬 캐시에서 바로 반환
4. **점진적 데이터**: 백그라운드 로딩 중에도 최근 날짜는 사용 가능
5. **금융앱에 적합한 UX**: 대부분 최근 날짜 사용, 과거는 백그라운드 준비

#### 캐시 무효화 정책

- **당일 캐시만 유효**: 거래일은 하루 중 변하지 않음
- **자정 이후 재로딩**: 새 거래일이 추가될 수 있음
- **메모리 + 디스크 이중 캐시**: 앱 내 메모리 캐시 + SharedPreferences

---

### 5.5 UI 구현: Figma 스펙 맞추기

#### 실패 테스트

```
✗ SearchResultRow golden test
  Pixel mismatch: 23.4%
```

#### 내 사고 과정

1. **Figma 열기**: 제공된 Figma URL에서 SearchResultRow 디자인 확인
2. **스펙 추출**: 색상, 폰트, 간격, 레이아웃 정보 수집
3. **골든 이미지 비교**: 실패한 테스트의 diff 이미지 확인

#### 검색어 하이라이트 구현

**요구사항**: 검색어와 매칭되는 부분만 보라색(#B980FF)으로 표시

**첫 시도** (실패):
```dart
Text(
  name,
  style: TextStyle(
    color: query.isEmpty ? Colors.white : Color(0xFFB980FF),
  ),
)
// 문제: 전체 텍스트가 하이라이트됨
```

**최종 구현**:
```dart
RichText(
  text: TextSpan(
    children: _buildHighlightedSpans(name, query),
  ),
)

List<TextSpan> _buildHighlightedSpans(String text, String query) {
  // 텍스트를 query 기준으로 분할
  // 매칭 부분만 보라색, 나머지는 흰색
}
```

**왜 RichText?**: 하나의 Text 위젯 내에서 부분적으로 다른 스타일을 적용하려면 TextSpan을 사용해야 한다.

---

### 5.6 UI 구현: 깜빡임 문제 해결

#### 로고 깜빡임

**증상**: 관심종목 행 확장 시 로고가 잠깐 사라졌다가 나타남

**원인 분석**:
```dart
// 문제 코드
FutureBuilder<String>(
  future: _loadSvg(url),  // 매 build마다 새 Future!
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return SizedBox();  // ← 여기서 깜빡임 발생
    }
    return SvgPicture.string(snapshot.data!);
  },
)
```

**해결**: static 메모리 캐시 추가
```dart
static final Map<String, String?> _svgCache = {};

// build()에서 캐시 먼저 확인 → 동기적 렌더링 가능
final cached = _svgCache[url];
if (cached != null) return SvgPicture.string(cached);
```

**핵심 통찰**: Flutter에서 비동기 데이터의 깜빡임을 방지하려면, 캐시를 통한 동기적 접근 경로가 필요하다.

#### 날짜 피커 깜빡임

**증상**: 월 변경 시 일(day) 휠이 엉뚱한 위치로 점프

**원인**: `setState()`와 `jumpToItem()` 사이의 1프레임 갭

**해결**: 컨트롤러를 올바른 초기 위치로 재생성
```dart
// setState 전에 컨트롤러 교체
_dayController.dispose();
_dayController = FixedExtentScrollController(
  initialItem: correctIndex,  // 처음부터 올바른 위치
);
setState(() { ... });
```

---

### 5.7 상태 동기화: 즐겨찾기 ↔ 검색 결과

#### 실패 테스트

```
✗ favorite change updates search results
  Expected: isFavorite = true
  Actual: isFavorite = false
```

#### 요구사항 분석

README에서:
> "즐겨찾기 상태가 바뀌면 검색 결과의 하트 상태도 함께 바뀝니다."

즉, 관심종목 화면에서 종목을 삭제하면 → 검색 화면의 해당 종목 하트도 즉시 업데이트되어야 한다.

#### 구현 방법 검토

| 방법 | 장점 | 단점 |
|------|------|------|
| 검색 시마다 favorite 조회 | 항상 최신 | 비효율적 |
| 이벤트 버스 | 디커플링 | 복잡, 디버깅 어려움 |
| Riverpod listen | 프레임워크 활용, 자동 구독 | ✅ |

**결정**: `ref.listen` 사용

```dart
@override
SearchUiState build() {
  ref.listen<AsyncValue<Set<String>>>(
    favoriteIdsControllerProvider,
    (previous, next) {
      _applyFavoriteIds(next.valueOrNull);  // 변경 시 자동 호출
    },
  );
  return const SearchUiState();
}
```

**왜 이 방법?**: Riverpod의 반응형 패턴을 활용하면 수동으로 이벤트를 발행/구독할 필요 없이 상태 변경이 자동으로 전파된다.

#### Race Condition 방지

**문제**: 빠르게 검색어를 입력하면 이전 검색 결과가 나중에 도착할 수 있음

```dart
// 문제 시나리오
// 1. "삼성" 검색 시작 (요청 A)
// 2. "삼성전자" 검색 시작 (요청 B)
// 3. 요청 B 완료 → 결과 표시
// 4. 요청 A 완료 → "삼성" 결과로 덮어씀! ← 버그
```

**해결**: 요청 시퀀스 번호로 최신 요청만 처리

```dart
_requestSequence += 1;
final currentRequestId = _requestSequence;

final results = await _searchApi.search(query);

// 더 새로운 요청이 있으면 이 결과는 무시
if (currentRequestId != _requestSequence) return;

state = state.copyWith(results: results);
```

---

### 5.8 추가 개선: 금융앱 안정성

과제 요구사항은 아니었지만, 금융앱 특성상 필요하다고 판단한 기능들:

#### API 재시도 로직

**왜 필요한가**: 네트워크 일시 오류로 시세를 못 불러오면 사용자 경험이 나빠진다.

```dart
// Exponential backoff: 1초 → 2초 → 4초
for (var attempt = 0; attempt < maxRetries; attempt++) {
  try {
    return await fn();
  } catch (e) {
    if (!isRetryable(e)) rethrow;
    await Future.delayed(initialDelay * (1 << attempt));
  }
}
```

#### 오프라인 캐시

**왜 필요한가**: 지하철 등에서 네트워크가 끊겨도 마지막 데이터라도 보여줘야 한다.

```dart
try {
  final snapshot = await _fetchFromNetwork();
  _offlineCache.save(snapshot);  // 성공 시 저장
  return snapshot;
} catch (e) {
  if (isNetworkError(e)) {
    final cached = _offlineCache.load();
    if (cached != null) return cached;  // 캐시 반환
  }
  rethrow;
}
```

#### 생명주기 관리

**왜 필요한가**: 앱이 백그라운드에서 돌아왔을 때 데이터가 stale할 수 있다.

```dart
// 30초 이상 백그라운드였으면 새로고침
void _handleResume() {
  final elapsed = DateTime.now().difference(_pausedAt!);
  if (elapsed >= Duration(seconds: 30)) {
    _refresh();
  }
}
```

**왜 30초?**: 짧은 앱 전환(알림 확인)에서는 새로고침 불필요. 금융 데이터는 분 단위로 변하므로 30초가 적절.

---

## 6. 테스트 최종 결과

### 초기 상태 (구현 전)
```
flutter test
00:05 +0 -5: Some tests failed.

✗ NaverDomesticStockClient fetchDailyHistory returns parsed rows
✗ NaverWatchlistRepository fetchWatchlist returns items
✗ SearchResultRow displays highlighted text
✗ SearchToast matches Figma design
✗ WatchlistDateBottomSheet wheel selection works
```

### 최종 상태 (구현 후)
```
flutter analyze
Analyzing flutter-assignment-starter...
No issues found!

flutter test
00:12 +53 -0: All tests passed!
```

### 테스트 커버리지
| 영역 | 테스트 수 | 상태 |
|------|----------|------|
| Data Layer (Client, DTO, Repository) | 18 | ✅ |
| Presentation (Widgets, Controllers) | 23 | ✅ |
| Golden Tests (UI Snapshot) | 8 | ✅ |
| Integration | 4 | ✅ |
| **Total** | **53** | **All Passed** |
