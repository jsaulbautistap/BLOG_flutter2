import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';
import 'blog_page.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://uwbnkrfmuxrxocrocaeg.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3Ym5rcmZtdXhyeG9jcm9jYWVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE1NzAzMDMsImV4cCI6MjA2NzE0NjMwM30.82A_cLq7ixI1a3osEegSHcnaXqSzb0TUeA7jHhQjOkg',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Turismo Ciudadano',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase = Supabase.instance.client;
  String? userRole;
  StreamSubscription<List<Map<String, dynamic>>>? _perfilSubscription;

  @override
  void initState() {
    super.initState();

    supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;

      if (event == AuthChangeEvent.signedIn) {
        _loadUserRole();
        _subscribeToProfileChanges();
      } else if (event == AuthChangeEvent.signedOut) {
        setState(() {
          userRole = null;
        });
        _perfilSubscription?.cancel();
        _perfilSubscription = null;
      }
    });

    if (supabase.auth.currentUser != null) {
      _loadUserRole();
      _subscribeToProfileChanges();
    }
  }

  Future<void> _loadUserRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        userRole = null;
      });
      return;
    }
    final perfil = await supabase
        .from('perfiles')
        .select('rol')
        .eq('id', user.id)
        .maybeSingle();

    setState(() {
      userRole = perfil?['rol'];
    });
  }

  void _subscribeToProfileChanges() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _perfilSubscription?.cancel();

    _perfilSubscription = supabase
        .from('perfiles')
        .stream(primaryKey: ['id'])
        .eq('id', user.id)
        .listen((data) {
          if (data.isNotEmpty) {
            final updatedRol = data[0]['rol'] as String?;
            if (updatedRol != userRole) {
              setState(() {
                userRole = updatedRol;
              });
            }
          }
        });
  }

  @override
  void dispose() {
    _perfilSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return const LoginPage();
    }

   

    return const BlogPage();
  }
}
