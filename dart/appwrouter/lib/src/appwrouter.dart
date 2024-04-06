// ignore: lines_longer_than_80_chars
// ignore_for_file: avoid_dynamic_calls, inference_failure_on_function_return_type

import 'dart:convert';

import 'package:appwrouter/appwrouter.dart';
import 'package:dart_appwrite/dart_appwrite.dart';

/// {@template appwrouter}
/// A router for appwrite cloud functions
/// {@endtemplate}

class Appwrouter {
  /// Singleton instance of the router
  factory Appwrouter() {
    return _instance;
  }
  Appwrouter._internal();

  /// Singleton instance of the router
  static Appwrouter get instance => _instance;

  /// Registration of all versions, routes and handlers
  Map<String, VersionedRoutes> versions = {};
  static final Appwrouter _instance = Appwrouter._internal();

  /// A method for registration for version routes
  void register({
    required String version,
    required MethodType method,
    required String path,
    required RouteHandler handler,
  }) {
    if (!versions.containsKey(version)) {
      versions[version] = VersionedRoutes();
    }
    if (!versions[version]!.routes.containsKey(path)) {
      versions[version]!.routes[path] = Route();
    }
    versions[version]!.routes[path]!.methods[method] = handler;
  }

  /// A Client instance from Appwrite SDK
  late final Client _client;

  /// A Request mimic from Appwrite Context
  late final AppwrouterRequest _req;

  /// A Response mimic from Appwrite Context
  late final AppwrouterResponse _res;

  /// A log method from Appwrite Context
  late final dynamic _log;

  /// An error log method from Appwrite context
  late final dynamic _errorLog;

  /// GET registration method
  void get({
    required String version,
    required String path,
    required RouteHandler handler,
  }) {
    register(
      version: version,
      method: MethodType.get,
      path: path,
      handler: handler,
    );
  }

  /// POST registration method
  void post({
    required String version,
    required String path,
    required RouteHandler handler,
  }) {
    register(
      version: version,
      method: MethodType.post,
      path: path,
      handler: handler,
    );
  }

  /// DELETE registration method
  void delete({
    required String version,
    required String path,
    required RouteHandler handler,
  }) {
    register(
      version: version,
      method: MethodType.delete,
      path: path,
      handler: handler,
    );
  }

  /// PUT registration method
  void put({
    required String version,
    required String path,
    required RouteHandler handler,
  }) {
    register(
      version: version,
      method: MethodType.put,
      path: path,
      handler: handler,
    );
  }

  /// PATCH registration method
  void patch({
    required String version,
    required String path,
    required RouteHandler handler,
  }) {
    register(
      version: version,
      method: MethodType.patch,
      path: path,
      handler: handler,
    );
  }

  /// A function to match the route
  RouteMatchHandler? matchRoute({
    required String version,
    required MethodType method,
    required String path,
  }) {
    final versionRoutes = versions[version];
    if (versionRoutes == null) return null;

    for (final MapEntry(:key, :value) in versionRoutes.routes.entries) {
      if (value.methods[method] != null) {
        final routePattern = key
            .split('/')
            .where(
              (item) => item.isNotEmpty,
            )
            .toList();
        final pathSegments = path
            .split('/')
            .where(
              (item) => item.isNotEmpty,
            )
            .toList();

        if (routePattern.length != pathSegments.length) return null;

        final params = <String, dynamic>{};
        var isMatch = true;
        for (var i = 0; i < routePattern.length; i++) {
          if (routePattern[i].startsWith(':')) {
            params[routePattern[i].substring(1)] = pathSegments[i];
          } else if (routePattern[i] != pathSegments[i]) {
            isMatch = false;
            break;
          }
        }

        if (isMatch) {
          final handler = value.methods[method];

          if (handler != null) {
            return RouteMatchHandler(
              params: params,
              handler: handler,
            );
          }
        }
      }
    }

    return null;
  }

  // TODO: add a method to generate the path parameters
  /// A function to handle the request
  Future<dynamic> handleRequest({
    required AppwrouterRequest req,
    required AppwrouterResponse res,
    required dynamic log,
    required dynamic error,
    required Client client,
  }) async {
    final pathRequest = req.path;
    final pathSegments = pathRequest.split('/');
    if (pathSegments.length < 2) {
      error('Bad request');
      return res.send(
          jsonEncode(
            {'message': 'Bad request'},
          ),
          400,
          {
            'content-type': 'application/json',
          });
    }

    final version = pathSegments[1];
    final method = MethodType.fromCode(
      req.method.toUpperCase(),
    );
    final path = '/${pathSegments.sublist(2).join('/')}';

    final matchedRoute = matchRoute(
      version: version,
      method: method,
      path: path,
    );

    if (matchedRoute == null) {
      error('No route found for $path with method $method');
      return res.send(
          jsonEncode(
            {
              'message':
                  // ignore: lines_longer_than_80_chars
                  'The requested endpoint $path was not found for API version $version.',
            },
          ),
          404,
          {
            'content-type': 'application/json',
          });
    }

    log('Matched route: $pathRequest with method $method');

    try {
      final newReq = req.copyWith(params: matchedRoute.params);

      return await matchedRoute.handler(
        req: newReq,
        res: res,
        log: log,
        error: error,
        client: client,
      );
    } catch (e) {
      error('Error while handling request: $e');
      return res.send(
          jsonEncode(
            {
              'message': 'Internal server error',
            },
          ),
          500,
          {
            'content-type': 'application/json',
          });
    }
  }

  /// A method for initialization of the Appwrouter
  Future<dynamic> initialize(
    dynamic context, {
    Future<dynamic> Function(
      AppwrouterRequest req,
      AppwrouterResponse res,
      MiddlewarePayload payload,
      Client client,
      Future<dynamic> Function(String path) redirect,
      Future<dynamic> Function() next,
    )? onMiddleware,
    Future<dynamic> Function(
      AppwrouterRequest req,
      AppwrouterResponse res,
      dynamic errorLog,
      Object error,
    )? onError,
  }) async {
    final req = AppwrouterRequest.parse(context.req);
    final res = AppwrouterResponse.parse(context.res);
    final log = context.log;
    final error = context.error;
    try {
      _client = Client();
      _req = req;
      _res = res;
      _log = log;
      _errorLog = error;

      if (onMiddleware == null) {
        return await handleRequest(
          req: req,
          res: res,
          log: log,
          error: error,
          client: _client,
        );
      } else {
        final triggeredType = TriggeredType.fromCode(
          req.headers['x-appwrite-trigger'] as String,
        );
        String? fullEventType;
        EventType? eventType;
        Map<String, dynamic>? eventMap;

        if (triggeredType == TriggeredType.event) {
          fullEventType = req.headers['x-appwrite-event'] as String;
          eventType = EventType.fromCode(fullEventType);
          eventMap = req.body as Map<String, dynamic>;
        }

        final middlewarePayload = MiddlewarePayload(
          method: MethodType.fromCode(req.method),
          triggeredType: triggeredType,
          eventType: eventType,
          eventMap: eventMap,
        );

        log('Middleware payload: $middlewarePayload');

        final onMiddlewareResponse = await onMiddleware(
          req,
          res,
          middlewarePayload,
          _client,
          _redirect,
          _next,
        );

        if (onMiddlewareResponse is! Future<dynamic>) {
          throw Exception('''
The onMiddleware function should return a Future<dynamic> but got ${onMiddlewareResponse.runtimeType}
To fix this, use the next as a `return await next();`. If you use the redirect then,
use `return await redirect('/v1/path'). If the error is still there, please raise an issue at
https://github.com/moshOntong-IT/appwrouter/issues.

This error occured because you did not get the Response object from `AppwrouterResponse`.
''');
        } else {
          return onMiddlewareResponse;
        }
      }
    } catch (e) {
      if (onError == null) {
        error(e.toString());
        return res.send(
            jsonEncode({
              'message': 'Internal Server Error',
            }),
            500,
            {
              'content-type': 'application/json',
            });
      } else {
        return onError(req, res, error, e);
      }
    }
  }

  Future<dynamic> _redirect(String path) async {
    return handleRequest(
      req: _req.copyWith(path: path),
      res: _res,
      log: _log,
      error: _errorLog,
      client: _client,
    );
  }

  Future<dynamic> _next() async {
    return handleRequest(
      req: _req,
      res: _res,
      log: _log,
      error: _errorLog,
      client: _client,
    );
  }
}
