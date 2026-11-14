import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class AppTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;

  /// Fonte de largura fixa (cifra: o acorde fica em cima da sílaba certa).
  final bool monospace;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.focusNode,
    this.textInputAction,
    this.monospace = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          obscureText: widget.obscureText && !_showPassword,
          // Campo de várias linhas precisa ser multiline: no navegador o
          // TextInputType.text vira <input>, que joga fora as quebras de
          // linha de um texto colado (a cifra virava um parágrafo corrido).
          keyboardType: widget.maxLines != 1 &&
                  !widget.obscureText &&
                  widget.keyboardType == TextInputType.text
              ? TextInputType.multiline
              : widget.keyboardType,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          focusNode: widget.focusNode,
          textInputAction: widget.textInputAction,
          style: TextStyle(
            fontFamily: widget.monospace ? 'JetBrainsMono' : 'Poppins',
            fontSize: widget.monospace ? 13 : 15,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: widget.prefixIcon,
            suffixIcon: widget.obscureText
                ? IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textSecondaryLight,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() => _showPassword = !_showPassword);
                    },
                  )
                : widget.suffixIcon,
          ),
        ),
      ],
    );
  }
}
