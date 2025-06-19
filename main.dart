// ReyuFlow GATE Scheduler Assistant (Voice-Guided with Persistent Schedule Storage + GPT UI + Text Input)

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await NotificationService().init();
  runApp(ReyuFlowApp());
}

class ReyuFlowApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReyuFlow GATE Assistant',
      theme: ThemeData.dark(),
      home: HomeScreen(),
    );
  }
}

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final payload = response.payload;
        print('Notification clicked with payload: \$payload');
      },
    );
  }

  Future<void> scheduleCustomNotification(
      int hour, int minute, String message, int id) async {
    await _notifications.zonedSchedule(
      id,
      'ReyuFlow Reminder',
      message,
      _nextInstanceOfTime(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_channel_id',
          'Daily Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'today_schedule',
    );
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(Duration(days: 1));
    }
    return scheduled;
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterTts flutterTts = FlutterTts();
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _spokenText = "";
  String _gptResponse = "";
  final Map<String, String> dateToTopic = {};
  String todayTopic = "";
  int startHour = 7;
  final TextEditingController _textController = TextEditingController();

  final List<Map<String, dynamic>> schedule = [
    {
      "subject": "Signals & Systems",
      "start": "2025-06-19",
      "days": 10,
      "lectures": 49
    },
    {
      "subject": "Engineering Maths",
      "start": "2025-06-29",
      "days": 14,
      "lectures": 56
    },
    {
      "subject": "Digital Electronics",
      "start": "2025-07-13",
      "days": 7,
      "lectures": 42
    },
    {
      "subject": "Network Theory",
      "start": "2025-07-20",
      "days": 10,
      "lectures": 49
    },
    {
      "subject": "Electronic Devices",
      "start": "2025-07-30",
      "days": 7,
      "lectures": 42
    },
    {
      "subject": "Analog Circuits",
      "start": "2025-08-06",
      "days": 10,
      "lectures": 49
    },
    {
      "subject": "Control Systems",
      "start": "2025-08-16",
      "days": 8,
      "lectures": 40
    },
    {
      "subject": "Communications",
      "start": "2025-08-24",
      "days": 10,
      "lectures": 49
    },
    {
      "subject": "Electromagnetics",
      "start": "2025-09-03",
      "days": 10,
      "lectures": 49
    },
    {
      "subject": "General Aptitude",
      "start": "2025-09-13",
      "days": 15,
      "lectures": 45
    },
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    loadSchedule().then((_) {
      scheduleGateReminders();
      checkYesterdayStatusAndPostpone();
      suggestTodayTopic();
    });
  }

  String _formattedDate(DateTime date) {
    return "\${date.year.toString().padLeft(4, '0')}-\${date.month.toString().padLeft(2, '0')}-\${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> loadSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('dateToTopic')) {
      generateSchedule();
      await prefs.setString('dateToTopic', jsonEncode(dateToTopic));
    } else {
      final stored = prefs.getString('dateToTopic')!;
      final decoded = jsonDecode(stored) as Map<String, dynamic>;
      dateToTopic.clear();
      decoded.forEach((k, v) => dateToTopic[k] = v);
    }
  }

  void generateSchedule() {
    for (var item in schedule) {
      final startDate = DateTime.parse(item['start']);
      final days = item['days'];
      final lectures = item['lectures'];
      final int perDay = (lectures / days).ceil();
      int lectureNumber = 1;
      for (int i = 0; i < days; i++) {
        final date = startDate.add(Duration(days: i));
        final dateStr = _formattedDate(date);
        final topic =
            "\${item['subject']} – Lecture \${lectureNumber} to \${lectureNumber + perDay - 1} of \$lectures";
        dateToTopic[dateStr] = topic;
        if (_formattedDate(DateTime.now()) == dateStr) {
          todayTopic = topic;
        }
        lectureNumber += perDay;
      }
    }
  }

  Future<void> checkYesterdayStatusAndPostpone() async {
    final prefs = await SharedPreferences.getInstance();
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    final key = _formattedDate(yesterday);
    final completed = prefs.getBool("done_\$key") ?? false;
    if (!completed) {
      final Map<String, String> newSchedule = {};
      dateToTopic.forEach((dateStr, topic) {
        final date = DateTime.parse(dateStr).add(Duration(days: 1));
        newSchedule[_formattedDate(date)] = topic;
      });
      dateToTopic
        ..clear()
        ..addAll(newSchedule);
      await prefs.setString('dateToTopic', jsonEncode(dateToTopic));
      await speak(
          "You didn't complete yesterday's task. Postponing your schedule by one day.");
    }
  }

  void suggestTodayTopic() {
    final today = DateTime.now();
    final key = _formattedDate(today);
    if (dateToTopic.containsKey(key)) {
      todayTopic = dateToTopic[key]!;
      final message = "Today’s GATE topic is: \$todayTopic";
      speak(message);
    }
  }

  Future<void> speak(String text) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1);
    await flutterTts.speak(text);
  }

  void scheduleGateReminders() {
    final notifier = NotificationService();
    notifier.scheduleCustomNotification(
        7, 0, "Wake up and revise short notes.", 1);
    notifier.scheduleCustomNotification(
        9, 0, "Start GATE subject study block 1.", 2);
    notifier.scheduleCustomNotification(
        13, 0, "Resume GATE subject block 2 after lunch.", 3);
    notifier.scheduleCustomNotification(
        16, 30, "Time for mock tests or previous year questions.", 4);
    notifier.scheduleCustomNotification(
        20, 0, "End-of-day recap and error logging.", 5);
  }

  void listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
            onResult: (val) => setState(() {
                  _spokenText = val.recognizedWords;
                  if (_spokenText.isNotEmpty) {
                    callGPT(_spokenText);
                  }
                }));
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> callGPT(String prompt) async {
    final response = await http.post(
      Uri.parse("https://api.openai.com/v1/chat/completions"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer sk-YOUR-KEY-HERE"
      },
      body: jsonEncode({
        "model": "gpt-3.5-turbo",
        "messages": [
          {
            "role": "system",
            "content": "You are a personal GATE exam assistant..."
          },
          {"role": "user", "content": prompt}
        ]
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() => _gptResponse = data['choices'][0]['message']['content']);
      speak(_gptResponse);
    } else {
      speak("Sorry, I couldn't reach the server.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ReyuFlow GATE Scheduler')),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              color: Colors.black12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Today:",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(todayTopic, style: TextStyle(fontSize: 16)),
                  SizedBox(height: 16),
                  Text("🕖 \$startHour:00 AM – Wake up and revise short notes"),
                  Text(
                      "🕘 \${startHour + 2}:00 AM – Study block 1: \$todayTopic"),
                  Text(
                      "🕐 \${startHour + 6}:00 PM – Study block 2: \$todayTopic"),
                  Text("🕟 \${startHour + 9}:30 PM – Mock tests / PYQs"),
                  Text("🕗 \${startHour + 13}:00 PM – Recap & log errors"),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(16),
                children: [
                  if (_spokenText.isNotEmpty)
                    ListTile(title: Text("You (voice): \$_spokenText")),
                  if (_gptResponse.isNotEmpty)
                    ListTile(title: Text("GPT: \$_gptResponse")),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 80.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: "Type your query here...",
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final text = _textController.text.trim();
                      if (text.isNotEmpty) {
                        setState(() => _spokenText = text);
                        callGPT(text);
                        _textController.clear();
                      }
                    },
                    child: Text("Send"),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: FloatingActionButton(
          onPressed: listen,
          child: Icon(_isListening ? Icons.mic_off : Icons.mic),
        ),
      ),
    );
  }
}

