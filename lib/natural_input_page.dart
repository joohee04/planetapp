// natural_input_page.dart
// 기능:
// - 자연어로 일정 텍스트 입력
// - "자동 분류하기" 버튼으로 입력 내용 자동 분류
// - 자동 분류 결과(날짜, 과목, 카테고리) 표시 및 수정 가능한 드롭다운 제공
// - 시작일, 마감일 날짜 선택 다이얼로그
// - "저장하기" 버튼으로 Firestore에 일정 저장
// - 저장 후 화면 초기화 및 부모 위젯에 날짜 변경 알림

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 날짜 포맷팅
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore Timestamp
import 'package:firebase_auth/firebase_auth.dart'; // Firebase 인증
import 'calendar_widget.dart'; // 캘린더 위젯 임포트

import 'services/category_classifier.dart'; // 카테고리 분류기 임포트

class NaturalInputPage extends StatefulWidget {
  final DateTime? selectedDate; // 부모로부터 전달받는 초기 선택 날짜
  final void Function(DateTime) onDateSelected; // 날짜 변경 시 부모 호출 콜백

  const NaturalInputPage({
    super.key,
    this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<NaturalInputPage> createState() => _NaturalInputPageState();
}

class _NaturalInputPageState extends State<NaturalInputPage> {
  final TextEditingController _inputController = TextEditingController();

  DateTime? _startDate; // 시작일
  DateTime? _endDate; // 마감일

  String? detectedDate; // 인식된 날짜 문자열 (표시용)
  String? detectedSubject; // 인식된 과목
  String? detectedCategory; // 인식된 카테고리

  bool showResult = false; // 자동 분류 결과 보여줄지 여부
  bool isEditing = false; // 텍스트 필드 편집 가능 여부

  // 과목 및 카테고리 선택지
  final List<String> categoryOptions = ['시험', '과제', '팀플', '기타'];
  final List<String> subjectOptions = ['데이터통신', '캡스톤디자인', '운영체제', '기타', '일정'];

  @override
  void initState() {
    super.initState();
    // 초기 선택 날짜가 있으면 시작일로 세팅 및 표시
    if (widget.selectedDate != null) {
      _startDate = widget.selectedDate;
      detectedDate = _formatDate(widget.selectedDate!);
      _inputController.text = '';
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  // 날짜를 "yyyy-MM-dd (요일)" 형태의 한글 문자열로 포맷팅
  String _formatDate(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dayKR = weekdays[date.weekday - 1];
    return '${DateFormat('yyyy-MM-dd').format(date)} ($dayKR)';
  }

  // 입력 문자열에서 "X월 Y일" 형태의 날짜 추출 함수
  DateTime? extractDateFromInput(String input) {
    final regExp = RegExp(r'(\d{1,2})월\s*(\d{1,2})일');
    final match = regExp.firstMatch(input);
    if (match != null) {
      final month = int.parse(match.group(1)!);
      final day = int.parse(match.group(2)!);
      final now = DateTime.now();
      return DateTime(now.year, month, day);
    }
    return null;
  }

  // "자동 분류하기" 버튼 누르면 호출되는 함수
  Future<void> classifyInput() async {
    String input = _inputController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('일정을 입력해주세요')));
      return;
    }

    setState(() {
      // 시작일이 이미 있으면 그대로 표시
      if (_startDate != null) {
        detectedDate = _formatDate(_startDate!);
      } else {
        // 입력문자열에서 날짜 추출 시도
        DateTime? extractedDate = extractDateFromInput(input);
        if (extractedDate != null) {
          _startDate = extractedDate;
          detectedDate = _formatDate(extractedDate);
        } else {
          detectedDate = '날짜 인식 안됨';
          _startDate = null;
        }
      }

      // 과목 자동 인식: subjectOptions 목록에 포함된 단어 중 첫번째 발견 항목 선택
      detectedSubject = null;
      for (var subject in subjectOptions) {
        if (input.contains(subject)) {
          detectedSubject = subject;
          break;
        }
      }
      // 과목 인식 실패 시 입력 텍스트 앞부분 단어로 임시 지정
      if (detectedSubject == null) {
        String temp = input
            .replaceAll(RegExp(r'\d{1,2}월\s*\d{1,2}일'), '')
            .trim();
        List<String> parts = temp.split(RegExp(r'\s+'));
        detectedSubject = parts.isNotEmpty ? parts[0] : '일정';
      }

      // 카테고리 자동 분류 함수 호출 (외부 함수)
      detectedCategory = classifyCategory(input);

      showResult = true; // 결과 표시 모드 활성화
      isEditing = false; // 입력 필드 읽기 전용으로 설정
    });
  }

  // "저장하기" 버튼 누르면 Firestore에 일정 저장
  Future<void> saveTodo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다')));
      return;
    }

    // 자동 분류된 필수 데이터가 없으면 저장 불가 안내
    if (_startDate == null ||
        detectedSubject == null ||
        detectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('자동 분류를 먼저 실행하고 정확한 값을 입력해주세요')),
      );
      return;
    }

    try {
      // Firestore에 저장할 데이터 객체 생성
      final todoData = {
        'title': _inputController.text,
        'startDate': Timestamp.fromDate(_startDate!), // 시작일 저장
        'endDate': _endDate != null
            ? Timestamp.fromDate(_endDate!)
            : null, // 마감일 저장(없으면 null)
        'subject': detectedSubject,
        'category': detectedCategory,
        'createdAt': Timestamp.now(),
      };

      // Firestore 경로: todos/{userId}/userTodos 컬렉션
      final todoRef = FirebaseFirestore.instance
          .collection('todos')
          .doc(user.uid)
          .collection('userTodos');

      await todoRef.add(todoData); // 새 문서 추가

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('일정이 저장되었습니다!')));

      widget.onDateSelected(_startDate!); // 부모 위젯에 날짜 변경 알림

      // 저장 후 입력 및 상태 초기화
      setState(() {
        _inputController.clear();
        detectedDate = null;
        detectedSubject = null;
        detectedCategory = null;
        showResult = false;
        _startDate = null;
        _endDate = null;
        isEditing = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 중 오류 발생: $e')));
    }
  }

  // 시작일 선택 다이얼로그 표시
  Future<void> _selectStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        detectedDate = _formatDate(picked);
      });
    }
  }

  // 마감일 선택 다이얼로그 표시
  Future<void> _selectEndDate() async {
    if (_startDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 시작일을 선택해주세요')));
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate!,
      firstDate: _startDate!,
      lastDate: DateTime(_startDate!.year + 5),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  // D-Day 텍스트 생성 함수 (남은 날짜/오늘/지난 날짜 표시)
  String getDDayText(DateTime deadline) {
    final now = DateTime.now();
    final diff = deadline
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;

    if (diff > 0) {
      return 'D-${diff}'; // 마감일까지 남은 날짜
    } else if (diff == 0) {
      return 'D-DAY'; // 오늘이 마감일
    } else {
      return 'D+${-diff}'; // 마감일 지남
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('자연어 일정 추가')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 자연어 일정 입력 필드
            TextField(
              controller: _inputController,
              decoration: const InputDecoration(
                labelText: '일정을 자연어로 입력하세요',
                hintText: '예: 7월 9일 데이터통신 과제 제출',
              ),
              readOnly: !isEditing && showResult, // 결과 표시 시 읽기전용
              maxLines: null,
              autofocus: isEditing || !showResult, // 편집모드나 결과 없으면 자동 포커스
            ),
            const SizedBox(height: 12),

            // 자동 분류하기 버튼
            ElevatedButton(
              onPressed: classifyInput,
              child: const Text('자동 분류하기'),
            ),
            const SizedBox(height: 20),

            // 자동 분류 결과 표시
            if (showResult)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📌 자동 분류 결과',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // 날짜 표시 및 선택 버튼
                  Row(
                    children: [
                      const Text('날짜: '),
                      TextButton(
                        onPressed: _startDate == null ? null : _selectStartDate,
                        child: Text(detectedDate ?? '선택 안됨'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 과목 드롭다운
                  Row(
                    children: [
                      const Text('과목: '),
                      DropdownButton<String>(
                        value: subjectOptions.contains(detectedSubject)
                            ? detectedSubject
                            : subjectOptions.first,
                        items: subjectOptions
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            detectedSubject = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 카테고리 드롭다운
                  Row(
                    children: [
                      const Text('카테고리: '),
                      DropdownButton<String>(
                        value: categoryOptions.contains(detectedCategory)
                            ? detectedCategory
                            : categoryOptions.first,
                        items: categoryOptions
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            detectedCategory = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 마감일 날짜 선택 및 D-Day 표시
                  Row(
                    children: [
                      const Text('마감일: '),
                      TextButton(
                        onPressed: _endDate == null ? _selectEndDate : null,
                        child: Text(
                          _endDate != null
                              ? DateFormat('yyyy-MM-dd').format(_endDate!) +
                                    " (" +
                                    getDDayText(_endDate!) +
                                    ")"
                              : '선택 안됨',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 수정 및 저장 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            isEditing = true; // 편집 모드 전환
                          });
                        },
                        child: const Text('수정'),
                      ),
                      ElevatedButton(
                        onPressed: saveTodo, // Firestore 저장 함수 호출
                        child: const Text('저장하기'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
