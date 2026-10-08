import 'package:chorki_player/src/data/model/byte_model.dart';
import 'package:chorki_player/src/errors/no_internet_exception.dart';
import 'package:chorki_player/src/errors/server_exception.dart';
import 'package:chorki_player/src/helpers/json_helper.dart';
import 'package:chorki_player/src/network/api_result.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Response<dynamic> _response(int? statusCode, {dynamic data}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: '/test'),
    statusCode: statusCode,
    data: data,
  );
}

void main() {
  group('JsonHelper', () {
    test('getJsonString returns the value or an empty fallback', () {
      final helper = JsonHelper(json: {'name': 'chorki', 'empty': '', 'n': 5});

      expect(helper.getJsonString('name'), 'chorki');
      expect(helper.getJsonString('empty'), '');
      expect(helper.getJsonString('missing'), '');
      expect(helper.getJsonString('n'), '5');
    });

    test('getJsonInt parses ints, doubles and numeric strings', () {
      final helper = JsonHelper(
        json: {'int': 3, 'double': 4.0, 'string': '7', 'bad': 'x'},
      );

      expect(helper.getJsonInt('int'), 3);
      expect(helper.getJsonInt('double'), 4);
      expect(helper.getJsonInt('string'), 7);
      expect(helper.getJsonInt('bad'), 0);
      expect(helper.getJsonInt('missing'), 0);
    });

    test('getJsonBool never throws on non-bool values', () {
      final helper = JsonHelper(json: {'on': true, 'str': 'true', 'bad': 1});

      expect(helper.getJsonBool('on'), isTrue);
      expect(helper.getJsonBool('str'), isTrue);
      expect(helper.getJsonBool('bad'), isFalse);
    });

    test('getJsonList only accepts lists of maps', () {
      final helper = JsonHelper(
        json: {
          'items': [
            {'id': 1},
          ],
          'notList': 'x',
        },
      );

      expect(helper.getJsonList('items'), [
        {'id': 1},
      ]);
      expect(helper.getJsonList('notList'), isEmpty);
      expect(helper.getJsonList('missing'), isEmpty);
    });

    test('non-map json yields safe defaults', () {
      final helper = JsonHelper(json: null);

      expect(helper.getJsonString('any'), '');
      expect(helper.getJsonInt('any'), 0);
      expect(helper.getJsonDouble('any'), 0.0);
      expect(helper.getJsonMap('any'), isEmpty);
    });
  });

  group('NoInternetException', () {
    test('uses a default message and stringifies clearly', () {
      const exception = NoInternetException();

      expect(exception.message, 'No internet connection');
      expect(
        exception.toString(),
        'NoInternetException: No internet connection',
      );
    });

    test('allows a custom message override', () {
      const exception = NoInternetException(message: 'Offline mode');

      expect(exception.message, 'Offline mode');
      expect(exception.toString(), 'NoInternetException: Offline mode');
    });
  });

  group('ApiResult.fromResponse', () {
    test('success statuses return the decoded data', () {
      final result = ApiResult.fromResponse(_response(200, data: {'ok': true}));

      expect(result.statusCode, 200);
      expect(result.data, {'ok': true});
    });

    test('204 returns success without decoding a body', () {
      final result = ApiResult.fromResponse(_response(204, data: ''));

      expect(result.statusCode, 204);
      expect(result.data, isNull);
    });

    test('JSON string bodies are decoded', () {
      final result = ApiResult.fromResponse(
        _response(200, data: '{"ok":true}'),
      );

      expect(result.data, {'ok': true});
    });

    test('422 throws ServerException with the server message', () {
      expect(
        () => ApiResult.fromResponse(
          _response(422, data: {'message': ' Invalid input '}),
        ),
        throwsA(
          isA<ServerException>().having(
            (e) => e.serverMessage,
            'serverMessage',
            'Invalid input',
          ),
        ),
      );
    });

    test('server errors surface the server message', () {
      expect(
        () => ApiResult.fromResponse(_response(500, data: {'message': 'boom'})),
        throwsA(
          isA<ServerException>().having(
            (e) => e.serverMessage,
            'serverMessage',
            'boom',
          ),
        ),
      );
    });

    test('non-map bodies do not crash message extraction', () {
      expect(
        () => ApiResult.fromResponse(_response(500, data: [1, 2, 3])),
        throwsA(
          isA<ServerException>().having(
            (e) => e.serverMessage,
            'serverMessage',
            isNull,
          ),
        ),
      );
    });
  });

  group('ByteModel.fromJson', () {
    test('maps payload fields', () {
      final model = ByteModel.fromJson({
        'data': {
          'id': 12,
          'poster_background': 'https://img',
          'url': 'https://video',
        },
      });

      expect(model.id, 12);
      expect(model.thumbnailUrl, 'https://img');
      expect(model.url, 'https://video');
    });

    test('toEntity maps to the domain entity', () {
      final entity = ByteModel.fromJson({
        'data': {'id': 1, 'poster_background': 'p', 'url': 'u'},
      }).toEntity();

      expect(entity.id, 1);
      expect(entity.thumbnailUrl, 'p');
      expect(entity.url, 'u');
    });

    test('malformed payloads yield safe defaults', () {
      final model = ByteModel.fromJson(null);

      expect(model.id, 0);
      expect(model.thumbnailUrl, '');
      expect(model.url, '');
    });
  });
}
