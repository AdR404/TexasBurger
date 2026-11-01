import 'dart:convert';

/// Build-time destination. Invalid staging configuration never falls back to main.
class SupabaseEnvironment {
  const SupabaseEnvironment._(this.name, this.url, this.publicKey);
  static const mainUrl = 'https://zlljyvowdripxdgvhilz.supabase.co';
  final String name;
  final String url;
  final String publicKey;
  String get projectId => Uri.parse(url).host.split('.').first;
  String get label => name == 'main' ? 'Principal' : 'Pruebas';

  factory SupabaseEnvironment.resolve({
    required String mainPublicKey,
    String name = const String.fromEnvironment(
      'TEXAS_ENV',
      defaultValue: 'main',
    ),
    String testUrl = const String.fromEnvironment('TEXAS_TEST_SUPABASE_URL'),
    String testKey = const String.fromEnvironment(
      'TEXAS_TEST_SUPABASE_PUBLIC_KEY',
    ),
    String testRef = const String.fromEnvironment('TEXAS_TEST_PROJECT_REF'),
  }) {
    if (name != 'main' && name != 'test') {
      throw StateError('TEXAS_ENV debe ser main o test');
    }
    if (name == 'main') {
      if (testUrl.isNotEmpty || testKey.isNotEmpty || testRef.isNotEmpty) {
        throw StateError(
          'Configuración de pruebas presente sin TEXAS_ENV=test',
        );
      }
      return SupabaseEnvironment._(name, mainUrl, mainPublicKey);
    }
    final uri = Uri.tryParse(testUrl);
    if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(testRef) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != '$testRef.supabase.co' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.host == Uri.parse(mainUrl).host) {
      throw StateError(
        'URL y referencia de pruebas inválidas o apuntan al principal',
      );
    }
    if (!testKey.startsWith('sb_publishable_')) {
      try {
        final claims =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(
                      base64Url.normalize(testKey.split('.')[1]),
                    ),
                  ),
                )
                as Map;
        if (claims['role'] != 'anon' || claims['ref'] != testRef) {
          throw const FormatException();
        }
      } catch (_) {
        throw StateError(
          'Se requiere una clave pública de pruebas; nunca una clave administrativa',
        );
      }
    } else if (testKey.length < 25) {
      throw StateError('Clave pública de pruebas incompleta');
    }
    // Opaque publishable keys cannot prove their project locally; Auth/API must
    // validate them. The HTTPS host and independent expected ref fix the target.
    return SupabaseEnvironment._(name, 'https://${uri.host}', testKey);
  }
}
