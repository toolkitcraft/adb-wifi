import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:adb_wifi_core/testing.dart';
import 'package:test/test.dart';

const macHome = '/Users/me';
const macSdkAdb = '/Users/me/Library/Android/sdk/platform-tools/adb';

HostPlatform mac([Map<String, String> env = const {}]) =>
    HostPlatform(os: HostOs.macos, environment: {'HOME': macHome, ...env});

List<String> pathsOf(List<AdbCandidate> candidates) => [
  for (final c in candidates) c.path,
];

void main() {
  group('adbCandidates', () {
    test('macOS: SDK variables, default SDK, Homebrew, then PATH', () {
      final candidates = adbCandidates(
        mac({
          'ANDROID_HOME': '/sdk/home',
          'ANDROID_SDK_ROOT': '/sdk/root',
          'PATH': '/usr/bin:/bin',
        }),
      );
      expect(candidates, [
        (path: '/sdk/home/platform-tools/adb', source: AdbSource.androidHome),
        (
          path: '/sdk/root/platform-tools/adb',
          source: AdbSource.androidSdkRoot,
        ),
        (path: macSdkAdb, source: AdbSource.defaultSdk),
        (path: '/opt/homebrew/bin/adb', source: AdbSource.homebrew),
        (path: '/usr/local/bin/adb', source: AdbSource.homebrew),
        (path: '/usr/bin/adb', source: AdbSource.path),
        (path: '/bin/adb', source: AdbSource.path),
      ]);
    });

    test('Windows: adb.exe, LOCALAPPDATA, ";" and quoted PATH entries', () {
      final candidates = adbCandidates(
        const HostPlatform(
          os: HostOs.windows,
          environment: {
            'USERPROFILE': r'C:\Users\me',
            'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
            'PATH': r'C:\Windows;"C:\Program Files\Tools"',
          },
        ),
      );
      expect(candidates, [
        (
          path: r'C:\Users\me\AppData\Local\Android\Sdk\platform-tools\adb.exe',
          source: AdbSource.defaultSdk,
        ),
        (path: r'C:\Windows\adb.exe', source: AdbSource.path),
        (path: r'C:\Program Files\Tools\adb.exe', source: AdbSource.path),
      ]);
    });

    test('Linux: ~/Android/Sdk and PATH, no Homebrew', () {
      final candidates = adbCandidates(
        const HostPlatform(
          os: HostOs.linux,
          environment: {'HOME': '/home/me', 'PATH': '/usr/local/bin'},
        ),
      );
      expect(pathsOf(candidates), [
        '/home/me/Android/Sdk/platform-tools/adb',
        '/usr/local/bin/adb',
      ]);
    });

    test('a path seen twice keeps its first, better source', () {
      final candidates = adbCandidates(
        mac({
          'ANDROID_HOME': '$macHome/Library/Android/sdk/',
          'PATH': '/opt/homebrew/bin:/usr/bin',
        }),
      );
      expect(candidates, [
        (path: macSdkAdb, source: AdbSource.androidHome),
        (path: '/opt/homebrew/bin/adb', source: AdbSource.homebrew),
        (path: '/usr/local/bin/adb', source: AdbSource.homebrew),
        (path: '/usr/bin/adb', source: AdbSource.path),
      ]);
    });

    test('Windows duplicates ignore letter case', () {
      final candidates = adbCandidates(
        const HostPlatform(
          os: HostOs.windows,
          environment: {
            'ANDROID_HOME': r'C:\Android\Sdk',
            'ANDROID_SDK_ROOT': r'c:\android\sdk',
          },
        ),
      );
      expect(candidates, [
        (
          path: r'C:\Android\Sdk\platform-tools\adb.exe',
          source: AdbSource.androidHome,
        ),
      ]);
    });

    test('blank variables and empty or relative PATH entries are skipped', () {
      final candidates = adbCandidates(
        mac({'ANDROID_HOME': '  ', 'PATH': ':.:bin:/usr/bin:'}),
      );
      expect(
        candidates.where((c) => c.source == AdbSource.androidHome),
        isEmpty,
      );
      expect(
        pathsOf(candidates.where((c) => c.source == AdbSource.path).toList()),
        ['/usr/bin/adb'],
      );
    });

    test('no HOME means no default SDK folder', () {
      final candidates = adbCandidates(
        const HostPlatform(os: HostOs.linux, environment: {}),
      );
      expect(candidates, isEmpty);
    });
  });

  group('findAdb', () {
    test('prefers the SDK adb and lists the others', () {
      final result = findAdb(
        mac({'PATH': '/usr/bin'}),
        FakeFileProbe({'/opt/homebrew/bin/adb', macSdkAdb, '/usr/bin/adb'}),
      );
      expect(result, isA<AdbFound>());
      final found = result as AdbFound;
      expect(found.adb, (path: macSdkAdb, source: AdbSource.defaultSdk));
      expect(pathsOf(found.others), ['/opt/homebrew/bin/adb', '/usr/bin/adb']);
    });

    test('finds adb on PATH when nothing else exists', () {
      final result = findAdb(
        mac({'PATH': '/usr/bin'}),
        FakeFileProbe({'/usr/bin/adb'}),
      );
      expect(result, isA<AdbFound>());
      final found = result as AdbFound;
      expect(found.adb, (path: '/usr/bin/adb', source: AdbSource.path));
      expect(found.others, isEmpty);
    });

    test('reports every place it searched when adb is missing', () {
      final platform = mac({'PATH': '/usr/bin'});
      final result = findAdb(platform, FakeFileProbe({}));
      expect(result, isA<AdbNotFound>());
      expect((result as AdbNotFound).searched, adbCandidates(platform));
    });
  });

  test('HostPlatform.current() works on this computer', () {
    final platform = HostPlatform.current();
    expect(HostOs.values, contains(platform.os));
  });
}
