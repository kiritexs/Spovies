import 'package:envied/envied.dart';

part 'env.g.dart';

/// Environment variables loaded at compile time via `envied`.
///
/// Create a `.env` file at project root with:
/// ```
/// TMDB_READ_ACCESS_TOKEN=your_token_here
/// ```
///
/// Then run: `dart run build_runner build`
@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'TMDB_READ_ACCESS_TOKEN', obfuscate: true)
  static final String tmdbApiKey = _Env.tmdbApiKey;
}
