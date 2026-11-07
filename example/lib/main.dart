import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

/// Demo app for `modern_chess_board`. Filled in as features land.
class ExampleApp extends StatelessWidget {
  /// Creates the demo app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Modern Chess Board',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4E7837)),
      home: const Scaffold(
        body: Center(child: Text('Modern Chess Board demo')),
      ),
    );
  }
}
