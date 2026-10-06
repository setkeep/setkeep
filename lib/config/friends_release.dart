/// Friend comments remain closed for the first general-app release.
/// The implementation and stored data are retained for a later launch.
const friendCommentsPublicEnabled = bool.fromEnvironment(
  'SETKEEP_FRIEND_COMMENTS_PUBLIC',
  defaultValue: false,
);
