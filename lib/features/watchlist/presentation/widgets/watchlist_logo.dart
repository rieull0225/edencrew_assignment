import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/clients/naver_domestic_stock_client.dart';
import '../../domain/models/watchlist_models.dart';
import '../../../../theme/app_theme.dart';

/// 관심종목 로고 위젯.
///
/// 이미지 캐싱 전략:
/// - CachedNetworkImage: PNG/JPG 등 래스터 이미지용
/// - 커스텀 SVG 캐시: SVG 파일용 (메모리 + 디스크 캐시)
///
/// 깜빡임 방지 구현:
/// - static Map으로 SVG 문자열 메모리 캐시
/// - build() 메서드에서 동기적으로 캐시 확인
/// - 캐시 히트 시 즉시 렌더링 (비동기 대기 없음)
///
/// 폴백 처리:
/// - 로고 URL 없거나 로딩 실패 시 모노그램 표시
/// - 종목명에서 앞글자 추출 (영문: 2자, 한글: 1자)
/// - 종목 ID로 일관된 배경색 결정

String fallbackMonogram(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }

  final asciiTokens = RegExp(
    r'[A-Za-z0-9]+',
  ).allMatches(trimmed).map((match) => match.group(0)!).toList(growable: false);

  if (asciiTokens.isNotEmpty) {
    if (asciiTokens.length == 1) {
      final token = asciiTokens.first;
      return token.substring(0, token.length > 1 ? 2 : 1).toUpperCase();
    }
    return asciiTokens.take(2).map((token) => token[0]).join().toUpperCase();
  }

  return String.fromCharCode(trimmed.runes.first);
}

bool isSvgLogoUrl(String url) => url.toLowerCase().endsWith('.svg');

Color fallbackLogoColor(String seed) {
  const palette = [
    Color(0xFF4780FF),
    Color(0xFFF93F62),
    Color(0xFF00C27A),
    Color(0xFFFF8A00),
    Color(0xFF8E7CFF),
    Color(0xFF26A69A),
  ];

  final code = seed.runes.fold<int>(0, (total, value) => total + value);
  return palette[code % palette.length];
}

/// Custom cache manager for Naver stock logos with proper headers
class _NaverLogoCacheManager {
  static const key = 'naverStockLogoCache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 200,
    ),
  );
}

class WatchlistLogo extends StatelessWidget {
  const WatchlistLogo({required this.item, super.key});

  final WatchlistItem item;

  @override
  Widget build(BuildContext context) {
    if (item.logoUrl case final String url?) {
      final fallback = _FallbackLogo(
        label: fallbackMonogram(item.name),
        seed: item.id,
      );
      final normalizedUrl = url.toLowerCase();

      if (isSvgLogoUrl(normalizedUrl)) {
        return _CachedSvgLogo(url: url, fallback: fallback);
      }

      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          cacheManager: _NaverLogoCacheManager.instance,
          placeholder: (context, url) => fallback,
          errorWidget: (context, url, error) => fallback,
          httpHeaders: naverDesktopLikeHeaders(),
        ),
      );
    }

    return _FallbackLogo(label: fallbackMonogram(item.name), seed: item.id);
  }
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo({required this.label, required this.seed});

  final String label;
  final String seed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = fallbackLogoColor(seed);
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: AppTypography.listName.copyWith(
              color: AppColors.grays.white,
              fontWeight: FontWeight.w700,
              fontSize: label.length > 1 ? 9 : 10,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// SVG 로고 캐싱 위젯.
///
/// 캐싱 전략:
/// - _svgStringCache: static Map으로 SVG 문자열 메모리 캐시
/// - _loadingUrls: 중복 로딩 방지용 Set
/// - flutter_cache_manager: 디스크 캐시 (7일 유효)
///
/// 깜빡임 방지:
/// - build()에서 동기적으로 캐시 확인
/// - 캐시 히트 시 FutureBuilder 없이 즉시 렌더링
/// - 위젯 rebuild 시에도 깜빡임 없음
class _CachedSvgLogo extends StatefulWidget {
  const _CachedSvgLogo({required this.url, required this.fallback});

  final String url;
  final Widget fallback;

  @override
  State<_CachedSvgLogo> createState() => _CachedSvgLogoState();
}

class _CachedSvgLogoState extends State<_CachedSvgLogo> {
  // Static cache for immediate access on rebuild
  static final Map<String, String?> _svgStringCache = {};
  static final Set<String> _loadingUrls = {};

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  void _ensureLoaded() {
    // Already cached or currently loading
    if (_svgStringCache.containsKey(widget.url) || _loadingUrls.contains(widget.url)) {
      return;
    }

    _loadingUrls.add(widget.url);
    _loadSvg();
  }

  Future<void> _loadSvg() async {
    try {
      final file = await _NaverLogoCacheManager.instance.getSingleFile(
        widget.url,
        headers: naverDesktopLikeHeaders(),
      );
      final bytes = await file.readAsBytes();
      final body = utf8.decode(bytes, allowMalformed: true).trimLeft();
      final svgMatch = RegExp(r'<svg[\s\S]*</svg>').firstMatch(body);
      _svgStringCache[widget.url] = svgMatch?.group(0);
    } catch (_) {
      _svgStringCache[widget.url] = null;
    } finally {
      _loadingUrls.remove(widget.url);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check cache synchronously - no flicker on rebuild
    final cached = _svgStringCache[widget.url];
    if (cached != null && cached.isNotEmpty) {
      return ClipOval(
        child: SvgPicture.string(
          cached,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
        ),
      );
    }

    return widget.fallback;
  }
}
