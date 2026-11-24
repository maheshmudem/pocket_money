import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/brand_logo.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../bloc/auth_cubit.dart';

/// Covers `SCR-ONB-002` (Welcome), `SCR-AUTH-001` (Sign In),
/// `SCR-AUTH-002` (Create Account), and `SCR-AUTH-003` (Recovery).
class WelcomeAuthPage extends StatefulWidget {
  const WelcomeAuthPage({super.key});

  @override
  State<WelcomeAuthPage> createState() => _WelcomeAuthPageState();
}

enum _AuthTab { welcome, signIn, register, recovery }

class _WelcomeAuthPageState extends State<WelcomeAuthPage> {
  _AuthTab _tab = _AuthTab.welcome;
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cubit = context.read<AuthCubit>();
    if (_tab == _AuthTab.signIn) {
      await cubit.login(email: _emailCtrl.text, password: _passwordCtrl.text);
    } else if (_tab == _AuthTab.register) {
      await cubit.register(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        displayName: _nameCtrl.text,
      );
    } else if (_tab == _AuthTab.recovery) {
      await cubit.requestPasswordReset(_emailCtrl.text);
    }
  }

  ({double score, String label, Color color}) _passwordStrength(
    String pwd,
    PocketCfoColors cfo,
  ) {
    var points = 0;
    if (pwd.length >= 10) points++;
    if (pwd.length >= 14) points++;
    if (RegExp(r'[A-Z]').hasMatch(pwd) && RegExp(r'[a-z]').hasMatch(pwd)) {
      points++;
    }
    if (RegExp(r'[0-9]').hasMatch(pwd)) points++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pwd)) points++;

    if (pwd.isEmpty) {
      return (score: 0.0, label: 'Min 10 characters', color: cfo.subtleText);
    }
    if (points <= 2) {
      return (score: 0.35, label: 'Weak passphrase', color: cfo.expense);
    }
    if (points <= 4) {
      return (score: 0.70, label: 'Good strength', color: cfo.warning);
    }
    return (score: 1.0, label: 'Strong passphrase', color: cfo.success);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    final switchDuration = AppMotion.resolve(context, AppMotion.standard);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.75),
            radius: 1.15,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.65),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= AppBreakpoints.expanded;
              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? AppSpacing.xl : AppSpacing.md,
                    vertical: AppSpacing.lg,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 1040 : 460),
                    child: BlocBuilder<AuthCubit, AuthState>(
                      builder: (context, state) {
                        final statusBanners = <Widget>[
                          if (state.failure != null) ...[
                            PressScaleCard(
                              backgroundColor: cfo.expenseContainer,
                              borderColor: cfo.expense.withValues(alpha: 0.35),
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: cfo.expense,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      state.failure!.message,
                                      style: TextStyle(
                                        color: cfo.expense,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          if (state.infoMessage != null) ...[
                            PressScaleCard(
                              backgroundColor: cfo.successContainer,
                              borderColor: cfo.success.withValues(alpha: 0.35),
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: cfo.success,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      state.infoMessage!,
                                      style: TextStyle(
                                        color: cfo.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ];

                        final brandHeader = StaggeredFadeSlide(
                          index: 0,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              PocketCfoLogo(
                                size: isWide ? 52 : 48,
                                animateEntrance: true,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusFull,
                                        ),
                                      ),
                                      child: Text(
                                        'LOCAL-FIRST • ENCRYPTED',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: scheme.onPrimaryContainer,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.6,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Pocket CFO',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineMedium,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: const Key('welcome_view_tour_btn'),
                                tooltip: 'App Walkthrough Tour',
                                onPressed: () =>
                                    context.push('/onboarding?replay=true'),
                                icon: Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 20,
                                  color: cfo.subtleText,
                                ),
                              ),
                              const ThemeQuickToggleButton(
                                size: 42,
                                iconSize: 22,
                              ),
                            ],
                          ),
                        );

                        final activeCard = AnimatedSwitcher(
                          duration: switchDuration,
                          child: _tab == _AuthTab.welcome
                              ? KeyedSubtree(
                                  key: const ValueKey('welcome_card'),
                                  child: _buildWelcomeCard(
                                    context,
                                    state,
                                    includeFeatures: !isWide,
                                  ),
                                )
                              : KeyedSubtree(
                                  key: ValueKey('auth_form_${_tab.name}'),
                                  child: _buildAuthForm(context, state),
                                ),
                        );

                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    brandHeader,
                                    const SizedBox(height: AppSpacing.lg),
                                    Text(
                                      'Smart money clarity for your life, family & business.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(height: 1.2),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      'Track accounts, splits, budgets, loans & FX with zero spreadsheets — backed by an immutable double-entry SQLite vault.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(color: cfo.subtleText),
                                    ),
                                    const SizedBox(height: AppSpacing.xl),
                                    _FeatureBullet(
                                      icon: Icons.enhanced_encryption_rounded,
                                      iconColor: scheme.primary,
                                      iconBg: scheme.primaryContainer,
                                      title: 'Private AES-256 Vault',
                                      subtitle:
                                          'Encrypted directly on your device with Keystore keys.',
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    _FeatureBullet(
                                      icon: Icons.layers_rounded,
                                      iconColor: cfo.income,
                                      iconBg: cfo.incomeContainer,
                                      title: 'Multi-Profile Isolation',
                                      subtitle:
                                          'Separate Personal, Family, and Business ledgers & FX.',
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    _FeatureBullet(
                                      icon: Icons.cloud_done_rounded,
                                      iconColor: cfo.transfer,
                                      iconBg: cfo.transferContainer,
                                      title: 'Instant Offline Speed',
                                      subtitle:
                                          'Works 100% offline; link cloud sync whenever you want.',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xxxl),
                              Expanded(
                                flex: 5,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 440,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [...statusBanners, activeCard],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            brandHeader,
                            const SizedBox(height: AppSpacing.md),
                            ...statusBanners,
                            activeCard,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(
    BuildContext context,
    AuthState state, {
    required bool includeFeatures,
  }) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    return StaggeredFadeSlide(
      index: 1,
      child: PressScaleCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        borderRadius: AppSpacing.radiusXl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (includeFeatures) ...[
              Text(
                'Smart money clarity for your life, family & business.',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Track accounts, splits, budgets, loans & FX with zero spreadsheets.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
              ),
              const SizedBox(height: AppSpacing.md),
              _FeatureBullet(
                icon: Icons.enhanced_encryption_rounded,
                iconColor: scheme.primary,
                iconBg: scheme.primaryContainer,
                title: 'Private AES-256 Vault',
                subtitle:
                    'Encrypted directly on your device with Keystore keys.',
              ),
              const SizedBox(height: AppSpacing.xs),
              _FeatureBullet(
                icon: Icons.layers_rounded,
                iconColor: cfo.income,
                iconBg: cfo.incomeContainer,
                title: 'Multi-Profile Isolation',
                subtitle:
                    'Separate Personal, Family, and Business ledgers & FX.',
              ),
              const SizedBox(height: AppSpacing.xs),
              _FeatureBullet(
                icon: Icons.cloud_done_rounded,
                iconColor: cfo.transfer,
                iconBg: cfo.transferContainer,
                title: 'Instant Offline Speed',
                subtitle:
                    'Works 100% offline; link cloud sync whenever you want.',
              ),
              const SizedBox(height: AppSpacing.md),
            ] else ...[
              Text(
                'Workspace Access',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Start immediately with an isolated on-device vault or sign in to sync across devices.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            FilledButton.icon(
              onPressed: state.isSubmitting
                  ? null
                  : () => context.read<AuthCubit>().continueOfflineLocal(),
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Start Offline Local Workspace'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: state.isSubmitting
                  ? null
                  : () => setState(() => _tab = _AuthTab.signIn),
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Sign In with Cloud Account'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: state.isSubmitting
                  ? null
                  : () => setState(() => _tab = _AuthTab.register),
              child: const Text('Create Cloud Account'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: cfo.surfaceTonal,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 15,
                    color: cfo.subtleText,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Never collects bank passwords, ATM PINs, or UPI PINs.',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthForm(BuildContext context, AuthState state) {
    final cfo = context.cfoColors;
    final title = switch (_tab) {
      _AuthTab.signIn => 'Sign In',
      _AuthTab.register => 'Create Cloud Account',
      _AuthTab.recovery => 'Password Recovery',
      _AuthTab.welcome => '',
    };
    final strength = _passwordStrength(_passwordCtrl.text, cfo);

    return PressScaleCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderRadius: AppSpacing.radiusXl,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => setState(() => _tab = _AuthTab.welcome),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_tab == _AuthTab.register) ...[
              FintechTextFormField(
                label: 'Display Name',
                controller: _nameCtrl,
                leadingIcon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                showClearButton: true,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            FintechTextFormField(
              label: 'Email Address',
              controller: _emailCtrl,
              leadingIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              showClearButton: true,
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Enter a valid email address'
                  : null,
            ),
            if (_tab != _AuthTab.recovery) ...[
              const SizedBox(height: AppSpacing.sm),
              FintechTextFormField(
                label: 'Password',
                controller: _passwordCtrl,
                leadingIcon: Icons.lock_outline_rounded,
                obscureText: true,
                enableObscureToggle: true,
                onChanged: (_) {
                  if (_tab == _AuthTab.register) {
                    setState(() {});
                  }
                },
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (_tab == _AuthTab.register && v.length < 10) {
                    return 'Use at least 10 characters';
                  }
                  return null;
                },
              ),
              if (_tab == _AuthTab.register) ...[
                const SizedBox(height: AppSpacing.xs),
                AnimatedProgressBar(
                  value: strength.score,
                  color: strength.color,
                  height: 6,
                ),
                const SizedBox(height: 4),
                Text(
                  strength.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: strength.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: state.isSubmitting ? null : _submit,
              child: state.isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(title),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_tab == _AuthTab.signIn)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: AppSpacing.xs,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _tab = _AuthTab.recovery),
                    child: const Text('Forgot password?'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _tab = _AuthTab.register),
                    child: const Text('Create account'),
                  ),
                ],
              ),
            if (_tab == _AuthTab.register)
              TextButton(
                onPressed: () => setState(() => _tab = _AuthTab.signIn),
                child: const Text('Already have an account? Sign In'),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconSquircle(
          icon: icon,
          iconColor: iconColor,
          backgroundColor: iconBg,
          size: 40,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.cfoColors.subtleText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
