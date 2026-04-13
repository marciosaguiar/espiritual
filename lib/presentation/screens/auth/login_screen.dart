import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      name: _nameCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? AppStrings.errorGeneric),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.authGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      const SizedBox(height: 60),
                      // Logo
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        AppStrings.appName,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Text(
                        AppStrings.appTagline,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 48),
                      // Form Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Entrar na conta',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryLight,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Bem-vindo de volta, levita!',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              const SizedBox(height: 24),
                              AppTextField(
                                label: AppStrings.name,
                                hint: AppStrings.namePlaceholder,
                                controller: _nameCtrl,
                                prefixIcon: const Icon(Icons.person_outline, size: 20),
                                textInputAction: TextInputAction.next,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return AppStrings.errorNameRequired;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              AppTextField(
                                label: AppStrings.password,
                                hint: AppStrings.passwordPlaceholder,
                                controller: _passwordCtrl,
                                obscureText: true,
                                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _login(),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return AppStrings.errorPasswordRequired;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              Consumer<AuthProvider>(
                                builder: (ctx, auth, _) => AppGradientButton(
                                  label: AppStrings.login,
                                  isLoading: auth.isLoading,
                                  onPressed: _login,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Register link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            AppStrings.dontHaveAccount,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              AppStrings.createAccount,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
