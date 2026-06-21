import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// API 재시도 유틸리티.
///
/// 금융앱 안정성을 위한 exponential backoff 재시도 구현.
/// - 네트워크 일시적 오류 시 자동 재시도
/// - 재시도 간격: 1초 → 2초 → 4초 (exponential backoff)
/// - 최대 3회 재시도 후 실패
///
/// 재시도 대상 오류:
/// - SocketException: 네트워크 연결 실패
/// - DioException (connectionTimeout, receiveTimeout): 타임아웃
/// - DioException (connectionError): 연결 오류
///
/// 재시도하지 않는 오류:
/// - 4xx/5xx HTTP 오류 (서버 응답은 받았으므로)
/// - FormatException (파싱 오류)
class ApiRetry {
  const ApiRetry({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
  });

  final int maxRetries;
  final Duration initialDelay;

  /// 재시도 가능한 오류인지 판별.
  bool isRetryable(Object error) {
    // 네트워크 연결 실패
    if (error is SocketException) {
      return true;
    }

    // Dio 타임아웃 및 연결 오류
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
          return true;
        default:
          return false;
      }
    }

    return false;
  }

  /// 재시도 로직으로 함수 실행.
  ///
  /// [fn]: 실행할 비동기 함수
  /// [onRetry]: 재시도 시 호출되는 콜백 (로깅용)
  Future<T> execute<T>(
    Future<T> Function() fn, {
    void Function(int attempt, Object error)? onRetry,
  }) async {
    var lastError = Object();

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;

        // 마지막 시도이거나 재시도 불가능한 오류면 즉시 throw
        if (attempt >= maxRetries - 1 || !isRetryable(e)) {
          rethrow;
        }

        // 재시도 콜백 호출
        onRetry?.call(attempt + 1, e);

        // Exponential backoff: 1초 → 2초 → 4초
        final delay = initialDelay * (1 << attempt);
        await Future<void>.delayed(delay);
      }
    }

    // 이론상 도달 불가
    throw lastError;
  }
}

/// 전역 재시도 인스턴스.
const apiRetry = ApiRetry();

/// 네트워크 오류인지 확인 (오프라인 감지용).
bool isNetworkError(Object error) {
  if (error is SocketException) {
    return true;
  }

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return true;
      default:
        return false;
    }
  }

  return false;
}
