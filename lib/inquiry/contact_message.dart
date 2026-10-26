import 'dart:math';

const contactSupportEmail = 'setkeep.app@gmail.com';

String createContactCaseId({DateTime? now}) {
  final date = (now ?? DateTime.now()).toUtc();
  final day =
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
  final random = Random.secure();
  final token =
      '${random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}'
      '${random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0')}';
  return 'SKQ-$day-${token.toUpperCase()}';
}

Uri contactMailUri({required String subject, required String body}) => Uri(
  scheme: 'mailto',
  path: contactSupportEmail,
  // mailto requires percent-encoded spaces, rather than queryParameters' '+'.
  query:
      'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
);
