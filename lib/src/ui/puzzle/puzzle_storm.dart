import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_service.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:lichess_mobile/src/model/settings/brightness.dart';
import 'package:lichess_mobile/src/ui/puzzle/puzzle_screen.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/countdown_clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chessground/chessground.dart' as cg;
import 'package:dartchess/dartchess.dart';

import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_providers.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_repository.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_storm.dart';
import 'package:lichess_mobile/src/styles/lichess_colors.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/widgets/adaptive_dialog.dart';
import 'package:lichess_mobile/src/widgets/board_preview.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/utils/chessground_compat.dart';
import "package:lichess_mobile/src/utils/l10n_context.dart";
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';

import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/ui/settings/toggle_sound_button.dart';
import 'package:lichess_mobile/src/widgets/table_board_layout.dart';

class PuzzleStormScreen extends StatelessWidget {
  const PuzzleStormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      androidBuilder: _androidBuilder,
      iosBuilder: _iosBuilder,
    );
  }

  Widget _androidBuilder(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [ToggleSoundButton()],
        title: const Text('Puzzle Storm'),
      ),
      body: const _Load(),
    );
  }

  Widget _iosBuilder(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Puzzle Storm'),
        trailing: ToggleSoundButton(),
      ),
      child: const _Load(),
    );
  }
}

class _Load extends ConsumerWidget {
  const _Load();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storm = ref.watch(stormProvider);
    return storm.when(
      data: (data) {
        return _Body(data: data);
      },
      loading: () => const CenterLoadingIndicator(),
      error: (e, s) {
        debugPrint(
          'SEVERE: [PuzzleStreakScreen] could not load streak; $e\n$s',
        );
        return Center(
          child: TableBoardLayout(
            topTable: kEmptyWidget,
            bottomTable: kEmptyWidget,
            boardData: const cg.BoardData(
              fen: kEmptyFen,
              interactableSide: cg.InteractableSide.none,
              orientation: cg.Side.white,
            ),
            errorMessage: e.toString(),
          ),
        );
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final PuzzleStormResponse data;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stormCtrlProvier = StormCtrlProvider(data.puzzles);
    final puzzleState = ref.watch(stormCtrlProvier);

    puzzleState.clock.timeStream.listen((e) {
      if (e.$1 == Duration.zero && puzzleState.clock.endAt == null) {
        // end function is always called from here
        ref.read(stormCtrlProvier.notifier).end();
        showDialog<void>(
          context: context,
          builder: (context) => _RunStats(ref.watch(stormCtrlProvier).stats!),
        );
      }
    });
    final content = Column(
      children: [
        Expanded(
          child: Center(
            child: SafeArea(
              child: TableBoardLayout(
                boardData: cg.BoardData(
                  onMove: (move, {isPremove}) => ref
                      .read(stormCtrlProvier.notifier)
                      .onUserMove(Move.fromUci(move.uci)!),
                  orientation: puzzleState.pov.cg,
                  interactableSide: puzzleState.position.isGameOver
                      ? cg.InteractableSide.none
                      : puzzleState.pov == Side.white
                          ? cg.InteractableSide.white
                          : cg.InteractableSide.black,
                  fen: puzzleState.position.fen,
                  isCheck: puzzleState.position.isCheck,
                  lastMove: puzzleState.lastMove?.cg,
                  sideToMove: puzzleState.position.turn.cg,
                  validMoves: puzzleState.validMoves,
                ),
                topTable: _TopBar(
                  ctrl: stormCtrlProvier,
                ),
                bottomTable: _Combo(stormCtrlProvier),
              ),
            ),
          ),
        ),
        _BottomBar(stormCtrlProvier),
      ],
    );

    return !puzzleState.clock.isActive
        ? content
        : WillPopScope(
            child: content,
            onWillPop: () async {
              final result = await showAdaptiveDialog<bool>(
                context: context,
                builder: (context) => YesNoDialog(
                  title: const Text('Are you sure?'),
                  content: const Text(
                    'Do you want to end this run?',
                  ),
                  onYes: () {
                    return Navigator.of(context).pop(true);
                  },
                  onNo: () => Navigator.of(context).pop(false),
                ),
              );
              return result ?? false;
            },
          );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.ctrl,
  });

  final StormCtrlProvider ctrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzleState = ref.watch(ctrl);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            LichessIcons.storm,
            size: 50.0,
            color: LichessColors.brag,
          ),
          const SizedBox(width: 8),
          if (!puzzleState.clock.isActive && puzzleState.stats == null)
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.stormMoveToStart,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: LichessColors.brag,
                    ),
                  ),
                  Text(
                    puzzleState.pov == Side.white
                        ? context.l10n.stormYouPlayTheWhitePiecesInAllPuzzles
                        : context.l10n.stormYouPlayTheBlackPiecesInAllPuzzles,
                    style: const TextStyle(color: LichessColors.brag),
                  ),
                ],
              ),
            )
          else
            Text(
              puzzleState.numSolved.toString(),
              style: const TextStyle(
                fontSize: 30.0,
                fontWeight: FontWeight.bold,
                color: LichessColors.brag,
              ),
            ),
          const Spacer(),
          StormClockWidget(ctrl: ctrl),
        ],
      ),
    );
  }
}

class _Combo extends ConsumerStatefulWidget {
  const _Combo(this.ctrl);

  final StormCtrlProvider ctrl;

  @override
  ConsumerState<_Combo> createState() => _ComboState();
}

class _ComboState extends ConsumerState<_Combo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  StormCombo combo = StormCombo();

  static const levels = [3, 5, 7, 10];

  @override
  void initState() {
    super.initState();
    combo = ref.read(widget.ctrl.select((value) => value.combo));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      value: combo.percent() / 100,
    );
  }

  @override
  void didUpdateWidget(covariant _Combo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ctrl != widget.ctrl) {
      combo = StormCombo();
    }
    final newVal = combo.percent() / 100;
    if (_controller.value != newVal) {
      // next lvl reached
      if (_controller.value > newVal && combo.current != 0) {
        if (ref.read(boardPreferencesProvider).hapticFeedback) {
          HapticFeedback.heavyImpact();
        }
        _controller.animateTo(1.0, curve: Curves.easeInOut).then(
          (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            if (mounted) {
              _controller.value = 0;
            }
          },
        );
        return;
      }
      _controller.animateTo(newVal, curve: Curves.easeIn);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lvl = combo.level();
    final indicatorColor = Theme.of(context).colorScheme.secondary;

    final comboShades = generateShades(
      indicatorColor,
      ref.watch(currentBrightnessProvider) == Brightness.light,
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: combo.current.toString(),
                    style: TextStyle(
                      fontSize: 35,
                      fontWeight: FontWeight.bold,
                      color: defaultTargetPlatform == TargetPlatform.iOS
                          ? CupertinoTheme.of(context).textTheme.textStyle.color
                          : null,
                    ),
                  ),
                  TextSpan(
                    text: '\nCombo',
                    style: TextStyle(
                      color: defaultTargetPlatform == TargetPlatform.iOS
                          ? CupertinoTheme.of(context).textTheme.textStyle.color
                          : null,
                    ),
                  )
                ],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 25,
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: _controller.value == 1.0
                            ? [
                                BoxShadow(
                                  color: indicatorColor.withOpacity(0.3),
                                  blurRadius: 10.0,
                                  spreadRadius: 2.0,
                                ),
                              ]
                            : [],
                      ),
                      child: ClipRRect(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(3.0)),
                        child: LinearProgressIndicator(
                          value: _controller.value,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(indicatorColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: levels.mapIndexed((index, level) {
                      final isCurrentLevel = index < lvl;
                      return AnimatedContainer(
                        alignment: Alignment.center,
                        curve: Curves.easeIn,
                        duration: const Duration(milliseconds: 1000),
                        width: 28 * MediaQuery.of(context).textScaleFactor,
                        height: 24 * MediaQuery.of(context).textScaleFactor,
                        decoration: isCurrentLevel
                            ? BoxDecoration(
                                color: comboShades[index],
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(3.0),
                                ),
                              )
                            : null,
                        child: Text(
                          '${level}s',
                          style: TextStyle(
                            color: isCurrentLevel
                                ? Theme.of(context).colorScheme.onSecondary
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Color> generateShades(Color baseColor, bool light) {
    final shades = <Color>[];

    final int r = baseColor.red;
    final int g = baseColor.green;
    final int b = baseColor.blue;

    const int step = 20;

    // Generate darker shades
    for (int i = 4; i >= 2; i = i - 2) {
      final int newR = (r - i * step).clamp(0, 255);
      final int newG = (g - i * step).clamp(0, 255);
      final int newB = (b - i * step).clamp(0, 255);
      shades.add(Color.fromARGB(baseColor.alpha, newR, newG, newB));
    }

    // Generate lighter shades
    for (int i = 2; i <= 3; i++) {
      final int newR = (r + i * step).clamp(0, 255);
      final int newG = (g + i * step).clamp(0, 255);
      final int newB = (b + i * step).clamp(0, 255);
      shades.add(Color.fromARGB(baseColor.alpha, newR, newG, newB));
    }

    if (light) {
      return shades.reversed.toList();
    }

    return shades;
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar(this.ctrl);

  final StormCtrlProvider ctrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzleState = ref.watch(ctrl);
    return Container(
      padding: Styles.horizontalBodyPadding,
      color: defaultTargetPlatform == TargetPlatform.iOS
          ? CupertinoTheme.of(context).barBackgroundColor
          : Theme.of(context).bottomAppBarTheme.color,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            BottomBarButton(
              icon: Icons.delete,
              label: context.l10n.stormNewRun,
              shortLabel: 'New Run',
              highlighted: true,
              showAndroidShortLabel: true,
              onTap: () => ref.invalidate(stormProvider),
            ),
            if (puzzleState.clock.endAt == null)
              BottomBarButton(
                icon: LichessIcons.flag,
                label: context.l10n.stormEndRun,
                highlighted: puzzleState.clock.startAt != null,
                shortLabel: 'End Run',
                showAndroidShortLabel: true,
                onTap: () {
                  if (puzzleState.clock.startAt != null) {
                    puzzleState.clock.sendEnd();
                  }
                },
              ),
            if (puzzleState.stats != null)
              BottomBarButton(
                icon: Icons.open_in_new,
                label: 'Result',
                highlighted: true,
                shortLabel: 'Result',
                showAndroidShortLabel: true,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _RunStats(puzzleState.stats!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RunStats extends StatelessWidget {
  const _RunStats(this.stats);
  final StormRunStats stats;

  @override
  Widget build(BuildContext context) {
    return CupertinoPopupSurface(
      child: defaultTargetPlatform == TargetPlatform.iOS
          ? CupertinoPageScaffold(child: _DialogBody(stats))
          : Scaffold(body: _DialogBody(stats)),
    );
  }
}

class _DialogBody extends ConsumerWidget {
  const _DialogBody(this.stats);

  final StormRunStats stats;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListSection(
            header: Text(context.l10n.stormRaceComplete),
            headerTrailing: IconButton(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(left: 50),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
            children: [
              _StatsRow(
                context.l10n.stormPuzzlesSolved,
                stats.score.toString(),
              ),
              _StatsRow(context.l10n.stormMoves, stats.moves.toString()),
              _StatsRow(
                context.l10n.accuracy,
                '${(((stats.moves - stats.errors) / stats.moves) * 100).toStringAsFixed(2)}%',
              ),
              _StatsRow(
                context.l10n.stormCombo,
                stats.comboBest.toString(),
              ),
              _StatsRow(context.l10n.stormTime, '${stats.time.inSeconds}s'),
              _StatsRow(
                context.l10n.stormTimePerMove,
                '${stats.timePerMove.toStringAsFixed(1)}s',
              ),
              _StatsRow(
                context.l10n.stormHighestSolved,
                stats.highest.toString(),
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          FatButton(
            semanticsLabel: "Play Again",
            onPressed: () {
              ref.invalidate(stormProvider);
              Navigator.of(context).pop();
            },
            child: Text(context.l10n.stormPlayAgain),
          ),
          ListSection(
            header: Text(context.l10n.stormPuzzlesPlayed),
            children: [
              LayoutBuilder(
                builder: (context, constrains) {
                  final crossAxisCount =
                      constrains.maxWidth > kTabletThreshold ? 4 : 2;
                  final boardWidth = constrains.maxWidth / crossAxisCount;
                  final footerHeight = calculateFooterHeight(context);
                  return LayoutGrid(
                    columnSizes: List.generate(crossAxisCount, (_) => 1.fr),
                    rowSizes: List.generate(
                      (stats.history.length / crossAxisCount).ceil(),
                      (_) => auto,
                    ),
                    children: stats.history.map((e) {
                      final (side, fen, lastMove) = e.$1.preview();
                      return SizedBox(
                        width: boardWidth,
                        height: boardWidth + footerHeight,
                        child: BoardPreview(
                          onTap: () async {
                            final session = ref.read(authSessionProvider);
                            Puzzle? puzzle;
                            try {
                              puzzle = await ref
                                  .read(puzzleProvider(e.$1.id).future);
                            } catch (e) {
                              showPlatformSnackbar(context, e.toString());
                            } finally {
                              if (puzzle != null) {
                                pushPlatformRoute(
                                  context,
                                  builder: (_) => PuzzleScreen(
                                    theme: PuzzleTheme.mix,
                                    initialPuzzleContext: PuzzleContext(
                                      theme: PuzzleTheme.mix,
                                      puzzle: puzzle!,
                                      userId: session?.user.id,
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          orientation: side.cg,
                          fen: fen,
                          lastMove: lastMove.cg,
                          footer: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                ColoredBox(
                                  color: e.$2
                                      ? LichessColors.good
                                      : LichessColors.red,
                                  child: Row(
                                    children: [
                                      if (e.$2)
                                        const Icon(
                                          color: Colors.white,
                                          Icons.done,
                                          size: 20,
                                        )
                                      else
                                        const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      Text(
                                        '${e.$3.inSeconds}s',
                                        overflow: TextOverflow.fade,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Text(e.$1.rating.toString()),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  double calculateFooterHeight(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: Theme.of(context).textTheme.bodySmall?.fontSize ?? 14.0,
    );
    final timeTextPainter = TextPainter(
      text: TextSpan(text: "100s", style: textStyle),
      textDirection: TextDirection.ltr,
    );
    timeTextPainter.layout();

    return (timeTextPainter.height) * MediaQuery.of(context).textScaleFactor +
        17.0;
  }
}

class _StatsRow extends StatelessWidget {
  final String label;
  final String? value;

  const _StatsRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          if (value != null) Text(value!),
        ],
      ),
    );
  }
}
