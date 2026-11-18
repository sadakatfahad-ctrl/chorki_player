import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../theme/chorki_player_theme.dart';
import 'error.dart';
import 'no_internet_exception.dart';
import 'server_exception.dart';

/// What went wrong, in a form the app can branch on.
enum ChorkiErrorCode {
  /// No network connection.
  noInternet,

  /// The route request or the video load took too long.
  timeout,

  /// The route API answered 401.
  unauthorized,

  /// The route API answered 403.
  forbidden,

  /// The route API answered 404: the byte does not exist.
  notFound,

  /// The route API answered 4xx (other than the above).
  badRequest,

  /// The route API answered 5xx.
  server,

  /// The route API answered, but not in the expected shape.
  malformedResponse,

  /// The route resolved without a video URL.
  noVideoUrl,

  /// The video could not be loaded (unreachable URL, unsupported format).
  videoLoad,

  /// The video failed while playing.
  playback,

  /// Anything else.
  unknown,
}

/// Where in the pipeline a [ChorkiPlayerError] happened.
enum ChorkiErrorStage {
  /// Resolving the byte route.
  route,

  /// Creating and initializing the video.
  load,

  /// While the video played.
  playback,
}

/// A failure the player shows (and reports to analytics).
///
/// [code] says what happened; [isTransient] says whether retrying may help.
/// The player silently retries transient errors a few times before it shows
/// the error view.
class ChorkiPlayerError implements Exception {
  /// Creates an error.
  const ChorkiPlayerError(
    this.code, {
    this.stage = ChorkiErrorStage.route,
    this.statusCode,
    this.detail,
  });

  /// Maps an exception from the network or video layer.
  factory ChorkiPlayerError.from(
    Object error, {
    ChorkiErrorStage stage = ChorkiErrorStage.route,
  }) {
    if (error is ChorkiPlayerError) return error;
    if (error is NoInternetException || isConnectionFailure(error)) {
      return ChorkiPlayerError(ChorkiErrorCode.noInternet, stage: stage);
    }
    if (error is TimeoutException) {
      return ChorkiPlayerError(ChorkiErrorCode.timeout, stage: stage);
    }
    if (error is DioException &&
        (error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout)) {
      return ChorkiPlayerError(ChorkiErrorCode.timeout, stage: stage);
    }
    if (error is ServerException) {
      final status = error.statusCode ?? 0;
      return ChorkiPlayerError(
        switch (status) {
          401 => ChorkiErrorCode.unauthorized,
          403 => ChorkiErrorCode.forbidden,
          404 => ChorkiErrorCode.notFound,
          >= 500 => ChorkiErrorCode.server,
          >= 400 => ChorkiErrorCode.badRequest,
          _ => ChorkiErrorCode.malformedResponse,
        },
        stage: stage,
        statusCode: error.statusCode,
        detail: error.serverMessage ?? error.message,
      );
    }
    if (error is FormatException || error is TypeError) {
      return ChorkiPlayerError(
        ChorkiErrorCode.malformedResponse,
        stage: stage,
        detail: '$error',
      );
    }
    if (error is SocketException || error is HttpException) {
      return ChorkiPlayerError(ChorkiErrorCode.noInternet, stage: stage);
    }
    return ChorkiPlayerError(
      ChorkiErrorCode.unknown,
      stage: stage,
      detail: '$error',
    );
  }

  /// What happened.
  final ChorkiErrorCode code;

  /// Where it happened.
  final ChorkiErrorStage stage;

  /// The HTTP status of a route API error.
  final int? statusCode;

  /// Developer-facing detail (server message, platform error). Not
  /// localized; do not show it to viewers.
  final String? detail;

  /// Whether retrying may help (network, timeouts, 5xx, video errors).
  bool get isTransient => switch (code) {
    ChorkiErrorCode.noInternet ||
    ChorkiErrorCode.timeout ||
    ChorkiErrorCode.server ||
    ChorkiErrorCode.videoLoad ||
    ChorkiErrorCode.playback ||
    ChorkiErrorCode.unknown => true,
    ChorkiErrorCode.unauthorized ||
    ChorkiErrorCode.forbidden ||
    ChorkiErrorCode.notFound ||
    ChorkiErrorCode.badRequest ||
    ChorkiErrorCode.malformedResponse ||
    ChorkiErrorCode.noVideoUrl => false,
  };

  /// The viewer-facing message from [strings].
  String message(ChorkiPlayerStrings strings) => switch (code) {
    ChorkiErrorCode.noInternet => strings.noInternet,
    ChorkiErrorCode.videoLoad ||
    ChorkiErrorCode.playback ||
    ChorkiErrorCode.noVideoUrl => strings.videoFailed,
    ChorkiErrorCode.server ||
    ChorkiErrorCode.timeout ||
    ChorkiErrorCode.unauthorized ||
    ChorkiErrorCode.forbidden ||
    ChorkiErrorCode.notFound ||
    ChorkiErrorCode.badRequest ||
    ChorkiErrorCode.malformedResponse => strings.serverError,
    ChorkiErrorCode.unknown => strings.genericError,
  };

  @override
  bool operator ==(Object other) =>
      other is ChorkiPlayerError &&
      other.code == code &&
      other.stage == stage &&
      other.statusCode == statusCode &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(code, stage, statusCode, detail);

  @override
  String toString() =>
      'ChorkiPlayerError(${code.name}, ${stage.name}'
      '${statusCode == null ? '' : ', $statusCode'}'
      '${detail == null ? '' : ', $detail'})';
}
