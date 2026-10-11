import 'package:erp_kayan/core/storage/token_store.dart';
import 'package:erp_kayan/features/auth/presentation/providers/auth_providers.dart'
    show tokenStoreProvider;
import 'package:erp_kayan/features/data/presentation/providers/data_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The links behind every download and print button.
///
/// These URLs are opened by the browser itself, as a navigation that cannot
/// carry an Authorization header - so each one must carry the access token in
/// its query, and the server accepts it there on those routes only. A link
/// built without a token looks exactly like a working button and downloads
/// nothing but a 401, which is worth a test of its own.
class FakeTokenStore extends TokenStore {
  @override
  Future<String?> readAccessToken() async => 'TOKEN.123';
}

void main() {
  group('ReportLinkBuilder', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(FakeTokenStore())],
      );
      addTearDown(container.dispose);
    });

    test('a report file link carries the token and the chosen format', () async {
      final url = await container.read(reportLinkProvider).file(
            report: 'trial-balance',
            format: 'xlsx',
            language: 'ar',
            from: '2026-01-01',
            to: '2026-12-31',
          );
      expect(url, contains('/exports/trial-balance/download?'));
      expect(url, contains('token=TOKEN.123'));
      expect(url, contains('format=xlsx'));
      expect(url, contains('lang=ar'));
      expect(url, contains('from=2026-01-01'));
      expect(url, contains('to=2026-12-31'));
    });

    test('filters the caller did not give are left out, never sent empty', () async {
      final url = await container.read(reportLinkProvider).file(
            report: 'trial-balance',
            format: 'csv',
            language: 'en',
          );
      expect(url, isNot(contains('from=')));
      expect(url, isNot(contains('to=')));
      expect(url, isNot(contains('accountId=')));
    });

    test('the print link can ask for the print dialogue by itself', () async {
      final links = container.read(reportLinkProvider);
      final auto = await links.print(report: 'trial-balance', language: 'ar');
      expect(auto, contains('/exports/trial-balance/print?'));
      expect(auto, contains('auto=1'));
      expect(auto, contains('token=TOKEN.123'));

      final paper = await links.print(
        report: 'trial-balance',
        language: 'ar',
        auto: false,
      );
      expect(paper, isNot(contains('auto=')));
    });

    test('list links name the list and carry the screen\'s filters', () async {
      final url = await container.read(reportLinkProvider).listFile(
            list: 'customers',
            format: 'xlsx',
            language: 'ar',
            filters: const {'q': 'acme', 'status': 'active'},
          );
      expect(url, contains('/exports/lists/customers/download?'));
      expect(url, contains('q=acme'));
      expect(url, contains('status=active'));
      expect(url, contains('token=TOKEN.123'));
    });

    test('backup links point at the right routes and authenticate', () async {
      final links = container.read(reportLinkProvider);
      final company = await links.backup();
      expect(company, contains('/backup/download?'));
      expect(company, contains('token=TOKEN.123'));

      final full = await links.fullBackupDownload('kayan-full-2026.dump');
      expect(
        full,
        contains('/backup/full/kayan-full-2026.dump/download?'),
      );
      expect(full, contains('token=TOKEN.123'));
    });

    test('the import template link names the kind being imported', () async {
      final url = await container.read(reportLinkProvider).importTemplate(
            kind: 'customers',
            language: 'en',
          );
      expect(url, contains('/import/templates/customers?'));
      expect(url, contains('lang=en'));
      expect(url, contains('token=TOKEN.123'));
    });
  });
}
