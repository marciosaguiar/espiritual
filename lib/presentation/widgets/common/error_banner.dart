import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// A strip shown above a list when it could not be loaded.
///
/// Before this, a failed listener left the screen looking merely empty — which
/// a person reads as "the app is broken" or "there is nothing here". Saying
/// what happened, and offering a retry, is the difference between a bug and a
/// hiccup.
class ErrorBanner extends StatelessWidget {
  final String message;

  /// Tapping "Tentar de novo" calls this. Hidden when null.
  final VoidCallback? onRetry;

  const ErrorBanner({super.key, required this.message, this.onRetry});

  /// Nothing when [message] is null, the strip otherwise. Lets a screen write
  /// `ErrorBanner.maybe(provider.error, onRetry: ...)` without an `if`.
  static Widget maybe(String? message, {VoidCallback? onRetry}) {
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    return ErrorBanner(message: message, onRetry: onRetry);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.red,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Tentar de novo',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.red,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
