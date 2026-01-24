/// A result from a fuzzy search query.
class FuzzyMatchResult {
  /// The original item string that matched.
  final String item;

  /// The calculated relevance score. Higher is better.
  final int score;

  /// Optional list of indices in [item] that matched the query characters.
  /// (Reserved for future highlighting support).
  final List<int>? matchedIndices;

  const FuzzyMatchResult({
    required this.item,
    required this.score,
    this.matchedIndices,
  });

  @override
  String toString() => 'FuzzyMatchResult(score: $score, item: $item)';
}

/// A high-performance fuzzy matching engine optimized for file paths.
///
/// It uses a greedy heuristic algorithm that prioritizes:
/// - Matches at word/path boundaries (e.g. 'fb' matches 'foo/bar').
/// - Consecutive character matches.
/// - CamelCase transitions.
/// - Matches within the filename over the directory path.
class FuzzyMatcher {
  // Scoring Weights
  static const int _scoreMatch = 16;
  static const int _scoreBonusBoundary = 16; // Start of component (/, _, ., etc.)
  static const int _scoreBonusConsecutive = 8;
  static const int _scoreBonusCamelCase = 12;
  static const int _scoreFilenameBonus = 4;
  static const int _penaltyGap = -1;
  static const int _minScoreThreshold = -1000;
  static const int _failScore = -10000;
  static const int _maxScanDistance = 50; // Max lookahead for a character

  /// Performs a fuzzy search on a list of items.
  ///
  /// [items] is the list of strings (e.g. file paths) to search.
  /// [query] is the search string.
  /// Returns a list of [FuzzyMatchResult] sorted by score descending.
  static List<FuzzyMatchResult> search(
    List<String> items,
    String query, {
    int limit = 50,
  }) {
    if (query.isEmpty) {
      return items.take(limit).map((e) => FuzzyMatchResult(item: e, score: 0)).toList();
    }

    // Prepare query codes once (lowercase, spaces stripped or kept depending on logic)
    // We strictly use integer code units for performance (zero allocation).
    // Note: We ignore spaces in query to allow "foo bar" matching "foo/bar" easily.
    final List<int> queryCodes = query.toLowerCase().codeUnits.where((c) => c != 32).toList();
    if (queryCodes.isEmpty) return [];

    final List<FuzzyMatchResult> results = [];

    for (final item in items) {
      final score = _calculateScore(item, queryCodes);
      if (score > _minScoreThreshold) {
        results.add(FuzzyMatchResult(item: item, score: score));
      }
    }

    // Sort: score DESC, then length ASC (prefer shorter matches for same score)
    results.sort((a, b) {
      if (b.score != a.score) return b.score.compareTo(a.score);
      return a.item.length.compareTo(b.item.length);
    });

    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  static int _calculateScore(String target, List<int> queryCodes) {
    final targetLower = target.toLowerCase();
    final targetLowerCodes = targetLower.codeUnits;
    final targetOriginalCodes = target.codeUnits;
    
    final int n = queryCodes.length;
    final int m = targetLowerCodes.length;

    if (n > m) return _failScore;

    // 1. Fast Subsequence Check
    int qIdx = 0;
    int tIdx = 0;
    while (qIdx < n && tIdx < m) {
      if (targetLowerCodes[tIdx] == queryCodes[qIdx]) {
        qIdx++;
      }
      tIdx++;
    }
    if (qIdx < n) return _failScore;

    // 2. Scoring Loop (Greedy with boundary preference)
    int score = 0;
    int lastMatchIdx = -1;
    tIdx = 0;
    
    // Find where the filename starts to apply filename bonus
    // forward slash = 47
    int filenameStart = -1;
    for (int i = m - 1; i >= 0; i--) {
      if (targetLowerCodes[i] == 47) {
        filenameStart = i + 1;
        break;
      }
    }
    if (filenameStart == -1) filenameStart = 0;

    for (int i = 0; i < n; i++) {
      final int qChar = queryCodes[i];
      int bestIdx = -1;
      int bestLocalScore = _failScore;

      // Scan for the best next character match
      for (int j = tIdx; j < m; j++) {
        // Optimization: Don't scan too far for a single character
        if (j > tIdx + _maxScanDistance) break;

        if (targetLowerCodes[j] == qChar) {
          int currentScore = _scoreMatch;

          // Boundary bonus
          // Check previous char for boundary
          final bool isBoundary = j == 0 || _isBoundary(targetLowerCodes[j - 1]);
          final bool isCamel = !isBoundary && _isUpper(targetOriginalCodes[j]);
          
          if (isBoundary) {
            currentScore += _scoreBonusBoundary;
          } else if (isCamel) {
            currentScore += _scoreBonusCamelCase;
          }

          // Consecutive bonus
          if (lastMatchIdx != -1 && j == lastMatchIdx + 1) {
            currentScore += _scoreBonusConsecutive;
          }

          // Gap penalty
          if (lastMatchIdx != -1) {
            currentScore += (j - lastMatchIdx - 1) * _penaltyGap;
          }

          // Filename bonus
          if (j >= filenameStart) {
            currentScore += _scoreFilenameBonus;
          }

          if (currentScore > bestLocalScore) {
            bestLocalScore = currentScore;
            bestIdx = j;
            
            // Greedy Optimization: If we found a strong match (boundary/camel/consecutive), take it.
            if (isBoundary || isCamel || (lastMatchIdx != -1 && j == lastMatchIdx + 1)) {
              break; 
            }
          }
        }
      }

      if (bestIdx != -1) {
        score += bestLocalScore;
        lastMatchIdx = bestIdx;
        tIdx = bestIdx + 1;
      } else {
        return _failScore;
      }
    }

    return score;
  }

  static bool _isBoundary(int charCode) {
    // / (47), \ (92), _ (95), - (45), . (46), space (32)
    return charCode == 47 || charCode == 92 || charCode == 95 || 
           charCode == 45 || charCode == 46 || charCode == 32;
  }

  static bool _isUpper(int charCode) {
    // 'A' (65) to 'Z' (90)
    return charCode >= 65 && charCode <= 90;
  }
}