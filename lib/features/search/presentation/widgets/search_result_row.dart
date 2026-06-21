import 'package:flutter/material.dart';

import '../../../watchlist/domain/models/watchlist_models.dart';
import '../../../../theme/app_assets.dart';
import '../../../../theme/app_theme.dart';
import '../../domain/services/search_text_utils.dart';
import '../layout/search_layout_spec.dart';
import 'search_action_bar.dart';

/// 검색 결과 행 위젯.
///
/// Figma 스펙 구현:
/// - 종목명 + 서브텍스트(종목코드, 시장) 2줄 구조
/// - 검색어 하이라이트: 보라색(#B980FF)으로 매칭 텍스트 강조
/// - 하트 버튼: 즐겨찾기 상태에 따라 빨간색/회색 전환
/// - 선택 시 액션바 확장 (매수/매도/지우기 버튼)
///
/// 탭 영역:
/// - 하트 아이콘은 20x20 슬롯이지만 터치 영역은 넓게 유지
/// - GestureDetector + opaque behavior로 탭 감지
class SearchResultRow extends StatelessWidget {
  const SearchResultRow({
    required this.item,
    required this.query,
    required this.isSelected,
    required this.layout,
    required this.onTap,
    required this.onHeartTap,
    required this.onActionTap,
    super.key,
  });

  final StockSearchItem item;
  final String query;
  final bool isSelected;
  final SearchLayoutSpec layout;
  final VoidCallback onTap;
  final VoidCallback onHeartTap;
  final ValueChanged<String> onActionTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('search-result-${item.id}'),
        onTap: onTap,
        child: Column(
          children: [
            SizedBox(
              key: Key('search-result-row-${item.id}'),
              height: SearchLayoutSpec.resultRowHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: layout.horizontalPadding,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SearchTextColumn(item: item, query: query),
                    ),
                    const SizedBox(width: 12),
                    // 하트 아이콘: Figma 스펙에 따라 20x20 slot 사용
                    // 탭 영역을 넓히기 위해 GestureDetector로 감싸고 opaque 처리
                    GestureDetector(
                      key: Key('search-heart-${item.id}'),
                      onTap: onHeartTap,
                      behavior: HitTestBehavior.opaque,
                      child: AppAssetSlotIcon(
                        key: Key('search-heart-icon-${item.id}'),
                        assetPath: AppAssets.favoriteHeart,
                        slotWidth: 20,
                        slotHeight: 20,
                        assetWidth: AppAssetSizes.favoriteHeart.width,
                        assetHeight: AppAssetSizes.favoriteHeart.height,
                        color: item.isFavorite
                            ? AppColors.mainAndAccent.up_f93f62
                            : AppColors.darkTheme.c_424242,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 0),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: layout.horizontalPadding,
                ),
                child: KeyedSubtree(
                  key: Key('search-actions-${item.id}'),
                  child: SearchActionBar(
                    layout: layout,
                    onActionTap: onActionTap,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchTextColumn extends StatelessWidget {
  const _SearchTextColumn({required this.item, required this.query});

  final StockSearchItem item;
  final String query;

  static final _highlightColor = AppColors.mainAndAccent.point_b980ff;

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

  @override
  Widget build(BuildContext context) {
    final subtitle = buildSearchSubtitle(item);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: _buildHighlightedSpans(item.name, AppTypography.searchName),
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: _buildHighlightedSpans(subtitle, AppTypography.searchMeta),
          ),
        ),
      ],
    );
  }
}
