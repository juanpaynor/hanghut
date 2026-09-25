import 'package:bitemates/features/ticketing/widgets/registration_questions_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// team_comms #330: questions are no longer a flat list. Each case here is one
/// the message called out, plus the failure it warned about — asking a 5KM
/// entrant the 21KM finisher-shirt question.
void main() {
  Map<String, dynamic> q(
    String id, {
    String type = 'short_text',
    bool required = false,
    List<String>? tiers,
    String? dependsOn,
    List<String>? whenValues,
    String label = 'Q',
  }) =>
      {
        'id': id,
        'label': label,
        'question_type': type,
        'is_required': required,
        if (tiers != null) 'tier_ids': tiers,
        if (dependsOn != null) 'depends_on_question_id': dependsOn,
        if (whenValues != null) 'depends_on_values': whenValues,
      };

  List<String> ids(List<Map<String, dynamic>> l) =>
      l.map((e) => e['id'] as String).toList();

  group('tier scoping', () {
    final questions = [
      q('name'),
      q('shirt', tiers: ['21k'], label: 'Finisher shirt size'),
    ];

    test('the 21KM question is not asked of a 5KM buyer', () {
      expect(ids(RegistrationQuestionsForm.applicable(questions, {}, tierId: '5k')),
          ['name']);
    });

    test('it IS asked of a 21KM buyer', () {
      expect(ids(RegistrationQuestionsForm.applicable(questions, {}, tierId: '21k')),
          ['name', 'shirt']);
    });

    test('no tier chosen yet → nothing tier-scoped applies', () {
      expect(ids(RegistrationQuestionsForm.applicable(questions, {})), ['name']);
    });

    test('empty tier_ids means ask everyone', () {
      final all = [q('a', tiers: [])];
      expect(ids(RegistrationQuestionsForm.applicable(all, {}, tierId: '5k')), ['a']);
    });
  });

  group('conditional questions', () {
    final questions = [
      q('member', type: 'single_choice'),
      q('club', dependsOn: 'member', whenValues: ['Yes']),
    ];

    test('hidden until the trigger answer matches', () {
      expect(ids(RegistrationQuestionsForm.applicable(questions, {})), ['member']);
      expect(
          ids(RegistrationQuestionsForm.applicable(questions, {'member': 'No'})),
          ['member']);
    });

    test('shown on a match', () {
      expect(
          ids(RegistrationQuestionsForm.applicable(questions, {'member': 'Yes'})),
          ['member', 'club']);
    });

    test('multi_choice answer is a list — any overlap counts', () {
      expect(
          ids(RegistrationQuestionsForm.applicable(questions, {
            'member': ['Maybe', 'Yes']
          })),
          ['member', 'club']);
    });
  });

  group('sections', () {
    test('a heading whose whole group is hidden is dropped', () {
      final questions = [
        q('h1', type: 'section', label: 'About you'),
        q('name'),
        q('h2', type: 'section', label: '21KM only'),
        q('shirt', tiers: ['21k']),
      ];
      expect(ids(RegistrationQuestionsForm.applicable(questions, {}, tierId: '5k')),
          ['h1', 'name']);
      expect(ids(RegistrationQuestionsForm.applicable(questions, {}, tierId: '21k')),
          ['h1', 'name', 'h2', 'shirt']);
    });

    test('a section takes no answer and never blocks', () {
      final questions = [q('h1', type: 'section', required: true)];
      expect(RegistrationQuestionsForm.isDisplayOnly(questions.first), isTrue);
      expect(RegistrationQuestionsForm.validate(questions, {}), isNull);
    });
  });

  group('validation and payload', () {
    test('a required question the buyer never saw does not block', () {
      final questions = [q('shirt', required: true, tiers: ['21k'])];
      expect(RegistrationQuestionsForm.validate(questions, {}, tierId: '5k'), isNull);
      expect(RegistrationQuestionsForm.validate(questions, {}, tierId: '21k'),
          isNotNull);
    });

    test('an answer stranded by a tier change is not submitted', () {
      final questions = [q('shirt', tiers: ['21k'])];
      final answers = {'shirt': 'XL'};
      expect(
          RegistrationQuestionsForm.answersFor(questions, answers, tierId: '21k'),
          {'shirt': 'XL'});
      expect(
          RegistrationQuestionsForm.answersFor(questions, answers, tierId: '5k'),
          isEmpty);
    });

    test('section answers are never submitted', () {
      final questions = [q('h1', type: 'section')];
      expect(
          RegistrationQuestionsForm.answersFor(questions, {'h1': 'oops'}), isEmpty);
    });
  });

  group('unknown types', () {
    test('an unrecognised type still applies and is not display-only', () {
      final questions = [q('x', type: 'quantum_field')];
      expect(ids(RegistrationQuestionsForm.applicable(questions, {})), ['x']);
      expect(RegistrationQuestionsForm.isDisplayOnly(questions.first), isFalse);
    });

    test('a missing question_type does not throw', () {
      final bare = {'id': 'x', 'label': 'Q'};
      expect(RegistrationQuestionsForm.typeOf(bare), 'short_text');
      expect(ids(RegistrationQuestionsForm.applicable([bare], {})), ['x']);
    });
  });
}
