import 'package:countdown_todo/features/thirty_day_challenge/services/challenge_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes Markdown checklist markers from imported task titles', () {
    expect(
      ChallengeTextParser.parseTaskTitles(
        '- [ ] Read a book\n- [x] Take a walk\n+ [X] Call a friend',
      ),
      ['Read a book', 'Take a walk', 'Call a friend'],
    );
  });
}
