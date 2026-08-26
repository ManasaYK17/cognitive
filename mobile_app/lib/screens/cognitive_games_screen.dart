import 'package:flutter/material.dart';
import '../services/cognitive_features_service.dart';

const _games = <Map<String, dynamic>>[
  {'name': 'Memory Game', 'icon': Icons.grid_view, 'color': Colors.blue},
  {'name': 'Attention & Concentration', 'icon': Icons.visibility, 'color': Colors.orange},
  {'name': 'Pattern & Object Recognition', 'icon': Icons.extension, 'color': Colors.green},
  {'name': 'Daily Routine Recall', 'icon': Icons.event_note, 'color': Colors.pink},
];

class CognitiveGamesScreen extends StatelessWidget {
  final int patientId;
  final String sessionToken;
  const CognitiveGamesScreen({required this.patientId, required this.sessionToken, super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _games.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final game = _games[index];
          return SizedBox(
            height: 104,
            child: ElevatedButton.icon(
              icon: Icon(game['icon'] as IconData, size: 38),
              label: Text(game['name'] as String, style: const TextStyle(fontSize: 20)),
              style: ElevatedButton.styleFrom(backgroundColor: game['color'] as Color, alignment: Alignment.centerLeft),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GamePlayScreen(patientId: patientId, sessionToken: sessionToken, gameName: game['name'] as String),
              )),
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
  const GamePlayScreen({required this.patientId, required this.sessionToken, required this.gameName, super.key});
  @override
  State<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends State<GamePlayScreen> {
  final _service = CognitiveFeaturesService();
  int _question = 0;
  int _correct = 0;
  bool _saving = false;
  bool _finished = false;

  List<Map<String, String>> get _questions {
    if (widget.gameName == 'Pattern & Object Recognition') return [
      {'prompt': 'RED  •  BLUE  •  RED  •  BLUE  •  ?', 'answer': 'RED', 'other': 'GREEN'},
      {'prompt': 'STAR  •  CIRCLE  •  STAR  •  CIRCLE  •  ?', 'answer': 'STAR', 'other': 'SQUARE'},
      {'prompt': 'SUN  •  MOON  •  SUN  •  MOON  •  ?', 'answer': 'SUN', 'other': 'CLOUD'},
    ];
    if (widget.gameName == 'Daily Routine Recall') return [
      {'prompt': 'What comes first?', 'answer': 'Wake Up', 'other': 'Lunch'},
      {'prompt': 'What comes after Wake Up?', 'answer': 'Breakfast', 'other': 'Medicine'},
      {'prompt': 'What comes after Breakfast?', 'answer': 'Medicine', 'other': 'Wake Up'},
      {'prompt': 'What comes last?', 'answer': 'Lunch', 'other': 'Breakfast'},
    ];
    if (widget.gameName == 'Attention & Concentration') return [
      {'prompt': 'Find the fruit', 'answer': 'APPLE', 'other': 'CHAIR'},
      {'prompt': 'Find the animal', 'answer': 'CAT', 'other': 'TABLE'},
      {'prompt': 'Find the color', 'answer': 'BLUE', 'other': 'SPOON'},
    ];
    return [
      {'prompt': 'Remember: APPLE, KEY, FLOWER', 'answer': 'APPLE', 'other': 'TRAIN'},
      {'prompt': 'Which object did you see?', 'answer': 'KEY', 'other': 'BOOK'},
      {'prompt': 'Which object did you see?', 'answer': 'FLOWER', 'other': 'CUP'},
    ];
  }

  Future<void> _answer(String answer) async {
    if (_finished) return;
    if (answer == _questions[_question]['answer']) _correct++;
    if (_question + 1 < _questions.length) {
      setState(() => _question++);
    } else {
      setState(() => _finished = true);
      await _save();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.saveGameResult(widget.sessionToken, {
        'game_name': widget.gameName,
        'score': ((_correct / _questions.length) * 100).round(),
        'correct_answers': _correct,
        'total_questions': _questions.length,
      });
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final question = _questions[_question];
    final score = ((_correct / _questions.length) * 100).round();
    return Scaffold(
      appBar: AppBar(title: Text(widget.gameName)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _finished
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.check_circle, size: 84, color: Colors.green),
                const SizedBox(height: 20),
                Text('Your score: $score', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(_saving ? 'Saving score...' : 'Well done!', style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 28),
                ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to games', style: TextStyle(fontSize: 20))),
              ]))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Question ${_question + 1} of ${_questions.length}', style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 36),
                Expanded(child: Center(child: Text(question['prompt']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)))),
                _answerButton(question['answer']!),
                const SizedBox(height: 16),
                _answerButton(question['other']!),
              ]),
      ),
    );
  }

  Widget _answerButton(String label) => SizedBox(height: 72, child: ElevatedButton(onPressed: () => _answer(label), child: Text(label, style: const TextStyle(fontSize: 24))));
}
