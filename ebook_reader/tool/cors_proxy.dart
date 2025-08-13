// Auto-stopping CORS proxy for local Flutter web dev.
// Reuses a single HttpClient so upstream cookies persist.
import 'dart:async';
import 'dart:io';

const String userAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 8080 : 8080;
  final idleSec = args.length > 1 ? int.tryParse(args[1]) ?? 900 : 900;

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('CORS proxy on http://localhost:$port  (idle stop: $idleSec s)');

  // ONE shared client -> keeps cookies & redirects across requests
  final httpClient = HttpClient()
    ..userAgent = userAgent
    ..maxConnectionsPerHost = 6
    ..autoUncompress = true;

  Timer? idle;
  void resetIdle() {
    idle?.cancel();
    idle = Timer(Duration(seconds: idleSec), () async {
      stdout.writeln('Idle $idleSec s — quitting proxy');
      await server.close(force: true);
      httpClient.close(force: true);
      exit(0);
    });
  }
  resetIdle();

  ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    httpClient.close(force: true);
    exit(0);
  });
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    httpClient.close(force: true);
    exit(0);
  });

  await for (final req in server) {
    resetIdle();

    // Health check
    if (req.uri.path == '/' && !req.uri.queryParameters.containsKey('url')) {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..write('ok')
        ..close();
      continue;
    }

    final target = req.uri.queryParameters['url'];
    if (target == null || target.isEmpty) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..write('Missing "url" query parameter')
        ..close();
      continue;
    }

    try {
      final uri = Uri.parse(target);
      final upstream = await httpClient.openUrl('GET', uri);
      upstream.headers.set('Accept',
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      upstream.headers.set('Accept-Language', 'en-US,en;q=0.9');

      final upRes = await upstream.close();

      final out = req.response
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS')
        ..headers.set('Access-Control-Allow-Headers', 'Content-Type')
        ..statusCode = upRes.statusCode;

      final ct = upRes.headers.value('content-type');
      out.headers.set('content-type', ct ?? 'text/html; charset=utf-8');

      await upRes.pipe(out);
    } catch (e) {
      req.response
        ..statusCode = HttpStatus.badGateway
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..write('Proxy error: $e')
        ..close();
    }
  }
}
