/// General-app TRAINER entry points remain closed until the public launch.
/// Linked records and background synchronization are deliberately unaffected.
const trainerPublicAccessEnabled = bool.fromEnvironment(
  'SETKEEP_TRAINER_PUBLIC',
  defaultValue: false,
);
