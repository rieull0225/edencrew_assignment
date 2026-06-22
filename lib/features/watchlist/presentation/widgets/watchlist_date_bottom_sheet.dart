// ignore_for_file: unused_element

import 'package:flutter/material.dart';

import '../models/watchlist_date_picker_options.dart';
import '../../../../theme/app_theme.dart';

/// 날짜 선택 바텀시트.
///
/// Figma 스펙 구현:
/// - 연/월/일 3개의 휠 피커
/// - 선택 상태: 배경색 변경 + 폰트 스타일 변경
/// - 취소/확인 버튼
///
/// 깜빡임 방지 구현:
/// - 월/연 변경 시 일 목록이 바뀔 때 스크롤 컨트롤러 재생성
/// - setState 전에 새 컨트롤러를 올바른 초기 위치로 설정
/// - 이렇게 하면 잘못된 위치에서 애니메이션되는 깜빡임 현상 방지
class WatchlistDateBottomSheet extends StatefulWidget {
  const WatchlistDateBottomSheet({
    required this.availableDates,
    required this.initialDate,
    this.controller,
    this.onSubmitted,
    this.onCancelled,
    super.key,
  });

  final List<DateTime> availableDates;
  final DateTime initialDate;
  final WatchlistDateBottomSheetController? controller;
  final ValueChanged<DateTime>? onSubmitted;
  final VoidCallback? onCancelled;

  @override
  State<WatchlistDateBottomSheet> createState() =>
      _WatchlistDateBottomSheetState();
}

class _WatchlistDateBottomSheetState extends State<WatchlistDateBottomSheet> {
  static const double _itemExtent = 44;
  static const double _pickerHeight = 220;

  late final WatchlistDatePickerOptions _options;
  late FixedExtentScrollController _yearController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _dayController;

  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  @override
  void initState() {
    super.initState();
    _options = WatchlistDatePickerOptions.fromDates(widget.availableDates);
    final resolvedDate = _options.coerce(widget.initialDate);
    _selectedYear = resolvedDate.year;
    _selectedMonth = resolvedDate.month;
    _selectedDay = resolvedDate.day;
    _yearController = FixedExtentScrollController(
      initialItem: _yearIndex(_selectedYear),
    );
    _monthController = FixedExtentScrollController(
      initialItem: _monthIndex(_selectedMonth),
    );
    _dayController = FixedExtentScrollController(
      initialItem: _dayIndex(_selectedDay),
    );
    widget.controller?._attach(
      selectDate: _selectDateValue,
      confirm: _confirm,
      dismiss: _dismiss,
    );
  }

  @override
  void didUpdateWidget(covariant WatchlistDateBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller?._detach();
    widget.controller?._attach(
      selectDate: _selectDateValue,
      confirm: _confirm,
      dismiss: _dismiss,
    );
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  List<int> get _years => _options.years;

  List<int> get _months => _options.monthsForYear(_selectedYear);

  List<int> get _days =>
      _options.daysForMonth(year: _selectedYear, month: _selectedMonth);

  int _yearIndex(int year) => _years.indexOf(year).clamp(0, _years.length - 1);

  int _monthIndex(int month) =>
      _months.indexOf(month).clamp(0, _months.length - 1);

  int _dayIndex(int day) => _days.indexOf(day).clamp(0, _days.length - 1);

  void _scheduleWheelSync({bool syncMonth = false, bool syncDay = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (syncMonth && _monthController.hasClients) {
        _monthController.jumpToItem(_monthIndex(_selectedMonth));
      }

      if (syncDay && _dayController.hasClients) {
        _dayController.jumpToItem(_dayIndex(_selectedDay));
      }
    });
  }

  /// 연도 선택 처리.
  ///
  /// 깜빡임 방지 구현:
  /// - 연도 변경 시 월/일 목록이 모두 바뀔 수 있음
  /// - 월 컨트롤러도 필요시 재생성
  /// - 일 컨트롤러는 항상 재생성 (월이 바뀌면 일 목록도 바뀌므로)
  /// - 모든 컨트롤러를 올바른 위치로 설정 후 setState
  void _selectYear(int index) {
    final year = _years[index];
    if (year == _selectedYear) {
      return;
    }

    // Update year first to get correct _months and _days lists
    _selectedYear = year;

    // Check if month needs to change
    final months = _months;
    var shouldSyncMonth = false;
    if (!months.contains(_selectedMonth)) {
      _selectedMonth = months.first;
      shouldSyncMonth = true;
    }

    // Check if day needs to change and recreate controller
    final days = _days;
    final newDay = days.contains(_selectedDay) ? _selectedDay : days.first;

    // Recreate day controller with correct initial position
    _dayController.dispose();
    _dayController = FixedExtentScrollController(
      initialItem: days.indexOf(newDay).clamp(0, days.length - 1),
    );

    // Recreate month controller if needed
    if (shouldSyncMonth) {
      _monthController.dispose();
      _monthController = FixedExtentScrollController(
        initialItem: months.indexOf(_selectedMonth).clamp(0, months.length - 1),
      );
    }

    setState(() {
      _selectedDay = newDay;
    });
  }

  /// 월 선택 처리.
  ///
  /// 깜빡임 방지 구현:
  /// - 월 변경 시 일 목록이 바뀜 (ex: 31일 → 28일)
  /// - 기존 일이 새 목록에 없으면 첫 번째 날로 변경
  /// - 컨트롤러를 올바른 초기 위치로 재생성 후 setState
  /// - 이 순서로 해야 화면에 잘못된 위치가 잠깐 보이지 않음
  void _selectMonth(int index) {
    final month = _months[index];
    if (month == _selectedMonth) {
      return;
    }

    // Update month first to get correct _days list
    _selectedMonth = month;
    final days = _days;
    final newDay = days.contains(_selectedDay) ? _selectedDay : days.first;

    // Recreate day controller with correct initial position to avoid flicker
    _dayController.dispose();
    _dayController = FixedExtentScrollController(
      initialItem: days.indexOf(newDay).clamp(0, days.length - 1),
    );

    setState(() {
      _selectedDay = newDay;
    });
  }

  void _selectDay(int index) {
    final day = _days[index];
    if (day == _selectedDay) {
      return;
    }

    setState(() {
      _selectedDay = day;
    });
  }

  void _selectDateValue(DateTime value) {
    final resolvedDate = _options.coerce(value);
    setState(() {
      _selectedYear = resolvedDate.year;
      _selectedMonth = resolvedDate.month;
      _selectedDay = resolvedDate.day;
    });
    _scheduleWheelSync(syncMonth: true, syncDay: true);
  }

  void _confirm() {
    final resolvedDate = _options.resolve(
      year: _selectedYear,
      month: _selectedMonth,
      day: _selectedDay,
    );
    final onSubmitted = widget.onSubmitted;
    if (onSubmitted != null) {
      onSubmitted(resolvedDate);
      return;
    }
    Navigator.of(context).pop(resolvedDate);
  }

  void _dismiss() {
    final onCancelled = widget.onCancelled;
    if (onCancelled != null) {
      onCancelled();
      return;
    }
    Navigator.of(context).pop();
  }

  // 날짜 선택 바텀시트 구현:
  // - 헤더: "날짜 선택" 타이틀
  // - 연/월/일 picker: ListWheelScrollView 기반 _DateWheelPicker 사용
  // - 선택 상태: 배경색 변경 + 폰트 스타일 변경
  // - CTA: 취소/확인 버튼
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          key: const Key('watchlist-date-sheet'),
          decoration: BoxDecoration(
            color: AppColors.bg.bg_2_212121,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 56,
                child: Padding(
                  padding: EdgeInsets.only(left: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('날짜 선택', style: AppTypography.sheetTitle),
                  ),
                ),
              ),
              SizedBox(
                height: _pickerHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: _DateWheelPicker(
                        pickerKey: const Key('watchlist-date-picker-year'),
                        itemKeyPrefix: 'watchlist-date-item-year',
                        controller: _yearController,
                        values: _years,
                        selectedValue: _selectedYear,
                        formatter: (value) => '$value년',
                        onSelectedItemChanged: _selectYear,
                      ),
                    ),
                    Expanded(
                      child: _DateWheelPicker(
                        pickerKey: const Key('watchlist-date-picker-month'),
                        itemKeyPrefix: 'watchlist-date-item-month',
                        controller: _monthController,
                        values: _months,
                        selectedValue: _selectedMonth,
                        formatter: (value) => '$value월',
                        onSelectedItemChanged: _selectMonth,
                      ),
                    ),
                    Expanded(
                      child: _DateWheelPicker(
                        pickerKey: const Key('watchlist-date-picker-day'),
                        itemKeyPrefix: 'watchlist-date-item-day',
                        controller: _dayController,
                        values: _days,
                        selectedValue: _selectedDay,
                        formatter: (value) => '$value일',
                        onSelectedItemChanged: _selectDay,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _SheetButton(
                        buttonKey: const Key('watchlist-date-cancel'),
                        label: '취소',
                        backgroundColor: AppColors.bg.bg_4_333333,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SheetButton(
                        buttonKey: const Key('watchlist-date-confirm'),
                        label: '확인',
                        backgroundColor: AppColors.mainAndAccent.primary_ff8a00,
                        onTap: _confirm,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class WatchlistDateBottomSheetController {
  void Function(DateTime value)? _selectDate;
  VoidCallback? _confirm;
  VoidCallback? _dismiss;

  void _attach({
    required void Function(DateTime value) selectDate,
    required VoidCallback confirm,
    required VoidCallback dismiss,
  }) {
    _selectDate = selectDate;
    _confirm = confirm;
    _dismiss = dismiss;
  }

  void _detach() {
    _selectDate = null;
    _confirm = null;
    _dismiss = null;
  }

  void selectDate(DateTime value) {
    _selectDate?.call(value);
  }

  void confirm() {
    _confirm?.call();
  }

  void dismiss() {
    _dismiss?.call();
  }
}

class _DateWheelPicker extends StatelessWidget {
  const _DateWheelPicker({
    required this.pickerKey,
    required this.itemKeyPrefix,
    required this.controller,
    required this.values,
    required this.selectedValue,
    required this.formatter,
    required this.onSelectedItemChanged,
  });

  final Key pickerKey;
  final String itemKeyPrefix;
  final FixedExtentScrollController controller;
  final List<int> values;
  final int selectedValue;
  final String Function(int value) formatter;
  final ValueChanged<int> onSelectedItemChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 선택 영역 오버레이 (뒤에 고정)
        Center(
          child: Container(
            width: 100,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.bg.bg_4_333333,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        // 휠 피커 (앞에서 스크롤)
        ListWheelScrollView.useDelegate(
          key: pickerKey,
          controller: controller,
          physics: const FixedExtentScrollPhysics(),
          itemExtent: _WatchlistDateBottomSheetState._itemExtent,
          diameterRatio: 100,
          perspective: 0.00001,
          squeeze: 1,
          overAndUnderCenterOpacity: 1,
          onSelectedItemChanged: onSelectedItemChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: values.length,
            builder: (context, index) {
              final value = values[index];
              final isSelected = value == selectedValue;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  controller.animateToItem(
                    index,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: SizedBox(
                  height: _WatchlistDateBottomSheetState._itemExtent,
                  child: Center(
                    child: Text(
                      formatter(value),
                      key: Key('$itemKeyPrefix-$value'),
                      style: tabularTextStyle(
                        (isSelected
                                ? AppTypography.sheetPickerValue
                                : AppTypography.sheetOption)
                            .copyWith(
                              color: isSelected
                                  ? AppColors.text.text_fafafa
                                  : AppColors.text.text_3_9e9e9e,
                            ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.buttonKey,
    required this.label,
    required this.backgroundColor,
    required this.onTap,
  });

  final Key buttonKey;
  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextButton(
        key: buttonKey,
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: AppColors.text.text_fafafa,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: AppTypography.sheetButton.copyWith(
            color: AppColors.text.text_fafafa,
          ),
        ),
      ),
    );
  }
}
