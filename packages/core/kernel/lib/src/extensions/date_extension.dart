/// Extension methods for DateTime
extension DateTimeExtension on DateTime {
  /// Formats the date as a readable string (e.g., "Jan 15, 2024")
  String get formatReadable {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[month - 1]} $day, $year';
  }

  /// Formats the date as a short string (e.g., "15/01/2024")
  String get formatShort {
    return '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';
  }

  /// Formats the time as a 12-hour string (e.g., "2:30 PM")
  String get formatTime12Hour {
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final period = hour < 12 ? 'AM' : 'PM';
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Formats the time as a 24-hour string (e.g., "14:30")
  String get formatTime24Hour {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Returns true if the date is today
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  /// Returns true if the date is yesterday
  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year &&
        month == yesterday.month &&
        day == yesterday.day;
  }

  /// Returns true if the date is tomorrow
  bool get isTomorrow {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return year == tomorrow.year &&
        month == tomorrow.month &&
        day == tomorrow.day;
  }

  /// Returns the start of the day (00:00:00)
  DateTime get startOfDay {
    return DateTime(year, month, day);
  }

  /// Returns the end of the day (23:59:59.999)
  DateTime get endOfDay {
    return DateTime(year, month, day, 23, 59, 59, 999);
  }

  /// Returns the difference in days from now
  int get daysFromNow {
    final now = DateTime.now();
    return difference(now).inDays;
  }

  /// Returns a relative time string (e.g., "2 hours ago", "in 3 days")
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(this);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  /// Returns the age in years from this date
  int get age {
    final now = DateTime.now();
    int age = now.year - year;
    if (now.month < month || (now.month == month && now.day < day)) {
      age--;
    }
    return age;
  }

  /// Returns true if this date is in the same week as the other date
  bool isSameWeek(DateTime other) {
    final startOfWeek = subtract(Duration(days: weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return other.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
        other.isBefore(endOfWeek.add(const Duration(days: 1)));
  }

  /// Returns true if this date is in the same month as the other date
  bool isSameMonth(DateTime other) {
    return year == other.year && month == other.month;
  }

  /// Returns true if this date is in the same year as the other date
  bool isSameYear(DateTime other) {
    return year == other.year;
  }
}
