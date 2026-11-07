import 'package:flutter/material.dart';

/// Заглушка для модулів, які ще не реалізовані.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_outlined, size: 56, color: scheme.outline),
              const SizedBox(height: 16),
              Text('Скоро', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                note ?? 'Цей розділ з\'явиться в наступних версіях.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
