# Forgot Password Architecture

## Overview

Password reset via email using **Supabase Auth**. User receives a reset link, clicks it, sets new password on Supabase-hosted page.

---

## Flow

1. User taps "Forgot password?" on login screen
2. App validates email field is not empty
3. App calls `Supabase.instance.client.auth.resetPasswordForEmail(email)`
4. Supabase sends email with reset link
5. User sees: "Password reset link sent to {email}"
6. User clicks link in email → Supabase-hosted reset page
7. User sets new password
8. User logs in with new password

---

## Entry Points

### 1. Login Screen
**File:** `lib/screens/auth/account_entry_screen.dart`

- "Forgot password?" text button in sign-in mode
- Takes email from login form's email field
- Shows SnackBar with success/error

### 2. Lockout Overlay
**File:** `lib/widgets/lockout_overlay.dart`

- "Reset password" button shown when account is locked (5+ failed attempts)
- Uses the email that triggered the lockout
- Account remains locked until reset or 30-minute timer expires

---

## Code

### Service Layer
```dart
// lib/services/auth_service.dart
Future<void> resetPassword(String email) async {
  await _client.auth.resetPasswordForEmail(email.trim());
}
```

### Provider Layer
```dart
// lib/providers/auth_provider.dart
Future<bool> resetPassword(String email) async {
  try {
    await _db.resetPassword(email);
    return true;
  } catch (e) {
    _errorMessage = friendlyAuthErrorMessage(e);
    return false;
  }
}
```

### UI Layer
```dart
// lib/screens/auth/account_entry_screen.dart
Future<void> _forgotPassword() async {
  final email = _emailController.text.trim();
  if (email.isEmpty) {
    _showError('Please enter your email address first.');
    return;
  }
  
  final auth = Provider.of<AuthProvider>(context, listen: false);
  final success = await auth.resetPassword(email);
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success
          ? 'Password reset link sent to $email'
          : auth.errorMessage ?? 'Unable to send reset email.'),
      backgroundColor: success ? AppConstants.success : AppConstants.error,
    ),
  );
}
```

---

## Security

- **Email enumeration protection**: Same message for existing/non-existing emails
- **Rate limiting**: Supabase limits email sends (shows "Too many attempts" error)
- **Token security**: Managed by Supabase (cryptographic, one-time use, expires)
- **Lockout integration**: Accounts stay locked during reset process

---

## Error Messages

| Scenario | Message |
|----------|---------|
| Empty email field | "Please enter your email address first." |
| Success | "Password reset link sent to {email}" |
| Rate limited | "Too many attempts. Try again in about a minute." |
| Network error | "Unable to send reset email." |

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/screens/auth/account_entry_screen.dart` | Login screen with forgot password link |
| `lib/widgets/lockout_overlay.dart` | Lockout overlay with reset button |
| `lib/providers/auth_provider.dart` | `resetPassword()` method |
| `lib/services/auth_service.dart` | Supabase `resetPasswordForEmail()` call |
| `lib/utils/auth_error_messages.dart` | Error message mapping |

---

## Lockout Behavior

When account is locked (5+ failed attempts):
1. Lockout overlay appears with 30-minute countdown
2. "Reset password" is the primary action
3. Reset email is sent to locked email
4. Account **remains locked** until:
   - User successfully resets password, OR
   - 30-minute timer expires

---

## Supabase Configuration

- Reset token expiration: 3600 seconds (1 hour) - configurable in dashboard
- Email template: Managed by Supabase Auth
- Rate limiting: Enabled by default

---

## Summary

Simple flow: User taps "Forgot password?" → App calls `resetPasswordForEmail()` → Supabase sends email → User clicks link → Sets new password → Logs in. Security handled by Supabase (tokens, rate limiting) + app (email validation, error handling).
