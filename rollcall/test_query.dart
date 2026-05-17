import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabase = SupabaseClient(
    'https://vytqqwrcmmjuutysxwxl.supabase.co',
    'sb_publishable_kb2fFjGqeOYNIydlStdKVQ_umyYTxUl',
  );

  try {
    final res = await supabase
        .from('attendance')
        .select('*')
        .limit(1);
    print('Success: $res');
  } catch (e) {
    print('Error: $e');
  }
}
