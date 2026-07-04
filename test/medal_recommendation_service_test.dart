import 'package:flutter_test/flutter_test.dart';
import 'package:CountDownTodo/services/medal_recommendation_service.dart';
import 'package:CountDownTodo/services/timeline_service.dart';

void main() {
  group('MedalRecommendationService', () {
    // Mock TimelineSummary for testing
    late TimelineSummary mockSummary;

    setUp(() {
      mockSummary = TimelineSummary(
        searchCount: 5,
        todoCreatedCount: 10,
        todoEditedCount: 3,
        todoCompletedCount: 8,
        pomodoroCount: 15,
        longestPomodoroMinutes: 85,
        deepWorkCount: 3,
        consecutiveActiveDays: 5,
        totalFocusMinutes: 450,
        examPrepCount: 2,
        countdownCreatedCount: 2,
        countdownEditedCount: 0,
        countdownCompletedCount: 1,
        attendedCourses: const [],
        interruptionRate: 0.08,
        subjectDistribution: {
          'Math': 200.0,
          'English': 150.0,
          'Science': 100.0
        },
        peakHour: 14,
        hourlyDistribution: List.filled(24, 0),
        todoCompletionRate: 0.8,
        avgPomodoroMinutes: 30,
        homeworkRatio: 0.6,
        examRatio: 0.2,
      );
      mockSummary.hourlyDistribution[14] = 50;
      mockSummary.hourlyDistribution[15] = 48;
    });

    test('All medals are properly defined', () {
      expect(MedalRecommendationService.allMedals.length,
          greaterThanOrEqualTo(21));
      expect(MedalRecommendationService.allMedals.isEmpty, false);

      // Check uniqueness of IDs
      final ids =
          MedalRecommendationService.allMedals.map((m) => m.id).toList();
      expect(ids.length, equals(ids.toSet().length));
    });

    test('Calculate medal progress - focus_starter', () {
      final medal = MedalRecommendationService.allMedals
          .firstWhere((m) => m.id == 'focus_starter');
      final progress = MedalRecommendationService.calculateMedalProgress(
        medal,
        mockSummary,
        450,
        8,
        10,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
      );

      expect(progress.earned, true);
      expect(progress.progress, equals(1.0));
      expect(progress.stepsRemaining, 0);
    });

    test('Calculate medal progress - two_hour_guardian (incomplete)', () {
      final medal = MedalRecommendationService.allMedals
          .firstWhere((m) => m.id == 'two_hour_guardian');
      final progress = MedalRecommendationService.calculateMedalProgress(
        medal,
        mockSummary,
        100, // Only 100 minutes, need 120
        8,
        10,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
      );

      expect(progress.earned, false);
      expect(progress.progress, lessThan(1.0));
      expect(progress.progress, greaterThan(0.0));
      expect(progress.stepsRemaining, 20);
    });

    test('Calculate medal progress - two_hour_guardian (complete)', () {
      final medal = MedalRecommendationService.allMedals
          .firstWhere((m) => m.id == 'two_hour_guardian');
      final progress = MedalRecommendationService.calculateMedalProgress(
        medal,
        mockSummary,
        150, // 150 minutes
        8,
        10,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
      );

      expect(progress.earned, true);
      expect(progress.progress, equals(1.0));
      expect(progress.stepsRemaining, 0);
    });

    test('Calculate medal progress - task_harvester', () {
      final medal = MedalRecommendationService.allMedals
          .firstWhere((m) => m.id == 'task_harvester');
      final progress = MedalRecommendationService.calculateMedalProgress(
        medal,
        mockSummary,
        450,
        1, // At least 1 completed
        10,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
      );

      expect(progress.earned, true);
      expect(progress.progress, equals(1.0));
    });

    test('Calculate medal progress - plan_fulfiller', () {
      final medal = MedalRecommendationService.allMedals
          .firstWhere((m) => m.id == 'plan_fulfiller');

      // Test incomplete: 60% completion rate
      var progress = MedalRecommendationService.calculateMedalProgress(
        medal,
        mockSummary,
        450,
        6,
        10, // 60% completion
        1,
        1,
        0,
        0,
        0,
        0,
        0,
      );
      expect(progress.earned, false);

      // Test complete: 80% completion rate
      progress = MedalRecommendationService.calculateMedalProgress(
        medal,
        mockSummary,
        450,
        8,
        10, // 80% completion
        1,
        1,
        0,
        0,
        0,
        0,
        0,
      );
      expect(progress.earned, true);
    });

    test('Calculate medal progress - stable_output', () {
      final medal = MedalRecommendationService.allMedals
          .firstWhere((m) => m.id == 'stable_output');

      // Create summary with low interruption rate
      final summaryLowInterruption = TimelineSummary(
        searchCount: 0,
        todoCreatedCount: 0,
        todoEditedCount: 0,
        todoCompletedCount: 0,
        pomodoroCount: 5,
        longestPomodoroMinutes: 0,
        deepWorkCount: 0,
        consecutiveActiveDays: 0,
        totalFocusMinutes: 0,
        examPrepCount: 0,
        countdownCreatedCount: 0,
        countdownEditedCount: 0,
        countdownCompletedCount: 0,
        attendedCourses: const [],
        interruptionRate: 0.05, // 5% interruption
        subjectDistribution: const {},
        peakHour: 0,
        hourlyDistribution: List.filled(24, 0),
        todoCompletionRate: 0.0,
        avgPomodoroMinutes: 0,
        homeworkRatio: 0.0,
        examRatio: 0.0,
      );

      final progress = MedalRecommendationService.calculateMedalProgress(
        medal,
        summaryLowInterruption,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      );

      expect(progress.earned, true);
      expect(progress.progress, equals(1.0));
    });

    test('Get recommendations - returns top 3 unearned medals', () {
      final allProgresses = MedalRecommendationService.allMedals.map((medal) {
        return MedalRecommendationService.calculateMedalProgress(
          medal,
          mockSummary,
          450,
          8,
          10,
          1,
          1,
          2,
          5,
          3600,
          1800,
          300,
        );
      }).toList();

      final recommendations =
          MedalRecommendationService.recommendNext(allProgresses);

      expect(recommendations.length, lessThanOrEqualTo(3));
      // All should be unearned
      expect(recommendations.every((p) => !p.earned), true);
      // Should be sorted by steps remaining
      for (int i = 0; i < recommendations.length - 1; i++) {
        expect(
          recommendations[i].stepsRemaining,
          lessThanOrEqualTo(recommendations[i + 1].stepsRemaining),
        );
      }
    });

    test('Full recommendation flow', () {
      final recommendation = MedalRecommendationService.getRecommendations(
        mockSummary,
        450,
        8,
        10,
        1,
        1,
        2,
        5,
        3600,
        1800,
        300,
      );

      expect(recommendation.allMedals.length, greaterThanOrEqualTo(21));
      expect(recommendation.topRecommendations.length, lessThanOrEqualTo(3));
      expect(recommendation.earnedMedals.length, greaterThanOrEqualTo(0));

      // All earned medals should have progress == 1.0
      for (final medal in recommendation.earnedMedals) {
        expect(medal.progress, equals(1.0));
        expect(medal.earned, true);
      }

      // All top recommendations should be unearned
      for (final medal in recommendation.topRecommendations) {
        expect(medal.earned, false);
      }
    });

    test('Medal info has required fields', () {
      for (final medal in MedalRecommendationService.allMedals) {
        expect(medal.id.isNotEmpty, true);
        expect(medal.title.isNotEmpty, true);
        expect(medal.description.isNotEmpty, true);
        expect(medal.category.isNotEmpty, true);
        expect(medal.priority, greaterThanOrEqualTo(1));
        expect(medal.priority, lessThanOrEqualTo(5));
      }
    });

    test('Medal categories are valid', () {
      final validCategories = {
        'focus',
        'completion',
        'persistence',
        'efficiency',
        'breadth'
      };
      for (final medal in MedalRecommendationService.allMedals) {
        expect(validCategories.contains(medal.category), true);
      }
    });
  });
}
