import 'package:flutter/material.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  static const List<({String question, String answer})> _items = [
    (
      question: 'What is MrPlay?',
      answer:
          'MrPlay is a video hub that brings your favorite video websites '
          'together in one convenient place, with a built-in browser and '
          'player tools like background audio and a sleep timer.',
    ),
    (
      question: 'Is MrPlay free?',
      answer:
          'Yes. MrPlay is completely free to use and is supported by ads.',
    ),
    (
      question: 'Do you collect my personal data?',
      answer:
          'We keep data collection to a minimum. Your watch history is '
          'stored only on your device and you can clear it at any time '
          'from Settings.',
    ),
    (
      question: 'How do I add my own websites?',
      answer:
          'On the Hub page, tap the Add card, enter a name and a URL, and '
          'your shortcut will appear in the grid. Long-press a custom '
          'shortcut to remove it.',
    ),
    (
      question: 'How does background audio work?',
      answer:
          'Enable Background audio in Settings → Privacy & Security → '
          'Toggles to keep listening when you switch apps or lock your '
          'screen.',
    ),
    (
      question: "Why won't some videos play?",
      answer:
          'Playback depends on each website. Some sites restrict certain '
          'content, block specific regions, or require signing in to an '
          'account before playing their videos.',
    ),
    (
      question: 'How do I report a bug or suggest a feature?',
      answer:
          'Go to Settings → Contact Us and send us an email. We read every '
          'message and use your feedback to improve MrPlay.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAQ'),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return ExpansionTile(
            leading: const Icon(Icons.help_outline),
            title: Text(item.question),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.answer,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          );
        },
      ),
    );
  }
}
