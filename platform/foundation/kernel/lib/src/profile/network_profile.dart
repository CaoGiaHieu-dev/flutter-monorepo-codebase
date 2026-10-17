/// How the default HTTP client behaves — the limits and headers of the `Dio`
/// `ApiClient` builds.
///
/// Defaults are what the template did before an app could say anything: 20
/// seconds for each of connect, receive and send, no extra header, no
/// redirects followed. The base URL is not here: it is the `BASE_URL`
/// environment define, already per app and per flavor.
///
/// The `Authorization` and `language` headers, the retry policy and the
/// interceptor chain stay the shell's; a second client with another base URL
/// is `ApiClient.createClient(baseUrl:)`.
final class NetworkProfile {
  const NetworkProfile({
    this.connectTimeout = const Duration(seconds: 20),
    this.receiveTimeout = const Duration(seconds: 20),
    this.sendTimeout = const Duration(seconds: 20),
    this.headers = const {},
    this.followRedirects = false,
    this.authorizedHosts = const {},
  });

  /// How long a connection may take to open. Default 20 s.
  final Duration connectTimeout;

  /// How long to wait between two chunks of a response. Default 20 s.
  final Duration receiveTimeout;

  /// How long a request body may take to send. Default 20 s.
  final Duration sendTimeout;

  /// Headers every request of the default client carries, besides the JSON
  /// content type and the ones the interceptors add (`Authorization`,
  /// `language`). Default: none.
  ///
  /// A header that carries a credential, or one the shell owns, is refused
  /// (RULE-66): `ApiClient` throws at boot for any of [refusedHeaders].
  final Map<String, String> headers;

  /// Whether the client follows HTTP redirects. Default false.
  final bool followRedirects;

  /// Hosts, besides the one in the client's base URL (`BASE_URL`), that
  /// receive the bearer token — for an API that is split over several
  /// sub-domains. Default: none, so a request to any other host (a CDN, a
  /// presigned storage URL) goes out without credentials.
  ///
  /// Hosts only (`files.example.com`): no scheme, port or path.
  final Set<String> authorizedHosts;

  /// The names in [headers] an app may not set — compared case-insensitively:
  /// `authorization`, `cookie`, `set-cookie`, `proxy-authorization` (a
  /// credential belongs to the session owner and is redacted from logs, not
  /// hard-wired into the client) and `content-type` (the client is JSON).
  List<String> get refusedHeaders => [
    for (final name in headers.keys)
      if (_refused.contains(name.toLowerCase())) name,
  ];
}

const _refused = {
  'authorization',
  'cookie',
  'set-cookie',
  'proxy-authorization',
  'content-type',
};
