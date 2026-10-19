# THEME-PERF-10: ordered app palette fields (one jq process).
# Keep this order in sync with COLOR_VALUES in apply-gtk-theme.sh.
# Empty strings preserve the old jq `// empty` shell-variable semantics.
[
  (.app_background // .background // ""), # BG
  (.app_foreground // .on_background // ""), # FG
  (.app_accent // .primary // ""), # PRIMARY
  (.app_on_accent // .on_primary // ""), # ON_PRIMARY
  (.primary_container // ""), # PRIMARY_CONTAINER
  (.on_primary_container // ""), # ON_PRIMARY_CONTAINER
  (.app_view_bg // .surface // ""), # SURFACE
  (.app_foreground // .on_surface // ""), # ON_SURFACE
  (.app_surface_elevated // .surface_container // ""), # SURFACE_CONTAINER
  (.app_surface_popup // .surface_container_high // ""), # SURFACE_CONTAINER_HIGH
  (.app_surface // .surface_container_low // ""), # SURFACE_CONTAINER_LOW
  (.app_window_bg // .surface_dim // ""), # SURFACE_DIM
  (.app_border_subtle // .outline_variant // ""), # OUTLINE_VARIANT
  (.app_thumbnail_bg // .surface_container_highest // ""), # SURFACE_CONTAINER_HIGHEST
  (.app_headerbar_bg // ""), # APP_HEADERBAR_BG
  (.app_sidebar_bg // ""), # APP_SIDEBAR_BG
  (.app_card_bg // ""), # APP_CARD_BG
  (.app_popover_bg // ""), # APP_POPOVER_BG
  (.app_dialog_bg // ""), # APP_DIALOG_BG
  (.app_selection // ""), # APP_SELECTION
  (.app_selection_hover // ""), # APP_SELECTION_HOVER
  (.app_on_selection // ""), # APP_ON_SELECTION
  (.app_success // ""), # APP_SUCCESS
  (.app_warning // ""), # APP_WARNING
  (.app_error // ""), # APP_ERROR
  (.error // ""), # ERROR_COLOR
  (.tertiary // ""), # TERTIARY
  (.secondary // ""), # SECONDARY
  (.secondary_container // "") # SECONDARY_CONTAINER
] | .[]
