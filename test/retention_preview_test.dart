import 'package:flutter_test/flutter_test.dart';
import 'package:next_episode/retention_preview.dart';

void main() {
  test('visual preview expires only old metadata and retains both watched marks', () async {
    final db = await createRetentionPreview();
    addTearDown(db.close);
    final entries = await db.library();
    expect(entries, hasLength(2));
    expect(entries.singleWhere((e) => e.title.id == 900001).title.raw['content_unavailable'], true);
    expect(entries.singleWhere((e) => e.title.id == 900003).title.title, 'Sample space show');
    expect(await db.cached('series:900001'), isNull);
    expect(await db.cached('series:900003'), isNotNull);
    final marks = await db.customSelect('SELECT * FROM watched').get();
    expect(marks, hasLength(2));
  });
}
