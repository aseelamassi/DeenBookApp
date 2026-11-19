import 'package:flutter/material.dart';

import 'theme.dart';

/// Local-only, approximate UI guidance. Never logs or transmits passwords.
/// The existing registration validator still enforces the server-compatible
/// minimum length; this indicator does not alter that validation policy.
enum PasswordStrength { empty, weak, medium, strong }

class PasswordAssessment {
  const PasswordAssessment(this.strength, this.hint);

  final PasswordStrength strength;
  final String hint;

  String get label => switch (strength) {
        PasswordStrength.empty => 'لم تُكتب بعد',
        PasswordStrength.weak => 'ضعيفة',
        PasswordStrength.medium => 'متوسطة',
        PasswordStrength.strong => 'قوية',
      };

  int get segments => switch (strength) {
        PasswordStrength.empty => 0,
        PasswordStrength.weak => 1,
        PasswordStrength.medium => 2,
        PasswordStrength.strong => 3,
      };
}

PasswordAssessment assessPasswordStrength(String password) {
  if (password.isEmpty) {
    return const PasswordAssessment(
      PasswordStrength.empty,
      'ابدأ بكتابة كلمة المرور لمعرفة قوتها.',
    );
  }
  if (password.runes.length < 12) {
    return const PasswordAssessment(
      PasswordStrength.weak,
      'استخدم 12 حرفًا على الأقل. يُفضّل مزج الحروف والأرقام والرموز.',
    );
  }

  final lower = password.toLowerCase();
  const predictableParts = <String>[
    'password', 'qwerty', '123456', 'abcdef', 'admin123', '111111',
    '000000', 'كلمةالمرور',
  ];
  if (predictableParts.any(lower.contains) || password.runes.toSet().length < 6) {
    return const PasswordAssessment(
      PasswordStrength.weak,
      'تجنب الكلمات الشائعة أو الأنماط المتوقعة، وأضف تنوعًا أكبر.',
    );
  }

  final types = <bool>[
    RegExp(r'[a-z\u0600-\u06ff]').hasMatch(password),
    RegExp(r'[A-Z]').hasMatch(password),
    RegExp(r'[0-9\u0660-\u0669]').hasMatch(password),
    RegExp(r'[^a-zA-Z0-9\u0600-\u06ff\s]').hasMatch(password),
  ].where((present) => present).length;
  final length = password.runes.length;
  final distinct = password.runes.toSet().length;

  if (((length >= 16 && types >= 3) ||
          (length >= 20 && types >= 2)) &&
      distinct >= 9) {
    return const PasswordAssessment(
      PasswordStrength.strong,
      'اختيار جيد. استخدم كلمة مرور فريدة لا تستعملها لحسابات أخرى.',
    );
  }
  if ((types >= 2 || length >= 18) && distinct >= 6) {
    return const PasswordAssessment(
      PasswordStrength.medium,
      'لزيادة القوة: اجعلها أطول، وأضف تنوعًا وتجنب المعلومات المتوقعة.',
    );
  }
  return const PasswordAssessment(
    PasswordStrength.weak,
    'أضف حروفًا وأرقامًا أو رموزًا مختلفة، وتجنب التكرار.',
  );
}

/// Displays password strength immediately while the registration field changes.
class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final assessment = assessPasswordStrength(value.text);
          final strengthColor = switch (assessment.strength) {
            PasswordStrength.empty => muted,
            PasswordStrength.weak => const Color(0xFFBE123C),
            PasswordStrength.medium => const Color(0xFFD97706),
            PasswordStrength.strong => green,
          };
          return Semantics(
            liveRegion: true,
            label: 'قوة كلمة المرور: ${assessment.label}. ${assessment.hint}',
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'قوة كلمة المرور',
                        style: appText(11, color: secondaryText),
                      ),
                      Text(
                        assessment.label,
                        key: const Key('registration-password-strength-label'),
                        style: appText(11, color: strengthColor,
                            weight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: AnimatedContainer(
                            key: Key('registration-password-strength-bar-$i'),
                            duration: const Duration(milliseconds: 180),
                            height: 6,
                            decoration: BoxDecoration(
                              color: i < assessment.segments
                                  ? strengthColor
                                  : lineColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    assessment.hint,
                    key: const Key('registration-password-strength-hint'),
                    style: appText(10, color: secondaryText),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'مؤشر إرشادي تقريبي، وليس ضمانًا لأمان كلمة المرور.',
                    style: appText(9, color: muted),
                  ),
                ],
              ),
            ),
          );
        },
      );
