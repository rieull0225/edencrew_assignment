import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../theme/app_assets.dart';
import '../../../../theme/app_theme.dart';
import '../layout/search_layout_spec.dart';

/// 검색 화면 토스트 위젯.
///
/// Figma 토스트 스펙:
/// - 배경: rgba(37,37,37,0.7) - 반투명 다크 배경
/// - 테두리: rgba(185,128,255,0.2) - 보라색 20% 투명도
/// - blur: 10px - BackdropFilter로 구현
/// - border-radius: 16px
/// - shadow: offset(0,2) blurRadius 10
///
/// 아이콘 조합:
/// - 하트 아이콘(20x20) 위에 체크 아이콘(10x10) 우하단 배치
/// - Stack + Positioned로 겹쳐서 표현
class SearchToast extends StatelessWidget {
  const SearchToast({required this.layout, required this.message, super.key});

  final SearchLayoutSpec layout;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: SearchLayoutSpec.toastHeight,
          padding: EdgeInsets.symmetric(horizontal: 16 * layout.horizontalScale),
          decoration: BoxDecoration(
            // Figma: rgba(37,37,37,0.7)
            color: const Color(0xB3252525),
            borderRadius: BorderRadius.circular(16),
            // Figma: rgba(185,128,255,0.2) - 보라색 강조 테두리
            border: Border.all(color: const Color(0x33B980FF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Stack(
                  children: [
                    SizedBox(
                      key: const Key('search-toast-favorite-icon'),
                      width: 20,
                      height: 20,
                      child: AppAssetSlotIcon(
                        assetPath: AppAssets.favoriteHeart,
                        slotWidth: 20,
                        slotHeight: 20,
                        assetWidth: AppAssetSizes.favoriteHeart.width,
                        assetHeight: AppAssetSizes.favoriteHeart.height,
                        color: AppColors.mainAndAccent.up_f93f62,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        key: const Key('search-toast-check-icon'),
                        width: 10,
                        height: 10,
                        child: AppAssetSlotIcon(
                          assetPath: AppAssets.toastCheck,
                          slotWidth: 10,
                          slotHeight: 10,
                          assetWidth: AppAssetSizes.toastCheck.width,
                          assetHeight: AppAssetSizes.toastCheck.height,
                          color: AppColors.text.text_fafafa,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: AppTypography.searchToast,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
