import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'currency.dart';
import 'money.dart';

/// Real-world financial life-stage personas driving budgeting, EMI guardrails,
/// emergency-fund months, and saving strategies.
enum LifeStageStatus {
  studentStarter(
    wireValue: 'student_starter',
    shortLabel: 'Student',
    title: 'Student / Starter',
    tagline: 'Pocket money, stipend & first savings habit',
    baseNeedsPct: 50,
    baseWantsPct: 25,
    baseSavingsPct: 25,
    baseTaxPct: 0,
    baseMaxDtiPct: 10,
    baseEmergencyMonths: 3,
  ),
  bachelor(
    wireValue: 'bachelor',
    shortLabel: 'Bachelor',
    title: 'Bachelor / Single Earner',
    tagline: 'Lean PG/rent & aggressive 35% wealth compounding',
    baseNeedsPct: 40,
    baseWantsPct: 25,
    baseSavingsPct: 35,
    baseTaxPct: 0,
    baseMaxDtiPct: 30,
    baseEmergencyMonths: 6,
  ),
  marriedCouple(
    wireValue: 'married_couple',
    shortLabel: 'Couple',
    title: 'Married Couple (DINK)',
    tagline: 'Shared household, joint goals & home down-payment',
    baseNeedsPct: 45,
    baseWantsPct: 20,
    baseSavingsPct: 35,
    baseTaxPct: 0,
    baseMaxDtiPct: 32,
    baseEmergencyMonths: 6,
  ),
  familyWithKids(
    wireValue: 'family_with_kids',
    shortLabel: 'Family',
    title: 'Family with Kids',
    tagline: 'Rent/EMI, groceries, school fees & family safety net',
    baseNeedsPct: 55,
    baseWantsPct: 15,
    baseSavingsPct: 30,
    baseTaxPct: 0,
    baseMaxDtiPct: 28,
    baseEmergencyMonths: 8,
  ),
  sandwichFamily(
    wireValue: 'sandwich_family',
    shortLabel: 'Parents Care',
    title: 'Supporting Parents & Family',
    tagline: 'Household bills + parents medical care & strict EMI guard',
    baseNeedsPct: 60,
    baseWantsPct: 10,
    baseSavingsPct: 30,
    baseTaxPct: 0,
    baseMaxDtiPct: 25,
    baseEmergencyMonths: 9,
  ),
  freelancerBusiness(
    wireValue: 'freelancer_business',
    shortLabel: 'Freelancer',
    title: 'Freelancer / Business Owner',
    tagline: 'Variable income, 20% tax shield & 12-month cash runway',
    baseNeedsPct: 35,
    baseWantsPct: 10,
    baseSavingsPct: 35,
    baseTaxPct: 20,
    baseMaxDtiPct: 20,
    baseEmergencyMonths: 12,
  ),
  preRetirement(
    wireValue: 'pre_retirement',
    shortLabel: 'Debt-Free',
    title: 'Pre-Retirement / Debt-Free',
    tagline: 'Capital preservation, zero bad debt & 40% corpus focus',
    baseNeedsPct: 45,
    baseWantsPct: 15,
    baseSavingsPct: 40,
    baseTaxPct: 0,
    baseMaxDtiPct: 15,
    baseEmergencyMonths: 12,
  );

  const LifeStageStatus({
    required this.wireValue,
    required this.shortLabel,
    required this.title,
    required this.tagline,
    required this.baseNeedsPct,
    required this.baseWantsPct,
    required this.baseSavingsPct,
    required this.baseTaxPct,
    required this.baseMaxDtiPct,
    required this.baseEmergencyMonths,
  });

  final String wireValue;
  final String shortLabel;
  final String title;
  final String tagline;
  final int baseNeedsPct;
  final int baseWantsPct;
  final int baseSavingsPct;
  final int baseTaxPct;
  final int baseMaxDtiPct;
  final int baseEmergencyMonths;

  String get ratioBadge => baseTaxPct > 0
      ? '$baseNeedsPct/$baseWantsPct/$baseTaxPct/$baseSavingsPct • ${baseEmergencyMonths}m'
      : '$baseNeedsPct/$baseWantsPct/$baseSavingsPct • ${baseEmergencyMonths}m';

  static LifeStageStatus fromWire(String? raw) => switch (raw) {
    'student_starter' => LifeStageStatus.studentStarter,
    'bachelor' => LifeStageStatus.bachelor,
    'married_couple' => LifeStageStatus.marriedCouple,
    'family_with_kids' => LifeStageStatus.familyWithKids,
    'sandwich_family' => LifeStageStatus.sandwichFamily,
    'freelancer_business' => LifeStageStatus.freelancerBusiness,
    'pre_retirement' => LifeStageStatus.preRetirement,
    _ => LifeStageStatus.bachelor,
  };
}

enum HousingMode {
  renting('renting', 'Renting / PG'),
  homeLoanEmi('home_emi', 'Home Loan EMI'),
  ownedOrFamily('owned', 'Own / Family Home');

  const HousingMode(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static HousingMode fromWire(String? raw) => switch (raw) {
    'home_emi' => HousingMode.homeLoanEmi,
    'owned' => HousingMode.ownedOrFamily,
    _ => HousingMode.renting,
  };
}

enum DebtPayoffStrategy {
  avalanche(
    'Avalanche',
    'Highest interest rate first — saves maximum interest',
  ),
  snowball('Snowball', 'Smallest balance first — fastest debt-free wins');

  const DebtPayoffStrategy(this.label, this.subtitle);
  final String label;
  final String subtitle;
}

final class EffectiveLifeStageTargets extends Equatable {
  const EffectiveLifeStageTargets({
    required this.status,
    required this.dependentsCount,
    required this.housingMode,
    required this.needsPct,
    required this.wantsPct,
    required this.savingsPct,
    required this.taxPct,
    required this.maxSafeDtiPct,
    required this.emergencyMonths,
  });

  final LifeStageStatus status;
  final int dependentsCount;
  final HousingMode housingMode;
  final int needsPct;
  final int wantsPct;
  final int savingsPct;
  final int taxPct;
  final int maxSafeDtiPct;
  final int emergencyMonths;

  @override
  List<Object?> get props => [
    status,
    dependentsCount,
    housingMode,
    needsPct,
    wantsPct,
    savingsPct,
    taxPct,
    maxSafeDtiPct,
    emergencyMonths,
  ];
}

final class LifeStageCategoryInput extends Equatable {
  const LifeStageCategoryInput({
    required this.categoryId,
    required this.categoryName,
    required this.currentMonthSpendMinor,
  });

  final String categoryId;
  final String categoryName;
  final int currentMonthSpendMinor;

  @override
  List<Object?> get props => [categoryId, categoryName, currentMonthSpendMinor];
}

final class LifeStageCategoryRecommendation extends Equatable {
  const LifeStageCategoryRecommendation({
    required this.categoryId,
    required this.categoryName,
    required this.bucketLabel,
    required this.recommendedLimitMinor,
    required this.actualSpendMinor,
    required this.shareOfIncomePercent,
  });

  final String categoryId;
  final String categoryName;
  final String bucketLabel; // 'Essential Need' | 'Lifestyle Want'
  final int recommendedLimitMinor;
  final int actualSpendMinor;
  final double shareOfIncomePercent;

  bool get isOverRecommended =>
      recommendedLimitMinor > 0 && actualSpendMinor > recommendedLimitMinor;

  @override
  List<Object?> get props => [
    categoryId,
    categoryName,
    bucketLabel,
    recommendedLimitMinor,
    actualSpendMinor,
    shareOfIncomePercent,
  ];
}

final class LifeStageBudgetBlueprint extends Equatable {
  const LifeStageBudgetBlueprint({
    required this.currencyCode,
    required this.incomePoolMinor,
    required this.targets,
    required this.needsTargetMinor,
    required this.wantsTargetMinor,
    required this.taxTargetMinor,
    required this.savingsTargetMinor,
    required this.actualNeedsMinor,
    required this.actualWantsMinor,
    required this.actualTotalSpendMinor,
    required this.recommendations,
  });

  final String currencyCode;
  final int incomePoolMinor;
  final EffectiveLifeStageTargets targets;
  final int needsTargetMinor;
  final int wantsTargetMinor;
  final int taxTargetMinor;
  final int savingsTargetMinor;
  final int actualNeedsMinor;
  final int actualWantsMinor;
  final int actualTotalSpendMinor;
  final List<LifeStageCategoryRecommendation> recommendations;

  Map<String, int> get categoryLimitsMap => {
    for (final r in recommendations)
      if (r.recommendedLimitMinor > 0) r.categoryId: r.recommendedLimitMinor,
  };

  int get totalRecommendedCategoriesMinor =>
      recommendations.fold<int>(0, (s, r) => s + r.recommendedLimitMinor);

  @override
  List<Object?> get props => [
    currencyCode,
    incomePoolMinor,
    targets,
    needsTargetMinor,
    wantsTargetMinor,
    taxTargetMinor,
    savingsTargetMinor,
    actualNeedsMinor,
    actualWantsMinor,
    actualTotalSpendMinor,
    recommendations,
  ];
}

final class ActiveLoanSnapshot extends Equatable {
  const ActiveLoanSnapshot({
    required this.loanId,
    required this.name,
    required this.remainingPrincipalMinor,
    required this.monthlyEmiMinor,
    required this.annualInterestRateBps,
    required this.remainingMonths,
  });

  final String loanId;
  final String name;
  final int remainingPrincipalMinor;
  final int monthlyEmiMinor;
  final int annualInterestRateBps;
  final int remainingMonths;

  double get annualRatePercent => annualInterestRateBps / 100.0;
  bool get isHighInterestBadDebt => annualInterestRateBps >= 1200; // >= 12% APR

  @override
  List<Object?> get props => [
    loanId,
    name,
    remainingPrincipalMinor,
    monthlyEmiMinor,
    annualInterestRateBps,
    remainingMonths,
  ];
}

final class EmiHealthSummary extends Equatable {
  const EmiHealthSummary({
    required this.currencyCode,
    required this.monthlyIncomeMinor,
    required this.totalMonthlyEmiMinor,
    required this.totalRemainingDebtMinor,
    required this.dtiPercent,
    required this.maxSafeDtiPct,
    required this.safeEmiCeilingMinor,
    required this.availableNewEmiHeadroomMinor,
    required this.dtiStatus,
    required this.verdict,
    required this.highInterestLoans,
    required this.loans,
  });

  final String currencyCode;
  final int monthlyIncomeMinor;
  final int totalMonthlyEmiMinor;
  final int totalRemainingDebtMinor;
  final double dtiPercent;
  final int maxSafeDtiPct;
  final int safeEmiCeilingMinor;
  final int availableNewEmiHeadroomMinor;

  /// `'healthy'` | `'caution'` | `'stressed'`
  final String dtiStatus;
  final String verdict;
  final List<ActiveLoanSnapshot> highInterestLoans;
  final List<ActiveLoanSnapshot> loans;

  bool get hasHighInterestDebt => highInterestLoans.isNotEmpty;

  @override
  List<Object?> get props => [
    currencyCode,
    monthlyIncomeMinor,
    totalMonthlyEmiMinor,
    totalRemainingDebtMinor,
    dtiPercent,
    maxSafeDtiPct,
    safeEmiCeilingMinor,
    availableNewEmiHeadroomMinor,
    dtiStatus,
    verdict,
    highInterestLoans,
    loans,
  ];
}

final class DebtStrategyResult extends Equatable {
  const DebtStrategyResult({
    required this.strategy,
    required this.monthsToDebtFree,
    required this.totalInterestMinor,
    required this.monthsSavedVsBaseline,
    required this.interestSavedVsBaselineMinor,
    required this.payoffOrderNames,
  });

  final DebtPayoffStrategy strategy;
  final int monthsToDebtFree;
  final int totalInterestMinor;
  final int monthsSavedVsBaseline;
  final int interestSavedVsBaselineMinor;
  final List<String> payoffOrderNames;

  @override
  List<Object?> get props => [
    strategy,
    monthsToDebtFree,
    totalInterestMinor,
    monthsSavedVsBaseline,
    interestSavedVsBaselineMinor,
    payoffOrderNames,
  ];
}

final class DebtPayoffComparison extends Equatable {
  const DebtPayoffComparison({
    required this.extraMonthlyPrepaymentMinor,
    required this.baselineMonths,
    required this.baselineInterestMinor,
    required this.avalanche,
    required this.snowball,
    required this.recommendedStrategy,
  });

  final int extraMonthlyPrepaymentMinor;
  final int baselineMonths;
  final int baselineInterestMinor;
  final DebtStrategyResult avalanche;
  final DebtStrategyResult snowball;
  final DebtPayoffStrategy recommendedStrategy;

  int get avalancheAdvantageMinor =>
      math.max(0, snowball.totalInterestMinor - avalanche.totalInterestMinor);

  @override
  List<Object?> get props => [
    extraMonthlyPrepaymentMinor,
    baselineMonths,
    baselineInterestMinor,
    avalanche,
    snowball,
    recommendedStrategy,
  ];
}

final class NewEmiAffordabilityResult extends Equatable {
  const NewEmiAffordabilityResult({
    required this.currencyCode,
    required this.estimatedNewEmiMinor,
    required this.combinedMonthlyEmiMinor,
    required this.projectedDtiPercent,
    required this.maxSafeDtiPct,
    required this.remainingPostEmiIncomeMinor,
    required this.verdictCode,
    required this.headline,
    required this.detail,
  });

  final String currencyCode;
  final int estimatedNewEmiMinor;
  final int combinedMonthlyEmiMinor;
  final double projectedDtiPercent;
  final int maxSafeDtiPct;
  final int remainingPostEmiIncomeMinor;

  /// `'safe'` | `'tight'` | `'risky'`
  final String verdictCode;
  final String headline;
  final String detail;

  @override
  List<Object?> get props => [
    currencyCode,
    estimatedNewEmiMinor,
    combinedMonthlyEmiMinor,
    projectedDtiPercent,
    maxSafeDtiPct,
    remainingPostEmiIncomeMinor,
    verdictCode,
    headline,
    detail,
  ];
}

final class EmergencyShieldSnapshot extends Equatable {
  const EmergencyShieldSnapshot({
    required this.currencyCode,
    required this.essentialMonthlyOutgoMinor,
    required this.targetMonths,
    required this.targetCorpusMinor,
    required this.liquidCashMinor,
    required this.coveredMonths,
    required this.shortfallMinor,
    required this.monthlyBridgeSavingMinor,
    required this.shieldScore,
  });

  final String currencyCode;
  final int essentialMonthlyOutgoMinor;
  final int targetMonths;
  final int targetCorpusMinor;
  final int liquidCashMinor;
  final double coveredMonths;
  final int shortfallMinor;
  final int monthlyBridgeSavingMinor;

  /// `0..100` readiness score for radial gauge.
  final int shieldScore;

  bool get isFullyFunded => shortfallMinor <= 0 && targetCorpusMinor > 0;

  @override
  List<Object?> get props => [
    currencyCode,
    essentialMonthlyOutgoMinor,
    targetMonths,
    targetCorpusMinor,
    liquidCashMinor,
    coveredMonths,
    shortfallMinor,
    monthlyBridgeSavingMinor,
    shieldScore,
  ];
}

final class ProtectionCheckItem extends Equatable {
  const ProtectionCheckItem({
    required this.title,
    required this.subtitle,
    required this.priorityBadge,
  });

  final String title;
  final String subtitle;
  final String priorityBadge;

  @override
  List<Object?> get props => [title, subtitle, priorityBadge];
}

final class LifeStageActionTip extends Equatable {
  const LifeStageActionTip({
    required this.title,
    required this.detail,
    required this.tag,
  });

  final String title;
  final String detail;
  final String tag;

  @override
  List<Object?> get props => [title, detail, tag];
}

/// Profile-level bottom-up income & real monthly fixed commitments sheet.
final class MonthlyExpenseProfile extends Equatable {
  const MonthlyExpenseProfile({
    this.primaryIncomeMinor = 0,
    this.secondaryIncomeMinor = 0,
    this.rentOrHousingMinor = 0,
    this.groceriesMinor = 0,
    this.utilitiesMinor = 0,
    this.schoolFeesMinor = 0,
    this.insuranceMinor = 0,
    this.transportFuelMinor = 0,
    this.medicalMinor = 0,
    this.parentsSupportMinor = 0,
    this.subscriptionsMinor = 0,
    this.manualEmiMinor = 0,
    this.otherFixedMinor = 0,
  });

  final int primaryIncomeMinor;
  final int secondaryIncomeMinor;
  final int rentOrHousingMinor;
  final int groceriesMinor;
  final int utilitiesMinor;
  final int schoolFeesMinor;
  final int insuranceMinor;
  final int transportFuelMinor;
  final int medicalMinor;
  final int parentsSupportMinor;
  final int subscriptionsMinor;
  final int manualEmiMinor;
  final int otherFixedMinor;

  int get totalIncomeMinor =>
      math.max<int>(0, primaryIncomeMinor) +
      math.max<int>(0, secondaryIncomeMinor);

  int get totalEnteredExpensesMinor =>
      math.max<int>(0, rentOrHousingMinor) +
      math.max<int>(0, groceriesMinor) +
      math.max<int>(0, utilitiesMinor) +
      math.max<int>(0, schoolFeesMinor) +
      math.max<int>(0, insuranceMinor) +
      math.max<int>(0, transportFuelMinor) +
      math.max<int>(0, medicalMinor) +
      math.max<int>(0, parentsSupportMinor) +
      math.max<int>(0, subscriptionsMinor) +
      math.max<int>(0, manualEmiMinor) +
      math.max<int>(0, otherFixedMinor);

  bool get hasAnyEnteredExpenses => totalEnteredExpensesMinor > 0;

  MonthlyExpenseProfile copyWith({
    int? primaryIncomeMinor,
    int? secondaryIncomeMinor,
    int? rentOrHousingMinor,
    int? groceriesMinor,
    int? utilitiesMinor,
    int? schoolFeesMinor,
    int? insuranceMinor,
    int? transportFuelMinor,
    int? medicalMinor,
    int? parentsSupportMinor,
    int? subscriptionsMinor,
    int? manualEmiMinor,
    int? otherFixedMinor,
  }) => MonthlyExpenseProfile(
    primaryIncomeMinor: primaryIncomeMinor ?? this.primaryIncomeMinor,
    secondaryIncomeMinor: secondaryIncomeMinor ?? this.secondaryIncomeMinor,
    rentOrHousingMinor: rentOrHousingMinor ?? this.rentOrHousingMinor,
    groceriesMinor: groceriesMinor ?? this.groceriesMinor,
    utilitiesMinor: utilitiesMinor ?? this.utilitiesMinor,
    schoolFeesMinor: schoolFeesMinor ?? this.schoolFeesMinor,
    insuranceMinor: insuranceMinor ?? this.insuranceMinor,
    transportFuelMinor: transportFuelMinor ?? this.transportFuelMinor,
    medicalMinor: medicalMinor ?? this.medicalMinor,
    parentsSupportMinor: parentsSupportMinor ?? this.parentsSupportMinor,
    subscriptionsMinor: subscriptionsMinor ?? this.subscriptionsMinor,
    manualEmiMinor: manualEmiMinor ?? this.manualEmiMinor,
    otherFixedMinor: otherFixedMinor ?? this.otherFixedMinor,
  );

  Map<String, int> toJsonMap() => {
    'primary_income': primaryIncomeMinor,
    'secondary_income': secondaryIncomeMinor,
    'rent': rentOrHousingMinor,
    'groceries': groceriesMinor,
    'utilities': utilitiesMinor,
    'school_fees': schoolFeesMinor,
    'insurance': insuranceMinor,
    'transport': transportFuelMinor,
    'medical': medicalMinor,
    'parents': parentsSupportMinor,
    'subscriptions': subscriptionsMinor,
    'manual_emi': manualEmiMinor,
    'other_fixed': otherFixedMinor,
  };

  factory MonthlyExpenseProfile.fromJsonMap(Map<String, dynamic> m) {
    int read(String k) {
      final v = m[k];
      if (v is int) return math.max(0, v);
      if (v is num) return math.max(0, v.round());
      return 0;
    }

    return MonthlyExpenseProfile(
      primaryIncomeMinor: read('primary_income'),
      secondaryIncomeMinor: read('secondary_income'),
      rentOrHousingMinor: read('rent'),
      groceriesMinor: read('groceries'),
      utilitiesMinor: read('utilities'),
      schoolFeesMinor: read('school_fees'),
      insuranceMinor: read('insurance'),
      transportFuelMinor: read('transport'),
      medicalMinor: read('medical'),
      parentsSupportMinor: read('parents'),
      subscriptionsMinor: read('subscriptions'),
      manualEmiMinor: read('manual_emi'),
      otherFixedMinor: read('other_fixed'),
    );
  }

  @override
  List<Object?> get props => [
    primaryIncomeMinor,
    secondaryIncomeMinor,
    rentOrHousingMinor,
    groceriesMinor,
    utilitiesMinor,
    schoolFeesMinor,
    insuranceMinor,
    transportFuelMinor,
    medicalMinor,
    parentsSupportMinor,
    subscriptionsMinor,
    manualEmiMinor,
    otherFixedMinor,
  ];
}

final class ExpenseBenchmarkFlag extends Equatable {
  const ExpenseBenchmarkFlag({
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String title;
  final String detail;

  /// `'warning'` | `'danger'`
  final String severity;

  @override
  List<Object?> get props => [title, detail, severity];
}

final class SurplusWaterfallStep extends Equatable {
  const SurplusWaterfallStep({
    required this.stageNumber,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.amountMinor,
    required this.percentOfIncome,
    this.weeklyAllowanceMinor,
  });

  final int stageNumber;
  final String code;
  final String title;
  final String subtitle;
  final int amountMinor;
  final double percentOfIncome;
  final int? weeklyAllowanceMinor;

  @override
  List<Object?> get props => [
    stageNumber,
    code,
    title,
    subtitle,
    amountMinor,
    percentOfIncome,
    weeklyAllowanceMinor,
  ];
}

final class PlannedCategoryEnvelope extends Equatable {
  const PlannedCategoryEnvelope({
    required this.categoryName,
    required this.tierLabel,
    required this.amountMinor,
    required this.matchKeywords,
    required this.iconKey,
  });

  final String categoryName;
  final String tierLabel;
  final int amountMinor;
  final List<String> matchKeywords;
  final String iconKey;

  @override
  List<Object?> get props => [
    categoryName,
    tierLabel,
    amountMinor,
    matchKeywords,
    iconKey,
  ];
}

final class BottomUpCashFlowPlan extends Equatable {
  const BottomUpCashFlowPlan({
    required this.currencyCode,
    required this.totalIncomeMinor,
    required this.trackedLoanEmiMinor,
    required this.manualEmiMinor,
    required this.totalEmiMinor,
    required this.tier1SurvivalMinor,
    required this.tier2EssentialLivingMinor,
    required this.subscriptionsMinor,
    required this.otherFixedMinor,
    required this.taxReserveMinor,
    required this.totalCommittedOutgoMinor,
    required this.essentialOutgoForShieldMinor,
    required this.netSurplusMinor,
    required this.commitmentRatioPct,
    required this.planMode,
    required this.cashFlowScore,
    required this.recommendedPrepayMinor,
    required this.guiltFreeMonthlyMinor,
    required this.guiltFreeWeeklyMinor,
    required this.totalSavingsAndShieldMinor,
    required this.waterfallSteps,
    required this.deficitRescueSteps,
    required this.benchmarkFlags,
    required this.budgetEnvelopes,
  });

  final String currencyCode;
  final int totalIncomeMinor;
  final int trackedLoanEmiMinor;
  final int manualEmiMinor;
  final int totalEmiMinor;
  final int tier1SurvivalMinor;
  final int tier2EssentialLivingMinor;
  final int subscriptionsMinor;
  final int otherFixedMinor;
  final int taxReserveMinor;
  final int totalCommittedOutgoMinor;
  final int essentialOutgoForShieldMinor;
  final int netSurplusMinor;
  final double commitmentRatioPct;

  /// `'awaiting_income'` | `'deficit_rescue'` | `'tight_stabilize'` | `'wealth_waterfall'`
  final String planMode;
  final int cashFlowScore;
  final int recommendedPrepayMinor;
  final int guiltFreeMonthlyMinor;
  final int guiltFreeWeeklyMinor;
  final int totalSavingsAndShieldMinor;
  final List<SurplusWaterfallStep> waterfallSteps;
  final List<String> deficitRescueSteps;
  final List<ExpenseBenchmarkFlag> benchmarkFlags;
  final List<PlannedCategoryEnvelope> budgetEnvelopes;

  bool get isDeficit => netSurplusMinor < 0;
  int get shortfallMinor => netSurplusMinor < 0 ? -netSurplusMinor : 0;
  int get totalEssentialsWithoutEmiMinor =>
      tier1SurvivalMinor + tier2EssentialLivingMinor + otherFixedMinor;

  @override
  List<Object?> get props => [
    currencyCode,
    totalIncomeMinor,
    trackedLoanEmiMinor,
    manualEmiMinor,
    totalEmiMinor,
    tier1SurvivalMinor,
    tier2EssentialLivingMinor,
    subscriptionsMinor,
    otherFixedMinor,
    taxReserveMinor,
    totalCommittedOutgoMinor,
    essentialOutgoForShieldMinor,
    netSurplusMinor,
    commitmentRatioPct,
    planMode,
    cashFlowScore,
    recommendedPrepayMinor,
    guiltFreeMonthlyMinor,
    guiltFreeWeeklyMinor,
    totalSavingsAndShieldMinor,
    waterfallSteps,
    deficitRescueSteps,
    benchmarkFlags,
    budgetEnvelopes,
  ];
}

/// 100% Pure-Dart Life-Stage, EMI & Debt Management Engine (`ADR-003`).
abstract final class LifeStagePlannerEngine {
  static const _needKeywords = [
    'rent',
    'housing',
    'home',
    'mortgage',
    'emi',
    'loan',
    'grocer',
    'supermarket',
    'utility',
    'utilities',
    'bill',
    'electric',
    'water',
    'gas',
    'internet',
    'broadband',
    'mobile',
    'phone',
    'health',
    'medical',
    'doctor',
    'pharmacy',
    'hospital',
    'insurance',
    'school',
    'tuition',
    'education',
    'child',
    'daycare',
    'transport',
    'commute',
    'fuel',
    'petrol',
    'diesel',
    'parents',
    'payroll',
    'office',
    'software',
    'hosting',
    'tax',
    'gst',
    'maintenance',
  ];

  static bool isEssentialCategory(String categoryName) {
    final lower = categoryName.toLowerCase();
    for (final k in _needKeywords) {
      if (lower.contains(k)) return true;
    }
    return false;
  }

  /// Resolves adaptive Needs / Wants / Savings / Tax ratios, safe EMI DTI ceiling,
  /// and required emergency fund months based on status + dependents + housing.
  static EffectiveLifeStageTargets resolveEffectiveTargets({
    required LifeStageStatus status,
    int dependentsCount = 0,
    HousingMode housingMode = HousingMode.renting,
  }) {
    final deps = dependentsCount.clamp(0, 6);
    var needs = status.baseNeedsPct;
    var wants = status.baseWantsPct;
    var savings = status.baseSavingsPct;
    final tax = status.baseTaxPct;
    var maxDti = status.baseMaxDtiPct;
    var emergencyMo = status.baseEmergencyMonths;

    // Each dependent shifts +2% from Wants to Essentials and adds emergency depth.
    if (deps > 0) {
      final shift = math.min(deps * 2, math.max(0, wants - 5));
      needs += shift;
      wants -= shift;
      emergencyMo = math.min(12, emergencyMo + ((deps + 1) ~/ 2));
    }

    // Housing adaptation: Rent-free / own home boosts savings; Home EMI raises safe DTI slightly.
    if (housingMode == HousingMode.ownedOrFamily) {
      final rentFreedomShift = math.min(8, math.max(0, needs - 25));
      needs -= rentFreedomShift;
      savings += rentFreedomShift;
    } else if (housingMode == HousingMode.homeLoanEmi) {
      maxDti = math.min(38, maxDti + 5);
    }

    return EffectiveLifeStageTargets(
      status: status,
      dependentsCount: deps,
      housingMode: housingMode,
      needsPct: needs,
      wantsPct: wants,
      savingsPct: savings,
      taxPct: tax,
      maxSafeDtiPct: maxDti,
      emergencyMonths: emergencyMo,
    );
  }

  /// Generates status-tailored category budget caps across the user's real categories
  /// with exact zero-remainder accounting (`Categories + Tax + Savings == Income`).
  static LifeStageBudgetBlueprint buildCategoryBlueprint({
    required String currencyCode,
    required int incomePoolMinor,
    required EffectiveLifeStageTargets targets,
    required List<LifeStageCategoryInput> categories,
  }) {
    final safeIncome = math.max(0, incomePoolMinor);
    final taxMinor = targets.taxPct > 0
        ? (safeIncome * targets.taxPct) ~/ 100
        : 0;
    var savingsMinor = (safeIncome * targets.savingsPct) ~/ 100;
    final needsPool = (safeIncome * targets.needsPct) ~/ 100;
    final wantsPool = math.max(
      0,
      safeIncome - taxMinor - savingsMinor - needsPool,
    );

    final needsCats = <LifeStageCategoryInput>[];
    final wantsCats = <LifeStageCategoryInput>[];
    var actualNeeds = 0;
    var actualWants = 0;

    for (final c in categories) {
      if (isEssentialCategory(c.categoryName)) {
        needsCats.add(c);
        actualNeeds += c.currentMonthSpendMinor;
      } else {
        wantsCats.add(c);
        actualWants += c.currentMonthSpendMinor;
      }
    }

    final step = _friendlyStep(safeIncome, currencyCode);
    final alloc = <String, int>{};

    final effectiveNeedsPool = wantsCats.isEmpty
        ? (needsPool + wantsPool)
        : needsPool;
    final effectiveWantsPool = needsCats.isEmpty
        ? (needsPool + wantsPool)
        : wantsPool;

    _allocateByStatusWeights(
      poolMinor: needsCats.isNotEmpty ? effectiveNeedsPool : 0,
      cats: needsCats,
      status: targets.status,
      housingMode: targets.housingMode,
      step: step,
      out: alloc,
    );
    _allocateByStatusWeights(
      poolMinor: wantsCats.isNotEmpty ? effectiveWantsPool : 0,
      cats: wantsCats,
      status: targets.status,
      housingMode: targets.housingMode,
      step: step,
      out: alloc,
    );

    // Absorb any tiny rounding remainder into savings so zero-based sum is exact.
    if (safeIncome > 0 && categories.isNotEmpty) {
      final sumCats = alloc.values.fold<int>(0, (s, v) => s + v);
      final diff = safeIncome - (sumCats + taxMinor + savingsMinor);
      if (diff != 0) {
        if (savingsMinor + diff >= 0) {
          savingsMinor += diff;
        } else {
          final firstId = categories.first.categoryId;
          alloc[firstId] = math.max(0, (alloc[firstId] ?? 0) + diff);
        }
      }
    }

    final recs = <LifeStageCategoryRecommendation>[];
    for (final c in categories) {
      final recMinor = alloc[c.categoryId] ?? 0;
      final isNeed = isEssentialCategory(c.categoryName);
      recs.add(
        LifeStageCategoryRecommendation(
          categoryId: c.categoryId,
          categoryName: c.categoryName,
          bucketLabel: isNeed ? 'Essential Need' : 'Lifestyle Want',
          recommendedLimitMinor: recMinor,
          actualSpendMinor: c.currentMonthSpendMinor,
          shareOfIncomePercent: safeIncome > 0
              ? (recMinor * 100.0 / safeIncome)
              : 0.0,
        ),
      );
    }
    recs.sort(
      (a, b) => b.recommendedLimitMinor.compareTo(a.recommendedLimitMinor),
    );

    return LifeStageBudgetBlueprint(
      currencyCode: currencyCode,
      incomePoolMinor: safeIncome,
      targets: targets,
      needsTargetMinor: needsPool,
      wantsTargetMinor: wantsPool,
      taxTargetMinor: taxMinor,
      savingsTargetMinor: savingsMinor,
      actualNeedsMinor: actualNeeds,
      actualWantsMinor: actualWants,
      actualTotalSpendMinor: actualNeeds + actualWants,
      recommendations: recs,
    );
  }

  /// Evaluates EMI Debt-to-Income (DTI) health against the user's life-stage ceiling.
  static EmiHealthSummary analyzeEmiHealth({
    required String currencyCode,
    required int monthlyIncomeMinor,
    required EffectiveLifeStageTargets targets,
    required List<ActiveLoanSnapshot> loans,
    int manualMonthlyEmiMinor = 0,
  }) {
    final safeIncome = math.max<int>(0, monthlyIncomeMinor);
    final trackedEmi = loans.fold<int>(0, (s, l) => s + l.monthlyEmiMinor);
    final totalEmi = trackedEmi + math.max<int>(0, manualMonthlyEmiMinor);
    final totalDebt = loans.fold<int>(
      0,
      (s, l) => s + l.remainingPrincipalMinor,
    );
    final safeCeiling = (safeIncome * targets.maxSafeDtiPct) ~/ 100;
    final headroom = math.max<int>(0, safeCeiling - totalEmi);
    final dtiPct = safeIncome > 0
        ? (totalEmi * 100.0 / safeIncome)
        : (totalEmi > 0 ? 100.0 : 0.0);
    final badDebts = loans.where((l) => l.isHighInterestBadDebt).toList();

    final String status;
    final String verdict;
    if (totalEmi == 0) {
      status = 'healthy';
      verdict =
          'Zero active EMIs — your cash flow is 100% debt-free. Keep future EMIs below ${targets.maxSafeDtiPct}% of income.';
    } else if (dtiPct > targets.maxSafeDtiPct) {
      status = 'stressed';
      verdict =
          'EMI load (${dtiPct.round()}%) exceeds the safe ${targets.maxSafeDtiPct}% ceiling for ${targets.status.title}. Pause new loans and accelerate payoff.';
    } else if (dtiPct >= targets.maxSafeDtiPct * 0.78) {
      status = 'caution';
      verdict =
          'EMI load (${dtiPct.round()}%) is approaching your ${targets.maxSafeDtiPct}% limit. Keep remaining headroom for emergencies.';
    } else {
      status = 'healthy';
      verdict =
          'EMI load (${dtiPct.round()}%) sits safely inside your ${targets.maxSafeDtiPct}% ${targets.status.shortLabel} ceiling.';
    }

    return EmiHealthSummary(
      currencyCode: currencyCode,
      monthlyIncomeMinor: safeIncome,
      totalMonthlyEmiMinor: totalEmi,
      totalRemainingDebtMinor: totalDebt,
      dtiPercent: dtiPct,
      maxSafeDtiPct: targets.maxSafeDtiPct,
      safeEmiCeilingMinor: safeCeiling,
      availableNewEmiHeadroomMinor: headroom,
      dtiStatus: status,
      verdict: verdict,
      highInterestLoans: badDebts,
      loans: loans,
    );
  }

  /// Deterministic pure-Dart multi-loan payoff simulator comparing
  /// Baseline vs. Debt Avalanche (highest APR first) vs. Debt Snowball (smallest balance first).
  static DebtPayoffComparison simulateDebtPayoff({
    required List<ActiveLoanSnapshot> loans,
    required int extraMonthlyPrepaymentMinor,
  }) {
    final active = loans.where((l) => l.remainingPrincipalMinor > 0).toList();
    final extra = math.max(0, extraMonthlyPrepaymentMinor);

    if (active.isEmpty) {
      const emptyAvalanche = DebtStrategyResult(
        strategy: DebtPayoffStrategy.avalanche,
        monthsToDebtFree: 0,
        totalInterestMinor: 0,
        monthsSavedVsBaseline: 0,
        interestSavedVsBaselineMinor: 0,
        payoffOrderNames: [],
      );
      const emptySnowball = DebtStrategyResult(
        strategy: DebtPayoffStrategy.snowball,
        monthsToDebtFree: 0,
        totalInterestMinor: 0,
        monthsSavedVsBaseline: 0,
        interestSavedVsBaselineMinor: 0,
        payoffOrderNames: [],
      );
      return DebtPayoffComparison(
        extraMonthlyPrepaymentMinor: extra,
        baselineMonths: 0,
        baselineInterestMinor: 0,
        avalanche: emptyAvalanche,
        snowball: emptySnowball,
        recommendedStrategy: DebtPayoffStrategy.avalanche,
      );
    }

    final base = _runPayoffSim(
      loans: active,
      extraMonthlyMinor: 0,
      strategy: DebtPayoffStrategy.avalanche,
      rollFreedEmis: false,
    );
    final avRaw = _runPayoffSim(
      loans: active,
      extraMonthlyMinor: extra,
      strategy: DebtPayoffStrategy.avalanche,
      rollFreedEmis: true,
    );
    final sbRaw = _runPayoffSim(
      loans: active,
      extraMonthlyMinor: extra,
      strategy: DebtPayoffStrategy.snowball,
      rollFreedEmis: true,
    );

    final avalanche = DebtStrategyResult(
      strategy: DebtPayoffStrategy.avalanche,
      monthsToDebtFree: avRaw.months,
      totalInterestMinor: avRaw.totalInterest,
      monthsSavedVsBaseline: math.max(0, base.months - avRaw.months),
      interestSavedVsBaselineMinor: math.max(
        0,
        base.totalInterest - avRaw.totalInterest,
      ),
      payoffOrderNames: avRaw.payoffOrder,
    );
    final snowball = DebtStrategyResult(
      strategy: DebtPayoffStrategy.snowball,
      monthsToDebtFree: sbRaw.months,
      totalInterestMinor: sbRaw.totalInterest,
      monthsSavedVsBaseline: math.max(0, base.months - sbRaw.months),
      interestSavedVsBaselineMinor: math.max(
        0,
        base.totalInterest - sbRaw.totalInterest,
      ),
      payoffOrderNames: sbRaw.payoffOrder,
    );

    final rec = avalanche.totalInterestMinor <= snowball.totalInterestMinor
        ? DebtPayoffStrategy.avalanche
        : DebtPayoffStrategy.snowball;

    return DebtPayoffComparison(
      extraMonthlyPrepaymentMinor: extra,
      baselineMonths: base.months,
      baselineInterestMinor: base.totalInterest,
      avalanche: avalanche,
      snowball: snowball,
      recommendedStrategy: rec,
    );
  }

  /// Computes exact reducing-balance EMI and evaluates whether a prospective loan
  /// fits safely inside the user's life-stage DTI ceiling.
  static NewEmiAffordabilityResult evaluateNewEmiAffordability({
    required String currencyCode,
    required int monthlyIncomeMinor,
    required int existingMonthlyEmiMinor,
    required EffectiveLifeStageTargets targets,
    int? directMonthlyEmiMinor,
    int loanPrincipalMinor = 0,
    int annualInterestRateBps = 950,
    int termMonths = 36,
  }) {
    final int newEmi;
    if (directMonthlyEmiMinor != null && directMonthlyEmiMinor > 0) {
      newEmi = directMonthlyEmiMinor;
    } else if (loanPrincipalMinor > 0 && termMonths > 0) {
      newEmi = computeReducingBalanceEmiMinor(
        principalMinor: loanPrincipalMinor,
        annualInterestRateBps: annualInterestRateBps,
        termMonths: termMonths,
      );
    } else {
      newEmi = 0;
    }

    final safeIncome = math.max(0, monthlyIncomeMinor);
    final combined = math.max(0, existingMonthlyEmiMinor) + newEmi;
    final projDti = safeIncome > 0
        ? (combined * 100.0 / safeIncome)
        : (combined > 0 ? 100.0 : 0.0);
    final postEmi = math.max(0, safeIncome - combined);

    String fmt(int m) =>
        Money(amountMinor: m, currencyCode: currencyCode).format();

    final String code;
    final String headline;
    final String detail;
    if (safeIncome <= 0) {
      code = 'risky';
      headline = 'Add Monthly Income First';
      detail =
          'Set your monthly income pool to verify if ${fmt(newEmi)}/mo fits safely within your ${targets.status.shortLabel} DTI limit.';
    } else if (projDti <= targets.maxSafeDtiPct * 0.85) {
      code = 'safe';
      headline = 'Safe to Proceed';
      detail =
          'Adding ${fmt(newEmi)}/mo brings total EMIs to ${projDti.toStringAsFixed(1)}% of income — comfortably below your ${targets.maxSafeDtiPct}% ceiling.';
    } else if (projDti <= targets.maxSafeDtiPct) {
      code = 'tight';
      headline = 'Affordable — Keep Tight';
      detail =
          'Combined EMIs hit ${projDti.toStringAsFixed(1)}% (ceiling ${targets.maxSafeDtiPct}%). Increase down-payment by 10–15% if possible for extra family safety.';
    } else {
      code = 'risky';
      headline = 'High EMI Risk — Avoid or Downsize';
      detail =
          'Combined EMIs reach ${projDti.toStringAsFixed(1)}%, breaching your safe ${targets.maxSafeDtiPct}% ${targets.status.shortLabel} limit. Lower loan amount or extend down-payment first.';
    }

    return NewEmiAffordabilityResult(
      currencyCode: currencyCode,
      estimatedNewEmiMinor: newEmi,
      combinedMonthlyEmiMinor: combined,
      projectedDtiPercent: projDti,
      maxSafeDtiPct: targets.maxSafeDtiPct,
      remainingPostEmiIncomeMinor: postEmi,
      verdictCode: code,
      headline: headline,
      detail: detail,
    );
  }

  /// Reducing-balance monthly EMI formula in exact integer minor units.
  static int computeReducingBalanceEmiMinor({
    required int principalMinor,
    required int annualInterestRateBps,
    required int termMonths,
  }) {
    if (principalMinor <= 0 || termMonths <= 0) return 0;
    if (annualInterestRateBps <= 0) {
      return (principalMinor + termMonths - 1) ~/ termMonths;
    }
    final r = annualInterestRateBps / 120000.0;
    final p = math.pow(1.0 + r, termMonths);
    return (principalMinor * (r * p) / (p - 1.0)).round();
  }

  /// Calculates Essential-Outgo Emergency Fund Shield and tailored protection/saving rules.
  static ({
    EmergencyShieldSnapshot shield,
    List<ProtectionCheckItem> protection,
    List<LifeStageActionTip> playbook,
  })
  buildProtectionAndPlaybook({
    required String currencyCode,
    required EffectiveLifeStageTargets targets,
    required LifeStageBudgetBlueprint blueprint,
    required EmiHealthSummary emiHealth,
    required int liquidCashMinor,
    int? realEssentialOutgoMinor,
  }) {
    final plannedNeeds = blueprint.needsTargetMinor;
    final computedOutgo = math.max(
      plannedNeeds,
      blueprint.actualNeedsMinor + emiHealth.totalMonthlyEmiMinor,
    );
    final effectiveEssential =
        (realEssentialOutgoMinor != null && realEssentialOutgoMinor > 0)
        ? realEssentialOutgoMinor
        : (computedOutgo > 0
              ? computedOutgo
              : (blueprint.incomePoolMinor * targets.needsPct) ~/ 100);
    final targetCorpus = effectiveEssential * targets.emergencyMonths;
    final safeLiquid = math.max(0, liquidCashMinor);
    final coveredMonths = effectiveEssential > 0
        ? (safeLiquid / effectiveEssential)
        : 0.0;
    final shortfall = math.max(0, targetCorpus - safeLiquid);
    final monthlyBridge = shortfall > 0 ? (shortfall + 11) ~/ 12 : 0;
    final score = targetCorpus > 0
        ? ((safeLiquid * 100) / targetCorpus).round().clamp(0, 100)
        : 0;

    final shield = EmergencyShieldSnapshot(
      currencyCode: currencyCode,
      essentialMonthlyOutgoMinor: effectiveEssential,
      targetMonths: targets.emergencyMonths,
      targetCorpusMinor: targetCorpus,
      liquidCashMinor: safeLiquid,
      coveredMonths: coveredMonths,
      shortfallMinor: shortfall,
      monthlyBridgeSavingMinor: monthlyBridge,
      shieldScore: score,
    );

    String fmt(int m) =>
        Money(amountMinor: m, currencyCode: currencyCode).format();

    final protection = _protectionForStatus(targets, fmt);
    final playbook = _playbookForStatus(
      targets: targets,
      blueprint: blueprint,
      emiHealth: emiHealth,
      shield: shield,
      fmt: fmt,
    );

    return (shield: shield, protection: protection, playbook: playbook);
  }

  static List<ProtectionCheckItem> _protectionForStatus(
    EffectiveLifeStageTargets t,
    String Function(int) fmt,
  ) {
    return switch (t.status) {
      LifeStageStatus.studentStarter => const [
        ProtectionCheckItem(
          title: 'Zero High-Interest BNPL / Credit Debt',
          subtitle: 'Avoid buy-now-pay-later traps while building your base.',
          priorityBadge: 'Core Rule',
        ),
        ProtectionCheckItem(
          title: '3-Month Starter Liquid Buffer',
          subtitle:
              'Keep 3 months of hostel/food essentials in a savings account.',
          priorityBadge: 'Safety',
        ),
        ProtectionCheckItem(
          title: 'Skill-Up & First Index SIP',
          subtitle:
              'Start even a tiny monthly SIP to lock in early compounding.',
          priorityBadge: 'Growth',
        ),
      ],
      LifeStageStatus.bachelor => const [
        ProtectionCheckItem(
          title: 'Personal Health Cover (Beyond Employer)',
          subtitle:
              'Lock in low premiums early so job switches never leave you uninsured.',
          priorityBadge: 'Essential',
        ),
        ProtectionCheckItem(
          title: '6-Month Emergency Liquid Cushion',
          subtitle:
              'Split between sweep-in FD & liquid funds before aggressive risk.',
          priorityBadge: '6 Mo Rule',
        ),
        ProtectionCheckItem(
          title: 'Day-1 Auto-SIP (30–35% Take-Home)',
          subtitle:
              'Automate investments on salary day before lifestyle inflation kicks in.',
          priorityBadge: 'Wealth',
        ),
      ],
      LifeStageStatus.marriedCouple => const [
        ProtectionCheckItem(
          title: 'Joint Family Floater Health Insurance',
          subtitle:
              'Protect both partners against sudden hospitalization costs.',
          priorityBadge: 'Essential',
        ),
        ProtectionCheckItem(
          title: 'Pure Term Insurance (10–15× Annual Income)',
          subtitle:
              'Mandatory if planning a joint home loan or starting a family.',
          priorityBadge: 'Protection',
        ),
        ProtectionCheckItem(
          title: 'Shared Goals Sinking Funds',
          subtitle:
              'Ring-fence annual travel, home down-payment & festivals monthly.',
          priorityBadge: 'Planning',
        ),
      ],
      LifeStageStatus.familyWithKids => const [
        ProtectionCheckItem(
          title: 'Pure Term Life Cover (15× Annual Income)',
          subtitle:
              'Protects spouse, children, school fees & home loan liabilities.',
          priorityBadge: 'Must Have',
        ),
        ProtectionCheckItem(
          title: 'Family Floater Health + Super Top-Up',
          subtitle:
              'Covers rising pediatric & family hospital costs without breaking SIPs.',
          priorityBadge: 'Must Have',
        ),
        ProtectionCheckItem(
          title: 'School Fees & Annual Bills Sinking Fund',
          subtitle:
              'Divide yearly tuition, books & insurance by 12 so term months never hurt.',
          priorityBadge: 'Cash Flow',
        ),
      ],
      LifeStageStatus.sandwichFamily => const [
        ProtectionCheckItem(
          title: 'Dedicated Senior Citizen Health Cover',
          subtitle:
              'Keep parents on a separate policy + dedicated medical buffer.',
          priorityBadge: 'Critical',
        ),
        ProtectionCheckItem(
          title: '9-Month Essential Emergency Reserve',
          subtitle:
              'Higher cushion absorbs simultaneous medical & household shocks.',
          priorityBadge: '9 Mo Rule',
        ),
        ProtectionCheckItem(
          title: 'Pure Term Life Cover + Nominee Audit',
          subtitle:
              'Protect two generations of dependents with updated nominations.',
          priorityBadge: 'Protection',
        ),
      ],
      LifeStageStatus.freelancerBusiness => const [
        ProtectionCheckItem(
          title: 'Separate 20% Tax & GST Escrow Account',
          subtitle:
              'Sweep tax share from every invoice immediately — never spend tax cash.',
          priorityBadge: 'CA Rule',
        ),
        ProtectionCheckItem(
          title: '12-Month Lean-Month Cash Runway',
          subtitle:
              'Smooths client payment delays and dry quarters without taking loans.',
          priorityBadge: '12 Mo Rule',
        ),
        ProtectionCheckItem(
          title: 'Self-Funded Health, Term & NPS/PPF',
          subtitle:
              'Replace missing corporate PF & group insurance with personal covers.',
          priorityBadge: 'Safety',
        ),
      ],
      LifeStageStatus.preRetirement => const [
        ProtectionCheckItem(
          title: 'Zero Unsecured Debt Before Retirement',
          subtitle:
              'Clear all personal/car loans so retirement cash flow stays unburdened.',
          priorityBadge: 'Priority #1',
        ),
        ProtectionCheckItem(
          title: '12-Month Safe Liquid & FD Ladder',
          subtitle: 'Shield core living expenses from market drawdowns.',
          priorityBadge: '12 Mo Rule',
        ),
        ProtectionCheckItem(
          title: 'Comprehensive Health Cover + Medical Corpus',
          subtitle:
              'Ring-fence a dedicated healthcare reserve for golden years.',
          priorityBadge: 'Protection',
        ),
      ],
    };
  }

  static List<LifeStageActionTip> _playbookForStatus({
    required EffectiveLifeStageTargets targets,
    required LifeStageBudgetBlueprint blueprint,
    required EmiHealthSummary emiHealth,
    required EmergencyShieldSnapshot shield,
    required String Function(int) fmt,
  }) {
    final tips = <LifeStageActionTip>[];

    // 1. Status-tailored core saving rule.
    tips.add(
      LifeStageActionTip(
        title: 'Automate ${targets.savingsPct}% Payday Savings First',
        detail: blueprint.savingsTargetMinor > 0
            ? 'Move ${fmt(blueprint.savingsTargetMinor)}/mo on payday into savings/SIPs before spending on ${targets.wantsPct}% wants.'
            : 'Set your monthly income pool to lock in an automatic ${targets.savingsPct}% payday transfer.',
        tag: '${targets.savingsPct}% Save Rule',
      ),
    );

    // 2. Live EMI & Debt rule.
    if (emiHealth.dtiStatus == 'stressed') {
      tips.add(
        LifeStageActionTip(
          title: 'De-Stress EMIs Back Below ${targets.maxSafeDtiPct}%',
          detail:
              'Your EMIs are at ${emiHealth.dtiPercent.round()}% of income. Use Debt Avalanche in the EMI tab and redirect bonuses/increment cash to clear the highest-rate loan first.',
          tag: 'Urgent EMI',
        ),
      );
    } else if (emiHealth.hasHighInterestDebt) {
      tips.add(
        LifeStageActionTip(
          title:
              'Eliminate High-Interest Debt (${emiHealth.highInterestLoans.first.annualRatePercent.toStringAsFixed(1)}%)',
          detail:
              '${emiHealth.highInterestLoans.first.name} costs >= 12% APR. Every extra rupee prepaid here beats guaranteed FD returns tax-free.',
          tag: 'Avalanche',
        ),
      );
    } else {
      tips.add(
        LifeStageActionTip(
          title: 'Guard Your ${targets.maxSafeDtiPct}% EMI Ceiling',
          detail: emiHealth.availableNewEmiHeadroomMinor > 0
              ? 'Keep combined EMIs under ${fmt(emiHealth.safeEmiCeilingMinor)}/mo (current headroom: ${fmt(emiHealth.availableNewEmiHeadroomMinor)}/mo) and avoid financing wants on EMI.'
              : 'Never commit more than ${targets.maxSafeDtiPct}% of take-home income to total EMIs.',
          tag: 'EMI Guard',
        ),
      );
    }

    // 3. Emergency Shield gap rule.
    if (!shield.isFullyFunded && shield.shortfallMinor > 0) {
      tips.add(
        LifeStageActionTip(
          title: 'Build ${targets.emergencyMonths}-Month Essential Shield',
          detail:
              'Your essential outgo needs ${fmt(shield.targetCorpusMinor)} (${shield.coveredMonths.toStringAsFixed(1)} mo covered). Save ${fmt(shield.monthlyBridgeSavingMinor)}/mo for 12 months to close the gap.',
          tag: '${targets.emergencyMonths} Mo Shield',
        ),
      );
    } else if (shield.targetCorpusMinor > 0) {
      tips.add(
        LifeStageActionTip(
          title:
              'Emergency Shield Funded (${shield.coveredMonths.toStringAsFixed(1)} Months)',
          detail:
              'Your ${targets.emergencyMonths}-month safety cushion is complete — channel new surplus into long-term wealth goals or loan prepayment.',
          tag: 'Shield Ready',
        ),
      );
    }

    // 4. Status-specific household expense control rule.
    tips.add(switch (targets.status) {
      LifeStageStatus.familyWithKids ||
      LifeStageStatus.sandwichFamily => LifeStageActionTip(
        title: 'Pre-Fund Lumpy Family Bills Monthly',
        detail:
            'Rent, groceries & utilities stay predictable, but school fees, insurance & festivals spike cash flow. Turn annual family bills into monthly sinking funds.',
        tag: 'Family Rhythm',
      ),
      LifeStageStatus.freelancerBusiness => LifeStageActionTip(
        title: 'Budget on Your Leanest Month — Not Peak Months',
        detail: blueprint.taxTargetMinor > 0
            ? 'Park ${fmt(blueprint.taxTargetMinor)}/mo (${targets.taxPct}%) into Tax/GST reserve immediately and pay yourself a fixed monthly salary from business cash.'
            : 'Keep a separate tax reserve and pay yourself a fixed monthly baseline salary.',
        tag: 'Variable Income',
      ),
      LifeStageStatus.bachelor ||
      LifeStageStatus.studentStarter => const LifeStageActionTip(
        title: 'Beat Lifestyle Creep on Every Hike',
        detail:
            'When income rises, lock at least 60% of every salary hike into SIPs & emergency savings before upgrading rent, dining, or gadgets.',
        tag: 'Step-Up SIP',
      ),
      LifeStageStatus.marriedCouple => const LifeStageActionTip(
        title: 'Run a Monthly 15-Minute Money Sync',
        detail:
            'Keep joint Needs & Goals transparent in one shared plan while preserving a small guilt-free personal allowance for each partner.',
        tag: 'Joint Plan',
      ),
      LifeStageStatus.preRetirement => const LifeStageActionTip(
        title: 'De-Risk Core Corpus Gradually',
        detail:
            'Shift next 3–5 years of essential retirement spending into debt/FD ladders while letting long-term equity beat inflation.',
        tag: 'Preserve',
      ),
    });

    return tips;
  }

  static ({int months, int totalInterest, List<String> payoffOrder})
  _runPayoffSim({
    required List<ActiveLoanSnapshot> loans,
    required int extraMonthlyMinor,
    required DebtPayoffStrategy strategy,
    required bool rollFreedEmis,
  }) {
    final balances = <String, int>{
      for (final l in loans) l.loanId: l.remainingPrincipalMinor,
    };
    final byId = {for (final l in loans) l.loanId: l};
    final payoffOrder = <String>[];
    var totalInterest = 0;
    var month = 0;
    const maxMonths = 480;

    while (month < maxMonths && balances.values.any((b) => b > 0)) {
      month++;
      var freedEmiPool = 0;

      // 1. Accrue monthly interest & apply minimum scheduled EMI on each active loan.
      for (final l in loans) {
        final bal = balances[l.loanId] ?? 0;
        if (bal <= 0) {
          if (rollFreedEmis) freedEmiPool += l.monthlyEmiMinor;
          continue;
        }
        final interest = ((bal * l.annualInterestRateBps) / 120000.0).round();
        totalInterest += interest;
        final due = bal + interest;
        // Guard against negative amortization if EMI < interest.
        final minPay = math.max(l.monthlyEmiMinor, interest + 1);
        final pay = math.min(due, minPay);
        final nextBal = due - pay;
        balances[l.loanId] = nextBal;
        if (nextBal <= 0) {
          payoffOrder.add(l.name);
          if (rollFreedEmis && pay < l.monthlyEmiMinor) {
            freedEmiPool += (l.monthlyEmiMinor - pay);
          }
        }
      }

      // 2. Apply extra prepayment + rolled-over EMIs using chosen strategy order.
      var extraPool = extraMonthlyMinor + freedEmiPool;
      if (extraPool > 0) {
        final remainingLoans = loans
            .where((l) => (balances[l.loanId] ?? 0) > 0)
            .toList();
        remainingLoans.sort((a, b) {
          if (strategy == DebtPayoffStrategy.avalanche) {
            final cmpRate = b.annualInterestRateBps.compareTo(
              a.annualInterestRateBps,
            );
            if (cmpRate != 0) return cmpRate;
            return (balances[a.loanId] ?? 0).compareTo(balances[b.loanId] ?? 0);
          } else {
            final cmpBal = (balances[a.loanId] ?? 0).compareTo(
              balances[b.loanId] ?? 0,
            );
            if (cmpBal != 0) return cmpBal;
            return b.annualInterestRateBps.compareTo(a.annualInterestRateBps);
          }
        });

        for (final target in remainingLoans) {
          if (extraPool <= 0) break;
          final bal = balances[target.loanId] ?? 0;
          if (bal <= 0) continue;
          final applied = math.min(bal, extraPool);
          balances[target.loanId] = bal - applied;
          extraPool -= applied;
          if ((balances[target.loanId] ?? 0) <= 0) {
            payoffOrder.add(byId[target.loanId]!.name);
          }
        }
      }
    }

    return (
      months: month,
      totalInterest: totalInterest,
      payoffOrder: payoffOrder,
    );
  }

  static void _allocateByStatusWeights({
    required int poolMinor,
    required List<LifeStageCategoryInput> cats,
    required LifeStageStatus status,
    required HousingMode housingMode,
    required int step,
    required Map<String, int> out,
  }) {
    if (poolMinor <= 0 || cats.isEmpty) {
      for (final c in cats) {
        out[c.categoryId] = 0;
      }
      return;
    }

    final weights = <String, int>{};
    var totalWeight = 0;
    for (final c in cats) {
      final w = _categoryWeightForStatus(
        c.categoryName,
        status: status,
        housingMode: housingMode,
      );
      weights[c.categoryId] = w;
      totalWeight += w;
    }

    var distributed = 0;
    for (var i = 0; i < cats.length; i++) {
      final c = cats[i];
      if (i == cats.length - 1) {
        out[c.categoryId] = math.max(0, poolMinor - distributed);
      } else {
        final raw = totalWeight > 0
            ? (poolMinor * (weights[c.categoryId] ?? 10)) ~/ totalWeight
            : poolMinor ~/ cats.length;
        final rounded = math.min(
          math.max(0, poolMinor - distributed),
          _roundStep(raw, step),
        );
        out[c.categoryId] = rounded;
        distributed += rounded;
      }
    }
  }

  static int _categoryWeightForStatus(
    String categoryName, {
    required LifeStageStatus status,
    required HousingMode housingMode,
  }) {
    final lower = categoryName.toLowerCase();
    final isRent =
        lower.contains('rent') ||
        lower.contains('housing') ||
        lower.contains('home');
    final isGrocery = lower.contains('grocer') || lower.contains('supermarket');
    final isEdu =
        lower.contains('education') ||
        lower.contains('school') ||
        lower.contains('tuition') ||
        lower.contains('child');
    final isHealth =
        lower.contains('health') ||
        lower.contains('medical') ||
        lower.contains('insurance');
    final isUtil = lower.contains('util') || lower.contains('bill');
    final isFood = lower.contains('dining') || lower.contains('food');
    final isTravel = lower.contains('travel') || lower.contains('transport');

    if (isRent) {
      if (housingMode == HousingMode.ownedOrFamily) return 6;
      return switch (status) {
        LifeStageStatus.familyWithKids ||
        LifeStageStatus.marriedCouple ||
        LifeStageStatus.sandwichFamily => 38,
        LifeStageStatus.bachelor => 32,
        _ => 26,
      };
    }
    if (isGrocery) {
      return switch (status) {
        LifeStageStatus.familyWithKids || LifeStageStatus.sandwichFamily => 28,
        LifeStageStatus.marriedCouple => 22,
        _ => 15,
      };
    }
    if (isEdu) {
      return switch (status) {
        LifeStageStatus.familyWithKids => 20,
        LifeStageStatus.studentStarter => 22,
        _ => 8,
      };
    }
    if (isHealth) {
      return switch (status) {
        LifeStageStatus.sandwichFamily || LifeStageStatus.preRetirement => 24,
        LifeStageStatus.familyWithKids => 16,
        _ => 10,
      };
    }
    if (isUtil) return 14;
    if (isFood) {
      return switch (status) {
        LifeStageStatus.bachelor || LifeStageStatus.studentStarter => 28,
        _ => 16,
      };
    }
    if (isTravel) return 14;
    return 12;
  }

  /// Estimates realistic status-tailored starting expenses from monthly salary
  /// so users can populate their bottom-up sheet in 1 tap and tweak only what differs.
  static MonthlyExpenseProfile estimateTypicalExpenses({
    required int primaryIncomeMinor,
    int secondaryIncomeMinor = 0,
    required EffectiveLifeStageTargets targets,
    required String currencyCode,
    int trackedLoanEmiMinor = 0,
  }) {
    final total =
        math.max<int>(0, primaryIncomeMinor) +
        math.max<int>(0, secondaryIncomeMinor);
    if (total <= 0) {
      return const MonthlyExpenseProfile();
    }
    final step = _friendlyStep(total, currencyCode);
    int pct(double p) => _roundStep((total * p / 100.0).round(), step);

    final isOwned = targets.housingMode == HousingMode.ownedOrFamily;
    final isHomeEmi = targets.housingMode == HousingMode.homeLoanEmi;
    final deps = targets.dependentsCount;

    return switch (targets.status) {
      LifeStageStatus.studentStarter => MonthlyExpenseProfile(
        primaryIncomeMinor: primaryIncomeMinor,
        secondaryIncomeMinor: secondaryIncomeMinor,
        rentOrHousingMinor: isOwned ? 0 : pct(22),
        groceriesMinor: pct(16),
        utilitiesMinor: pct(5),
        schoolFeesMinor: pct(10),
        transportFuelMinor: pct(6),
        subscriptionsMinor: pct(3),
      ),
      LifeStageStatus.bachelor => MonthlyExpenseProfile(
        primaryIncomeMinor: primaryIncomeMinor,
        secondaryIncomeMinor: secondaryIncomeMinor,
        rentOrHousingMinor: isOwned ? pct(3) : (isHomeEmi ? pct(4) : pct(18)),
        groceriesMinor: pct(10),
        utilitiesMinor: pct(4),
        transportFuelMinor: pct(5),
        insuranceMinor: pct(2.5),
        subscriptionsMinor: pct(2.5),
        parentsSupportMinor: deps > 0 ? pct(math.min(12.0, deps * 5.0)) : 0,
      ),
      LifeStageStatus.marriedCouple => MonthlyExpenseProfile(
        primaryIncomeMinor: primaryIncomeMinor,
        secondaryIncomeMinor: secondaryIncomeMinor,
        rentOrHousingMinor: isOwned ? pct(3) : (isHomeEmi ? pct(4) : pct(20)),
        groceriesMinor: pct(11),
        utilitiesMinor: pct(5),
        transportFuelMinor: pct(5),
        insuranceMinor: pct(3.5),
        medicalMinor: pct(2),
        subscriptionsMinor: pct(2.5),
        parentsSupportMinor: deps > 0 ? pct(math.min(10.0, deps * 4.0)) : 0,
      ),
      LifeStageStatus.familyWithKids => MonthlyExpenseProfile(
        primaryIncomeMinor: primaryIncomeMinor,
        secondaryIncomeMinor: secondaryIncomeMinor,
        rentOrHousingMinor: isOwned ? pct(3) : (isHomeEmi ? pct(4) : pct(20)),
        groceriesMinor: pct(14 + math.min(4.0, deps * 1.0)),
        schoolFeesMinor: pct(9 + math.min(6.0, deps * 1.5)),
        utilitiesMinor: pct(5.5),
        transportFuelMinor: pct(5.5),
        insuranceMinor: pct(4.5),
        medicalMinor: pct(3),
        subscriptionsMinor: pct(2),
        parentsSupportMinor: deps >= 3 ? pct(5) : 0,
      ),
      LifeStageStatus.sandwichFamily => MonthlyExpenseProfile(
        primaryIncomeMinor: primaryIncomeMinor,
        secondaryIncomeMinor: secondaryIncomeMinor,
        rentOrHousingMinor: isOwned ? pct(3) : (isHomeEmi ? pct(4) : pct(18)),
        groceriesMinor: pct(14),
        schoolFeesMinor: pct(6),
        utilitiesMinor: pct(5.5),
        transportFuelMinor: pct(5),
        insuranceMinor: pct(5.5),
        medicalMinor: pct(5),
        parentsSupportMinor: pct(10),
        subscriptionsMinor: pct(1.5),
      ),
      LifeStageStatus.freelancerBusiness => MonthlyExpenseProfile(
        primaryIncomeMinor: primaryIncomeMinor,
        secondaryIncomeMinor: secondaryIncomeMinor,
        rentOrHousingMinor: isOwned ? pct(3) : pct(15),
        groceriesMinor: pct(9),
        utilitiesMinor: pct(5),
        transportFuelMinor: pct(4),
        insuranceMinor: pct(4),
        medicalMinor: pct(2),
        subscriptionsMinor: pct(4), // Work SaaS + personal tools
        parentsSupportMinor: deps > 0 ? pct(6) : 0,
      ),
      LifeStageStatus.preRetirement => MonthlyExpenseProfile(
        primaryIncomeMinor: primaryIncomeMinor,
        secondaryIncomeMinor: secondaryIncomeMinor,
        rentOrHousingMinor: isOwned ? pct(4) : pct(14),
        groceriesMinor: pct(12),
        utilitiesMinor: pct(5.5),
        transportFuelMinor: pct(4.5),
        insuranceMinor: pct(5),
        medicalMinor: pct(6),
        subscriptionsMinor: pct(1.5),
      ),
    };
  }

  /// Builds a CFP / Chartered Accountant Bottom-Up Cash Flow & Surplus Allocation
  /// Waterfall from the user's real income, real monthly commitments, and active EMIs.
  static BottomUpCashFlowPlan buildBottomUpCashFlowPlan({
    required String currencyCode,
    required EffectiveLifeStageTargets targets,
    required MonthlyExpenseProfile expenses,
    required int trackedLoanEmiMinor,
    required int liquidCashMinor,
    bool hasHighInterestDebt = false,
  }) {
    final totalIncome = expenses.totalIncomeMinor;
    final trackedEmi = math.max(0, trackedLoanEmiMinor);
    final manualEmi = math.max(0, expenses.manualEmiMinor);
    final totalEmi = trackedEmi + manualEmi;

    final tier1NoEmi =
        expenses.rentOrHousingMinor +
        expenses.schoolFeesMinor +
        expenses.insuranceMinor +
        expenses.parentsSupportMinor;
    final tier2 =
        expenses.groceriesMinor +
        expenses.utilitiesMinor +
        expenses.transportFuelMinor +
        expenses.medicalMinor;
    final subs = expenses.subscriptionsMinor;
    final otherFixed = expenses.otherFixedMinor;
    final taxReserve = targets.taxPct > 0 && totalIncome > 0
        ? (totalIncome * targets.taxPct) ~/ 100
        : 0;

    final essentialOutgo = tier1NoEmi + tier2 + totalEmi;
    final totalCommitted =
        tier1NoEmi + tier2 + totalEmi + subs + otherFixed + taxReserve;
    final netSurplus = totalIncome - totalCommitted;
    final commitmentRatioPct = totalIncome > 0
        ? (totalCommitted * 100.0 / totalIncome)
        : 0.0;

    String fmt(int minor) =>
        Money(amountMinor: minor, currencyCode: currencyCode).format();

    // Benchmark & Under-Protection Audit
    final flags = <ExpenseBenchmarkFlag>[];
    if (totalIncome > 0) {
      final housingPct = expenses.rentOrHousingMinor * 100.0 / totalIncome;
      final housingCap = targets.status == LifeStageStatus.bachelor
          ? 25.0
          : 30.0;
      if (housingPct > housingCap) {
        flags.add(
          ExpenseBenchmarkFlag(
            title: 'High Housing Cost (${housingPct.round()}% of income)',
            detail:
                'Rent/housing exceeds the ${housingCap.round()}% CFP guideline for ${targets.status.shortLabel}. Consider renegotiating or holding upgrades.',
            severity: 'warning',
          ),
        );
      }

      final subsPct = subs * 100.0 / totalIncome;
      if (subs > 0 &&
          subsPct > 3.5 &&
          targets.status != LifeStageStatus.freelancerBusiness) {
        flags.add(
          ExpenseBenchmarkFlag(
            title:
                'Subscription Creep (${fmt(subs)}/mo = ${fmt(subs * 12)}/yr)',
            detail:
                'Recurring apps/OTT/memberships take ${subsPct.toStringAsFixed(1)}% of income. Audit and cancel unused plans.',
            severity: 'warning',
          ),
        );
      }

      final emiPct = totalEmi * 100.0 / totalIncome;
      if (totalEmi > 0 && emiPct > targets.maxSafeDtiPct) {
        flags.add(
          ExpenseBenchmarkFlag(
            title:
                'EMI Over Limit (${emiPct.round()}% vs ${targets.maxSafeDtiPct}% max)',
            detail:
                'Combined EMIs (${fmt(totalEmi)}/mo) squeeze monthly flexibility. Avoid new loans and accelerate highest-APR payoff.',
            severity: 'danger',
          ),
        );
      }

      final needsInsuranceCheck =
          targets.status == LifeStageStatus.familyWithKids ||
          targets.status == LifeStageStatus.sandwichFamily ||
          targets.status == LifeStageStatus.marriedCouple ||
          targets.status == LifeStageStatus.freelancerBusiness;
      if (needsInsuranceCheck &&
          expenses.hasAnyEnteredExpenses &&
          expenses.insuranceMinor <= 0) {
        final suggestedIns = (totalIncome * 0.035).round();
        flags.add(
          ExpenseBenchmarkFlag(
            title: 'Zero Insurance Provision Detected',
            detail:
                'For ${targets.status.title}, ring-fence ~${fmt(suggestedIns)}/mo (annualized) for Family Health + Pure Term Life cover so one emergency never derails savings.',
            severity: 'danger',
          ),
        );
      }

      if (commitmentRatioPct > 75 && netSurplus >= 0) {
        flags.add(
          ExpenseBenchmarkFlag(
            title: 'High Fixed Commitments (${commitmentRatioPct.round()}%)',
            detail:
                'Over 75% of income goes to fixed obligations before discretionary spending. Keep lifestyle spending lean until income grows or an EMI closes.',
            severity: 'warning',
          ),
        );
      }
    }

    // Build real category budget envelopes from entered commitments.
    final envelopes = <PlannedCategoryEnvelope>[];
    void addEnv(
      String name,
      String group,
      int minor,
      List<String> matchKeywords,
      String iconKey,
    ) {
      if (minor <= 0) return;
      envelopes.add(
        PlannedCategoryEnvelope(
          categoryName: name,
          tierLabel: group,
          amountMinor: minor,
          matchKeywords: matchKeywords,
          iconKey: iconKey,
        ),
      );
    }

    addEnv(
      'Housing & Rent',
      'Fixed Survival',
      expenses.rentOrHousingMinor,
      const ['rent', 'housing', 'home'],
      'home',
    );
    addEnv('Groceries', 'Essential Living', expenses.groceriesMinor, const [
      'grocer',
      'supermarket',
    ], 'shopping_cart');
    addEnv('Education', 'Fixed Survival', expenses.schoolFeesMinor, const [
      'education',
      'school',
      'tuition',
      'fee',
    ], 'school');
    addEnv(
      'Utilities & Bills',
      'Essential Living',
      expenses.utilitiesMinor,
      const ['util', 'bill', 'electric', 'internet', 'wifi'],
      'bolt',
    );
    addEnv('Insurance', 'Protection', expenses.insuranceMinor, const [
      'insurance',
      'term',
      'policy',
    ], 'verified_user');
    addEnv(
      'Transport & Fuel',
      'Essential Living',
      expenses.transportFuelMinor,
      const ['transport', 'fuel', 'commute', 'travel'],
      'directions_car',
    );
    addEnv('Healthcare', 'Essential Living', expenses.medicalMinor, const [
      'health',
      'medical',
      'pharmacy',
      'doctor',
    ], 'medical_services');
    addEnv(
      'Parents & Care',
      'Family Support',
      expenses.parentsSupportMinor,
      const ['parent', 'family care', 'dependent'],
      'volunteer_activism',
    );
    addEnv(
      'Subscriptions',
      'Recurring Wants',
      expenses.subscriptionsMinor,
      const ['subscription', 'ott', 'software', 'cloud', 'gym'],
      'subscriptions',
    );
    addEnv(
      'Other Fixed Bills',
      'Fixed Living',
      expenses.otherFixedMinor,
      const ['other', 'misc', 'maintenance'],
      'receipt_long',
    );

    if (totalIncome <= 0) {
      return BottomUpCashFlowPlan(
        currencyCode: currencyCode,
        totalIncomeMinor: 0,
        trackedLoanEmiMinor: trackedEmi,
        manualEmiMinor: manualEmi,
        totalEmiMinor: totalEmi,
        tier1SurvivalMinor: tier1NoEmi,
        tier2EssentialLivingMinor: tier2,
        subscriptionsMinor: subs,
        otherFixedMinor: otherFixed,
        taxReserveMinor: 0,
        totalCommittedOutgoMinor: totalCommitted,
        essentialOutgoForShieldMinor: essentialOutgo,
        netSurplusMinor: netSurplus,
        commitmentRatioPct: 0,
        planMode: 'awaiting_income',
        cashFlowScore: 0,
        recommendedPrepayMinor: 0,
        guiltFreeMonthlyMinor: 0,
        guiltFreeWeeklyMinor: 0,
        totalSavingsAndShieldMinor: 0,
        waterfallSteps: const [],
        deficitRescueSteps: const [],
        benchmarkFlags: flags,
        budgetEnvelopes: envelopes,
      );
    }

    // Mode 1: Deficit Rescue Plan (Committed Outgo > Income)
    if (netSurplus < 0) {
      final shortfall = -netSurplus;
      final rescue = <String>[
        'Immediate cash-flow gap: ${fmt(shortfall)}/month — pause all discretionary shopping & dining until balanced.',
      ];
      if (subs > 0) {
        final cutSubs = math.min(shortfall, (subs * 0.70).round());
        rescue.add(
          'Trim Subscriptions immediately by ~${fmt(cutSubs)}/mo (cancel non-essential OTT, apps & memberships).',
        );
      }
      if (otherFixed > 0) {
        rescue.add(
          'Review ${fmt(otherFixed)}/mo in Other Fixed Bills for negotiable services.',
        );
      }
      if (totalEmi > (totalIncome * targets.maxSafeDtiPct) ~/ 100) {
        rescue.add(
          'EMIs take ${(totalEmi * 100 / totalIncome).round()}% of income — explore debt consolidation or tenure restructuring on high-rate loans.',
        );
      }
      rescue.add(
        'Breakeven target: cut ${fmt(shortfall)}/mo in expenses or add ${fmt(shortfall)}/mo in secondary income before restarting SIPs.',
      );

      return BottomUpCashFlowPlan(
        currencyCode: currencyCode,
        totalIncomeMinor: totalIncome,
        trackedLoanEmiMinor: trackedEmi,
        manualEmiMinor: manualEmi,
        totalEmiMinor: totalEmi,
        tier1SurvivalMinor: tier1NoEmi,
        tier2EssentialLivingMinor: tier2,
        subscriptionsMinor: subs,
        otherFixedMinor: otherFixed,
        taxReserveMinor: taxReserve,
        totalCommittedOutgoMinor: totalCommitted,
        essentialOutgoForShieldMinor: essentialOutgo,
        netSurplusMinor: netSurplus,
        commitmentRatioPct: commitmentRatioPct,
        planMode: 'deficit_rescue',
        cashFlowScore: 18,
        recommendedPrepayMinor: 0,
        guiltFreeMonthlyMinor: 0,
        guiltFreeWeeklyMinor: 0,
        totalSavingsAndShieldMinor: 0,
        waterfallSteps: const [],
        deficitRescueSteps: rescue,
        benchmarkFlags: flags,
        budgetEnvelopes: envelopes,
      );
    }

    // Mode 2 & 3: CFP 5-Stage Surplus Allocation Waterfall (Guaranteed Zero Remainder!)
    final surplusPct = netSurplus * 100.0 / totalIncome;
    final isTight = surplusPct < 12.0;

    // 1. Emergency Shield Fill (uses REAL essential outgo * target months!)
    final realEssentialBasis = essentialOutgo > 0
        ? essentialOutgo
        : (totalIncome * targets.needsPct) ~/ 100;
    final targetCorpus = realEssentialBasis * targets.emergencyMonths;
    final shieldGap = math.max<int>(
      0,
      targetCorpus - math.max<int>(0, liquidCashMinor),
    );
    final monthlyBridgeNeed = shieldGap > 0 ? (shieldGap + 11) ~/ 12 : 0;

    var remaining = netSurplus;
    final emergencyAlloc = shieldGap > 0
        ? math.min(
            remaining,
            math.min(
              monthlyBridgeNeed,
              (netSurplus * (isTight ? 0.45 : 0.35)).round(),
            ),
          )
        : 0;
    remaining -= emergencyAlloc;

    // 2. Extra EMI Prepayment (prioritize when high-APR debt or active EMIs exist)
    final emiPct = totalEmi * 100.0 / totalIncome;
    final double prepayShare = totalEmi <= 0
        ? 0.0
        : (hasHighInterestDebt || emiPct > targets.maxSafeDtiPct * 0.85
              ? 0.30
              : 0.14);
    final extraEmiAlloc = prepayShare > 0
        ? math.min(remaining, (netSurplus * prepayShare).round())
        : 0;
    remaining -= extraEmiAlloc;

    // 3. Guilt-Free Lifestyle & Weekly Pocket Cap
    final double lifestyleShare = isTight
        ? 0.25
        : switch (targets.status) {
            LifeStageStatus.bachelor || LifeStageStatus.studentStarter => 0.36,
            LifeStageStatus.marriedCouple => 0.30,
            LifeStageStatus.familyWithKids => 0.26,
            LifeStageStatus.sandwichFamily ||
            LifeStageStatus.freelancerBusiness => 0.22,
            LifeStageStatus.preRetirement => 0.24,
          };
    final lifestyleAlloc = math.min(
      remaining,
      (netSurplus * lifestyleShare).round(),
    );
    remaining -= lifestyleAlloc;

    // 4. Annual Sinking Funds (school renewals, annual insurance, travel/festivals)
    final sinkingShare = isTight
        ? 0.0
        : (targets.status == LifeStageStatus.familyWithKids ||
                  targets.status == LifeStageStatus.sandwichFamily
              ? 0.14
              : 0.10);
    final sinkingAlloc = sinkingShare > 0
        ? math.min(remaining, (netSurplus * sinkingShare).round())
        : 0;
    remaining -= sinkingAlloc;

    // 5. Wealth, SIP, Child Education & Retirement (absorbs exact remainder -> 100% allocated!)
    final wealthSipAlloc = math.max(0, remaining);

    final wealthTitle = switch (targets.status) {
      LifeStageStatus.familyWithKids => 'Child Education & Retirement SIP',
      LifeStageStatus.bachelor ||
      LifeStageStatus.studentStarter => 'High-Growth Equity SIP & Goals',
      LifeStageStatus.marriedCouple => 'Joint Wealth & Home Down-Payment SIP',
      LifeStageStatus.freelancerBusiness =>
        'Self-Funded Retirement (NPS/PPF/SIP)',
      LifeStageStatus.preRetirement => 'Safe Debt / FD Ladder & Corpus',
      LifeStageStatus.sandwichFamily => 'Long-Term Retirement & Medical Corpus',
    };

    final steps = <SurplusWaterfallStep>[
      if (emergencyAlloc > 0)
        SurplusWaterfallStep(
          stageNumber: 1,
          code: 'emergency',
          title: 'Emergency Shield (${targets.emergencyMonths}-Mo Buffer)',
          subtitle:
              'Closes ${fmt(shieldGap)} gap based on your real ${fmt(realEssentialBasis)}/mo essentials.',
          amountMinor: emergencyAlloc,
          percentOfIncome: emergencyAlloc * 100.0 / totalIncome,
        ),
      if (extraEmiAlloc > 0)
        SurplusWaterfallStep(
          stageNumber: 2,
          code: 'emi_prepay',
          title: 'Extra EMI Prepayment (Debt Freedom)',
          subtitle: hasHighInterestDebt
              ? 'Attack highest-APR loan first via Debt Avalanche to save max interest.'
              : 'Shortens loan tenure & frees up monthly cash flow years earlier.',
          amountMinor: extraEmiAlloc,
          percentOfIncome: extraEmiAlloc * 100.0 / totalIncome,
        ),
      if (sinkingAlloc > 0)
        SurplusWaterfallStep(
          stageNumber: 3,
          code: 'sinking',
          title: 'Annual Bills & Sinking Funds',
          subtitle:
              'Pre-funds lumpy annual school fees, insurance renewals, car service & travel.',
          amountMinor: sinkingAlloc,
          percentOfIncome: sinkingAlloc * 100.0 / totalIncome,
        ),
      if (wealthSipAlloc > 0)
        SurplusWaterfallStep(
          stageNumber: 4,
          code: 'wealth_sip',
          title: wealthTitle,
          subtitle:
              'Automate on Salary Day 1 so wealth compounds before lifestyle creep.',
          amountMinor: wealthSipAlloc,
          percentOfIncome: wealthSipAlloc * 100.0 / totalIncome,
        ),
      if (lifestyleAlloc > 0)
        SurplusWaterfallStep(
          stageNumber: 5,
          code: 'lifestyle',
          title: 'Guilt-Free Lifestyle & Dining Cap',
          subtitle:
              'Weekly pocket cap: ${fmt(lifestyleAlloc ~/ 4)}/week for dining, outings & shopping.',
          amountMinor: lifestyleAlloc,
          percentOfIncome: lifestyleAlloc * 100.0 / totalIncome,
          weeklyAllowanceMinor: lifestyleAlloc ~/ 4,
        ),
    ];

    // Add the Guilt-Free Lifestyle envelope into the real budget envelopes list!
    if (lifestyleAlloc > 0) {
      addEnv('Dining & Food', 'Guilt-Free Wants', lifestyleAlloc, const [
        'dining',
        'food',
        'shopping',
        'entertainment',
      ], 'restaurant');
    }

    final totalSaveAndShield =
        emergencyAlloc + extraEmiAlloc + sinkingAlloc + wealthSipAlloc;
    final savePct = totalSaveAndShield * 100.0 / totalIncome;

    var score = 55;
    if (savePct >= targets.savingsPct) {
      score += 25;
    } else if (savePct >= 15) {
      score += 15;
    } else if (savePct >= 8) {
      score += 6;
    }
    if (emiPct <= targets.maxSafeDtiPct) {
      score += 12;
    } else {
      score -= 18;
    }
    if (flags.every((f) => f.severity != 'danger')) {
      score += 8;
    } else {
      score -= 10;
    }

    return BottomUpCashFlowPlan(
      currencyCode: currencyCode,
      totalIncomeMinor: totalIncome,
      trackedLoanEmiMinor: trackedEmi,
      manualEmiMinor: manualEmi,
      totalEmiMinor: totalEmi,
      tier1SurvivalMinor: tier1NoEmi,
      tier2EssentialLivingMinor: tier2,
      subscriptionsMinor: subs,
      otherFixedMinor: otherFixed,
      taxReserveMinor: taxReserve,
      totalCommittedOutgoMinor: totalCommitted,
      essentialOutgoForShieldMinor: essentialOutgo,
      netSurplusMinor: netSurplus,
      commitmentRatioPct: commitmentRatioPct,
      planMode: isTight ? 'tight_stabilize' : 'wealth_waterfall',
      cashFlowScore: score.clamp(10, 100),
      recommendedPrepayMinor: extraEmiAlloc,
      guiltFreeMonthlyMinor: lifestyleAlloc,
      guiltFreeWeeklyMinor: lifestyleAlloc ~/ 4,
      totalSavingsAndShieldMinor: totalSaveAndShield,
      waterfallSteps: steps,
      deficitRescueSteps: const [],
      benchmarkFlags: flags,
      budgetEnvelopes: envelopes,
    );
  }

  static int _friendlyStep(int referenceMinor, String currencyCode) {
    final spec = CurrencyCatalog.byCode(currencyCode);
    final unit = spec != null ? math.pow(10, spec.minorUnit).toInt() : 100;
    final major = referenceMinor ~/ math.max(1, unit);
    if (major >= 50000) return 500 * unit;
    if (major >= 10000) return 100 * unit;
    if (major >= 2000) return 50 * unit;
    return 10 * unit;
  }

  static int _roundStep(int val, int step) {
    if (val <= 0) return 0;
    if (step <= 1) return val;
    return ((val + (step ~/ 2)) ~/ step) * step;
  }
}
