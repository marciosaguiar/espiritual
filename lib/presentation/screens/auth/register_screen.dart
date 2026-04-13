import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/user_model.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  UserInstrument _selectedInstrument = UserInstrument.vocalist;
  UserRole _selectedRole = UserRole.levita;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      name: _nameCtrl.text.trim(),
      password: _passwordCtrl.text,
      instrument: _selectedInstrument,
      role: _selectedRole,
    );
    if (success && mounted) {
      Navigator.pop(context);
    } else if (mounted) {
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
              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Criar\nConta',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Junte-se ao ministério de louvor',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
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
                                  if (v.trim().length < 3) {
                                    return AppStrings.errorNameTooShort;
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
                                textInputAction: TextInputAction.next,
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return AppStrings.errorPasswordRequired;
                                  }
                                  if (v.length < 6) {
                                    return AppStrings.errorPasswordTooShort;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              AppTextField(
                                label: AppStrings.confirmPassword,
                                hint: 'Repita a senha',
                                controller: _confirmCtrl,
                                obscureText: true,
                                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                textInputAction: TextInputAction.done,
                                validator: (v) {
                                  if (v != _passwordCtrl.text) {
                                    return AppStrings.errorPasswordsNotMatch;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              // Instrument selector
                              const Text(
                                'Instrumento',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: UserInstrument.values.map((inst) {
                                  final selected = _selectedInstrument == inst;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() => _selectedInstrument = inst);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.blue
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: selected
                                              ? AppColors.blue
                                              : Colors.grey.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        '${inst.emoji} ${inst.label}',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: selected
                                              ? Colors.white
                                              : AppColors.textPrimaryLight,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                              // Role selector (first user becomes admin)
                              const Text(
                                'Função',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: UserRole.values.map((role) {
                                  final selected = _selectedRole == role;
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() => _selectedRole = role);
                                      },
                                      child: Container(
                                        margin: EdgeInsets.only(
                                          right: role == UserRole.admin ? 0 : 8,
                                          left: role == UserRole.admin ? 8 : 0,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? AppColors.red
                                              : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: selected
                                                ? AppColors.red
                                                : Colors.grey.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          role == UserRole.admin ? '👑 ${role.label}' : '🎵 ${role.label}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: selected
                                                ? Colors.white
                                                : AppColors.textPrimaryLight,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                              Consumer<AuthProvider>(
                                builder: (ctx, auth, _) => AppGradientButton(
                                  label: AppStrings.register,
                                  isLoading: auth.isLoading,
                                  onPressed: _register,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            AppStrings.alreadyHaveAccount,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              AppStrings.loginHere,
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
