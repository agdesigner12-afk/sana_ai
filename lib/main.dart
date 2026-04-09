// ignore_for_file: depend_on_referenced_packages, library_private_types_in_public_api, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const SanaAI());
}

class SanaAI extends StatelessWidget {
  const SanaAI({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SanaState(),
      child: MaterialApp(
        title: 'Sana AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0A0A),
          primaryColor: const Color(0xFF00B4D8),
          textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0A0A0A),
            elevation: 0,
            centerTitle: true,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF1A1A1A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
            hintStyle: const TextStyle(color: Colors.grey),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// -------------------------------------------------------------
// Splash Screen (Onboarding & Permission)
// -------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showIntro = true;

  @override
  void initState() {
    super.initState();
    _checkFirstRun();
  }

  Future<void> _checkFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    final hasRun = prefs.getBool('has_run_before') ?? false;
    if (hasRun) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    } else {
      setState(() => _showIntro = true);
    }
  }

  Future<void> _markFirstRunComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_run_before', true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_showIntro) return const SizedBox.shrink();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF00B4D8), Color(0xFF90E0EF)],
              ).createShader(bounds),
              child: const Text(
                'सना',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'आपकी निजी AI सहायिका',
              style: GoogleFonts.outfit(
                fontSize: 22,
                color: const Color(0xFF00B4D8),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF00B4D8).withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.security, color: Color(0xFF00B4D8), size: 40),
                  const SizedBox(height: 16),
                  Text(
                    'Sana aapke phone mein hi rehti hai.\nKoi data bahar nahi jaata.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 16, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () async {
                await _markFirstRunComplete();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomePage()),
                );
              },
              icon: const Icon(Icons.arrow_forward),
              label: const Text('शुरू करें'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B4D8),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Main Home Page (State Machine: Download / Loading / Chat)
// -------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late SanaState state;
  bool _micAvailable = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTtsReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state = Provider.of<SanaState>(context, listen: false);
    _initSpeech();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      state.initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused) {
      _tts.stop();
    }
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (error) => debugPrint('STT Error: $error'),
    );
    if (mounted) setState(() => _micAvailable = available);
  }

  Future<void> _initTts() async {
    final prefs = await SharedPreferences.getInstance();
    final voice = prefs.getString('tts_voice') ?? 'hi-IN';
    final rate = prefs.getDouble('tts_rate') ?? 0.5;
    await _tts.setLanguage(voice);
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(1.0);
    if (mounted) setState(() => _isTtsReady = true);
  }

  Future<void> _startListening() async {
    if (!_micAvailable) {
      final granted = await Permission.microphone.request();
      if (!granted.isGranted) {
        _showSnackBar('माइक की अनुमति नहीं मिली');
        return;
      }
      await _initSpeech();
    }
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _msgController.text = result.recognizedWords;
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'hi_IN',
      onSoundLevelChange: (level) {},
      cancelOnError: true,
      partialResults: true,
      onDevice: true,
    );
    setState(() {});
  }

  void _stopListening() {
    _speech.stop();
    setState(() {});
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    state.addUserMessage(text);
    _msgController.clear();
    _scrollToBottom();
    final response = await state.sendMessage(text);
    if (response != null && state.autoSpeak) {
      await _speak(response);
    }
  }

  Future<void> _speak(String text) async {
    if (!_isTtsReady) return;
    await _tts.speak(text);
  }

  Future<void> _replayMessage(String text) async {
    await _speak(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF00B4D8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SanaState>(
      builder: (context, state, child) {
        return Scaffold(
          appBar: AppBar(
            title: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF00B4D8), Color(0xFFCAF0F8)],
              ).createShader(bounds),
              child: const Text('सना', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Color(0xFF00B4D8)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          body: _buildBody(state),
        );
      },
    );
  }

  Widget _buildBody(SanaState state) {
    switch (state.appState) {
      case AppState.loading:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00B4D8)),
              SizedBox(height: 16),
              Text('साना तैयार हो रही है...'),
            ],
          ),
        );
      case AppState.ready:
        return _ChatView(
          state: state,
          msgController: _msgController,
          scrollController: _scrollController,
          micAvailable: _micAvailable,
          isListening: _speech.isListening,
          onStartListen: _startListening,
          onStopListen: _stopListening,
          onSend: _sendMessage,
          onReplay: _replayMessage,
        );
      case AppState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(state.errorMessage ?? 'An unexpected error occurred.'),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => state.retry(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// -------------------------------------------------------------
// Chat View
// -------------------------------------------------------------
class _ChatView extends StatelessWidget {
  final SanaState state;
  final TextEditingController msgController;
  final ScrollController scrollController;
  final bool micAvailable;
  final bool isListening;
  final VoidCallback onStartListen;
  final VoidCallback onStopListen;
  final Function(String) onSend;
  final Function(String) onReplay;

  const _ChatView({
    required this.state,
    required this.msgController,
    required this.scrollController,
    required this.micAvailable,
    required this.isListening,
    required this.onStartListen,
    required this.onStopListen,
    required this.onSend,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: state.messages.length,
            itemBuilder: (context, index) {
              final msg = state.messages[index];
              final isUser = msg['role'] == 'user';
              return _MessageBubble(
                text: msg['content'] ?? '',
                isUser: isUser,
                onReplay: isUser ? null : () => onReplay(msg['content']!),
              );
            },
          ),
        ),
        if (state.isGenerating)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00B4D8)),
              ),
            ),
          ),
        _MessageInput(
          controller: msgController,
          micAvailable: micAvailable,
          isListening: isListening,
          onStartListen: onStartListen,
          onStopListen: onStopListen,
          onSend: onSend,
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final VoidCallback? onReplay;

  const _MessageBubble({required this.text, required this.isUser, this.onReplay});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF00B4D8),
              child: Text('सा', style: TextStyle(color: Colors.black, fontSize: 12)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF00B4D8).withOpacity(0.15) : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                border: isUser ? Border.all(color: const Color(0xFF00B4D8).withOpacity(0.3)) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    text,
                    style: TextStyle(color: isUser ? Colors.white : Colors.white70),
                  ),
                  if (!isUser && onReplay != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.volume_up, size: 18, color: Color(0xFF00B4D8)),
                        onPressed: onReplay,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF1A1A1A),
              child: Icon(Icons.person, size: 16, color: Color(0xFF00B4D8)),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final bool micAvailable;
  final bool isListening;
  final VoidCallback onStartListen;
  final VoidCallback onStopListen;
  final Function(String) onSend;

  const _MessageInput({
    required this.controller,
    required this.micAvailable,
    required this.isListening,
    required this.onStartListen,
    required this.onStopListen,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (micAvailable)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: isListening
                    ? [
                        BoxShadow(
                          color: const Color(0xFF00B4D8).withOpacity(0.6),
                          blurRadius: 15,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: IconButton(
                icon: Icon(
                  isListening ? Icons.mic : Icons.mic_none,
                  color: isListening ? const Color(0xFF00B4D8) : Colors.grey,
                ),
                onPressed: isListening ? onStopListen : onStartListen,
              ),
            ),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Message Sana...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF00B4D8)),
                  onPressed: () {
                    onSend(controller.text);
                  },
                ),
              ),
              onSubmitted: onSend,
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Settings Screen
// -------------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedVoice = 'hi-IN';
  double _speechRate = 0.5;
  bool _autoSpeak = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedVoice = prefs.getString('tts_voice') ?? 'hi-IN';
      _speechRate = prefs.getDouble('tts_rate') ?? 0.5;
      _autoSpeak = prefs.getBool('auto_speak') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_voice', _selectedVoice);
    await prefs.setDouble('tts_rate', _speechRate);
    await prefs.setBool('auto_speak', _autoSpeak);
    Provider.of<SanaState>(context, listen: false).updateSettings(
      voice: _selectedVoice,
      rate: _speechRate,
      autoSpeak: _autoSpeak,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Voice Settings', style: TextStyle(fontSize: 18, color: Color(0xFF00B4D8))),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('TTS Voice'),
            subtitle: Text(_selectedVoice == 'hi-IN' ? 'Hindi (India)' : 'English (US)'),
            trailing: Switch(
              value: _selectedVoice == 'hi-IN',
              onChanged: (val) {
                setState(() => _selectedVoice = val ? 'hi-IN' : 'en-US');
                _saveSettings();
              },
              activeColor: const Color(0xFF00B4D8),
            ),
          ),
          ListTile(
            title: const Text('Speech Rate'),
            subtitle: Slider(
              value: _speechRate,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              label: _speechRate.toStringAsFixed(1),
              activeColor: const Color(0xFF00B4D8),
              onChanged: (val) {
                setState(() => _speechRate = val);
                _saveSettings();
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Auto-speak responses'),
            value: _autoSpeak,
            onChanged: (val) {
              setState(() => _autoSpeak = val);
              _saveSettings();
            },
            activeColor: const Color(0xFF00B4D8),
          ),
          const Divider(height: 40),
          const Text('About', style: TextStyle(fontSize: 18, color: Color(0xFF00B4D8))),
          const ListTile(
            title: Text('Version'),
            subtitle: Text('1.0.0 (Beta)'),
          ),
          ListTile(
            title: const Text('Privacy'),
            subtitle: const Text('Everything stays on your device'),
            trailing: const Icon(Icons.security, color: Colors.green),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// State Management (DeepSeek API)
// -------------------------------------------------------------
enum AppState { loading, ready, error }

class SanaState extends ChangeNotifier {
  AppState appState = AppState.loading;
  String? errorMessage;

  List<Map<String, String>> messages = [];
  bool isGenerating = false;

  final Dio _dio = Dio();
  // अपनी DeepSeek API Key यहाँ डालें (यह महत्वपूर्ण है)
  final String _apiKey = 'sk-1f8c9957a1ef4bd19dff66c1cec44d50';

  // Settings
  String ttsVoice = 'hi-IN';
  double ttsRate = 0.5;
  bool autoSpeak = true;

  Future<void> initialize() async {
    try {
      // कोई मॉडल डाउनलोड नहीं, सीधे तैयार
      appState = AppState.ready;
      notifyListeners();
    } catch (e) {
      errorMessage = 'Initialization failed: $e';
      appState = AppState.error;
      notifyListeners();
    }
  }

  void addUserMessage(String text) {
    messages.add({'role': 'user', 'content': text});
    messages.add({'role': 'assistant', 'content': ''});
    notifyListeners();
  }

  Future<String?> sendMessage(String prompt) async {
    isGenerating = true;
    notifyListeners();

    try {
      final response = await _dio.post(
        'https://api.deepseek.com/chat/completions',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          },
        ),
        data: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'system', 'content': 'You are Sana, a helpful and friendly Hinglish AI assistant. Respond concisely in Hinglish.'},
            {'role': 'user', 'content': prompt},
          ],
          'stream': true,
        }),
      );

      // स्ट्रीमिंग रिस्पॉन्स को संभालना
      String fullResponse = '';
      await for (final chunk in response.data.stream) {
        final lines = chunk.toString().split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') continue;
            try {
              final json = jsonDecode(data);
              final content = json['choices'][0]['delta']['content'];
              if (content != null) {
                fullResponse += content;
                messages.last['content'] = fullResponse;
                notifyListeners();
              }
            } catch (_) {}
          }
        }
      }
      isGenerating = false;
      notifyListeners();
      return fullResponse;
    } catch (e) {
      messages.last['content'] = 'Error: ${e.toString()}';
      isGenerating = false;
      notifyListeners();
      return null;
    }
  }

  void updateSettings({String? voice, double? rate, bool? autoSpeak}) {
    if (voice != null) ttsVoice = voice;
    if (rate != null) ttsRate = rate;
    if (autoSpeak != null) this.autoSpeak = autoSpeak;
    notifyListeners();
  }

  void retry() {
    errorMessage = null;
    initialize();
  }
}