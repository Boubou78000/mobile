import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/account/ongoing_game.dart';
import 'package:lichess_mobile/src/model/auth/auth_session.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/user/user_repository.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_repository.g.dart';

@riverpod
Future<User?> account(Ref ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) return null;

  return ref.withClientCacheFor(
    (client) => AccountRepository(client).getProfile(),
    const Duration(hours: 1),
  );
}

@riverpod
Future<LightUser?> accountUser(Ref ref) async {
  return ref.watch(accountProvider.selectAsync((user) => user?.lightUser));
}

@riverpod
Future<IList<UserActivity>> accountActivity(Ref ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) return IList();
  return ref.withClientCacheFor(
    (client) => UserRepository(client).getActivity(session.user.id),
    const Duration(hours: 1),
  );
}

@riverpod
Future<IList<OngoingGame>> ongoingGames(Ref ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) return IList();

  return ref.withClientCacheFor(
    (client) => AccountRepository(client).getOngoingGames(nb: 20),
    const Duration(hours: 1),
  );
}

@Riverpod(keepAlive: true)
AccountService accountService(Ref ref) {
  return AccountService(ref);
}

class AccountService {
  const AccountService(this._ref);

  final Ref _ref;

  Future<void> setGameBookmark(GameId id, {required bool bookmark}) async {
    final session = _ref.read(authSessionProvider);
    if (session == null) return;

    await _ref.withClient((client) => AccountRepository(client).bookmark(id, bookmark: bookmark));

    _ref.invalidate(accountProvider);
  }
}

class AccountRepository {
  AccountRepository(this.client);

  final LichessClient client;
  final Logger _log = Logger('AccountRepository');

  Future<User> getProfile() {
    return client.readJson(Uri(path: '/api/account'), mapper: User.fromServerJson);
  }

  Future<void> saveProfile(Map<String, String> profile) async {
    final uri = Uri(path: '/account/profile');
    final response = await client.post(uri, headers: {'Accept': 'application/json'}, body: profile);

    if (response.statusCode >= 400) {
      throw http.ClientException('Failed to post save profile: ${response.statusCode}', uri);
    }
  }

  Future<IList<OngoingGame>> getOngoingGames({int? nb}) {
    return client.readJson(
      Uri(path: '/api/account/playing', queryParameters: nb != null ? {'nb': nb.toString()} : null),
      mapper: (Map<String, dynamic> json) {
        final list = json['nowPlaying'];
        if (list is! List<dynamic>) {
          _log.severe('Could not read json object as {nowPlaying: []}: expected a list.');
          throw Exception('Could not read json object as {nowPlaying: []}');
        }
        return list
            .map((e) => _ongoingGameFromJson(e as Map<String, dynamic>))
            .where((e) => e.variant.isReadSupported)
            .toIList();
      },
    );
  }

  Future<AccountPrefState> getPreferences() {
    return client.readJson(
      Uri(path: '/api/account/preferences'),
      mapper: (Map<String, dynamic> json) {
        return _accountPreferencesFromPick(pick(json, 'prefs').required());
      },
    );
  }

  Future<void> setPreference<T>(String prefKey, AccountPref<T> pref) async {
    final uri = Uri(path: '/api/account/preferences/$prefKey');

    final response = await client.post(uri, body: {prefKey: pref.toFormData});

    if (response.statusCode >= 400) {
      throw http.ClientException('Failed to set preference: ${response.statusCode}', uri);
    }
  }

  /// Bookmark the game for the given `id` if `bookmark` is true else unbookmark it
  Future<void> bookmark(GameId id, {required bool bookmark}) async {
    final uri = Uri(path: '/bookmark/$id', queryParameters: {'v': bookmark ? '1' : '0'});
    final response = await client.post(uri);
    if (response.statusCode >= 400) {
      throw http.ClientException('Failed to bookmark game: ${response.statusCode}', uri);
    }
  }
}

AccountPrefState _accountPreferencesFromPick(RequiredPick pick) {
  return (
    zenMode: Zen.fromInt(pick('zen').asIntOrThrow()),
    pieceNotation: PieceNotation.fromInt(pick('pieceNotation').asIntOrThrow()),
    showRatings: ShowRatings.fromInt(pick('ratings').asIntOrThrow()),
    premove: BooleanPref(pick('premove').asBoolOrThrow()),
    autoQueen: AutoQueen.fromInt(pick('autoQueen').asIntOrThrow()),
    autoThreefold: AutoThreefold.fromInt(pick('autoThreefold').asIntOrThrow()),
    takeback: Takeback.fromInt(pick('takeback').asIntOrThrow()),
    moretime: Moretime.fromInt(pick('moretime').asIntOrThrow()),
    clockSound: BooleanPref(pick('clockSound').asBoolOrThrow()),
    confirmResign: BooleanPref.fromInt(pick('confirmResign').asIntOrThrow()),
    submitMove: SubmitMove.fromInt(pick('submitMove').asIntOrThrow()),
    follow: BooleanPref(pick('follow').asBoolOrThrow()),
    challenge: Challenge.fromInt(pick('challenge').asIntOrThrow()),
  );
}

OngoingGame _ongoingGameFromJson(Map<String, dynamic> json) {
  return _ongoingGameFromPick(pick(json).required());
}

OngoingGame _ongoingGameFromPick(RequiredPick pick) {
  return OngoingGame(
    id: GameId(pick('gameId').asStringOrThrow()),
    fullId: GameFullId(pick('fullId').asStringOrThrow()),
    orientation: pick('color').asSideOrThrow(),
    fen: pick('fen').asStringOrThrow(),
    lastMove: pick('lastMove').asUciMoveOrNull(),
    perf: pick('perf').asPerfOrThrow(),
    speed: pick('speed').asSpeedOrThrow(),
    variant: pick('variant').asVariantOrThrow(),
    opponent: pick('opponent').asLightUserOrNull(),
    opponentRating: pick('opponent', 'rating').asIntOrNull(),
    opponentAiLevel: pick('opponent', 'aiLevel').asIntOrNull(),
    secondsLeft: pick('secondsLeft').asIntOrNull(),
    isMyTurn: pick('isMyTurn').asBoolOrThrow(),
  );
}
