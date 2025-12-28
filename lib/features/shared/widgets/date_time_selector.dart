import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateTimeSelector extends StatefulWidget {
  final DateTime? initialDate;
  final Function(DateTime) onDateTimeChanged;

  const DateTimeSelector({
    super.key,
    this.initialDate,
    required this.onDateTimeChanged,
  });

  @override
  State<DateTimeSelector> createState() => _DateTimeSelectorState();
}

class _DateTimeSelectorState extends State<DateTimeSelector> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = widget.initialDate ?? now;
    _selectedTime = TimeOfDay.fromDateTime(widget.initialDate ?? now.add(const Duration(minutes: 30)));
    
    // Round time to nearest 30 min if not initial
    if (widget.initialDate == null) {
      final minute = _selectedTime.minute;
      if (minute < 15) {
        _selectedTime = TimeOfDay(hour: _selectedTime.hour, minute: 0);
      } else if (minute < 45) {
        _selectedTime = TimeOfDay(hour: _selectedTime.hour, minute: 30);
      } else {
        _selectedTime = TimeOfDay(hour: _selectedTime.hour + 1, minute: 0);
      }
    }
  }

  void _updateDateTime() {
    final dateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    widget.onDateTimeChanged(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date Scroller
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ...List.generate(14, (index) {
                final date = DateTime.now().add(Duration(days: index));
                final isSelected = _isSameDay(date, _selectedDate);
                final isToday = _isSameDay(date, DateTime.now());

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                    });
                     _updateDateTime();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.black : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          isToday ? 'Today' : DateFormat('EEE').format(date),
                          style: TextStyle(
                            color: isSelected ? Colors.white70 : Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('d').format(date),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              // Custom Date Button
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                    _updateDateTime();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_month, color: Colors.black54, size: 20),
                      SizedBox(height: 4),
                      Text(
                        'More',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Time Scroller
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ..._generateTimeSlots().map((time) {
                final isSelected = time.hour == _selectedTime.hour && time.minute == _selectedTime.minute;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedTime = time);
                    _updateDateTime();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.black : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      time.format(context),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
              
              // Custom Time Button
               GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime,
                  );
                  if (picked != null) {
                    setState(() => _selectedTime = picked);
                     _updateDateTime();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                   decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                  child: const Text(
                    'Custom',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<TimeOfDay> _generateTimeSlots() {
    final slots = <TimeOfDay>[];
    // Generate slots every 30 mins from 8 AM to 10 PM
    // Adjust logic to be relevant to "Now" if IsToday? (Simulated for generic usage first)
    // For now, static commonly used times
    for (int hour = 8; hour <= 22; hour++) {
        slots.add(TimeOfDay(hour: hour, minute: 0));
        slots.add(TimeOfDay(hour: hour, minute: 30));
    }
    return slots;
  }
}
