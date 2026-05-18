import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await Supabase.initialize(
    url: 'https://vytqqwrcmmjuutysxwxl.supabase.co',
    anonKey: 'sb_publishable_kb2fFjGqeOYNIydlStdKVQ_umyYTxUl',
  );

  final supabase = Supabase.instance.client;
  final res = await supabase.from('users').select('id, first_name, last_name, title');
  
  print('Users and Titles:');
  for (var u in res) {
    print('${u['first_name']} ${u['last_name']}: ${u['title']}');
  }
}
