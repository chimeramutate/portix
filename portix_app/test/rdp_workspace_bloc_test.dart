import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/domain/entities/rdp/rdp_profile.dart';
import 'package:portix/src/domain/repositories/rdp/rdp_profile_repository.dart';
import 'package:portix/src/features/rdp/bloc/rdp_workspace_bloc.dart';

// ---------------------------------------------------------------------------
// Stub repository — pure in-memory, no file I/O
// ---------------------------------------------------------------------------

class _StubRdpProfileRepository extends RdpProfileRepository {
  _StubRdpProfileRepository(this._data);

  final List<RdpProfile> _data;
  bool failNext = false;
  String failMessage = 'stub error';

  @override
  Future<Either<Failure, List<RdpProfile>>> getProfiles() async {
    if (failNext) {
      failNext = false;
      return Left(Failure(failMessage));
    }
    return Right(List.unmodifiable(_data));
  }

  @override
  Future<Either<Failure, RdpProfile>> saveProfile(RdpProfile profile) async {
    if (failNext) {
      failNext = false;
      return Left(Failure(failMessage));
    }
    final idx = _data.indexWhere((p) => p.id == profile.id);
    final saved = profile.copyWith(status: RdpProfileStatus.offline);
    if (idx == -1) {
      _data.insert(0, saved);
    } else {
      _data[idx] = saved;
    }
    return Right(saved);
  }

  @override
  Future<Either<Failure, Null>> deleteProfile(String id) async {
    if (failNext) {
      failNext = false;
      return Left(Failure(failMessage));
    }
    _data.removeWhere((p) => p.id == id);
    return const Right(null);
  }

  @override
  Future<Either<Failure, RdpProfile>> importRdpFile(String filePath) async {
    return Left(Failure('not implemented in stub'));
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

RdpProfile _makeProfile({
  String id = 'p1',
  String name = 'Server A',
  String host = '10.0.0.1',
  int port = 3389,
  String group = 'RDP',
}) {
  return RdpProfile(
    id: id,
    name: name,
    host: host,
    port: port,
    username: 'admin',
    group: group,
    tags: const [],
    color: RdpProfileColor.blue,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _StubRdpProfileRepository repo;
  late RdpWorkspaceBloc bloc;

  setUp(() {
    repo = _StubRdpProfileRepository([]);
    bloc = RdpWorkspaceBloc(repository: repo);
  });

  tearDown(() => bloc.close());

  // =========================================================
  // INITIAL STATE
  // =========================================================

  group('initial state', () {
    test('starts with status initial', () {
      expect(bloc.state.status, equals(RdpWorkspaceStatus.initial));
    });

    test('starts with no profiles', () {
      expect(bloc.state.profiles, isEmpty);
    });

    test('starts with gallery view', () {
      expect(bloc.state.activeView, equals(RdpView.gallery));
    });

    test('starts with no selection', () {
      expect(bloc.state.selectedId, isNull);
    });
  });

  // =========================================================
  // PROFILES REQUESTED
  // =========================================================

  group('RdpProfilesRequested', () {
    test('emits ready with profiles on success', () async {
      repo = _StubRdpProfileRepository([_makeProfile()]);
      bloc = RdpWorkspaceBloc(repository: repo);

      bloc.add(const RdpProfilesRequested());

      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) =>
                s.status == RdpWorkspaceStatus.ready &&
                s.profiles.length == 1 &&
                s.profiles.first.name == 'Server A',
          ),
        ),
      );
    });

    test('emits failure when repository fails', () async {
      repo.failNext = true;
      repo.failMessage = 'disk error';
      bloc.add(const RdpProfilesRequested());

      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) =>
                s.status == RdpWorkspaceStatus.failure &&
                s.message.contains('disk error'),
          ),
        ),
      );
    });

    test('clears selection after loading', () async {
      repo = _StubRdpProfileRepository([_makeProfile()]);
      bloc = RdpWorkspaceBloc(repository: repo);

      // Select something first
      bloc.add(const RdpProfileSelected('p1'));
      await pumpEventQueue();

      bloc.add(const RdpProfilesRequested());

      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) => s.status == RdpWorkspaceStatus.ready && s.selectedId == null,
          ),
        ),
      );
    });
  });

  // =========================================================
  // PROFILE SELECTION
  // =========================================================

  group('RdpProfileSelected', () {
    test('sets selectedId', () async {
      bloc.add(const RdpProfileSelected('p1'));
      await pumpEventQueue();
      expect(bloc.state.selectedId, equals('p1'));
    });

    test('selectedProfile is null when profiles list is empty', () async {
      bloc.add(const RdpProfileSelected('p1'));
      await pumpEventQueue();
      expect(bloc.state.selectedProfile, isNull);
    });

    test('selectedProfile returns correct profile when loaded', () async {
      repo = _StubRdpProfileRepository([_makeProfile(id: 'p1', name: 'Alpha')]);
      bloc = RdpWorkspaceBloc(repository: repo);

      bloc.add(const RdpProfilesRequested());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) => s.status == RdpWorkspaceStatus.ready,
          ),
        ),
      );

      bloc.add(const RdpProfileSelected('p1'));
      await pumpEventQueue();

      expect(bloc.state.selectedProfile?.name, equals('Alpha'));
    });
  });

  // =========================================================
  // PROFILE SELECTION CLEARED
  // =========================================================

  group('RdpProfileSelectionCleared', () {
    test('clears selectedId', () async {
      bloc.add(const RdpProfileSelected('p1'));
      await pumpEventQueue();
      bloc.add(const RdpProfileSelectionCleared());
      await pumpEventQueue();
      expect(bloc.state.selectedId, isNull);
    });
  });

  // =========================================================
  // NEW PROFILE REQUESTED
  // =========================================================

  group('RdpNewProfileRequested', () {
    test('switches to form view', () async {
      bloc.add(const RdpNewProfileRequested());
      await pumpEventQueue();
      expect(bloc.state.activeView, equals(RdpView.form));
    });

    test('sets editingProfile with empty name', () async {
      bloc.add(const RdpNewProfileRequested());
      await pumpEventQueue();
      expect(bloc.state.editingProfile?.name, isEmpty);
    });

    test('editingProfile has default port 3389', () async {
      bloc.add(const RdpNewProfileRequested());
      await pumpEventQueue();
      expect(bloc.state.editingProfile?.port, equals(3389));
    });

    test('editingProfile has draft status', () async {
      bloc.add(const RdpNewProfileRequested());
      await pumpEventQueue();
      expect(bloc.state.editingProfile?.status, equals(RdpProfileStatus.draft));
    });
  });

  // =========================================================
  // PROFILE FORM CHANGED
  // =========================================================

  group('RdpProfileFormChanged', () {
    setUp(() {
      bloc.add(const RdpNewProfileRequested());
    });

    test('updates name in editingProfile', () async {
      await pumpEventQueue();
      bloc.add(
        const RdpProfileFormChanged(
          name: 'My Server',
          host: '10.0.0.1',
          port: '3389',
          username: 'admin',
          password: '',
          domain: '',
          group: 'RDP',
          desktopWidth: '1280',
          desktopHeight: '800',
          fullScreen: false,
          redirectDrives: false,
          redirectClipboard: true,
          enableCredSsp: false,
          alternateShell: '',
        ),
      );
      await pumpEventQueue();
      expect(bloc.state.editingProfile?.name, equals('My Server'));
    });

    test('updates port from string', () async {
      await pumpEventQueue();
      bloc.add(
        const RdpProfileFormChanged(
          name: 'S',
          host: '10.0.0.1',
          port: '3390',
          username: 'u',
          password: '',
          domain: '',
          group: 'RDP',
          desktopWidth: '1280',
          desktopHeight: '800',
          fullScreen: false,
          redirectDrives: false,
          redirectClipboard: true,
          enableCredSsp: false,
          alternateShell: '',
        ),
      );
      await pumpEventQueue();
      expect(bloc.state.editingProfile?.port, equals(3390));
    });

    test('keeps original port when non-numeric string given', () async {
      await pumpEventQueue();
      final originalPort = bloc.state.editingProfile?.port ?? 3389;
      bloc.add(
        RdpProfileFormChanged(
          name: 'S',
          host: '10.0.0.1',
          port: 'abc',
          username: 'u',
          password: '',
          domain: '',
          group: 'RDP',
          desktopWidth: '1280',
          desktopHeight: '800',
          fullScreen: false,
          redirectDrives: false,
          redirectClipboard: true,
          enableCredSsp: false,
          alternateShell: '',
        ),
      );
      await pumpEventQueue();
      expect(bloc.state.editingProfile?.port, equals(originalPort));
    });
  });

  // =========================================================
  // PROFILE SAVED
  // =========================================================

  group('RdpProfileSaved', () {
    test('validates empty name', () async {
      bloc.add(const RdpNewProfileRequested());
      await pumpEventQueue();
      // Leave name empty — don't call FormChanged
      bloc.add(const RdpProfileSaved());
      await pumpEventQueue();
      expect(bloc.state.message, isNotEmpty);
      expect(bloc.state.activeView, equals(RdpView.form)); // stays on form
    });

    test('saves valid profile and returns to gallery', () async {
      bloc.add(const RdpNewProfileRequested());
      await pumpEventQueue();

      bloc.add(
        const RdpProfileFormChanged(
          name: 'Production',
          host: '10.0.0.5',
          port: '3389',
          username: 'admin',
          password: '',
          domain: '',
          group: 'RDP',
          desktopWidth: '1280',
          desktopHeight: '800',
          fullScreen: false,
          redirectDrives: false,
          redirectClipboard: true,
          enableCredSsp: false,
          alternateShell: '',
        ),
      );
      await pumpEventQueue();

      bloc.add(const RdpProfileSaved());

      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) =>
                s.activeView == RdpView.gallery &&
                s.profiles.any((p) => p.name == 'Production'),
          ),
        ),
      );
    });

    test('validates empty host', () async {
      bloc.add(const RdpNewProfileRequested());
      await pumpEventQueue();

      bloc.add(
        const RdpProfileFormChanged(
          name: 'Some Profile',
          host: '',
          port: '3389',
          username: 'admin',
          password: '',
          domain: '',
          group: 'RDP',
          desktopWidth: '1280',
          desktopHeight: '800',
          fullScreen: false,
          redirectDrives: false,
          redirectClipboard: true,
          enableCredSsp: false,
          alternateShell: '',
        ),
      );
      await pumpEventQueue();

      bloc.add(const RdpProfileSaved());
      await pumpEventQueue();

      expect(bloc.state.message, isNotEmpty);
    });
  });

  // =========================================================
  // PROFILE DELETED
  // =========================================================

  group('RdpProfileDeleted', () {
    test('removes profile from list', () async {
      repo = _StubRdpProfileRepository([_makeProfile(id: 'del-1')]);
      bloc = RdpWorkspaceBloc(repository: repo);

      bloc.add(const RdpProfilesRequested());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>((s) => s.profiles.isNotEmpty),
        ),
      );

      bloc.add(const RdpProfileDeleted('del-1'));

      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) => s.profiles.every((p) => p.id != 'del-1'),
          ),
        ),
      );
    });

    test('clears selection when deleting selected profile', () async {
      repo = _StubRdpProfileRepository([_makeProfile(id: 'sel-1')]);
      bloc = RdpWorkspaceBloc(repository: repo);

      bloc.add(const RdpProfilesRequested());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) => s.status == RdpWorkspaceStatus.ready,
          ),
        ),
      );

      bloc.add(const RdpProfileSelected('sel-1'));
      await pumpEventQueue();

      bloc.add(const RdpProfileDeleted('sel-1'));

      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) => s.profiles.isEmpty && s.selectedId == null,
          ),
        ),
      );
    });
  });

  // =========================================================
  // SEARCH & FILTER
  // =========================================================

  group('search and filter', () {
    setUp(() async {
      repo = _StubRdpProfileRepository([
        _makeProfile(id: 'p1', name: 'Alpha', host: '10.0.0.1', group: 'RDP'),
        _makeProfile(
          id: 'p2',
          name: 'Beta',
          host: '10.0.0.2',
          group: 'Staging',
        ),
        _makeProfile(id: 'p3', name: 'Gamma', host: '10.0.0.3', group: 'RDP'),
      ]);
      bloc = RdpWorkspaceBloc(repository: repo);
      bloc.add(const RdpProfilesRequested());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) => s.status == RdpWorkspaceStatus.ready,
          ),
        ),
      );
    });

    test('filteredProfiles returns all when no filter', () {
      expect(bloc.state.filteredProfiles.length, equals(3));
    });

    test('filteredProfiles filters by search query', () async {
      bloc.add(const RdpSearchChanged('alpha'));
      await pumpEventQueue();
      expect(bloc.state.filteredProfiles.length, equals(1));
      expect(bloc.state.filteredProfiles.first.name, equals('Alpha'));
    });

    test('search is case-insensitive', () async {
      bloc.add(const RdpSearchChanged('BETA'));
      await pumpEventQueue();
      expect(bloc.state.filteredProfiles.length, equals(1));
      expect(bloc.state.filteredProfiles.first.name, equals('Beta'));
    });

    test('filteredProfiles filters by group', () async {
      bloc.add(const RdpGroupFilterChanged('Staging'));
      await pumpEventQueue();
      expect(bloc.state.filteredProfiles.length, equals(1));
      expect(bloc.state.filteredProfiles.first.name, equals('Beta'));
    });

    test('groups list includes All and unique groups', () {
      final groups = bloc.state.groups;
      expect(groups, contains('All'));
      expect(groups, contains('RDP'));
      expect(groups, contains('Staging'));
    });

    test('empty search returns all profiles', () async {
      bloc.add(const RdpSearchChanged('alpha'));
      await pumpEventQueue();
      bloc.add(const RdpSearchChanged(''));
      await pumpEventQueue();
      expect(bloc.state.filteredProfiles.length, equals(3));
    });
  });

  // =========================================================
  // NAVIGATION
  // =========================================================

  group('RdpNavigationChanged', () {
    test('switches to form view', () async {
      bloc.add(const RdpNavigationChanged(RdpView.form));
      await pumpEventQueue();
      expect(bloc.state.activeView, equals(RdpView.form));
    });

    test('switches back to gallery view', () async {
      bloc.add(const RdpNavigationChanged(RdpView.form));
      await pumpEventQueue();
      bloc.add(const RdpNavigationChanged(RdpView.gallery));
      await pumpEventQueue();
      expect(bloc.state.activeView, equals(RdpView.gallery));
    });
  });

  // =========================================================
  // PROFILE EDIT REQUESTED
  // =========================================================

  group('RdpProfileEditRequested', () {
    setUp(() async {
      repo = _StubRdpProfileRepository([
        _makeProfile(id: 'edit-1', name: 'Edit Me'),
      ]);
      bloc = RdpWorkspaceBloc(repository: repo);
      bloc.add(const RdpProfilesRequested());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<RdpWorkspaceState>(
            (s) => s.status == RdpWorkspaceStatus.ready,
          ),
        ),
      );
    });

    test('sets editingProfile and switches to form view', () async {
      bloc.add(const RdpProfileEditRequested('edit-1'));
      await pumpEventQueue();
      expect(bloc.state.activeView, equals(RdpView.form));
      expect(bloc.state.editingProfile?.name, equals('Edit Me'));
    });

    test('ignores unknown profile id', () async {
      final prevState = bloc.state;
      bloc.add(const RdpProfileEditRequested('nonexistent'));
      await pumpEventQueue();
      expect(bloc.state.activeView, equals(prevState.activeView));
    });
  });
}
