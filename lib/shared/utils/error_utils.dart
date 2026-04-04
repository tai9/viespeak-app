import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

String friendlyError(Object e) {
  if (e is AuthApiException) {
    switch (e.code) {
      case 'invalid_credentials':
        return 'Incorrect email or password. Please try again.';
      case 'user_already_exists':
        return 'An account with this email already exists.';
      case 'weak_password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'validation_failed':
        return 'Please enter a valid email address.';
      default:
        return e.message;
    }
  }

  if (e is SocketException) {
    return 'No internet connection. Please check your network.';
  }

  if (e is HttpException) {
    return 'Could not reach the server. Please try again later.';
  }

  return 'Something went wrong. Please try again.';
}
