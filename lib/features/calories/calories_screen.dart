import 'package:flutter/material.dart';

class CaloriesScreen extends StatelessWidget {
  const CaloriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calories')),
      body: const Center(child: Text('Recorded calories and statistics (Phase 5).')),
    );
  }
}
