# Flutter 과제 체크리스트

## 진행 상태

| 영역 | 항목 | 상태 | 비고 |
|------|------|------|------|
| **1. 데이터 연동** | | | |
| | DTO fromJson 구현 | ✅ | naver_stock_dtos.dart |
| | 검색 API 호출 | ✅ | naver_domestic_stock_client.dart |
| | Realtime API 호출 | ✅ | naver_domestic_stock_client.dart |
| | 메타데이터 API 호출 | ✅ | naver_domestic_stock_client.dart |
| | 일별 시세 HTML 파싱 | ✅ | naver_domestic_stock_client.dart |
| | Repository 검색 결과 변환 | ✅ | naver_watchlist_repository.dart |
| | Repository 관심종목 목록 구성 | ✅ | naver_watchlist_repository.dart |
| | Repository 거래일 목록 lazy load | ✅ | naver_watchlist_repository.dart |
| | Repository 상세 30거래일 window | ✅ | naver_watchlist_repository.dart |
| **2. UI 구현** | | | |
| | 검색 결과 행 - 2줄 텍스트 | ✅ | search_result_row.dart |
| | 검색 결과 행 - 검색어 하이라이트 | ✅ | search_result_row.dart |
| | 검색 결과 행 - 하트 버튼 (Figma 크기) | ✅ | search_result_row.dart - 20x20 slot |
| | 검색 결과 행 - 선택 시 액션 버튼 | ✅ | search_result_row.dart |
| | 검색 토스트 - blur 효과 | ✅ | search_toast.dart - sigmaX/Y: 10 |
| | 검색 토스트 - 배경/보더/그림자 | ✅ | search_toast.dart - Figma 스펙 반영 |
| | 검색 토스트 - 하트+체크 아이콘 조합 | ✅ | search_toast.dart |
| | 날짜 바텀시트 - 연/월/일 선택 영역 | ✅ | watchlist_date_bottom_sheet.dart |
| | 날짜 바텀시트 - 선택 상태 스타일 | ✅ | watchlist_date_bottom_sheet.dart |
| | 날짜 바텀시트 - 취소/확인 버튼 | ✅ | watchlist_date_bottom_sheet.dart |
| | 날짜 변경 후 목록/상세 동기화 | ✅ | watchlist_screen.dart |
| **3. 상태 동기화** | | | |
| | 즐겨찾기 변경 → 검색 결과 하트 반영 | ✅ | search_controller.dart |
| | 검색 직후 즐겨찾기 상태 반영 | ✅ | search_controller.dart |
| | 즐겨찾기 추가 시 토스트 표시 | ✅ | search_controller.dart |
| | 즐겨찾기 제거 시 토스트 숨김 | ✅ | search_controller.dart |
| **4. 검증** | | | |
| | flutter analyze 통과 | ✅ | No issues found |
| | flutter test 전체 통과 | ✅ | 53 tests passed |
| | TODO(assignment) 주석 제거 | ✅ | 전체 검색 완료 |
| | 구현 주석/메모 추가 | ✅ | 주요 파일에 구현 의도 주석 추가 |

---

## 상세 검토 기록

### 1. 데이터 연동

#### 1.1 DTO fromJson 구현
- **파일**: `lib/features/watchlist/data/dtos/naver_stock_dtos.dart`
- **테스트**: `test/features/watchlist/data/naver_stock_dtos_test.dart`
- **상태**: ✅ 완료
- **검토 결과**:
  - NaverSearchResultDto, NaverRealtimeQuoteDto, NaverStockMetaDto 등 모든 DTO에 fromJson 구현
  - nullable 필드 처리 및 기본값 설정 완료

#### 1.2 Client API 구현
- **파일**: `lib/features/watchlist/data/clients/naver_domestic_stock_client.dart`
- **상태**: ✅ 완료
- **검토 결과**:
  - searchStocks: 검색 API 구현
  - fetchRealtimeBatch: 실시간 시세 batch API 구현
  - fetchMeta: 메타데이터 API 구현
  - fetchDailyHistory: 일별 시세 HTML 파싱 구현

#### 1.3 Repository 구현
- **파일**: `lib/features/watchlist/data/repositories/naver_watchlist_repository.dart`
- **테스트**: `test/features/watchlist/data/naver_watchlist_repository_test.dart`
- **상태**: ✅ 완료
- **검토 결과**:
  - searchStocks: 검색 결과 → StockSearchItem 변환
  - getWatchlist: 관심종목 목록 구성 (realtimeBatch + meta 조합)
  - fetchAvailableDates: 거래일 목록 lazy load
  - getDetail: 30거래일 window 기반 상세 정보

---

### 2. UI 구현

#### 2.1 검색 결과 행
- **파일**: `lib/features/search/presentation/widgets/search_result_row.dart`
- **테스트**: `test/features/search/presentation/search_screen_test.dart`
- **Figma 확인 사항**: 하트 아이콘 slot 크기
- **상태**: ✅ 완료
- **검토 결과**:
  - 2줄 텍스트 (종목명 + 코드/시장) 구현
  - 검색어 하이라이트 (보라색 #B980FF) 구현
  - 하트 아이콘 20x20 slot (Figma 스펙 일치)
  - 선택 시 액션 버튼 (SearchActionBar) 표시

#### 2.2 검색 토스트
- **파일**: `lib/features/search/presentation/widgets/search_toast.dart`
- **Figma 확인 사항**: blur, 배경, 보더, 그림자, 아이콘 조합
- **상태**: ✅ 완료
- **검토 결과**:
  - blur: sigmaX/Y 10 (Figma 일치)
  - 배경: rgba(37,37,37,0.7) → Color(0xB3252525) (Figma 일치)
  - 보더: rgba(185,128,255,0.2) → Color(0x33B980FF) (Figma 일치 - 보라색 강조)
  - 그림자: 0,2 blur:10 rgba(0,0,0,0.25) (Figma 일치)
  - 하트+체크 아이콘 조합: 20x20 하트 + 10x10 체크 오버레이

#### 2.3 날짜 바텀시트
- **파일**: `lib/features/watchlist/presentation/widgets/watchlist_date_bottom_sheet.dart`
- **테스트**: `test/features/watchlist/presentation/watchlist_date_picker_options_test.dart`
- **상태**: ✅ 완료
- **검토 결과**:
  - 연/월/일 3열 ListWheelScrollView picker
  - 선택 상태: 배경색 변경 (bg_4_333333) + 폰트 스타일 변경
  - 취소/확인 버튼 구현

#### 2.4 날짜 변경 동기화
- **파일**: `lib/features/watchlist/presentation/screens/watchlist_screen.dart`
- **테스트**: `test/features/watchlist/presentation/watchlist_screen_test.dart`
- **상태**: ✅ 완료
- **검토 결과**:
  - _showDateBottomSheet: 날짜 선택 후 watchlistController.setAsOf 호출
  - _syncSelectedDetailWithSnapshot: 목록/상세 동기화

---

### 3. 상태 동기화

#### 3.1 SearchController 동기화
- **파일**: `lib/features/search/presentation/providers/search_controller.dart`
- **테스트**: `test/features/search/presentation/providers/search_controller_test.dart`
- **상태**: ✅ 완료
- **검토 결과**:
  - favoriteIdsController 구독으로 즐겨찾기 변경 감지
  - 검색 결과 즐겨찾기 상태 실시간 반영
  - 즐겨찾기 추가 시 토스트 메시지 설정
  - 즐겨찾기 제거 시 토스트 숨김

---

### 4. Figma 검토

#### Figma URL
- https://www.figma.com/design/Rqy5DLiBraOr7cckAQnC8V/ (복사본)

#### 검토 항목
| 요소 | Figma 스펙 | 현재 구현 | 일치 여부 |
|------|-----------|----------|----------|
| 검색 결과 하트 아이콘 slot | 20x20 | 20x20 | ✅ |
| 토스트 blur | 10px | sigmaX/Y: 10 | ✅ |
| 토스트 배경색 | rgba(37,37,37,0.7) | Color(0xB3252525) | ✅ |
| 토스트 border | rgba(185,128,255,0.2) | Color(0x33B980FF) | ✅ |
| 토스트 shadow | 0,2 blur:10 rgba(0,0,0,0.25) | BoxShadow(0,2,10,0x40000000) | ✅ |
| 토스트 하트 아이콘 | 20x20 | 20x20 | ✅ |
| 토스트 체크 아이콘 | 10x10 | 10x10 | ✅ |

---

### 5. 테스트 결과

#### 5.1 정적 분석
```
실행일시: 2026-06-20
결과: No issues found!
```

#### 5.2 단위 테스트
```
실행일시: 2026-06-20
총 테스트 수: 53
통과: 53
실패: 0
```

#### 5.3 골든 테스트
```
실행일시: 2026-06-20
결과: 모든 골든 테스트 통과 (baseline 업데이트 완료)
업데이트된 파일:
- search_results_selected.png
- search_toast.png
```

---

### 6. 최종 체크

- [x] 모든 TODO(assignment) 주석 제거됨
- [x] 구현 의도 주석 추가됨
- [x] flutter analyze 통과
- [x] flutter test 전체 통과
- [ ] 데모 실행 확인

