class MatchingService {
  /// Calculates match data between current user and a table
  /// Returns score (0.0-1.0), label, and color for UI
  Map<String, dynamic> calculateMatch({
    required Map<String, dynamic> currentUser,
    required Map<String, dynamic> table,
  }) {
    final score = _calculateMatchScore(currentUser, table);
    final label = _getMatchLabel(score);
    final color = _getMatchColor(score);
    final glowIntensity = _getGlowIntensity(score);

    return {
      'score': score,
      'label': label,
      'color': color,
      'glowIntensity': glowIntensity,
      'shouldPulse': score >= 0.6,
    };
  }

  /// Internal: Calculates a match score (0.0 to 1.0) between the current user and a table
  /// based on:
  /// 1. Personality Compatibility (Big 5) - 40%
  /// 2. Interest Overlap - 30%
  /// 3. Budget Fit - 20%
  /// 4. Goal Alignment - 10%
  double _calculateMatchScore(
    Map<String, dynamic> currentUser,
    Map<String, dynamic> table,
  ) {
    double totalScore = 0.0;
    double totalWeight = 0.0;

    // 1. Personality Match (Weight: 40%)
    final userPersonality = currentUser['user_personality'];
    final hostPersonality = _extractHostPersonality(table);

    if (userPersonality != null && hostPersonality != null) {
      final personalityScore = _calculatePersonalityCompatibility(
        userPersonality,
        hostPersonality,
      );
      totalScore += personalityScore * 0.4;
      totalWeight += 0.4;
    }

    // 2. Interest Overlap (Weight: 30%)
    final userInterests =
        (currentUser['user_interests'] as List?)
            ?.map((e) => e['interest_tag']['name'])
            .toSet() ??
        {};
    // For map_ready_tables, interests would need separate query or join
    // For now, skip if not available
    if (userInterests.isNotEmpty) {
      totalWeight += 0.3;
      // Placeholder: could enhance view to include host interests
    }

    // 3. Budget Fit (Weight: 20%)
    final userBudgetMin = currentUser['user_preferences']?['budget_min'] ?? 0;
    final userBudgetMax =
        currentUser['user_preferences']?['budget_max'] ?? 1000;
    final tableBudgetMin = table['budget_min_per_person'] ?? 0;
    final tableBudgetMax = table['budget_max_per_person'] ?? 0;

    bool budgetOverlap =
        (userBudgetMax >= tableBudgetMin) && (tableBudgetMax >= userBudgetMin);

    if (budgetOverlap) {
      totalScore += 1.0 * 0.2;
    }
    totalWeight += 0.2;

    // 4. Goal Alignment (Weight: 10%)
    final userGoal = currentUser['user_preferences']?['primary_goal'];
    final tableGoal = table['goal_type'];

    if (userGoal != null && tableGoal != null && userGoal == tableGoal) {
      totalScore += 1.0 * 0.1;
    }
    totalWeight += 0.1;

    // Normalize result
    if (totalWeight == 0) return 0.5;
    return totalScore / totalWeight;
  }

  Map<String, dynamic>? _extractHostPersonality(Map<String, dynamic> table) {
    // For map_ready_tables view, personality traits are in root
    if (table.containsKey('openness')) {
      return {
        'openness': table['openness'],
        'conscientiousness': table['conscientiousness'],
        'extraversion': table['extraversion'],
        'agreeableness': table['agreeableness'],
        'neuroticism': table['neuroticism'],
      };
    }

    // For nested structure
    return table['host_personality'];
  }

  double _calculatePersonalityCompatibility(
    Map<String, dynamic> p1,
    Map<String, dynamic> p2,
  ) {
    double diffSum = 0;
    final traits = [
      'openness',
      'conscientiousness',
      'extraversion',
      'agreeableness',
      'neuroticism',
    ];

    for (var trait in traits) {
      final v1 = (p1[trait] as num?)?.toDouble() ?? 3.0;
      final v2 = (p2[trait] as num?)?.toDouble() ?? 3.0;
      diffSum += (v1 - v2).abs();
    }

    // Max possible diff is 4 * 5 = 20
    return 1.0 - (diffSum / 20.0);
  }

  String _getMatchLabel(double score) {
    if (score >= 0.8) return 'Perfect Match';
    if (score >= 0.6) return 'Great Vibe';
    if (score >= 0.4) return 'Good Fit';
    return 'Worth Exploring';
  }

  String _getMatchColor(double score) {
    if (score >= 0.8) return '#00FFD1'; // Neon teal
    if (score >= 0.6) return '#FFB800'; // Amber
    if (score >= 0.4) return '#8B5CF6'; // Purple
    return '#6B7280'; // Gray
  }

  double _getGlowIntensity(double score) {
    if (score >= 0.8) return 1.0; // Full glow
    if (score >= 0.6) return 0.7;
    if (score >= 0.4) return 0.4;
    return 0.0;
  }
}
