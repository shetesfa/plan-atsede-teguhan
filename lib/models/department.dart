import 'package:flutter/material.dart';

class Department {
  final String id;
  final String name;
  final String shortName;
  final IconData icon;
  final Color color;
  final bool isSuperAdmin;

  const Department({
    required this.id,
    required this.name,
    required this.shortName,
    required this.icon,
    required this.color,
    this.isSuperAdmin = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Department && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  static const List<Department> allDepartments = [
    Department(
      id: 'admin',
      name: 'ጽ/ቤት',
      shortName: 'ጽ/ቤት',
      icon: Icons.account_balance,
      color: Color(0xFF7A1315),
      isSuperAdmin: true,
    ),
    Department(
      id: 'mezmur',
      name: 'መዝሙርና ስነጥበብ ክፍል',
      shortName: 'መዝሙር',
      icon: Icons.music_note,
      color: Color(0xFF8E24AA),
    ),
    Department(
      id: 'education',
      name: 'ትምህርት እና ስልጠና ክፍል',
      shortName: 'ትምህርት',
      icon: Icons.school,
      color: Color(0xFF1E88E5),
    ),
    Department(
      id: 'program',
      name: 'መርሃግብር እና ጉባኤያት ክፍል',
      shortName: 'መርሃግብር',
      icon: Icons.event,
      color: Color(0xFF00897B),
    ),
    Department(
      id: 'pr',
      name: 'መረጃና የውስጥ ግንኙነት ክፍል',
      shortName: 'መረጃ',
      icon: Icons.campaign,
      color: Color(0xFFD81B60),
    ),
    Department(
      id: 'members',
      name: 'አባላት አስተዳደር ክፍል',
      shortName: 'አባላት',
      icon: Icons.groups,
      color: Color(0xFF3949AB),
    ),
    Department(
      id: 'audit',
      name: 'ቁጥጥር ክፍል',
      shortName: 'ቁጥጥር',
      icon: Icons.fact_check,
      color: Color(0xFFE53935),
    ),
    Department(
      id: 'development',
      name: 'ልማትና በጎ አድራጎት ክፍል',
      shortName: 'ልማት',
      icon: Icons.volunteer_activism,
      color: Color(0xFF43A047),
    ),
    Department(
      id: 'finance',
      name: 'በጀት እና ንብረት አስተዳደር ክፍል',
      shortName: 'በጀት',
      icon: Icons.account_balance_wallet,
      color: Color(0xFFF4511E),
    ),
    Department(
      id: 'hr',
      name: 'ሰው ሀብት አስተዳደር ክፍል',
      shortName: 'ሰው ሀብት',
      icon: Icons.badge,
      color: Color(0xFF546E7A),
    ),
  ];
}
