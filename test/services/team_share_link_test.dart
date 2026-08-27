import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/services/team_share_link.dart';

void main() {
  test('builds a public Flutter Web hash link', () {
    expect(
      TeamShareLink.build('ABC 123'),
      'https://cdt.junpgle.me/#/share?code=ABC+123',
    );
  });

  test('repairs the old API path link', () {
    expect(
      TeamShareLink.normalize(
        shareUrl: 'https://api-cdt.junpgle.me/share/ABC123',
      ),
      'https://cdt.junpgle.me/#/share?code=ABC123',
    );
  });

  test('keeps an already valid hash link', () {
    const link = 'https://cdt.junpgle.me/#/share?code=ABC123';
    expect(TeamShareLink.normalize(shareUrl: link, shareCode: 'ABC123'), link);
  });

  test('parses query and path share routes', () {
    expect(TeamShareLink.codeFromRoute('/share?code=ABC123'), 'ABC123');
    expect(TeamShareLink.codeFromRoute('/share/ABC123'), 'ABC123');
    expect(
      TeamShareLink.codeFromRoute('#/share?code=ABC123'),
      'ABC123',
    );
    expect(
      TeamShareLink.codeFromRoute('https://cdt.junpgle.me/#/share?code=ABC123'),
      'ABC123',
    );
  });
}
