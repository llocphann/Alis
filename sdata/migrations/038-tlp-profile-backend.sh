# Retained migration identity; this integration is now optional in AlisIntergration.
# Never install helpers, enable services, mask providers or change profiles
# when installing/updating the core shell.
MIGRATION_ID="038-tlp-profile-backend"
MIGRATION_TITLE="Optional Alis-Intergration TLP profile backend"
MIGRATION_DESCRIPTION="Managed separately by the optional Alis-Intergration package."
MIGRATION_REQUIRED=false
migration_check() { return 1; }
migration_preview() { printf '%s\n' 'Install and configure Alis-Intergration separately to use this integration.'; }
migration_apply() { return 0; }
