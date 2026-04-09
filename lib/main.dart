import 'package:flutter/material.dart';

void main() {
  runApp(const SanaAIApp());
}

class SanaAIApp extends StatelessWidget {
  const SanaAIApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sana AI',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SanaAIHome(),
    );
  }
}

class SanaAIHome extends StatefulWidget {
  const SanaAIHome({Key? key}) : super(key: key);

  @override
  State<SanaAIHome> createState() => _SanaAIHomeState();
}

class _SanaAIHomeState extends State<SanaAIHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sana AI'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const <Widget>[
            Text(
              'Welcome to Sana AI',
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(height: 20),
            Text(
              'Offline Hinglish Voice Assistant',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
