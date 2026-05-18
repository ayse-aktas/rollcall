import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  test('Check Users and Titles', () async {
    final supabase = SupabaseClient(
      'https://vytqqwrcmmjuutysxwxl.supabase.co',
      'sb_publishable_kb2fFjGqeOYNIydlStdKVQ_umyYTxUl',
    );

    final res = await supabase.from('users').select('id, first_name, last_name, title');
    
    print('Users and Titles:');
    for (var u in res) {
      print('${u['first_name']} ${u['last_name']}: ${u['title']}');
    }
    
    expect(true, true);
  });
}
