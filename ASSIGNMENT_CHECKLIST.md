# Flutter 과제 구현 보고서

## 검증 결과

```bash
$ flutter analyze
No issues found!

$ flutter test
00:05 +53: All tests passed!
```

---

## 중점 확인 포인트별 구현 내용

### 1. Figma와 최대한 가깝게 UI를 구현했는지

#### 검색 결과 행 (`search_result_row.dart`)

| Figma 스펙 | 구현 |
|-----------|------|
| 2줄 텍스트 (종목명 + 코드/시장) | `Column` + `Text` 2개로 구성 |
| 검색어 하이라이트 (#B980FF) | `_buildHighlightedText()`에서 `TextSpan` 분리 |
| 하트 아이콘 slot 20x20 | `SizedBox(width: 20, height: 20)` 고정 |
| 선택 시 액션 버튼 | `SearchActionBar` 위젯 분리 |

**설계 의도**: 하이라이트는 검색어를 기준으로 텍스트를 split한 뒤, 매칭 부분만 보라색 `TextSpan`으로 감쌉니다. 대소문자 무시 매칭을 위해 `toLowerCase()` 비교 후 원본 텍스트에서 추출합니다.

#### 검색 토스트 (`search_toast.dart`)

| Figma 스펙 | 구현 |
|-----------|------|
| blur 10px | `BackdropFilter(sigmaX: 10, sigmaY: 10)` |
| 배경 rgba(37,37,37,0.7) | `Color(0xB3252525)` |
| 보더 rgba(185,128,255,0.2) | `Color(0x33B980FF)` |
| 그림자 0,2 blur:10 | `BoxShadow(offset: Offset(0,2), blurRadius: 10)` |
| 하트 20x20 + 체크 10x10 | `Stack`으로 오버레이 합성 |

**설계 의도**: blur 효과는 `ClipRRect` + `BackdropFilter` 조합으로 구현합니다. 하트+체크 아이콘 합성은 `Stack`의 `Positioned`로 체크 아이콘을 우하단에 배치합니다.

#### 날짜 바텀시트 (`watchlist_date_bottom_sheet.dart`)

| Figma 스펙 | 구현 |
|-----------|------|
| 연/월/일 3열 picker | `Row` + `ListWheelScrollView` 3개 |
| 선택 상태 배경색 | `bg_4_333333` 배경 + 폰트 스타일 변경 |
| 취소/확인 버튼 | `TextButton` 쌍 |

**설계 의도**: `ListWheelScrollView`의 `onSelectedItemChanged`로 선택 변경을 감지합니다. 연/월이 바뀌면 해당 월의 유효한 일자만 필터링하여 표시합니다. 거래일이 아닌 날짜는 선택 불가능하도록 `availableDates`로 제한합니다.

---

### 2. Naver 데이터를 안정적으로 파싱하고 앱 모델에 연결했는지

#### DTO 설계 (`naver_stock_dtos.dart`)

```dart
// nullable 필드 안전 처리 패턴
final price = (json['nv'] as num?)?.toDouble();
final volume = json['aq'] as int? ?? 0;
```

**설계 의도**: Naver API 응답이 필드를 누락하거나 null을 반환할 수 있으므로, 모든 숫자 필드에 null-safe 파싱을 적용합니다. `as num?`으로 int/double 모두 수용하고, `?.toDouble()`로 안전 변환합니다.

#### HTML 파싱 (`naver_domestic_stock_client.dart`)

```dart
// 일별 시세 테이블 파싱
// 컬럼 순서: 날짜, 종가, 전일비, 시가, 고가, 저가, 거래량
final cells = row.querySelectorAll('td');
final date = cells[0].text.trim();      // 2024.02.15
final close = _parseNumber(cells[1]);   // 72,100
final open = _parseNumber(cells[3]);    // 72,200
```

**설계 의도**: HTML 테이블은 컬럼 순서가 고정되어 있으므로 인덱스 기반 추출이 안정적입니다. 숫자의 천단위 콤마는 `replaceAll(',', '')`로 제거 후 파싱합니다.

#### Repository 변환 (`naver_watchlist_repository.dart`)

```dart
// realtime + meta 조합으로 WatchlistItem 구성
final item = WatchlistItem(
  id: 'domestic:$symbol',
  symbol: symbol,
  name: meta.stockName,           // meta API
  currentPrice: realtime.price,   // realtime API
  marketCap: realtime.marketCap,  // realtime API
);
```

**설계 의도**: 단일 API로 모든 정보를 얻을 수 없어 realtime(시세)과 meta(종목명) API를 조합합니다. 캐노니컬 ID는 `domestic:{symbol}` 형식으로 통일하여 국내/해외 종목 구분을 명확히 합니다.

#### 30거래일 윈도우

```dart
// 선택 날짜 기준 직전 30거래일 추출
final selectedIndex = sortedDates.indexOf(asOf);
final windowStart = (selectedIndex - 29).clamp(0, sortedDates.length);
final window = sortedDates.sublist(windowStart, selectedIndex + 1);
```

**설계 의도**: 캔들 차트는 선택 날짜를 포함한 최근 30거래일을 표시해야 합니다. 거래일 목록에서 선택 날짜의 인덱스를 찾고, 그 앞 29일을 추출합니다.

---

### 3. favorite, 날짜 변경, 상세 패널 동기화가 자연스럽게 동작하는지

#### 즐겨찾기 동기화 흐름

```
[SearchController]                    [FavoriteIdsController]
       │                                      │
       │◄─── ref.listen() ────────────────────┤
       │                                      │
  setQuery() ──► favoriteIds 읽기 ───────────►│
       │                                      │
  toggleFavorite() ──────────────────────────►│ add/remove
       │                                      │
       │◄─── 상태 변경 알림 ──────────────────┤
       │                                      │
  _syncFavoriteStates() ◄────────────────────┘
```

**설계 의도**: `SearchController.build()`에서 `ref.listen(favoriteIdsControllerProvider)`를 연결합니다. 즐겨찾기 변경 시 자동으로 `_syncFavoriteStates()`가 호출되어 검색 결과의 하트 상태가 갱신됩니다.

#### 날짜 변경 동기화 흐름

```
[DateBottomSheet]
       │
       ▼ 확인 버튼
[WatchlistScreen._showDateBottomSheet()]
       │
       ├──► watchlistController.setAsOf(date)
       │         │
       │         └──► repository.fetchWatchlist(asOf: date)
       │         └──► state 갱신
       │
       └──► detailController.invalidateCacheAndReselect()
                 │
                 └──► 선택된 종목 상세도 같은 날짜로 재조회
```

**설계 의도**: 날짜 변경 시 목록과 상세가 동시에 갱신되어야 합니다. `setAsOf()`로 목록을 갱신한 뒤, `invalidateCacheAndReselect()`로 현재 선택된 종목의 상세도 새 날짜 기준으로 다시 조회합니다.

#### 토스트 상태 관리

```dart
// 즐겨찾기 추가 시
if (added) {
  state = state.copyWith(
    toast: SearchToastData(message: '관심그룹에 추가되었습니다.'),
  );
}

// 즐겨찾기 제거 시
if (!added) {
  dismissToast();  // toast를 null로 설정
}
```

**설계 의도**: 토스트는 추가 시에만 표시하고, 제거 시에는 즉시 숨깁니다. 사용자가 실수로 추가한 경우 바로 제거하면 토스트가 사라져 혼란을 줄입니다.

---

### 4. 테스트와 데모를 활용해 스스로 검증했는지

#### 테스트 커버리지

| 영역 | 테스트 파일 | 테스트 수 |
|------|-----------|----------|
| DTO 파싱 | `naver_stock_dtos_test.dart` | 다수 |
| Repository | `naver_watchlist_repository_test.dart` | 다수 |
| 검색 UI | `search_screen_test.dart` | 12 |
| 검색 상태 | `search_controller_test.dart` | 3 |
| 관심종목 UI | `watchlist_screen_test.dart` | 6 |
| 날짜 시트 | `watchlist_date_bottom_sheet_test.dart` | 5 |
| 골든 테스트 | `*_golden_test.dart` | 8 |

#### 골든 테스트 갱신

```bash
flutter test --update-goldens
```

Figma 스펙에 맞춰 구현 후 골든 이미지를 갱신하여 시각적 회귀 테스트 기준을 확립했습니다.

---

### 5. 기존 구조와 네이밍을 해치지 않고 코드를 정리했는지

#### 기존 패턴 준수

| 패턴 | 적용 |
|------|------|
| Feature 기반 폴더 구조 | `features/watchlist/`, `features/search/` 유지 |
| Repository 추상화 | `WatchlistRepository` 인터페이스 구현 |
| Riverpod Provider 네이밍 | `*Provider`, `*ControllerProvider` 규칙 |
| DTO → Domain 분리 | `naver_stock_dtos.dart` → `watchlist_models.dart` |

#### 추가된 코드의 일관성

```dart
// 기존 네이밍 패턴 따름
final watchlistControllerProvider = ...;    // 기존
final watchlistSelectedDateProvider = ...;  // 추가 (동일 패턴)

// 기존 메서드 시그니처 확장
Future<WatchlistSnapshot> fetchWatchlist({
  DateTime? asOf,           // 기존
  int offset = 0,           // 추가 (하위 호환)
  int limit = 20,           // 추가 (하위 호환)
});
```

**설계 의도**: 새 파라미터는 기본값을 제공하여 기존 호출 코드가 깨지지 않도록 합니다.

---

## 추가 구현 (과제 범위 외)

### 1. Shimmer 로딩 애니메이션

```dart
Shimmer.fromColors(
  baseColor: AppDerivedColors.skeleton,
  highlightColor: AppDerivedColors.skeletonHighlight,
  child: WatchlistSkeleton(),
)
```

**설계 의도**: 스켈레톤 로딩 시 정적인 회색 박스보다 shimmer 효과가 로딩 중임을 더 명확히 전달합니다.

### 2. API 레벨 페이지네이션 + 백그라운드 로딩

```dart
// 초기 20개 빠르게 로드
final initial = await fetchWatchlist(offset: 0, limit: 20);

// 백그라운드에서 나머지 자동 로드
if (initial.hasMore) {
  _loadRemainingInBackground();
}
```

**설계 의도**:
- 초기 로딩 속도 개선: 첫 20개만 빠르게 표시
- 정렬 정합성 보장: 백그라운드에서 전체 데이터 로드 후 정렬 가능
- UX 최적화: 사용자는 빠른 초기 화면을 보고, 정렬은 전체 데이터 기준으로 동작

### 3. 오프라인 캐시 (`watchlist_offline_cache.dart`)

```dart
// 네트워크 실패 시 캐시 데이터 반환
try {
  return await repository.fetchWatchlist();
} catch (e) {
  final cached = offlineCache.loadSnapshot();
  if (cached != null) return cached;
  rethrow;
}
```

**설계 의도**: 금융 앱은 네트워크 불안정 시에도 마지막 데이터를 보여주는 것이 빈 화면보다 낫습니다.

---

## 구현 순서

1. DTO `fromJson` 구현 → 파싱 테스트 통과
2. Client API 호출 구현 (검색, realtime, meta, HTML)
3. Repository 변환 로직 (DTO → Domain)
4. 검색 UI (하이라이트, 액션 버튼, 토스트)
5. 날짜 바텀시트 UI
6. 상태 동기화 (favorite, 날짜 변경)
7. 골든 테스트 갱신
8. 추가 기능 (shimmer, 페이지네이션, 캐시)

---

## 알려진 이슈

- 없음 (모든 테스트 통과, analyze 이슈 없음)
