import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../watchlist/data/providers/watchlist_repository_provider.dart';
import '../../../watchlist/domain/models/watchlist_models.dart';
import '../../../watchlist/domain/repositories/watchlist_repository.dart';
import '../../../watchlist/presentation/providers/favorite_ids_controller.dart';

final searchControllerProvider =
    NotifierProvider<SearchController, SearchUiState>(SearchController.new);

/// 검색 화면 상태 관리 컨트롤러.
///
/// 상태 동기화 구현:
/// - favoriteIdsControllerProvider를 listen하여 즐겨찾기 변경 감지
/// - 검색 결과의 isFavorite 상태를 실시간으로 동기화
/// - 토스트 표시/숨김 자동 관리 (추가 시 표시, 제거 시 숨김)
///
/// 검색 요청 처리:
/// - _requestSequence로 race condition 방지
/// - 이전 요청 완료 전 새 요청 시 이전 결과 무시
/// - 빈 검색어 시 즉시 결과 초기화
class SearchController extends Notifier<SearchUiState> {
  WatchlistRepository get _repository => ref.read(watchlistRepositoryProvider);

  Timer? _toastTimer;
  int _requestSequence = 0;

  @override
  SearchUiState build() {
    ref.onDispose(() => _toastTimer?.cancel());
    // Listen to favorite state changes and re-map isFavorite on search results
    ref.listen<AsyncValue<Set<String>>>(
      favoriteIdsControllerProvider,
      (previous, next) {
        _applyFavoriteIds(next.valueOrNull);
      },
    );
    return const SearchUiState();
  }

  /// 검색어 설정 및 검색 실행.
  ///
  /// Race condition 처리:
  /// - 각 요청에 sequence ID 부여
  /// - 응답 도착 시 최신 요청인지 확인
  /// - 구버전 응답은 무시
  ///
  /// 상태 동기화:
  /// - 검색 완료 후 현재 즐겨찾기 상태를 결과에 반영
  /// - 검색 중에도 즐겨찾기 변경되면 listener가 자동 반영
  Future<void> setQuery(String query) async {
    _requestSequence += 1;
    final currentRequestId = _requestSequence;
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      _toastTimer?.cancel();
      state = state.copyWith(
        query: query,
        results: const AsyncData(<StockSearchItem>[]),
        selectedItemId: null,
        toast: null,
      );
      return;
    }

    final existingResults = state.results;
    final loadingResults = existingResults.hasValue
        ? const AsyncLoading<List<StockSearchItem>>().copyWithPrevious(
            existingResults,
          )
        : const AsyncLoading<List<StockSearchItem>>();

    state = state.copyWith(
      query: query,
      results: loadingResults,
      selectedItemId: null,
      toast: null,
    );

    final result = await AsyncValue.guard(
      () => _repository.searchStocks(query: trimmedQuery),
    );
    if (currentRequestId != _requestSequence) {
      return;
    }

    // Apply current favorite state to search results
    final favoriteIds = ref.read(favoriteIdsControllerProvider).valueOrNull ?? <String>{};
    final updatedResult = result.whenData((items) {
      return items.map((item) {
        return item.copyWith(isFavorite: favoriteIds.contains(item.id));
      }).toList();
    });

    state = state.copyWith(
      results: updatedResult,
      selectedItemId: null,
    );
  }

  void clearQuery() {
    _requestSequence += 1;
    _toastTimer?.cancel();
    state = state.copyWith(
      query: '',
      results: const AsyncData(<StockSearchItem>[]),
      selectedItemId: null,
      toast: null,
    );
  }

  void setFocused(bool isFocused) {
    if (state.isFocused == isFocused) {
      return;
    }
    state = state.copyWith(isFocused: isFocused);
  }

  void toggleSelection(StockSearchItem item) {
    state = state.copyWith(
      selectedItemId: state.selectedItemId == item.id ? null : item.id,
    );
  }

  void clearSelection() {
    if (state.selectedItemId == null) {
      return;
    }
    state = state.copyWith(selectedItemId: null);
  }

  /// 즐겨찾기 토글.
  ///
  /// 토스트 동작 규칙:
  /// - 즐겨찾기 추가 시: 토스트 표시 (2초 후 자동 숨김)
  /// - 즐겨찾기 제거 시: 토스트 즉시 숨김
  ///
  /// 상태 동기화:
  /// - 토글 후 즉시 검색 결과에 상태 반영
  /// - favoriteIdsController listener가 추가로 동기화 보장
  Future<bool> toggleFavorite(StockSearchItem item) async {
    final isAdded = await ref
        .read(favoriteIdsControllerProvider.notifier)
        .toggle(item.id);

    // Apply latest favorite state to current results
    final favoriteIds = ref.read(favoriteIdsControllerProvider).valueOrNull ?? <String>{};
    _applyFavoriteIds(favoriteIds);

    // Show or dismiss toast based on add/remove action
    if (isAdded) {
      _showToast(const SearchToastData(message: '관심그룹에 추가되었습니다.'));
    } else {
      dismissToast();
    }

    return isAdded;
  }

  void dismissToast() {
    _toastTimer?.cancel();
    if (state.toast == null) {
      return;
    }
    state = state.copyWith(toast: null);
  }

  // ignore: unused_element
  void _showToast(SearchToastData toast) {
    _toastTimer?.cancel();
    state = state.copyWith(toast: toast);
    _toastTimer = Timer(const Duration(seconds: 2), dismissToast);
  }

  void _applyFavoriteIds(Set<String>? favoriteIds) {
    if (favoriteIds == null) {
      return;
    }

    // Re-map isFavorite for current results
    final updatedResults = state.results.whenData((items) {
      return items.map((item) {
        return item.copyWith(isFavorite: favoriteIds.contains(item.id));
      }).toList();
    });

    // Check if selected item still exists in favorites (if it was a favorite)
    String? updatedSelectedItemId = state.selectedItemId;
    // We keep selectedItemId as-is since it represents selection in the UI,
    // not favorite status

    state = state.copyWith(
      results: updatedResults,
      selectedItemId: updatedSelectedItemId,
    );
  }
}

@immutable
class SearchUiState {
  const SearchUiState({
    this.query = '',
    this.results = const AsyncData(<StockSearchItem>[]),
    this.selectedItemId,
    this.isFocused = false,
    this.toast,
  });

  final String query;
  final AsyncValue<List<StockSearchItem>> results;
  final String? selectedItemId;
  final bool isFocused;
  final SearchToastData? toast;

  SearchUiState copyWith({
    String? query,
    AsyncValue<List<StockSearchItem>>? results,
    Object? selectedItemId = _sentinel,
    bool? isFocused,
    Object? toast = _sentinel,
  }) {
    return SearchUiState(
      query: query ?? this.query,
      results: results ?? this.results,
      selectedItemId: selectedItemId == _sentinel
          ? this.selectedItemId
          : selectedItemId as String?,
      isFocused: isFocused ?? this.isFocused,
      toast: toast == _sentinel ? this.toast : toast as SearchToastData?,
    );
  }
}

@immutable
class SearchToastData {
  const SearchToastData({required this.message});

  final String message;
}

const _sentinel = Object();
