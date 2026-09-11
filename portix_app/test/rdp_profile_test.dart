import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/domain/entities/rdp/rdp_profile.dart';

void main() {
  // =========================================================
  // HELPERS
  // =========================================================

  RdpProfile makeProfile({
    String id = 'p1',
    String host = '10.0.0.1',
    int port = 3389,
    String username = 'admin',
    String alternateShell = '',
  }) {
    return RdpProfile(
      id: id,
      name: 'Test',
      host: host,
      port: port,
      username: username,
      group: 'RDP',
      tags: const [],
      color: RdpProfileColor.blue,
      alternateShell: alternateShell,
    );
  }

  // =========================================================
  // COMPUTED PROPERTIES
  // =========================================================

  group('address getter', () {
    test('formats host:port', () {
      expect(
        makeProfile(host: '192.168.1.5', port: 3389).address,
        equals('192.168.1.5:3389'),
      );
    });

    test('shows "Not configured" when host is empty', () {
      expect(makeProfile(host: '').address, equals('Not configured'));
    });

    test('includes non-standard port', () {
      expect(
        makeProfile(host: 'myserver', port: 3390).address,
        equals('myserver:3390'),
      );
    });
  });

  group('isConnectable', () {
    test('true when host is non-empty', () {
      expect(makeProfile(host: '10.0.0.1').isConnectable, isTrue);
    });

    test('false when host is empty', () {
      expect(makeProfile(host: '').isConnectable, isFalse);
    });
  });

  group('isCyberArkPsm', () {
    test('true when alternateShell contains psm (case insensitive)', () {
      expect(makeProfile(alternateShell: 'PSM@vault').isCyberArkPsm, isTrue);
      expect(makeProfile(alternateShell: 'psm@vault').isCyberArkPsm, isTrue);
      expect(makeProfile(alternateShell: 'PsM@vault').isCyberArkPsm, isTrue);
    });

    test('false when alternateShell is empty', () {
      expect(makeProfile(alternateShell: '').isCyberArkPsm, isFalse);
    });

    test('false when alternateShell does not contain psm', () {
      expect(makeProfile(alternateShell: 'cmd.exe').isCyberArkPsm, isFalse);
    });
  });

  // =========================================================
  // copyWith
  // =========================================================

  group('copyWith', () {
    test('updates host', () {
      final p = makeProfile(host: 'old.host');
      expect(p.copyWith(host: 'new.host').host, equals('new.host'));
    });

    test('updates port', () {
      final p = makeProfile(port: 3389);
      expect(p.copyWith(port: 3390).port, equals(3390));
    });

    test('clears password when clearPassword is true', () {
      const p = RdpProfile(
        id: 'p',
        name: 'n',
        host: 'h',
        port: 3389,
        username: 'u',
        password: 'secret',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
      );
      expect(p.copyWith(clearPassword: true).password, isNull);
    });

    test('original is unchanged after copyWith', () {
      final original = makeProfile(host: 'original');
      original.copyWith(host: 'modified');
      expect(original.host, equals('original'));
    });

    test('clearSourceRdpFilePath sets it to null', () {
      const p = RdpProfile(
        id: 'p',
        name: 'n',
        host: 'h',
        port: 3389,
        username: 'u',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
        sourceRdpFilePath: '/some/path.rdp',
      );
      expect(
        p.copyWith(clearSourceRdpFilePath: true).sourceRdpFilePath,
        isNull,
      );
    });

    test('updates fullScreen', () {
      final p = makeProfile();
      expect(p.copyWith(fullScreen: true).fullScreen, isTrue);
    });

    test('updates desktopWidth and desktopHeight', () {
      final p = makeProfile();
      final updated = p.copyWith(desktopWidth: 1920, desktopHeight: 1080);
      expect(updated.desktopWidth, equals(1920));
      expect(updated.desktopHeight, equals(1080));
    });
  });

  // =========================================================
  // EQUALITY (Equatable)
  // =========================================================

  group('equality', () {
    test('same fields are equal', () {
      const p1 = RdpProfile(
        id: 'x',
        name: 'n',
        host: 'h',
        port: 3389,
        username: 'u',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
      );
      const p2 = RdpProfile(
        id: 'x',
        name: 'n',
        host: 'h',
        port: 3389,
        username: 'u',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
      );
      expect(p1, equals(p2));
    });

    test('different ids are not equal', () {
      const p1 = RdpProfile(
        id: 'a',
        name: 'n',
        host: 'h',
        port: 3389,
        username: 'u',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
      );
      const p2 = RdpProfile(
        id: 'b',
        name: 'n',
        host: 'h',
        port: 3389,
        username: 'u',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
      );
      expect(p1, isNot(equals(p2)));
    });

    test('different hosts are not equal', () {
      final p1 = makeProfile(host: 'a.com');
      final p2 = makeProfile(host: 'b.com');
      expect(p1, isNot(equals(p2)));
    });
  });

  // =========================================================
  // STATUS ENUM
  // =========================================================

  group('RdpProfileStatus', () {
    test('offline is default status', () {
      expect(makeProfile().status, equals(RdpProfileStatus.offline));
    });

    test('all statuses exist', () {
      expect(
        RdpProfileStatus.values,
        containsAll([
          RdpProfileStatus.offline,
          RdpProfileStatus.connecting,
          RdpProfileStatus.connected,
          RdpProfileStatus.error,
          RdpProfileStatus.draft,
        ]),
      );
    });
  });

  // =========================================================
  // COLOR ENUM
  // =========================================================

  group('RdpProfileColor', () {
    test('all colors exist', () {
      expect(
        RdpProfileColor.values,
        containsAll([
          RdpProfileColor.blue,
          RdpProfileColor.cyan,
          RdpProfileColor.green,
          RdpProfileColor.amber,
          RdpProfileColor.pink,
        ]),
      );
    });
  });
}
