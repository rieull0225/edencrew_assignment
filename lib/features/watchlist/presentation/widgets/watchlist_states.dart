import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../theme/app_theme.dart';

class WatchlistSkeleton extends StatelessWidget {
  const WatchlistSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Shimmer 효과로 로딩 중임을 시각적으로 표현
    // - baseColor: 스켈레톤 기본 색상
    // - highlightColor: 반짝이는 하이라이트 색상
    // - 다크 테마에 맞게 어두운 톤 사용
    return Shimmer.fromColors(
      baseColor: AppDerivedColors.skeleton,
      highlightColor: AppDerivedColors.skeletonHighlight,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: 10,
        itemBuilder: (context, index) {
          return const SizedBox(
            height: 56,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _SkeletonCircle(),
                  SizedBox(width: 8),
                  Expanded(child: _SkeletonBar(widthFactor: 0.56)),
                  SizedBox(width: 12),
                  SizedBox(
                    width: 90,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SkeletonBar(widthFactor: 0.8),
                        SizedBox(height: 6),
                        _SkeletonBar(widthFactor: 0.5),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class WatchlistEmptyState extends StatelessWidget {
  const WatchlistEmptyState({required this.onRefresh, super.key});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_remove_rounded,
              color: AppColors.text.text_2_bdbdbd,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              '표시할 관심종목이 없습니다.',
              style: TextStyle(
                color: AppColors.text.text_fafafa,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '종목을 추가한 뒤 다시 불러와 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text.text_2_bdbdbd,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRefresh,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.mainAndAccent.primary_ff8a00,
                foregroundColor: Colors.black,
              ),
              child: const Text('새로고침'),
            ),
          ],
        ),
      ),
    );
  }
}

class WatchlistErrorState extends StatelessWidget {
  const WatchlistErrorState({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: AppColors.text.text_2_bdbdbd,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              '관심종목을 불러오지 못했습니다.',
              style: TextStyle(
                color: AppColors.text.text_fafafa,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '잠시 후 다시 시도하거나 네트워크 연결을 확인해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text.text_2_bdbdbd,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('watchlist-retry-button'),
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.mainAndAccent.primary_ff8a00,
                foregroundColor: Colors.black,
              ),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCircle extends StatelessWidget {
  const _SkeletonCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        color: AppDerivedColors.skeleton,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: AppDerivedColors.skeleton,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}
