import 'dart:math';

import 'package:continuum_example/hybrid/dtos.dart';

/// Simulated backend API for hybrid-mode examples.
final class BackendApi {
  final Random _random = Random();

  Future<UserDto> createUser(CreateUserRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (request.email.contains('invalid')) {
      throw ApiValidationException('Email domain not allowed');
    }

    return UserDto(
      id: 'user-${_random.nextInt(10000)}',
      name: request.name,
      email: request.email,
      isActive: true,
    );
  }

  Future<UserDto> updateUser(String userId, UpdateUserRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_random.nextDouble() < 0.1) {
      throw ApiNetworkException('Connection timeout');
    }

    return UserDto(
      id: userId,
      name: request.name ?? 'Jane Doe',
      email: request.email ?? 'existing@example.com',
      isActive: true,
    );
  }
}
