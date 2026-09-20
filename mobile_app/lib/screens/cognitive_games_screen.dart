import 'package:flutter/material.dart';
import '../services/cognitive_features_service.dart';

const _games = <Map<String, dynamic>>[
  {'name': 'Sequence Memory', 'icon': Icons.repeat, 'color': Colors.indigo},
  {'name': 'Image Matching', 'icon': Icons.image_search, 'color': Colors.teal},
  {'name': 'Missing Card Memory', 'icon': Icons.grid_on_rounded, 'color': Colors.deepOrange},
  {'name': 'Daily Routine Recall', 'icon': Icons.event_note, 'color': Colors.pink},
];

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
        childAspectRatio: 1.05,
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
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(game['icon'] as IconData, size: 42, color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    game['name'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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
    required this.question,
    required this.options,
    required this.answer,
  });

  final String question;
  final List<String> options;
  final String answer;
}

class _GamePlayScreenState extends State<GamePlayScreen> {
  final _service = CognitiveFeaturesService();

  bool _loading = true;
  bool _finished = false;
  bool _gameStarted = false;
  int _difficultyLevel = 1;
  int _correctAnswers = 0;
  int _incorrectAnswers = 0;
  int _wrongSelections = 0;
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
  int _missingAttempts = 0;

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
    _difficultyLevel = level;
    _correctAnswers = 0;
    _incorrectAnswers = 0;
    _wrongSelections = 0;
    _totalAttempts = 0;
    _questionIndex = 0;
    _feedbackMessage = null;

    switch (widget.gameName) {
      case 'Sequence Memory':
        _buildSequenceGame(level);
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

  void _buildSequenceGame(int level) {
    final gridSize = level >= 4 ? 4 : 3;
    final totalCards = gridSize * gridSize;
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
    _missingChoices = [
      imagePool[0],
      imagePool[1],
      imagePool[2],
      imagePool[3],
    ];

    final missingValue = imagePool[_missingCardPosition];
    _missingChoices = _missingChoices.toSet().toList()..shuffle();
    if (!_missingChoices.contains(missingValue)) {
      _missingChoices[0] = missingValue;
    }
    _missingChoices = _missingChoices.take(4).toList()..shuffle();
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
        question: 'What comes after ${_routineActivities[1]}?',
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
        question: 'What comes before ${_routineActivities[2]}?',
        options: _routineActivities.length > 2
            ? [
                _routineActivities[1],
                _routineActivities[3],
                _routineActivities[0],
              ]
            : const [],
        answer: _routineActivities[1],
      ),
      _RoutineQuestion(
        question: 'What is the first activity?',
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
    final totalQuestions = _getTotalQuestions();
    final safeCorrectAnswers = _correctAnswers.clamp(0, totalQuestions);
    final score = _calculateScore(safeCorrectAnswers, totalQuestions);

    setState(() {
      _finished = true;
    });

    try {
      await _service.saveGameResult(widget.sessionToken, {
        'game_name': widget.gameName,
        'score': score,
        'correct_answers': safeCorrectAnswers,
        'total_questions': totalQuestions,
      });
    } catch (_) {}
  }

  int _getTotalQuestions() {
    switch (widget.gameName) {
      case 'Sequence Memory':
        return _sequenceCards.length;
      case 'Image Matching':
        return _matchingPairs.length;
      case 'Missing Card Memory':
        return 1;
      case 'Daily Routine Recall':
        return _routineQuestions.length;
      default:
        return 1;
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
            ? 'Find ${_sequenceTarget}'
            : 'Sequence Completed!';
      });

      if (_sequenceTarget > _sequenceCards.length) {
        _finishSession();
      }
      return;
    }

    setState(() {
      _incorrectAnswers++;
      _wrongSelections++;
      _feedbackMessage = 'Try again';
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
        _feedbackMessage = 'Match!';
      });

      if (_correctAnswers >= _matchingPairs.length) {
        await _finishSession();
        return;
      }
    } else {
      setState(() {
        _incorrectAnswers++;
        _wrongSelections++;
        _feedbackMessage = 'Not a match';
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
      _feedbackMessage = matched ? 'Great job!' : 'Try again';
    });
  }

  void _onMissingChoiceTap(String choice) {
    if (!_gameStarted || _finished) {
      return;
    }

    _missingAttempts++;
    final missingValue = _missingCards[_missingCardPosition].value;

    if (choice == missingValue) {
      setState(() {
        _correctAnswers++;
        _feedbackMessage = 'Correct!';
      });
      _finishSession();
      return;
    }

    setState(() {
      _incorrectAnswers++;
      _wrongSelections++;
      _feedbackMessage = 'Try again';
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
        _feedbackMessage = 'Correct!';
      } else {
        _incorrectAnswers++;
        _feedbackMessage = 'Not quite';
      }
    });

    if (_questionIndex < _routineQuestions.length - 1) {
      setState(() {
        _questionIndex++;
        _feedbackMessage = 'Next question';
      });
      return;
    }

    _finishSession();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.gameName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_finished) {
      final totalQuestions = _getTotalQuestions();
      final accuracy = totalQuestions == 0 ? 0.0 : (_correctAnswers / totalQuestions) * 100;

      return Scaffold(
        appBar: AppBar(title: Text(widget.gameName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, size: 80, color: Colors.green),
                    const SizedBox(height: 20),
                    Text(
                      'Game completed',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Game: ${widget.gameName}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Accuracy: ${accuracy.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 20),
                    ),
                    Text(
                      'Correct: $_correctAnswers/$totalQuestions',
                      style: const TextStyle(fontSize: 20),
                    ),
                    Text(
                      'Errors: $_incorrectAnswers',
                      style: const TextStyle(fontSize: 20),
                    ),
                    Text(
                      'Attempts: $_totalAttempts',
                      style: const TextStyle(fontSize: 20),
                    ),
                    Text(
                      'Difficulty: Level $_difficultyLevel',
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back to games', style: TextStyle(fontSize: 20)),
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
        return const Center(child: Text('Game unavailable'));
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
                'Remember where each number is located.\nOpen the numbers in order from 1 to ${_sequenceCards.length}.',
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
                  child: const Text('START', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
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
                'Find ${_sequenceTarget}',
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
              const Text(
                'Remember the card locations and the matching pairs.',
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
                  child: const Text('START', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Open one card, then another card.',
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Remember all the cards.\nOne card will be missing.',
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
                  child: const Text('START', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Which card is missing?',
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
              const Text(
                'Observe the routine below carefully.',
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
                          '${index + 1}. ${_routineActivities[index]}',
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
                  child: const Text('START', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
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

    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                currentQuestion.question,
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
                      child: Text(option, style: const TextStyle(fontSize: 20)),
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
