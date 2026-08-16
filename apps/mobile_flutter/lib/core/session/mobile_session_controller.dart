import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/backend_api_client.dart';
import '../database/mobile_repository.dart';
import '../models/mobile_auth_user.dart';
import '../models/mobile_models.dart';
import '../models/mobile_session.dart';
import '../runtime/mobile_runtime_config.dart';

const String _staffKey = 'staff_users';
const String _legacyPinKey = 'owner_pin_hash';

// Persisted JWT session (cloud auth mode), so a login survives app restarts.
const String _jwtAccessKey = 'jwt_access';
const String _jwtRefreshKey = 'jwt_refresh';
const String _jwtShopKey = 'jwt_shop_id';
const String _jwtRoleKey = 'jwt_role';
const String _jwtEmailKey = 'jwt_email';
const String _jwtMembershipKey = 'jwt_membership';
// The member's custom permission set (JSON), so the UI enforces it after a
// restart without another network fetch.
const String _jwtPermsKey = 'jwt_permissions';
// The last workspace this device was signed into. Used to detect a shop switch
// and wipe the previous tenant's cached data. Survives logout on purpose.
const String _activeShopKey = 'active_shop_id';

bool get _cloudAuthMode => MobileRuntimeConfig.backendAuthMode == 'jwt';

/// A local staff account: name + role + hashed PIN.
class StaffUser {
  const StaffUser({
    required this.id,
    required this.name,
    required this.role,
    required this.pinHash,
  });

  final String id;
  final String name;
  final String role; // owner | manager | staff
  final String pinHash;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'role': role,
    'pin': pinHash,
  };

  factory StaffUser.fromJson(Map<String, dynamic> j) => StaffUser(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    role: (j['role'] ?? 'staff').toString(),
    pinHash: (j['pin'] ?? '').toString(),
  );
}

class MobileSessionNotifier extends AsyncNotifier<MobileSession?> {
  String? _currentStaffId;

  @override
  Future<MobileSession?> build() async {
    // In cloud (JWT) mode, restore a persisted login so the user stays signed
    // in across restarts. The stored access token is reused directly; if it has
    // expired, the API client swaps the refresh token for a new pair on the
    // first 401 and repeats the call, so nobody is bounced to a login screen
    // in the middle of a sale.
    if (_cloudAuthMode) {
      final repo = ref.read(shopRepositoryProvider);
      final access = await repo.readSetting(_jwtAccessKey) ?? '';
      final shopId = await repo.readSetting(_jwtShopKey) ?? '';
      if (access.isNotEmpty && shopId.isNotEmpty) {
        final email = await repo.readSetting(_jwtEmailKey) ?? '';
        final role = await repo.readSetting(_jwtRoleKey) ?? 'owner';
        final membershipId = await repo.readSetting(_jwtMembershipKey) ?? '';
        final perms = _decodePerms(await repo.readSetting(_jwtPermsKey));
        return _sessionFromStored(
          access: access,
          email: email,
          shopId: shopId,
          role: role,
          membershipId: membershipId,
          customPermissions: perms,
        );
      }
    }
    return null;
  }

  /// Tenant isolation on the client: if this device was last signed into a
  /// DIFFERENT shop, wipe all locally-cached workspace data before the new
  /// session opens, so the new tenant never sees the previous one's records.
  /// Same-shop re-login keeps local (possibly-unsynced) data.
  Future<void> _wipeIfShopChanged(String newShopId) async {
    final repo = ref.read(shopRepositoryProvider);
    final active = await repo.readSetting(_activeShopKey) ?? '';
    if (active != newShopId) {
      await repo.clearAllWorkspaceData();
    }
    await repo.writeSetting(_activeShopKey, newShopId);
  }

  MobileSession _sessionFromStored({
    required String access,
    required String email,
    required String shopId,
    required String role,
    required String membershipId,
    Map<String, dynamic>? customPermissions,
  }) {
    final user = MobileAuthUser.cloud(
      uid: email,
      email: email,
      displayName: email,
      accessToken: access,
    );
    return MobileSession.authenticated(
      user: user,
      shopId: shopId,
      role: role,
      membershipId: membershipId,
      email: email,
      customPermissions: customPermissions,
    );
  }

  Map<String, dynamic> _decodePerms(String? raw) {
    if (raw == null || raw.isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  /// Register a new owner + shop, then sign in. Returns null on success or a
  /// user-facing error message. The register endpoint provisions the shop and
  /// returns tokens + shop, so no separate login or membership fetch is needed.
  Future<String?> cloudRegister({
    required String ownerName,
    required String email,
    required String password,
    required String businessName,
    String mobile = '',
    String businessType = 'retail',
    String stateCode = '',
    String gstin = '',
  }) async {
    final repo = ref.read(shopRepositoryProvider);
    final client = ref.read(backendApiClientProvider);
    final trimmedEmail = email.trim();
    try {
      state = const AsyncValue.loading();
      final result = await client.register(
        ownerName: ownerName.trim(),
        email: trimmedEmail,
        password: password,
        businessName: businessName.trim(),
        mobile: mobile.trim(),
        businessType: businessType,
        stateCode: stateCode.trim(),
        gstin: gstin.trim(),
      );
      final access = (result['access'] ?? '').toString();
      final shopId = (result['shop_id'] ?? '').toString();
      if (access.isEmpty || shopId.isEmpty) {
        state = const AsyncValue.data(null);
        return 'Registration failed - please try again.';
      }
      final role = (result['role'] ?? 'owner').toString();
      final shopName = (result['shop_name'] ?? businessName).toString();

      // A newly-registered shop is a different tenant: wipe any cached data.
      await _wipeIfShopChanged(shopId);
      await repo.writeSetting(_jwtAccessKey, access);
      await repo.writeSetting(_jwtRefreshKey, (result['refresh'] ?? '').toString());
      await repo.writeSetting(_jwtShopKey, shopId);
      await repo.writeSetting(_jwtRoleKey, role);
      await repo.writeSetting(_jwtEmailKey, trimmedEmail);
      await repo.writeSetting(_jwtMembershipKey, '');

      // Seed the local shop document for the fresh workspace.
      await repo.saveShopDocument(<String, dynamic>{
        'name': shopName,
        'tagline': 'Business Hub',
        'footer': 'Thank you for your business!',
        'currency': 'INR',
        'phone': mobile.trim(),
        'plan_tier': 'starter',
        'enabled_features': <String, bool>{
          'inventory': true,
          'pos': true,
          'customers': true,
          'history': true,
          'team': true,
          'attendance': true,
          'expenses': true,
          'advanced_ops': true,
        },
      });

      state = AsyncValue.data(
        _sessionFromStored(
          access: access,
          email: trimmedEmail,
          shopId: shopId,
          role: role,
          membershipId: '',
        ),
      );
      return null;
    } on BackendApiException catch (e) {
      state = const AsyncValue.data(null);
      return e.message;
    } catch (e) {
      state = const AsyncValue.data(null);
      return 'Registration failed. Check your connection and try again.';
    }
  }

  /// Accept a shop invitation with a code, creating/activating the account and
  /// signing into the shop. Returns null on success or an error message.
  Future<String?> cloudAcceptInvite({
    required String code,
    required String name,
    required String password,
  }) async {
    final repo = ref.read(shopRepositoryProvider);
    final client = ref.read(backendApiClientProvider);
    try {
      state = const AsyncValue.loading();
      final result = await client.acceptInvite(
        token: code.trim(),
        name: name.trim(),
        password: password,
      );
      final access = (result['access'] ?? '').toString();
      final shopId = (result['shop_id'] ?? '').toString();
      if (access.isEmpty || shopId.isEmpty) {
        state = const AsyncValue.data(null);
        return 'Could not join - please try again.';
      }
      final role = (result['role'] ?? 'staff').toString();
      final email = (result['email'] ?? '').toString();
      final shopName = (result['shop_name'] ?? 'Your shop').toString();

      // Joining a shop is a (potentially different) tenant: wipe cached data.
      await _wipeIfShopChanged(shopId);
      await repo.writeSetting(_jwtAccessKey, access);
      await repo.writeSetting(_jwtRefreshKey, (result['refresh'] ?? '').toString());
      await repo.writeSetting(_jwtShopKey, shopId);
      await repo.writeSetting(_jwtRoleKey, role);
      await repo.writeSetting(_jwtEmailKey, email);
      await repo.writeSetting(_jwtMembershipKey, '');

      final existing = await repo.readSetting('settings');
      if (existing == null || existing.isEmpty) {
        await repo.saveShopDocument(<String, dynamic>{
          'name': shopName,
          'tagline': 'Business Hub',
          'footer': 'Thank you for your business!',
          'currency': 'INR',
          'phone': '',
          'plan_tier': 'starter',
          'enabled_features': <String, bool>{
            'inventory': true,
            'pos': true,
            'customers': true,
            'history': true,
            'team': true,
            'attendance': true,
            'expenses': true,
            'advanced_ops': true,
          },
        });
      }

      state = AsyncValue.data(
        _sessionFromStored(
          access: access,
          email: email,
          shopId: shopId,
          role: role,
          membershipId: '',
        ),
      );
      return null;
    } on BackendApiException catch (e) {
      state = const AsyncValue.data(null);
      return e.message;
    } catch (e) {
      state = const AsyncValue.data(null);
      return 'Could not join. Check the code and your connection.';
    }
  }

  /// Sign in against the backend with email + password (JWT). Returns null on
  /// success, or a user-facing error message. Resolves the caller's shop from
  /// their membership so sync targets the real backend workspace.
  Future<String?> cloudLogin(String email, String password) async {
    final repo = ref.read(shopRepositoryProvider);
    final client = ref.read(backendApiClientProvider);
    final trimmedEmail = email.trim();
    try {
      state = const AsyncValue.loading();
      final tokens = await client.obtainToken(
        email: trimmedEmail,
        password: password,
      );
      final access = tokens['access'] ?? '';
      if (access.isEmpty) {
        state = const AsyncValue.data(null);
        return 'Sign-in failed - no token returned.';
      }
      final tempUser = MobileAuthUser.cloud(
        uid: trimmedEmail,
        email: trimmedEmail,
        displayName: trimmedEmail,
        accessToken: access,
      );
      final memberships = await client.getShopMemberships(user: tempUser);
      final active = memberships.where((m) => m.status == 'active').toList();
      if (active.isEmpty) {
        state = const AsyncValue.data(null);
        return 'This account has no active shop yet.';
      }
      // Prefer the last-selected shop if the user still belongs to it, so a
      // multi-shop user returns to where they were.
      final remembered = await repo.readSetting(_activeShopKey) ?? '';
      final rememberedMatches =
          active.where((x) => x.shopId == remembered).toList();
      final m = rememberedMatches.isNotEmpty ? rememberedMatches.first : active.first;

      // Signing into this shop: if it differs from the last active shop on
      // this device, wipe the previous tenant's cached data first.
      await _wipeIfShopChanged(m.shopId);
      await repo.writeSetting(_jwtAccessKey, access);
      await repo.writeSetting(_jwtRefreshKey, tokens['refresh'] ?? '');
      await repo.writeSetting(_jwtShopKey, m.shopId);
      await repo.writeSetting(_jwtRoleKey, m.role);
      await repo.writeSetting(_jwtEmailKey, trimmedEmail);
      await repo.writeSetting(_jwtMembershipKey, m.id);
      await repo.writeSetting(_jwtPermsKey, jsonEncode(m.permissions));

      // Seed the local shop document from the backend shop, once.
      final existing = await repo.readSetting('settings');
      if (existing == null || existing.isEmpty) {
        await repo.saveShopDocument(<String, dynamic>{
          'name': m.shopName,
          'tagline': 'Business Hub',
          'footer': 'Thank you for your business!',
          'currency': m.shopCurrencyCode,
          'phone': m.shopPhone,
          'plan_tier': m.shopPlanTier,
          'enabled_features': m.shopEnabledFeatures,
        });
      }

      state = AsyncValue.data(
        _sessionFromStored(
          access: access,
          email: trimmedEmail,
          shopId: m.shopId,
          role: m.role,
          membershipId: m.id,
          customPermissions: m.permissions,
        ),
      );
      return null;
    } on BackendApiException catch (e) {
      state = const AsyncValue.data(null);
      return e.message;
    } catch (e) {
      state = const AsyncValue.data(null);
      return 'Sign-in failed. Check your connection and try again.';
    }
  }

  String _hash(String pin) =>
      sha256.convert(utf8.encode('business-hub:$pin')).toString();

  Future<List<StaffUser>> _loadStaff() async {
    final repo = ref.read(shopRepositoryProvider);
    final raw = await repo.readSetting(_staffKey);
    if (raw == null || raw.isEmpty) {
      // Migrate a legacy single-owner PIN into the staff store.
      final legacy = await repo.readSetting(_legacyPinKey);
      if (legacy != null && legacy.isNotEmpty) {
        final owner = StaffUser(
          id: 'owner',
          name: 'Owner',
          role: 'owner',
          pinHash: legacy,
        );
        await _saveStaff(<StaffUser>[owner]);
        return <StaffUser>[owner];
      }
      return const <StaffUser>[];
    }
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => StaffUser.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const <StaffUser>[];
    }
  }

  Future<void> _saveStaff(List<StaffUser> staff) async {
    await ref
        .read(shopRepositoryProvider)
        .writeSetting(
          _staffKey,
          jsonEncode(staff.map((s) => s.toJson()).toList()),
        );
  }

  /// Whether any staff account exists (first-run vs returning).
  Future<bool> hasPin() async => (await _loadStaff()).isNotEmpty;

  Future<List<StaffUser>> listStaff() => _loadStaff();

  /// Resolve the PIN to a staff member and unlock. First PIN on a fresh
  /// install becomes the owner. Returns false for an unknown PIN.
  Future<bool> login(String pin) async {
    final repo = ref.read(shopRepositoryProvider);
    final staff = await _loadStaff();
    final hashed = _hash(pin);

    StaffUser? user;
    if (staff.isEmpty) {
      user = StaffUser(id: 'owner', name: 'Owner', role: 'owner', pinHash: hashed);
      await _saveStaff(<StaffUser>[user]);
    } else {
      for (final s in staff) {
        if (s.pinHash == hashed) {
          user = s;
          break;
        }
      }
      if (user == null) return false;
    }

    state = const AsyncValue.loading();
    _currentStaffId = user.id;

    // Seed the shop document only once, so signing out never wipes edits.
    final existing = await repo.readSetting('settings');
    if (existing == null || existing.isEmpty) {
      await repo.saveShopDocument(<String, dynamic>{
        'name': MobileRuntimeConfig.localShopName,
        'tagline': 'Business Hub',
        'footer': 'Thank you for your business!',
        'currency': 'INR',
        'phone': '',
        'plan_tier': 'growth',
        'enabled_features': <String, bool>{
          'inventory': true,
          'pos': true,
          'customers': true,
          'history': true,
          'team': true,
          'attendance': true,
          'expenses': true,
          'advanced_ops': true,
        },
      });
    }

    state = AsyncValue.data(
      MobileSession.localUser(
        staffId: user.id,
        name: user.name,
        role: user.role,
      ),
    );
    return true;
  }

  /// Change the currently signed-in user's PIN.
  /// Whether the signed-in staff member has a till PIN at all.
  ///
  /// Without this the UI asked for a "current PIN" that never existed, so
  /// anyone who had not set one could never set one — the dialog rejected
  /// every value including the correct (empty) one.
  Future<bool> hasStaffPin() async {
    final staff = await _loadStaff();
    final id = _currentStaffId ?? 'owner';
    final idx = staff.indexWhere((s) => s.id == id);
    return idx >= 0 && staff[idx].pinHash.trim().isNotEmpty;
  }

  Future<bool> changePin(String currentPin, String newPin) async {
    final staff = await _loadStaff();
    final id = _currentStaffId ?? 'owner';
    final idx = staff.indexWhere((s) => s.id == id);
    if (idx < 0) return false;
    // First-time set: there is nothing to verify against.
    final existing = staff[idx].pinHash.trim();
    if (existing.isNotEmpty && existing != _hash(currentPin)) return false;
    staff[idx] = StaffUser(
      id: staff[idx].id,
      name: staff[idx].name,
      role: staff[idx].role,
      pinHash: _hash(newPin),
    );
    await _saveStaff(staff);
    return true;
  }

  /// Add a staff member. Returns an error message, or null on success.
  Future<String?> addStaff({
    required String name,
    required String role,
    required String pin,
  }) async {
    if (pin.trim().length < 4) return 'PIN must be 4 digits.';
    final staff = await _loadStaff();
    final hashed = _hash(pin);
    if (staff.any((s) => s.pinHash == hashed)) {
      return 'That PIN is already used by another staff member.';
    }
    staff.add(
      StaffUser(
        id: 'staff-${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim().isEmpty ? 'Staff' : name.trim(),
        role: role,
        pinHash: hashed,
      ),
    );
    await _saveStaff(staff);
    return null;
  }

  Future<void> updateStaffRole(String id, String role) async {
    final staff = await _loadStaff();
    final idx = staff.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    staff[idx] = StaffUser(
      id: staff[idx].id,
      name: staff[idx].name,
      role: role,
      pinHash: staff[idx].pinHash,
    );
    await _saveStaff(staff);
  }

  Future<void> removeStaff(String id) async {
    final staff = await _loadStaff();
    staff.removeWhere((s) => s.id == id);
    await _saveStaff(staff);
  }

  /// Switch the active shop for a user who belongs to several, without logging
  /// out. Same JWT authorizes all their shops. Wipes the previous shop's local
  /// cache (isolation), loads the new shop's role + permissions, and remembers
  /// the choice. Returns null on success or an error message.
  Future<String?> switchShop(String shopId) async {
    final session = state.asData?.value;
    if (session == null) return 'You are not signed in.';
    final client = ref.read(backendApiClientProvider);
    final repo = ref.read(shopRepositoryProvider);
    try {
      final memberships = await client.getShopMemberships(user: session.user);
      final matches = memberships
          .where((m) => m.shopId == shopId && m.status == 'active')
          .toList();
      if (matches.isEmpty) {
        return 'You are not an active member of that shop.';
      }
      final m = matches.first;
      if (m.shopId == (session.shopId ?? '')) return null; // already here

      state = const AsyncValue.loading();
      await _wipeIfShopChanged(m.shopId); // clears the previous shop's cache
      await repo.writeSetting(_jwtShopKey, m.shopId);
      await repo.writeSetting(_jwtRoleKey, m.role);
      await repo.writeSetting(_jwtMembershipKey, m.id);
      await repo.writeSetting(_jwtPermsKey, jsonEncode(m.permissions));
      await _seedShopDocFromMembership(repo, m);

      state = AsyncValue.data(
        _sessionFromStored(
          access: session.user.authToken ?? '',
          email: session.email,
          shopId: m.shopId,
          role: m.role,
          membershipId: m.id,
          customPermissions: m.permissions,
        ),
      );
      return null;
    } catch (e) {
      // restore the previous session on failure
      state = AsyncValue.data(session);
      return 'Could not switch shop. Check your connection.';
    }
  }

  Future<void> _seedShopDocFromMembership(
    ShopRepository repo,
    ShopMembershipAccessRecord m,
  ) async {
    await repo.saveShopDocument(<String, dynamic>{
      'name': m.shopName,
      'tagline': 'Business Hub',
      'footer': 'Thank you for your business!',
      'currency': m.shopCurrencyCode,
      'phone': m.shopPhone,
      'plan_tier': m.shopPlanTier,
      'enabled_features': m.shopEnabledFeatures.isNotEmpty
          ? m.shopEnabledFeatures
          : <String, bool>{
              'inventory': true,
              'pos': true,
              'customers': true,
              'history': true,
              'team': true,
              'attendance': true,
              'expenses': true,
              'advanced_ops': true,
            },
    });
  }

  /// Re-fetch this member's role + custom permissions from the backend and
  /// apply them to the live session, so an admin's permission change takes
  /// effect without the member logging in again. Best-effort; safe to call on
  /// app resume. Does nothing outside cloud mode.
  Future<void> refreshPermissions() async {
    if (!_cloudAuthMode) return;
    final session = state.asData?.value;
    if (session == null || (session.shopId ?? '').isEmpty) return;
    final client = ref.read(backendApiClientProvider);
    final repo = ref.read(shopRepositoryProvider);
    try {
      final memberships = await client.getShopMemberships(user: session.user);
      final matches =
          memberships.where((x) => x.shopId == session.shopId).toList();
      if (matches.isEmpty) return;
      final m = matches.first;
      await repo.writeSetting(_jwtRoleKey, m.role);
      await repo.writeSetting(_jwtPermsKey, jsonEncode(m.permissions));
      state = AsyncValue.data(
        _sessionFromStored(
          access: session.user.authToken ?? '',
          email: session.email,
          shopId: session.shopId!,
          role: m.role,
          membershipId: m.id,
          customPermissions: m.permissions,
        ),
      );
    } catch (_) {
      // best effort - keep the current session on any failure
    }
  }

  /// Send a shop invitation to a teammate (owner/manager). Requires an active
  /// cloud session. Returns (error, code): on success error is null and code is
  /// the invite code (also emailed to the invitee); on failure code is null.
  Future<({String? error, String? code, bool emailSent, String emailError})>
      sendInvite({
    required String email,
    required String role,
  }) async {
    final session = state.asData?.value;
    if (session == null || (session.shopId ?? '').isEmpty) {
      return (
        error: 'You need to be signed in to a shop to invite people.',
        code: null,
        emailSent: false,
        emailError: '',
      );
    }
    final client = ref.read(backendApiClientProvider);
    try {
      final result = await client.createInvite(
        user: session.user,
        shopId: session.shopId!,
        email: email.trim(),
        role: role,
      );
      return (
        error: null,
        code: (result['invite_code'] ?? '').toString(),
        emailSent: result['email_sent'] == true,
        emailError: (result['email_error'] ?? '').toString(),
      );
    } on BackendApiException catch (e) {
      return (error: e.message, code: null, emailSent: false, emailError: '');
    } catch (e) {
      return (
        error: 'Could not send the invite. Please try again.',
        code: null,
        emailSent: false,
        emailError: '',
      );
    }
  }

  Future<void> logout() async {
    // Clear the in-memory session FIRST and synchronously, so the UI reacts to
    // a signed-out state immediately (a single click). Persisted tokens are
    // then wiped in the background - the live session is already gone.
    _currentStaffId = null;
    state = const AsyncValue.data(null);
    if (_cloudAuthMode) {
      final repo = ref.read(shopRepositoryProvider);
      for (final key in <String>[
        _jwtAccessKey,
        _jwtRefreshKey,
        _jwtShopKey,
        _jwtRoleKey,
        _jwtEmailKey,
        _jwtMembershipKey,
      ]) {
        await repo.writeSetting(key, '');
      }
    }
  }
}

final mobileSessionProvider =
    AsyncNotifierProvider<MobileSessionNotifier, MobileSession?>(() {
      return MobileSessionNotifier();
    });
