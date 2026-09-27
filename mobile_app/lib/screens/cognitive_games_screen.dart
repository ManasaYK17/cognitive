import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_language.dart';
import '../services/cognitive_features_service.dart';

const _games = <Map<String, dynamic>>[
  {'name': 'Sequence Memory', 'icon': Icons.repeat, 'color': Colors.indigo},
  {'name': 'Image Matching', 'icon': Icons.image_search, 'color': Colors.teal},
  {'name': 'Missing Card Memory', 'icon': Icons.grid_on_rounded, 'color': Colors.deepOrange},
  {'name': 'Daily Routine Recall', 'icon': Icons.event_note, 'color': Colors.pink},
];

const _missingCardDistractors = ['🍌', '⚽', '🐟'];

const _gameNameKeys = {
  'Sequence Memory': 'game_sequence_memory',
  'Image Matching': 'game_image_matching',
  'Missing Card Memory': 'game_missing_card_memory',
  'Daily Routine Recall': 'game_daily_routine_recall',
};

const _routineActivityKeys = {
  'Wake Up': 'routine_wake_up',
  'Brush': 'routine_brush',
  'Breakfast': 'routine_breakfast',
  'Medicine': 'routine_medicine',
  'Walk': 'routine_walk',
  'Rest': 'routine_rest',
};

String _translateGameText(String key, {Map<String, String> values = const {}}) {
  var text = AppLanguage().translate(key);
  for (final entry in values.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value);
  }
  return text;
}

String _localizedGameName(String name) =>
    _translateGameText(_gameNameKeys[name] ?? 'game_unavailable');

String _localizedRoutineActivity(String activity) =>
    _translateGameText(_routineActivityKeys[activity] ?? activity);

class CognitiveGamesScreen extends StatelessWidget {
  final int patientId;
  final String sessionToken;

  const CognitiveGamesScreen({
    required this.patientId,
    required this.sessionToken,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: _games.length,
      itemBuilder: (context, index) {
        final game = _games[index];

        return Card(
          color: game['color'] as Color,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GamePlayScreen(
                  patientId: patientId,
                  sessionToken: sessionToken,
                  gameName: game['name'] as String,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(game['icon'] as IconData, size: 32, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(
                    _localizedGameName(game['name'] as String),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class GamePlayScreen extends StatefulWidget {
  final int patientId;
  final String sessionToken;
  final String gameName;

  const GamePlayScreen({
    required this.patientId,
    required this.sessionToken,
    required this.gameName,
    super.key,
  });

  @override
  State<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _MemoryCard {
  _MemoryCard({
    required this.id,
    required this.value,
    required this.pairId,
  });

  final int id;
  final String value;
  final int pairId;
  bool revealed = false;
  bool matched = false;
}

class _RoutineQuestion {
  const _RoutineQuestion({
    required this.questionKey,
    required this.options,
    required this.answer,
    this.activity,
  });

  final String questionKey;
  final List<String> options;
  final String answer;
  final String? activity;
}

class _GamePlayScreenState extends State<GamePlayScreen> {
  final _service = CognitiveFeaturesService();

  bool _loading = true;
  bool _finished = false;
  bool _gameStarted = false;
  bool _savingResult = false;
  bool _scoreSaved = false;
  String? _scoreSaveError;
  int _difficultyLevel = 1;
  int _correctAnswers = 0;
  int _incorrectAnswers = 0;
  int _totalAttempts = 0;
  int _questionIndex = 0;

  String? _feedbackMessage;

  List<_MemoryCard> _sequenceCards = const [];
  int _sequenceTarget = 1;
  int _sequenceGridSize = 3;

  List<_MemoryCard> _matchingCards = const [];
  List<int> _selectedImageIndices = const [];
  bool _imageSelectionLocked = false;
  final List<String> _matchingPairs = [
    '🍎',
    '🚗',
    '🏠',
    '📖',
    '☕',
    '🌳',
  ];

  List<_MemoryCard> _missingCards = const [];
  int _missingCardPosition = -1;
  List<String> _missingChoices = const [];

  List<String> _routineActivities = const [];
  List<_RoutineQuestion> _routineQuestions = const [];

  @override
  void initState() {
    super.initState();
    _loadPreviousPerformanceAndBuildGame();
  }

  Future<void> _loadPreviousPerformanceAndBuildGame() async {
    try {
      final results = await _service.getGameResults(widget.sessionToken, widget.patientId);
      final sameGameResults = results.where((item) => item['game_name'] == widget.gameName).toList();
      final suggestedLevel = _determineDifficultyLevel(sameGameResults);
      _setupGame(suggestedLevel);
    } catch (_) {
      _setupGame(1);
    }
  }

  int _determineDifficultyLevel(List<dynamic> sameGameResults) {
    if (sameGameResults.isEmpty) {
      return 1;
    }

    final recent = sameGameResults.take(3).toList();
    final accuracies = <double>[];

    for (final result in recent) {
      final correct = result['correct_answers'] as int? ?? 0;
      final total = result['total_questions'] as int? ?? 1;
      final accuracy = total <= 0 ? 0.0 : (correct / total) * 100;
      accuracies.add(accuracy);
    }

    final averageAccuracy = accuracies.isEmpty
        ? 0.0
        : accuracies.reduce((a, b) => a + b) / accuracies.length;

    if (averageAccuracy >= 80) {
      return 4;
    }
    if (averageAccuracy >= 60) {
      return 3;
    }
    if (averageAccuracy >= 40) {
      return 2;
    }
    return 1;
  }

  void _setupGame(int level) {
    if (!mounted) return;
    _difficultyLevel = level;
    _correctAnswers = 0;
    _incorrectAnswers = 0;
    _totalAttempts = 0;
    _questionIndex = 0;
    _feedbackMessage = null;

    switch (widget.gameName) {
      case 'Sequence Memory':
        _buildSequenceGame();
        break;
      case 'Image Matching':
        _buildImageMatchingGame(level);
        break;
      case 'Missing Card Memory':
        _buildMissingCardGame(level);
        break;
      case 'Daily Routine Recall':
        _buildRoutineGame(level);
        break;
    }

    setState(() {
      _gameStarted = false;
      _finished = false;
      _loading = false;
    });
  }

  void _buildSequenceGame() {
    const totalCards = 9;
    const gridSize = 3;
    final values = List<int>.generate(totalCards, (index) => index + 1)..shuffle();

    _sequenceCards = List<_MemoryCard>.generate(
      values.length,
      (index) => _MemoryCard(
        id: index,
        value: values[index].toString(),
        pairId: values[index],
      ),
    );

    _sequenceGridSize = gridSize;
    _sequenceTarget = 1;
  }

  void _buildImageMatchingGame(int level) {
    final pairs = level >= 4
        ? [
            '🍎',
            '🍋',
            '🚗',
            '🚌',
            '🏠',
            '📖',
          ]
        : _matchingPairs;

    final cards = <_MemoryCard>[];
    for (int pairIndex = 0; pairIndex < pairs.length; pairIndex++) {
      final label = pairs[pairIndex];
      cards.add(_MemoryCard(id: pairIndex * 2, value: label, pairId: pairIndex));
      cards.add(_MemoryCard(id: pairIndex * 2 + 1, value: label, pairId: pairIndex));
    }

    cards.shuffle();
    _matchingCards = cards;
    _selectedImageIndices = [];
    _imageSelectionLocked = false;
  }

  void _buildMissingCardGame(int level) {
    final imagePool = [
      '🍎',
      '🍋',
      '🍇',
      '🚗',
      '🚌',
      '🏠',
      '📖',
      '☕',
      '🌳',
    ];

    imagePool.shuffle();

    final cards = <_MemoryCard>[];
    for (int i = 0; i < 9; i++) {
      cards.add(_MemoryCard(id: i, value: imagePool[i], pairId: i));
    }

    _missingCards = cards;
    _missingCardPosition = 4;
    final missingValue = imagePool[_missingCardPosition];
    _missingChoices = [missingValue, ..._missingCardDistractors]..shuffle();
  }

  void _buildRoutineGame(int level) {
    final routineSize = switch (level) {
      1 => 3,
      2 => 4,
      3 => 5,
      _ => 6,
    };

    final baseActivities = [
      'Wake Up',
      'Brush',
      'Breakfast',
      'Medicine',
      'Walk',
      'Rest',
    ];

    _routineActivities = baseActivities.take(routineSize).toList();

    _routineQuestions = [
      _RoutineQuestion(
        questionKey: 'routine_after',
        activity: _routineActivities[1],
        options: _routineActivities.length > 2
            ? [
                _routineActivities[2],
                _routineActivities[0],
                _routineActivities[1],
              ]
            : const [],
        answer: _routineActivities[2],
      ),
      _RoutineQuestion(
        questionKey: 'routine_before',
        activity: _routineActivities[2],
        options: _routineActivities.length > 2
            ? [
                _routineActivities[1],
                _routineActivities.length > 3 ? _routineActivities[3] : _routineActivities[2],
                _routineActivities[0],
              ]
            : const [],
        answer: _routineActivities[1],
      ),
      _RoutineQuestion(
        questionKey: 'routine_first',
        options: _routineActivities
            .map((item) => item)
            .toList()
          ..shuffle(),
        answer: _routineActivities.first,
      ),
    ];
  }

  int _calculateScore(int correct, int total) {
    if (total <= 0) return 0;
    final normalizedCorrect = correct.clamp(0, total);
    return ((normalizedCorrect / total) * 100).round();
  }

  Future<void> _finishSession() async {
    if (_finished) return;

    setState(() {
      _finished = true;
    });
    await _saveResult();
  }

  Future<void> _saveResult() async {
    if (_savingResult) return;
    final totalAttempts = _totalAttempts > _correctAnswers ? _totalAttempts : _correctAnswers;
    final denominator = totalAttempts > 0 ? totalAttempts : 1;
    final safeCorrectAnswers = _correctAnswers.clamp(0, denominator);
    final score = _calculateScore(safeCorrectAnswers, denominator);
    setState(() {
      _savingResult = true;
      _scoreSaveError = null;
    });

    try {
      await _service.saveGameResult(widget.sessionToken, {
        'game_name': widget.gameName,
        'score': score,
        'correct_answers': safeCorrectAnswers,
        'total_questions': denominator,
      });
      if (!mounted) return;
      setState(() => _scoreSaved = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _scoreSaveError = 'Could not send this result to your caregiver. Check the connection and retry.');
    } finally {
      if (mounted) setState(() => _savingResult = false);
    }
  }

  void _startGame() {
    setState(() {
      _gameStarted = true;
      _feedbackMessage = null;
      _selectedImageIndices = [];
    });
  }

  void _onSequenceCardTap(int index) {
    if (!_gameStarted || _finished || _sequenceCards[index].revealed) {
      return;
    }

    final tappedValue = int.tryParse(_sequenceCards[index].value) ?? 0;
    _totalAttempts++;

    if (tappedValue == _sequenceTarget) {
      setState(() {
        _sequenceCards[index].revealed = true;
        _correctAnswers++;
        _sequenceTarget++;
        _feedbackMessage = _sequenceTarget <= _sequenceCards.length
          ? _translateGameText('sequence_find', values: {'number': '$_sequenceTarget'})
          : _translateGameText('sequence_completed');
      });

      if (_sequenceTarget > _sequenceCards.length) {
        _finishSession();
      }
      return;
    }

    setState(() {
      _incorrectAnswers++;
      _feedbackMessage = _translateGameText('game_try_again');
    });
  }

  Future<void> _onImageCardTap(int index) async {
    if (!_gameStarted || _finished || _imageSelectionLocked) {
      return;
    }

    final card = _matchingCards[index];
    if (card.revealed || card.matched) {
      return;
    }

    setState(() {
      card.revealed = true;
      _selectedImageIndices = [..._selectedImageIndices, index];
    });

    if (_selectedImageIndices.length < 2) {
      return;
    }

    _imageSelectionLocked = true;
    _totalAttempts++;

    final firstIndex = _selectedImageIndices[0];
    final secondIndex = _selectedImageIndices[1];
    final firstCard = _matchingCards[firstIndex];
    final secondCard = _matchingCards[secondIndex];

    final matched = firstCard.pairId == secondCard.pairId;

    if (matched) {
      setState(() {
        firstCard.matched = true;
        secondCard.matched = true;
        _correctAnswers++;
        _feedbackMessage = _translateGameText('image_match');
      });

      if (_correctAnswers >= _matchingPairs.length) {
        await _finishSession();
        return;
      }
    } else {
      setState(() {
        _incorrectAnswers++;
        _feedbackMessage = _translateGameText('image_not_match');
      });
    }

    await Future.delayed(const Duration(milliseconds: 650));

    if (!mounted) {
      return;
    }

    setState(() {
      if (!matched) {
        firstCard.revealed = false;
        secondCard.revealed = false;
      }
      _selectedImageIndices = [];
      _imageSelectionLocked = false;
        _feedbackMessage = matched
          ? _translateGameText('game_great_job')
          : _translateGameText('game_try_again');
    });
  }

  void _onMissingChoiceTap(String choice) {
    if (!_gameStarted || _finished) {
      return;
    }

    _totalAttempts++;
    final missingValue = _missingCards[_missingCardPosition].value;

    if (choice == missingValue) {
      setState(() {
        _correctAnswers++;
        _feedbackMessage = _translateGameText('game_correct');
      });
      _finishSession();
      return;
    }

    setState(() {
      _incorrectAnswers++;
      _feedbackMessage = _translateGameText('game_try_again');
    });
  }

  void _onRoutineAnswer(String answer) {
    if (!_gameStarted || _finished) {
      return;
    }

    final currentQuestion = _routineQuestions[_questionIndex];

    setState(() {
      _totalAttempts++;
      if (answer == currentQuestion.answer) {
        _correctAnswers++;
        _feedbackMessage = _translateGameText('game_correct');
      } else {
        _incorrectAnswers++;
        _feedbackMessage = _translateGameText('routine_not_quite');
      }
    });

    if (_questionIndex < _routineQuestions.length - 1) {
      setState(() {
        _questionIndex++;
        _feedbackMessage = _translateGameText('routine_next_question');
      });
      return;
    }

    _finishSession();
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<AppLanguage>(context);
    final gameTitle = _localizedGameName(widget.gameName);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(gameTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_finished) {
      final totalAttempts = _totalAttempts > _correctAnswers ? _totalAttempts : _correctAnswers;
      final accuracy = totalAttempts == 0 ? 0.0 : (_correctAnswers / totalAttempts) * 100;

      return Scaffold(
        appBar: AppBar(title: Text(gameTitle)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, size: 80, color: Colors.green),
                    const SizedBox(height: 20),
                    Text(
                      _translateGameText('game_completed'),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _translateGameText('game_label', values: {'game': gameTitle}),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _translateGameText('accuracy_label', values: {'accuracy': accuracy.toStringAsFixed(0)}),
                      style: const TextStyle(fontSize: 20),
                    ),
                    Text(
                      _translateGameText('correct_attempts_label', values: {
                        'correct': '$_correctAnswers',
                        'attempts': '$totalAttempts',
                      }),
                      style: const TextStyle(fontSize: 20),
                    ),
                    Text(
                      _translateGameText('errors_label', values: {'errors': '$_incorrectAnswers'}),
                      style: const TextStyle(fontSize: 20),
                    ),
                    Text(
                      _translateGameText('attempts_label', values: {'attempts': '$_totalAttempts'}),
                      style: const TextStyle(fontSize: 20),
                    ),
                    Text(
                      _translateGameText('difficulty_label', values: {'level': '$_difficultyLevel'}),
                      style: const TextStyle(fontSize: 20),
                    ),
                    if (_savingResult) ...[
                      const SizedBox(height: 12),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(_translateGameText('sending_result')),
                    ] else if (_scoreSaveError != null) ...[
                      const SizedBox(height: 12),
                      Text(_translateGameText('score_save_failed'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(onPressed: _saveResult, icon: const Icon(Icons.refresh), label: Text(_translateGameText('retry'))),
                    ] else if (_scoreSaved) ...[
                      const SizedBox(height: 12),
                      Text(_translateGameText('result_sent')),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(_translateGameText('back_to_games'), style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.gameName)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildCurrentGameBody(),
      ),
    );
  }

  Widget _buildCurrentGameBody() {
    switch (widget.gameName) {
      case 'Sequence Memory':
        return _gameStarted ? _buildSequencePlayCard() : _buildSequenceObservationCard();
      case 'Image Matching':
        return _gameStarted ? _buildImageMatchingPlayCard() : _buildImageMatchingObservationCard();
      case 'Missing Card Memory':
        return _gameStarted ? _buildMissingCardPlayCard() : _buildMissingCardObservationCard();
      case 'Daily Routine Recall':
        return _gameStarted ? _buildRoutinePlayCard() : _buildRoutineObservationCard();
      default:
        return Center(child: Text(_translateGameText('game_unavailable')));
    }
  }

  Widget _buildSequenceObservationCard() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _translateGameText('sequence_observe', values: {'number': '${_sequenceCards.length}'}),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              _buildSequenceGrid(revealAll: true),
              const SizedBox(height: 22),
              SizedBox(
                height: 72,
                child: ElevatedButton(
                  onPressed: _startGame,
                  child: Text(_translateGameText('game_start'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSequencePlayCard() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _translateGameText('sequence_find', values: {'number': '$_sequenceTarget'}),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (_feedbackMessage != null)
                Text(
                  _feedbackMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 18),
              _buildSequenceGrid(revealAll: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSequenceGrid({required bool revealAll}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _sequenceGridSize,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _sequenceCards.length,
      itemBuilder: (context, index) {
        final card = _sequenceCards[index];
        final showNumber = revealAll || card.revealed;

        return Card(
          color: showNumber ? Colors.white : Colors.blue.shade100,
          child: InkWell(
            onTap: () => _onSequenceCardTap(index),
            child: Center(
              child: Text(
                showNumber ? card.value : '?',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageMatchingObservationCard() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                Text(
                  _translateGameText('image_observe'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              _buildImageMatchingGrid(revealAll: true),
              const SizedBox(height: 22),
              SizedBox(
                height: 72,
                child: ElevatedButton(
                  onPressed: _startGame,
                  child: Text(_translateGameText('game_start'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageMatchingPlayCard() {
    return Center(
      child: Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _translateGameText('image_open_pair'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              if (_feedbackMessage != null)
                Text(
                  _feedbackMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 18),
              _buildImageMatchingGrid(revealAll: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageMatchingGrid({required bool revealAll}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _matchingCards.length,
      itemBuilder: (context, index) {
        final card = _matchingCards[index];
        final showValue = revealAll || card.revealed || card.matched;

        return Card(
          color: card.matched
              ? Colors.green.shade200
              : (showValue ? Colors.white : Colors.blue.shade100),
          child: InkWell(
            onTap: () => _onImageCardTap(index),
            child: Center(
              child: Text(
                showValue ? card.value : '?',
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMissingCardObservationCard() {
    return Center(
      child: Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _translateGameText('missing_observe'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              _buildMissingCardGrid(showAll: true),
              const SizedBox(height: 22),
              SizedBox(
                height: 72,
                child: ElevatedButton(
                  onPressed: _startGame,
                  child: Text(_translateGameText('game_start'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMissingCardPlayCard() {
    return Center(
      child: Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _translateGameText('missing_question'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              _buildMissingCardGrid(showAll: false),
              const SizedBox(height: 20),
              if (_feedbackMessage != null)
                Text(
                  _feedbackMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: _missingChoices
                    .map(
                      (choice) => SizedBox(
                        width: 140,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () => _onMissingChoiceTap(choice),
                          child: Text(choice, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMissingCardGrid({required bool showAll}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.1,
      ),
      itemCount: _missingCards.length,
      itemBuilder: (context, index) {
        final card = _missingCards[index];
        final isMissing = showAll ? false : index == _missingCardPosition;

        return Card(
          color: isMissing ? Colors.grey.shade200 : Colors.blue.shade100,
          child: Center(
            child: Text(
              isMissing ? '' : card.value,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoutineObservationCard() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _translateGameText('routine_observe'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              Column(
                children: [
                  for (int index = 0; index < _routineActivities.length; index++)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${index + 1}. ${_localizedRoutineActivity(_routineActivities[index])}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 72,
                child: ElevatedButton(
                  onPressed: _startGame,
                  child: Text(_translateGameText('game_start'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoutinePlayCard() {
    final currentQuestion = _routineQuestions[_questionIndex];
    final questionValues = currentQuestion.activity == null
        ? const <String, String>{}
        : {'activity': _localizedRoutineActivity(currentQuestion.activity!)};

    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _translateGameText(currentQuestion.questionKey, values: questionValues),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              if (_feedbackMessage != null)
                Text(
                  _feedbackMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 18),
              ...currentQuestion.options.map(
                (option) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () => _onRoutineAnswer(option),
                      child: Text(_localizedRoutineActivity(option), style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
