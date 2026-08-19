
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../core/constants.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  String? _errorMessage;
  int? _selectedGradeId;
  List<Map<String, dynamic>> _grades = [];

  @override
  void initState() {
    super.initState();
    _fetchGrades();
  }

  Future<void> _fetchGrades() async {
    try {
      final service = ref.read(supabaseServiceProvider);
      final grades = await service.getGrades();
      if (mounted) setState(() => _grades = grades);
    } catch (e) {
      debugPrint('Error fetching grades: $e');
    }
  }

  Future<void> _handleSignup() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null; 
    });

    try {
      if (_fullNameController.text.trim().isEmpty) throw 'Full Name is required';
      if (_emailController.text.trim().isEmpty) throw 'Email is required';
      if (_passwordController.text.length < 6) throw 'Password must be at least 6 characters';
      if (_passwordController.text != _confirmPasswordController.text) throw 'Passwords do not match';
      
      final gradeId = _selectedGradeId ?? (_grades.isNotEmpty ? _grades.first['id'] as int : 10);

      final auth = ref.read(authServiceProvider);
      await auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        gradeId: gradeId,
      );
      
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.person_add_outlined, size: 64, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text(
                  'Create Account',
                  style: AppTextStyles.heading1,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    color: Colors.red.shade50,
                    child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade800)),
                  ),
            
                TextField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
            
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                
                DropdownButtonFormField<int>(
                  value: _selectedGradeId,
                  decoration: const InputDecoration(labelText: 'Select Grade', border: OutlineInputBorder()),
                  items: _grades.map((grade) {
                    return DropdownMenuItem<int>(
                      value: grade['id'] as int,
                      child: Text(grade['name']),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedGradeId = val),
                ),
                const SizedBox(height: 16),
            
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm Password', border: OutlineInputBorder()),
                  onSubmitted: (_) => _handleSignup(),
                ),
                const SizedBox(height: 24),
                
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                      : const Text('Sign Up'),
                ),
                
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text("Already have an account? Log In"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
