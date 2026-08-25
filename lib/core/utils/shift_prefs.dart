/// Per-user SharedPreferences keys for shift check-in state.
class ShiftPrefs {
  static String startedDateKey(String authId) => 'shift_started_date_$authId';
  static String checkInTimeKey(String authId) => 'shift_checkin_time_$authId';
  static String formattedTimeKey(String authId) => 'shift_checkin_time_formatted_$authId';
}
