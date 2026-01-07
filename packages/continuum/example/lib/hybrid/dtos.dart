final class CreateUserRequest {
  final String name;
  final String email;

  CreateUserRequest({required this.name, required this.email});

  Map<String, Object> toJson() {
    return <String, Object>{'name': name, 'email': email};
  }
}

final class UpdateUserRequest {
  final String? name;
  final String? email;

  UpdateUserRequest({this.name, this.email});

  Map<String, Object> toJson() {
    final Map<String, Object> result = <String, Object>{};
    if (name != null) {
      result['name'] = name!;
    }
    if (email != null) {
      result['email'] = email!;
    }
    return result;
  }
}

final class UserDto {
  final String id;
  final String name;
  final String email;
  final bool isActive;

  UserDto({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
  });
}

final class ApiValidationException implements Exception {
  final String message;

  ApiValidationException(this.message);

  @override
  String toString() {
    return message;
  }
}

final class ApiNetworkException implements Exception {
  final String message;

  ApiNetworkException(this.message);

  @override
  String toString() {
    return message;
  }
}
