/// Supplied at build time with --dart-define-from-file=.env.
const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
const supportContactLabel = supportEmail == ''
    ? 'Support contact not configured'
    : supportEmail;
