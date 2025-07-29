// main.dart
// 기능:
// - Firebase 초기화 및 Firebase Cloud Messaging(FCM) 백그라운드 메시지 처리
// - 포그라운드 및 백그라운드 푸시 알림 수신 시 SnackBar 표시 및 화면 전환 처리
// - FCM 토큰 Firestore 저장 및 권한 요청 관리
// - flutter_local_notifications 초기화 (로컬 알림)
// - 앱 주요 화면 라우팅 설정 및 로그인 상태 분기(AuthGate 사용)

// timezone 초기화
// 로컬 알림 예약 함수
// main() 내부 수정

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// flutter_local_notifications 패키지 임포트
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// timezone 패키지 import
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'firebase_options.dart';
import 'services/fcm_service.dart'; // FCM 관련 서비스 클래스
import 'auth_gate.dart'; // 로그인 상태 분기용 위젯

// 주요 화면 임포트
import 'auth_test_page.dart';
import 'home_page.dart';
import 'pages/profile_page.dart';
import 'pages/change_password_page.dart';
import 'pages/todo_test_page.dart'; // 할일 관리 페이지
import 'pages/filter_page.dart';
import 'calendar_page.dart';
import 'natural_input_page.dart'; // 자연어 입력 페이지

// 일정 수정 페이지 임포트
import 'pages/edit_todo_page.dart';

// flutter_local_notifications 플러그인 인스턴스 (전역)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// 네비게이터 키 추가: 푸시 알림 클릭 시 화면 전환에 사용
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 백그라운드 상태에서 FCM 메시지 수신 시 호출되는 핸들러 함수
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase 초기화 (백그라운드에서 앱이 완전히 종료된 상태라도 Firebase 초기화 필요)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('💬 백그라운드 푸시 수신: ${message.messageId}');
}

// flutter_local_notifications 초기화 함수
Future<void> initializeLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  // iOS 알림 초기화 설정 추가 (DarwinInitializationSettings 사용)
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    // onSelectNotification: (String? payload) async {
    //   // 알림 클릭 시 처리 (필요하면 구현)
    // },
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Timezone 초기화 (로컬 알림 정확한 시간 계산용)
  tz.initializeTimeZones();

  // flutter_local_notifications 초기화
  await initializeLocalNotifications();

  // 백그라운드 메시지 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 푸시 알림 클릭 시 앱이 열리면서 호출되는 리스너 등록
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('💬 푸시 알림 클릭: ${message.messageId}');
    // navigatorKey를 통해 화면 이동 처리
    navigatorKey.currentState?.pushNamed('/home');
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FcmService _fcmService = FcmService(); // FCM 서비스 인스턴스 생성

  @override
  void initState() {
    super.initState();
    _initializeFCM();
  }

  // FCM 초기화 및 권한 요청, 토큰 저장, 메시지 수신 리스너 설정
  void _initializeFCM() {
    _fcmService.requestPermission(); // 알림 권한 요청
    _fcmService.saveTokenToFirestore(); // FCM 토큰 Firestore 저장
    _fcmService.listenForegroundMessages(context); // 포그라운드 메시지 수신 리스너
    _fcmService.setupInteractedMessage(context); // 앱이 푸시 알림으로 열렸을 때 처리
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '할일 일정 앱',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // navigatorKey 등록
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AuthGate(), // 로그인 여부에 따른 화면 분기 처리
      // 앱 라우트 설정
      routes: {
        '/login': (context) => const AuthTestPage(), // 로그인 화면
        '/home': (context) => HomePage(), // 홈 화면
        '/profile': (context) => const ProfilePage(), // 프로필 화면
        '/changePassword': (context) =>
            const ChangePasswordPage(), // 비밀번호 변경 화면
        '/todo_manage': (context) => const TodoTestPage(), // 할일 관리 화면 (별칭)
        '/todo_test': (context) => const TodoTestPage(), // 할일 관리 화면
        '/filter': (context) => const FilterPage(), // 필터 페이지
        '/calendar': (context) => const CalendarPage(), // 캘린더 페이지
        '/natural_input': (context) => NaturalInputPage(
          // 자연어 입력 페이지
          selectedDate: DateTime.now(),
          onDateSelected: (DateTime selectedDate) {
            print('Selected Date: $selectedDate');
          },
        ),

        // 일정 수정 페이지 라우팅 (arguments로 todoData 전달 필요)
        '/edit_todo': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>;
          return EditTodoPage(todoData: args);
        },
      },
    );
  }
}

// 마감 5분 전에 로컬 알림 예약 함수
Future<void> scheduleDeadlineNotification(DateTime deadlineTime) async {
  final scheduledTime = tz.TZDateTime.from(
    deadlineTime,
    tz.local,
  ).subtract(const Duration(minutes: 5));

  await flutterLocalNotificationsPlugin.zonedSchedule(
    0,
    '📌 마감 5분 전 알림',
    '5분 뒤 마감될 일정이 있어요!',
    scheduledTime,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'deadline_channel',
        '마감 알림',
        channelDescription: '마감 시간 전에 알림을 보냅니다',
        importance: Importance.max,
        priority: Priority.high,
      ),
    ),
    androidAllowWhileIdle: true,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.dateAndTime,
  );
}
