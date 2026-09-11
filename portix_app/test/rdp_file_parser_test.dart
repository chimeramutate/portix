import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/domain/entities/rdp/rdp_file_parser.dart';
import 'package:portix/src/domain/entities/rdp/rdp_profile.dart';

void main() {
  const parser = RdpFileParser();

  // =========================================================
  // HELPERS
  // =========================================================

  RdpProfile parse(String content, {String id = 'test-id', String? filePath}) {
    return parser.parse(content, profileId: id, filePath: filePath);
  }

  // =========================================================
  // BASIC PARSING
  // =========================================================

  group('basic field parsing', () {
    test('extracts host from full address', () {
      final p = parse('full address:s:192.168.1.10\nusername:s:admin\n');
      expect(p.host, equals('192.168.1.10'));
    });

    test('uses default port 3389 when not specified', () {
      final p = parse('full address:s:myserver.com\nusername:s:admin\n');
      expect(p.port, equals(3389));
    });

    test('extracts port from full address colon notation', () {
      final p = parse('full address:s:myserver.com:3390\nusername:s:admin\n');
      expect(p.host, equals('myserver.com'));
      expect(p.port, equals(3390));
    });

    test('server port field takes precedence over port in full address', () {
      final p = parse(
        'full address:s:myserver.com:9999\nserver port:i:3391\nusername:s:bob\n',
      );
      expect(p.port, equals(3391));
    });

    test('extracts username', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:jdoe\n');
      expect(p.username, equals('jdoe'));
    });

    test('assigns given profile id', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:x\n', id: 'my-id');
      expect(p.id, equals('my-id'));
    });
  });

  // =========================================================
  // DOMAIN / USERNAME SPLITTING
  // =========================================================

  group('domain\\username splitting', () {
    test('splits DOMAIN\\user into domain and username', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:CORP\\jdoe\n');
      expect(p.domain, equals('CORP'));
      expect(p.username, equals('jdoe'));
    });

    test('no domain when username has no backslash', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:jdoe\n');
      expect(p.domain, isNull);
      expect(p.username, equals('jdoe'));
    });

    test('CyberArk localhost\\PSM@session format parsed correctly', () {
      final p = parse(
        'full address:s:172.20.35.10\nusername:s:localhost\\PSM@abc123\n',
      );
      expect(p.domain, equals('localhost'));
      expect(p.username, equals('PSM@abc123'));
    });
  });

  // =========================================================
  // DISPLAY SETTINGS
  // =========================================================

  group('display settings', () {
    test('desktop resolution parsed correctly', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\ndesktopwidth:i:1920\ndesktopheight:i:1080\n',
      );
      expect(p.desktopWidth, equals(1920));
      expect(p.desktopHeight, equals(1080));
    });

    test('defaults to 1280x800 when resolution missing', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:u\n');
      expect(p.desktopWidth, equals(1280));
      expect(p.desktopHeight, equals(800));
    });

    test('fullscreen when screen mode id is 2', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nscreen mode id:i:2\n',
      );
      expect(p.fullScreen, isTrue);
    });

    test('not fullscreen when screen mode id is 1', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nscreen mode id:i:1\n',
      );
      expect(p.fullScreen, isFalse);
    });

    test('not fullscreen by default', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:u\n');
      expect(p.fullScreen, isFalse);
    });
  });

  // =========================================================
  // CREDENTIAL SSP
  // =========================================================

  group('CredSSP setting', () {
    test('enableCredSsp false when EnableCredSspSupport is 0', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nEnableCredSspSupport:i:0\n',
      );
      expect(p.enableCredSsp, isFalse);
    });

    test('enableCredSsp true when EnableCredSspSupport is 1', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nEnableCredSspSupport:i:1\n',
      );
      expect(p.enableCredSsp, isTrue);
    });

    test('enableCredSsp false by default when field missing', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:u\n');
      // parser defaults missing enablecredsspsupport to 0
      expect(p.enableCredSsp, isFalse);
    });
  });

  // =========================================================
  // REDIRECT DRIVES
  // =========================================================

  group('redirect drives', () {
    test('redirectDrives true when redirectdrives is 1', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nredirectdrives:i:1\n',
      );
      expect(p.redirectDrives, isTrue);
      expect(p.localSharePath, equals(RdpProfile.defaultLocalSharePath));
    });

    test('redirectDrives true when drivestoredirect is present', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\ndrivestoredirect:s:*\n',
      );
      expect(p.redirectDrives, isTrue);
      expect(p.localSharePath, equals(RdpProfile.defaultLocalSharePath));
    });

    test('redirectDrives false by default', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:u\n');
      expect(p.redirectDrives, isFalse);
      expect(p.localSharePath, isNull);
    });
  });

  // =========================================================
  // CYBERARK PSM DETECTION
  // =========================================================

  group('CyberArk PSM detection', () {
    test('isCyberArkPsm is true when alternate shell contains psm', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nalternate shell:s:PSM@target\n',
      );
      expect(p.isCyberArkPsm, isTrue);
    });

    test('group is CyberArk PSM when alternate shell contains psm', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nalternate shell:s:PSM@target\n',
      );
      expect(p.group, equals('CyberArk PSM'));
    });

    test('group is RDP when no alternate shell', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:u\n');
      expect(p.group, equals('RDP'));
    });

    test('tags include cyberark and psm for PSM profiles', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nalternate shell:s:PSM@x\n',
      );
      expect(p.tags, containsAll(['cyberark', 'psm']));
    });

    test('tags are empty for non-PSM profiles', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:u\n');
      expect(p.tags, isEmpty);
    });
  });

  // =========================================================
  // FULL CYBERARK SCENARIO
  // =========================================================

  test('parses full CyberArk PSM .rdp file correctly', () {
    const content = '''
full address:s:172.20.35.10
server port:i:3389
username:s:localhost\\PSM@abc123
alternate shell:s:PSM@abc123
desktopwidth:i:1920
desktopheight:i:1080
EnableCredSspSupport:i:1''';

    final p = parse(content, id: 'psm-id');

    expect(p.id, equals('psm-id'));
    expect(p.host, equals('172.20.35.10'));
    expect(p.port, equals(3389));
    expect(p.username, equals('PSM@abc123'));
    expect(p.domain, equals('localhost'));
    expect(p.isCyberArkPsm, isTrue);
    expect(p.alternateShell, equals('PSM@abc123'));
    expect(p.desktopWidth, equals(1920));
    expect(p.desktopHeight, equals(1080));
    expect(p.enableCredSsp, isTrue);
  });

  // =========================================================
  // NAME DERIVATION
  // =========================================================

  group('profile name derivation', () {
    test('uses filename without .rdp extension', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\n',
        filePath: '/home/user/production-server.rdp',
      );
      expect(p.name, equals('production-server'));
    });

    test('strips trailing UUID from filename', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\n',
        filePath:
            '/downloads/MyServer.97879249-5c68-4b2a-9c3d-1234567890ab.rdp',
      );
      expect(p.name, equals('MyServer'));
    });

    test('falls back to alternate shell name when no file path', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nalternate shell:s:PSM@target\n',
      );
      expect(p.name, equals('PSM@target'));
    });

    test('falls back to RDP host when no file path and no alternate shell', () {
      final p = parse('full address:s:rdpserver.local\nusername:s:u\n');
      expect(p.name, equals('RDP – rdpserver.local'));
    });

    test('uses New RDP when host is empty and no file path', () {
      final p = parse('username:s:u\n');
      expect(p.name, equals('New RDP'));
    });
  });

  // =========================================================
  // SERIALIZE → PARSE ROUNDTRIP
  // =========================================================

  group('serialize round-trip', () {
    test('serialize preserves host and port', () {
      const original = RdpProfile(
        id: 'rt-1',
        name: 'Test',
        host: '10.0.0.5',
        port: 3390,
        username: 'alice',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
      );
      final serialized = parser.serialize(original);
      final restored = parse(serialized, id: 'rt-1');

      expect(restored.host, equals(original.host));
      expect(restored.port, equals(original.port));
    });

    test('serialize preserves username', () {
      const original = RdpProfile(
        id: 'rt-2',
        name: 'Test',
        host: '10.0.0.5',
        port: 3389,
        username: 'bob',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
      );
      final serialized = parser.serialize(original);
      final restored = parse(serialized, id: 'rt-2');

      expect(restored.username, equals(original.username));
    });

    test('serialize preserves domain\\username', () {
      const original = RdpProfile(
        id: 'rt-3',
        name: 'Test',
        host: '10.0.0.5',
        port: 3389,
        username: 'jdoe',
        domain: 'CORP',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
      );
      final serialized = parser.serialize(original);
      final restored = parse(serialized, id: 'rt-3');

      expect(restored.username, equals('jdoe'));
      expect(restored.domain, equals('CORP'));
    });

    test('serialize preserves desktop resolution', () {
      const original = RdpProfile(
        id: 'rt-4',
        name: 'Test',
        host: '10.0.0.5',
        port: 3389,
        username: 'u',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
        desktopWidth: 1920,
        desktopHeight: 1080,
      );
      final serialized = parser.serialize(original);
      final restored = parse(serialized, id: 'rt-4');

      expect(restored.desktopWidth, equals(1920));
      expect(restored.desktopHeight, equals(1080));
    });

    test('serialize preserves fullscreen flag', () {
      const original = RdpProfile(
        id: 'rt-5',
        name: 'Test',
        host: '10.0.0.5',
        port: 3389,
        username: 'u',
        group: 'RDP',
        tags: [],
        color: RdpProfileColor.blue,
        fullScreen: true,
      );
      final serialized = parser.serialize(original);
      final restored = parse(serialized, id: 'rt-5');

      expect(restored.fullScreen, isTrue);
    });

    test('serialize includes alternate shell when present', () {
      const original = RdpProfile(
        id: 'rt-6',
        name: 'CyberArk',
        host: '10.0.0.5',
        port: 3389,
        username: 'PSM@sess',
        group: 'CyberArk PSM',
        tags: [],
        color: RdpProfileColor.cyan,
        alternateShell: 'PSM@sess',
      );
      final serialized = parser.serialize(original);
      expect(serialized, contains('alternate shell:s:PSM@sess'));
    });
  });

  // =========================================================
  // EDGE CASES
  // =========================================================

  group('edge cases', () {
    test('empty content produces default values', () {
      final p = parse('');
      expect(p.port, equals(3389));
      expect(p.desktopWidth, equals(1280));
      expect(p.desktopHeight, equals(800));
    });

    test('malformed port falls back to 3389', () {
      final p = parse(
        'full address:s:10.0.0.1\nusername:s:u\nserver port:i:not_a_number\n',
      );
      expect(p.port, equals(3389));
    });

    test('handles CRLF line endings', () {
      final p = parse('full address:s:10.0.0.1\r\nusername:s:admin\r\n');
      expect(p.host, equals('10.0.0.1'));
      expect(p.username, equals('admin'));
    });

    test('status defaults to offline', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:u\n');
      expect(p.status, equals(RdpProfileStatus.offline));
    });

    test('color defaults to cyan', () {
      final p = parse('full address:s:10.0.0.1\nusername:s:u\n');
      expect(p.color, equals(RdpProfileColor.cyan));
    });
  });
}
