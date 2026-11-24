import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/brand_logo.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../bloc/app_lock_cubit.dart';

/// Biometric + Mandatory Salted-PIN Fallback Lock Gate (`SCR-SEC-001`, `AC-SEC-001`).
class AppLockGateScreen extends StatefulWidget {
  const AppLockGateScreen({super.key});

  @override
  State<AppLockGateScreen> createState() => _AppLockGateScreenState();
}

class _AppLockGateScreenState extends State<AppLockGateScreen>
    with SingleTickerProviderStateMixin {
  final _pinCtrl = TextEditingController();
  late final AnimationController _shakeCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _pinCtrl.addListener(_onPinChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lockState = context.read<AppLockCubit>().state;
      if (lockState.biometricEnabled && lockState.biometricAvailable) {
        context.read<AppLockCubit>().unlockWithBiometrics();
      }
    });
  }

  void _onPinChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pinCtrl.removeListener(_onPinChanged);
    _pinCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _appendDigit(String digit) {
    if (_pinCtrl.text.length >= 12) return;
    HapticFeedback.selectionClick();
    _pinCtrl.text = '${_pinCtrl.text}$digit';
  }

  void _backspace() {
    if (_pinCtrl.text.isEmpty) return;
    HapticFeedback.selectionClick();
    _pinCtrl.text = _pinCtrl.text.substring(0, _pinCtrl.text.length - 1);
  }

  void _clearPin() {
    if (_pinCtrl.text.isEmpty) return;
    HapticFeedback.selectionClick();
    _pinCtrl.clear();
  }

  Future<void> _verifyPin() async {
    if (_pinCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    final ok = await context.read<AppLockCubit>().unlockWithPin(_pinCtrl.text);
    if (!ok && mounted) {
      HapticFeedback.heavyImpact();
      _pinCtrl.clear();
      if (!MediaQuery.disableAnimationsOf(context)) {
        _shakeCtrl.forward(from: 0.0);
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    final pinLen = _pinCtrl.text.length;
    final dotSlots = math.max(4, math.min(pinLen, 12));

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.7),
            radius: 1.1,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.55),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: BlocBuilder<AppLockCubit, AppLockState>(
                  builder: (context, state) {
                    return AnimatedBuilder(
                      animation: _shakeCtrl,
                      builder: (context, child) {
                        final t = _shakeCtrl.value;
                        final dx = math.sin(t * math.pi * 4) * 10 * (1 - t);
                        return Transform.translate(
                          offset: Offset(dx, 0),
                          child: child,
                        );
                      },
                      child: PressScaleCard(
                        borderRadius: AppSpacing.radiusXl,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Center(
                              child: PocketCfoLogo(
                                size: 56,
                                animateEntrance: true,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Pocket CFO Locked',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              'Authenticate to unlock your encrypted profiles.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cfo.subtleText),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            // Animated tactile PIN dot visualizer
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var i = 0; i < dotSlots; i++)
                                  AnimatedContainer(
                                    duration: AppMotion.resolve(
                                      context,
                                      AppMotion.fast,
                                    ),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    width: i < pinLen ? 12 : 10,
                                    height: i < pinLen ? 12 : 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i < pinLen
                                          ? scheme.primary
                                          : cfo.divider,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            if (state.errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: cfo.expenseContainer,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusMd,
                                  ),
                                ),
                                child: Text(
                                  state.errorMessage!,
                                  style: TextStyle(
                                    color: cfo.expense,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            FintechTextField(
                              label: 'Fallback App PIN',
                              controller: _pinCtrl,
                              leadingIcon: Icons.pin_outlined,
                              obscureText: true,
                              enableObscureToggle: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              onSubmitted: (_) => _verifyPin(),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _PinKeypad(
                              onDigit: _appendDigit,
                              onBackspace: _backspace,
                              onClear: _clearPin,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FilledButton(
                              onPressed: _submitting ? null : _verifyPin,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Unlock with PIN'),
                            ),
                            if (state.biometricEnabled &&
                                state.biometricAvailable) ...[
                              const SizedBox(height: AppSpacing.sm),
                              OutlinedButton.icon(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  context
                                      .read<AppLockCubit>()
                                      .unlockWithBiometrics();
                                },
                                icon: const Icon(Icons.fingerprint_rounded),
                                label: const Text('Use Biometrics'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final rows = const [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['CLR', '0', 'DEL'],
    ];

    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            children: [
              for (final key in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Material(
                      color: cfo.surfaceTonal,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        onTap: () {
                          if (key == 'CLR') {
                            onClear();
                          } else if (key == 'DEL') {
                            onBackspace();
                          } else {
                            onDigit(key);
                          }
                        },
                        child: SizedBox(
                          height: 48,
                          child: Center(
                            child: key == 'DEL'
                                ? const Icon(Icons.backspace_outlined, size: 18)
                                : key == 'CLR'
                                ? Text(
                                    'Clear',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: cfo.subtleText),
                                  )
                                : Text(
                                    key,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
