#!/usr/bin/env python3
"""Regression contract for the v1.0 Material-only global style boundary."""

from pathlib import Path
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
APPEARANCE = ROOT / "modules" / "common" / "Appearance.qml"
THEME_SERVICE = ROOT / "services" / "ThemeService.qml"
STYLED_POPUP = ROOT / "modules" / "bar" / "StyledPopup.qml"
BAR = ROOT / "modules" / "bar" / "Bar.qml"
VERTICAL_BAR = ROOT / "modules" / "verticalBar" / "VerticalBar.qml"
WEATHER_BAR = ROOT / "modules" / "bar" / "weather" / "WeatherBar.qml"
BAR_MEDIA_POPUP = ROOT / "modules" / "mediaControls" / "BarMediaPopup.qml"
PLAYER_CONTROL = ROOT / "modules" / "mediaControls" / "PlayerControl.qml"
BATTERY_INDICATOR = ROOT / "modules" / "bar" / "BatteryIndicator.qml"
CLOCK_WIDGET = ROOT / "modules" / "bar" / "ClockWidget.qml"
NOTIFICATION_UNREAD_COUNT = ROOT / "modules" / "bar" / "NotificationUnreadCount.qml"
ACTIVE_WINDOW = ROOT / "modules" / "bar" / "ActiveWindow.qml"
RESOURCE = ROOT / "modules" / "bar" / "Resource.qml"
CLIPPED_PROGRESS_BAR = ROOT / "modules" / "common" / "widgets" / "ClippedProgressBar.qml"
STYLED_PROGRESS_BAR = ROOT / "modules" / "common" / "widgets" / "StyledProgressBar.qml"
MATERIAL_SYMBOL = ROOT / "modules" / "common" / "widgets" / "MaterialSymbol.qml"
TOOLBAR_TEXT_FIELD = ROOT / "modules" / "common" / "widgets" / "ToolbarTextField.qml"
TOOLBAR_TAB_BUTTON = ROOT / "modules" / "common" / "widgets" / "ToolbarTabButton.qml"
TOOLBAR_TAB_BAR = ROOT / "modules" / "common" / "widgets" / "ToolbarTabBar.qml"
MATERIAL_TEXT_AREA = ROOT / "modules" / "common" / "widgets" / "MaterialTextArea.qml"
STYLED_DROP_SHADOW = ROOT / "modules" / "common" / "widgets" / "StyledDropShadow.qml"
CIRCULAR_PROGRESS = ROOT / "modules" / "common" / "widgets" / "CircularProgress.qml"
SECONDARY_TAB_BAR = ROOT / "modules" / "common" / "widgets" / "SecondaryTabBar.qml"
SCROLL_TO_BOTTOM_BUTTON = ROOT / "modules" / "sidebarLeft" / "ScrollToBottomButton.qml"
PAGE_PLACEHOLDER = ROOT / "modules" / "common" / "widgets" / "PagePlaceholder.qml"
SELECTION_DIALOG = ROOT / "modules" / "common" / "widgets" / "SelectionDialog.qml"
TOAST_NOTIFICATION = ROOT / "modules" / "common" / "widgets" / "ToastNotification.qml"
WINDOW_DIALOG = ROOT / "modules" / "common" / "widgets" / "WindowDialog.qml"
CHEATSHEET_KEYBIND_ROW = ROOT / "modules" / "cheatsheet" / "CheatsheetKeybindRow.qml"
STATUS_RINGS = ROOT / "modules" / "sidebarLeft" / "widgets" / "StatusRings.qml"
QUICK_LAUNCH = ROOT / "modules" / "sidebarLeft" / "widgets" / "QuickLaunch.qml"
EVENT_CARD = ROOT / "modules" / "sidebarRight" / "events" / "EventCard.qml"
SYSMON_WIDGET = ROOT / "modules" / "sidebarRight" / "sysmon" / "SysMonWidget.qml"
STOPWATCH = ROOT / "modules" / "sidebarRight" / "pomodoro" / "Stopwatch.qml"
CENTER_WIDGET_GROUP = ROOT / "modules" / "sidebarRight" / "CenterWidgetGroup.qml"
WEB_APP_VIEW = ROOT / "modules" / "sidebarLeft" / "plugins" / "WebAppView.qml"
PLUGINS_TAB = ROOT / "modules" / "sidebarLeft" / "plugins" / "PluginsTab.qml"
ANIME = ROOT / "modules" / "sidebarLeft" / "Anime.qml"
BOORU_RESPONSE = ROOT / "modules" / "sidebarLeft" / "anime" / "BooruResponse.qml"
STYLED_OVERLAY_WIDGET = ROOT / "modules" / "ii" / "overlay" / "StyledOverlayWidget.qml"
FILTER_CHIP = ROOT / "modules" / "common" / "widgets" / "FilterChip.qml"
GROUP_BUTTON = ROOT / "modules" / "common" / "widgets" / "GroupButton.qml"
NAVIGATION_RAIL_BUTTON = ROOT / "modules" / "common" / "widgets" / "NavigationRailButton.qml"
INPUT_CHIP = ROOT / "modules" / "common" / "widgets" / "InputChip.qml"
SELECTION_GROUP_BUTTON = ROOT / "modules" / "common" / "widgets" / "SelectionGroupButton.qml"
MATERIAL_PLACEHOLDER_MESSAGE = ROOT / "modules" / "common" / "widgets" / "MaterialPlaceholderMessage.qml"
NOTIFICATION_ITEM = ROOT / "modules" / "common" / "widgets" / "NotificationItem.qml"
NOTIFICATION_GROUP = ROOT / "modules" / "common" / "widgets" / "NotificationGroup.qml"
NOTIFICATION_ACTION_BUTTON = ROOT / "modules" / "common" / "widgets" / "NotificationActionButton.qml"
NOTIFICATION_GROUP_EXPAND_BUTTON = ROOT / "modules" / "common" / "widgets" / "NotificationGroupExpandButton.qml"
NOTIFICATION_APP_ICON = ROOT / "modules" / "common" / "widgets" / "NotificationAppIcon.qml"
CONTENT_SUBSECTION_LABEL = ROOT / "modules" / "common" / "widgets" / "ContentSubsectionLabel.qml"
KEYBOARD_FOCUS_RING = ROOT / "modules" / "common" / "widgets" / "KeyboardFocusRing.qml"
KEYBOARD_KEY = ROOT / "modules" / "common" / "widgets" / "KeyboardKey.qml"
MATERIAL_SHAPE_SYMBOL = ROOT / "modules" / "common" / "widgets" / "MaterialShapeWrappedMaterialSymbol.qml"
FLOATING_ACTION_BUTTON = ROOT / "modules" / "common" / "widgets" / "FloatingActionButton.qml"
DATE_PICKER = ROOT / "modules" / "common" / "widgets" / "DatePicker.qml"
DIALOG_BUTTON = ROOT / "modules" / "common" / "widgets" / "DialogButton.qml"
DIALOG_LIST_ITEM = ROOT / "modules" / "common" / "widgets" / "DialogListItem.qml"
ICON_TOOLBAR_BUTTON = ROOT / "modules" / "common" / "widgets" / "IconToolbarButton.qml"
COLLAPSIBLE_SECTION = ROOT / "modules" / "common" / "widgets" / "CollapsibleSection.qml"
CONTENT_SECTION = ROOT / "modules" / "common" / "widgets" / "ContentSection.qml"
MATERIAL_TEXT_FIELD = ROOT / "modules" / "common" / "widgets" / "MaterialTextField.qml"
STYLED_TEXT_AREA = ROOT / "modules" / "common" / "widgets" / "StyledTextArea.qml"
TOOLBAR_BUTTON = ROOT / "modules" / "common" / "widgets" / "ToolbarButton.qml"
NOTICE_BOX = ROOT / "modules" / "common" / "widgets" / "NoticeBox.qml"
RIPPLE_BUTTON_WITH_ICON = ROOT / "modules" / "common" / "widgets" / "RippleButtonWithIcon.qml"
STYLED_TOOLTIP_CONTENT = ROOT / "modules" / "common" / "widgets" / "StyledToolTipContent.qml"
TOOLBAR = ROOT / "modules" / "common" / "widgets" / "Toolbar.qml"
TIMER_INDICATOR = ROOT / "modules" / "bar" / "TimerIndicator.qml"
SHELL_UPDATE_INDICATOR = ROOT / "modules" / "bar" / "ShellUpdateIndicator.qml"
UTIL_BUTTONS = ROOT / "modules" / "bar" / "UtilButtons.qml"
LEFT_SIDEBAR_BUTTON = ROOT / "modules" / "bar" / "LeftSidebarButton.qml"
BAR_CONTENT = ROOT / "modules" / "bar" / "BarContent.qml"
BAR_GROUP = ROOT / "modules" / "bar" / "BarGroup.qml"
CIRCLE_UTIL_BUTTON = ROOT / "modules" / "bar" / "CircleUtilButton.qml"
SCROLL_HINT = ROOT / "modules" / "bar" / "ScrollHint.qml"
BAR_TASKBAR_BUTTON = ROOT / "modules" / "bar" / "BarTaskbarButton.qml"
BAR_TASKBAR_WINDOW_PREVIEW = ROOT / "modules" / "bar" / "BarTaskbarWindowPreview.qml"
WORKSPACES = ROOT / "modules" / "bar" / "Workspaces.qml"
SYS_TRAY = ROOT / "modules" / "bar" / "SysTray.qml"
SYS_TRAY_MENU = ROOT / "modules" / "bar" / "SysTrayMenu.qml"
CONTEXT_MENU = ROOT / "modules" / "common" / "widgets" / "ContextMenu.qml"
GLASS_BACKGROUND = ROOT / "modules" / "common" / "widgets" / "GlassBackground.qml"
STYLED_RADIO_BUTTON = ROOT / "modules" / "common" / "widgets" / "StyledRadioButton.qml"
RIPPLE_BUTTON = ROOT / "modules" / "common" / "widgets" / "RippleButton.qml"
STYLED_RECTANGULAR_SHADOW = ROOT / "modules" / "common" / "widgets" / "StyledRectangularShadow.qml"
STYLED_COMBO_BOX = ROOT / "modules" / "common" / "widgets" / "StyledComboBox.qml"
FONT_SELECTOR = ROOT / "modules" / "common" / "widgets" / "FontSelector.qml"
ICON_THEME_SELECTOR = ROOT / "modules" / "common" / "widgets" / "IconThemeSelector.qml"
CONFIG_SELECTION_ARRAY = ROOT / "modules" / "common" / "widgets" / "ConfigSelectionArray.qml"
CONFIG_SPIN_BOX = ROOT / "modules" / "common" / "widgets" / "ConfigSpinBox.qml"
CONFIG_SWITCH = ROOT / "modules" / "common" / "widgets" / "ConfigSwitch.qml"
STYLED_SPIN_BOX = ROOT / "modules" / "common" / "widgets" / "StyledSpinBox.qml"
SETTINGS_SWITCH = ROOT / "modules" / "common" / "widgets" / "SettingsSwitch.qml"
SETTINGS_NOTE = ROOT / "modules" / "common" / "widgets" / "SettingsNote.qml"
SETTINGS_CARD_SECTION = ROOT / "modules" / "common" / "widgets" / "SettingsCardSection.qml"
SETTINGS_GROUP = ROOT / "modules" / "common" / "widgets" / "SettingsGroup.qml"
STYLED_TEXT_INPUT = ROOT / "modules" / "common" / "widgets" / "StyledTextInput.qml"
STYLED_SLIDER = ROOT / "modules" / "common" / "widgets" / "StyledSlider.qml"
SETTINGS_OVERLAY = ROOT / "modules" / "settings" / "SettingsOverlay.qml"
SETTINGS_LIVE_SEARCH_RESULTS = ROOT / "modules" / "common" / "widgets" / "SettingsLiveSearchResults.qml"
SETTINGS_WINDOW = ROOT / "settings.qml"
CONTROL_PANEL_DATE_TIME = ROOT / "modules" / "controlPanel" / "DateTimeHeader.qml"
CONTROL_PANEL_WALLPAPER = ROOT / "modules" / "controlPanel" / "WallpaperSection.qml"
CONTROL_PANEL_WEATHER = ROOT / "modules" / "controlPanel" / "WeatherSection.qml"
CONTROL_PANEL_SLIDERS = ROOT / "modules" / "controlPanel" / "SlidersSection.qml"
CONTROL_PANEL_SYSTEM = ROOT / "modules" / "controlPanel" / "SystemSection.qml"
CONTROL_PANEL_PROFILE = ROOT / "modules" / "controlPanel" / "ProfileHeader.qml"
CONTROL_PANEL_QUICK_ACTIONS = ROOT / "modules" / "controlPanel" / "QuickActionsSection.qml"
CONTROL_PANEL_MEDIA = ROOT / "modules" / "controlPanel" / "MediaSection.qml"
CONTROL_PANEL_CONTENT = ROOT / "modules" / "controlPanel" / "ControlPanelContent.qml"
ON_SCREEN_KEYBOARD = ROOT / "modules" / "onScreenKeyboard" / "OnScreenKeyboard.qml"
OSK_KEY = ROOT / "modules" / "onScreenKeyboard" / "OskKey.qml"
SCREEN_CORNERS = ROOT / "modules" / "screenCorners" / "ScreenCorners.qml"
SIDEBAR_LEFT_CONTENT = ROOT / "modules" / "sidebarLeft" / "SidebarLeftContent.qml"
SIDEBAR_RIGHT_CONTENT = ROOT / "modules" / "sidebarRight" / "SidebarRightContent.qml"
COMPACT_SIDEBAR_RIGHT_CONTENT = ROOT / "modules" / "sidebarRight" / "CompactSidebarRightContent.qml"
VERTICAL_BAR_CONTENT = ROOT / "modules" / "verticalBar" / "VerticalBarContent.qml"
VERTICAL_CLOCK_WIDGET = ROOT / "modules" / "verticalBar" / "VerticalClockWidget.qml"
VERTICAL_DATE_WIDGET = ROOT / "modules" / "verticalBar" / "VerticalDateWidget.qml"
OVERVIEW_SEARCH_BAR = ROOT / "modules" / "overview" / "SearchBar.qml"
OVERVIEW_SEARCH_ITEM = ROOT / "modules" / "overview" / "SearchItem.qml"
OVERVIEW_SEARCH_WIDGET = ROOT / "modules" / "overview" / "SearchWidget.qml"
OVERVIEW_ACTION_MODE_VIEW = ROOT / "modules" / "overview" / "ActionModeView.qml"
OVERVIEW_ALL_APPS_GRID = ROOT / "modules" / "overview" / "OverviewAllAppsGrid.qml"
OVERVIEW_DASHBOARD = ROOT / "modules" / "overview" / "OverviewDashboard.qml"
DASHBOARD_CONTENT = ROOT / "modules" / "dashboard" / "DashboardContent.qml"
OVERVIEW_NIRI_WIDGET = ROOT / "modules" / "overview" / "OverviewNiriWidget.qml"
OVERVIEW_WIDGET = ROOT / "modules" / "overview" / "OverviewWidget.qml"
WELCOME = ROOT / "welcome.qml"


def require(text: str, token: str, source: str) -> None:
    if token not in text:
        raise AssertionError(
            f"{source} is missing required Material-only contract token: {token!r}"
        )


def forbid(text: str, token: str, source: str) -> None:
    if token in text:
        raise AssertionError(
            f"{source} still contains retired global-style routing: {token!r}"
        )


def main() -> None:
    appearance = APPEARANCE.read_text(encoding="utf-8")
    theme_service = THEME_SERVICE.read_text(encoding="utf-8")
    styled_popup = STYLED_POPUP.read_text(encoding="utf-8")
    bar = BAR.read_text(encoding="utf-8")
    vertical_bar = VERTICAL_BAR.read_text(encoding="utf-8")
    weather_bar = WEATHER_BAR.read_text(encoding="utf-8")
    bar_media_popup = BAR_MEDIA_POPUP.read_text(encoding="utf-8")
    player_control = PLAYER_CONTROL.read_text(encoding="utf-8")
    battery_indicator = BATTERY_INDICATOR.read_text(encoding="utf-8")
    clock_widget = CLOCK_WIDGET.read_text(encoding="utf-8")
    notification_unread_count = NOTIFICATION_UNREAD_COUNT.read_text(encoding="utf-8")
    active_window = ACTIVE_WINDOW.read_text(encoding="utf-8")
    resource = RESOURCE.read_text(encoding="utf-8")
    clipped_progress_bar = CLIPPED_PROGRESS_BAR.read_text(encoding="utf-8")
    styled_progress_bar = STYLED_PROGRESS_BAR.read_text(encoding="utf-8")
    material_symbol = MATERIAL_SYMBOL.read_text(encoding="utf-8")
    toolbar_text_field = TOOLBAR_TEXT_FIELD.read_text(encoding="utf-8")
    toolbar_tab_button = TOOLBAR_TAB_BUTTON.read_text(encoding="utf-8")
    toolbar_tab_bar = TOOLBAR_TAB_BAR.read_text(encoding="utf-8")
    material_text_area = MATERIAL_TEXT_AREA.read_text(encoding="utf-8")
    styled_drop_shadow = STYLED_DROP_SHADOW.read_text(encoding="utf-8")
    circular_progress = CIRCULAR_PROGRESS.read_text(encoding="utf-8")
    secondary_tab_bar = SECONDARY_TAB_BAR.read_text(encoding="utf-8")
    scroll_to_bottom_button = SCROLL_TO_BOTTOM_BUTTON.read_text(encoding="utf-8")
    page_placeholder = PAGE_PLACEHOLDER.read_text(encoding="utf-8")
    selection_dialog = SELECTION_DIALOG.read_text(encoding="utf-8")
    toast_notification = TOAST_NOTIFICATION.read_text(encoding="utf-8")
    window_dialog = WINDOW_DIALOG.read_text(encoding="utf-8")
    cheatsheet_keybind_row = CHEATSHEET_KEYBIND_ROW.read_text(encoding="utf-8")
    status_rings = STATUS_RINGS.read_text(encoding="utf-8")
    quick_launch = QUICK_LAUNCH.read_text(encoding="utf-8")
    event_card = EVENT_CARD.read_text(encoding="utf-8")
    sysmon_widget = SYSMON_WIDGET.read_text(encoding="utf-8")
    stopwatch = STOPWATCH.read_text(encoding="utf-8")
    center_widget_group = CENTER_WIDGET_GROUP.read_text(encoding="utf-8")
    web_app_view = WEB_APP_VIEW.read_text(encoding="utf-8")
    plugins_tab = PLUGINS_TAB.read_text(encoding="utf-8")
    anime = ANIME.read_text(encoding="utf-8")
    booru_response = BOORU_RESPONSE.read_text(encoding="utf-8")
    styled_overlay_widget = STYLED_OVERLAY_WIDGET.read_text(encoding="utf-8")
    filter_chip = FILTER_CHIP.read_text(encoding="utf-8")
    group_button = GROUP_BUTTON.read_text(encoding="utf-8")
    navigation_rail_button = NAVIGATION_RAIL_BUTTON.read_text(encoding="utf-8")
    input_chip = INPUT_CHIP.read_text(encoding="utf-8")
    selection_group_button = SELECTION_GROUP_BUTTON.read_text(encoding="utf-8")
    material_placeholder_message = MATERIAL_PLACEHOLDER_MESSAGE.read_text(encoding="utf-8")
    notification_item = NOTIFICATION_ITEM.read_text(encoding="utf-8")
    notification_group = NOTIFICATION_GROUP.read_text(encoding="utf-8")
    notification_action_button = NOTIFICATION_ACTION_BUTTON.read_text(encoding="utf-8")
    notification_group_expand_button = NOTIFICATION_GROUP_EXPAND_BUTTON.read_text(encoding="utf-8")
    notification_app_icon = NOTIFICATION_APP_ICON.read_text(encoding="utf-8")
    content_subsection_label = CONTENT_SUBSECTION_LABEL.read_text(encoding="utf-8")
    keyboard_focus_ring = KEYBOARD_FOCUS_RING.read_text(encoding="utf-8")
    keyboard_key = KEYBOARD_KEY.read_text(encoding="utf-8")
    material_shape_symbol = MATERIAL_SHAPE_SYMBOL.read_text(encoding="utf-8")
    floating_action_button = FLOATING_ACTION_BUTTON.read_text(encoding="utf-8")
    date_picker = DATE_PICKER.read_text(encoding="utf-8")
    dialog_button = DIALOG_BUTTON.read_text(encoding="utf-8")
    dialog_list_item = DIALOG_LIST_ITEM.read_text(encoding="utf-8")
    icon_toolbar_button = ICON_TOOLBAR_BUTTON.read_text(encoding="utf-8")
    collapsible_section = COLLAPSIBLE_SECTION.read_text(encoding="utf-8")
    content_section = CONTENT_SECTION.read_text(encoding="utf-8")
    material_text_field = MATERIAL_TEXT_FIELD.read_text(encoding="utf-8")
    styled_text_area = STYLED_TEXT_AREA.read_text(encoding="utf-8")
    toolbar_button = TOOLBAR_BUTTON.read_text(encoding="utf-8")
    notice_box = NOTICE_BOX.read_text(encoding="utf-8")
    ripple_button_with_icon = RIPPLE_BUTTON_WITH_ICON.read_text(encoding="utf-8")
    styled_tooltip_content = STYLED_TOOLTIP_CONTENT.read_text(encoding="utf-8")
    toolbar = TOOLBAR.read_text(encoding="utf-8")
    timer_indicator = TIMER_INDICATOR.read_text(encoding="utf-8")
    shell_update_indicator = SHELL_UPDATE_INDICATOR.read_text(encoding="utf-8")
    util_buttons = UTIL_BUTTONS.read_text(encoding="utf-8")
    left_sidebar_button = LEFT_SIDEBAR_BUTTON.read_text(encoding="utf-8")
    bar_content = BAR_CONTENT.read_text(encoding="utf-8")
    bar_group = BAR_GROUP.read_text(encoding="utf-8")
    circle_util_button = CIRCLE_UTIL_BUTTON.read_text(encoding="utf-8")
    scroll_hint = SCROLL_HINT.read_text(encoding="utf-8")
    bar_taskbar_button = BAR_TASKBAR_BUTTON.read_text(encoding="utf-8")
    bar_taskbar_window_preview = BAR_TASKBAR_WINDOW_PREVIEW.read_text(encoding="utf-8")
    right_sidebar_start = bar_content.index("id: rightSidebarButtonComponent")
    right_sidebar_end = bar_content.find("\n    Component {", right_sidebar_start + 1)
    right_sidebar_block = bar_content[right_sidebar_start:
        right_sidebar_end if right_sidebar_end >= 0 else len(bar_content)]
    workspaces = WORKSPACES.read_text(encoding="utf-8")
    sys_tray = SYS_TRAY.read_text(encoding="utf-8")
    sys_tray_menu = SYS_TRAY_MENU.read_text(encoding="utf-8")
    context_menu = CONTEXT_MENU.read_text(encoding="utf-8")
    glass_background = GLASS_BACKGROUND.read_text(encoding="utf-8")
    styled_radio_button = STYLED_RADIO_BUTTON.read_text(encoding="utf-8")
    ripple_button = RIPPLE_BUTTON.read_text(encoding="utf-8")
    styled_rectangular_shadow = STYLED_RECTANGULAR_SHADOW.read_text(encoding="utf-8")
    styled_combo_box = STYLED_COMBO_BOX.read_text(encoding="utf-8")
    font_selector = FONT_SELECTOR.read_text(encoding="utf-8")
    icon_theme_selector = ICON_THEME_SELECTOR.read_text(encoding="utf-8")
    config_selection_array = CONFIG_SELECTION_ARRAY.read_text(encoding="utf-8")
    config_spin_box = CONFIG_SPIN_BOX.read_text(encoding="utf-8")
    config_switch = CONFIG_SWITCH.read_text(encoding="utf-8")
    styled_spin_box = STYLED_SPIN_BOX.read_text(encoding="utf-8")
    settings_switch = SETTINGS_SWITCH.read_text(encoding="utf-8")
    settings_note = SETTINGS_NOTE.read_text(encoding="utf-8")
    settings_card_section = SETTINGS_CARD_SECTION.read_text(encoding="utf-8")
    settings_group = SETTINGS_GROUP.read_text(encoding="utf-8")
    styled_text_input = STYLED_TEXT_INPUT.read_text(encoding="utf-8")
    styled_slider = STYLED_SLIDER.read_text(encoding="utf-8")
    settings_overlay = SETTINGS_OVERLAY.read_text(encoding="utf-8")
    settings_live_search_results = SETTINGS_LIVE_SEARCH_RESULTS.read_text(encoding="utf-8")
    settings_window = SETTINGS_WINDOW.read_text(encoding="utf-8")
    control_panel_date_time = CONTROL_PANEL_DATE_TIME.read_text(encoding="utf-8")
    control_panel_wallpaper = CONTROL_PANEL_WALLPAPER.read_text(encoding="utf-8")
    control_panel_weather = CONTROL_PANEL_WEATHER.read_text(encoding="utf-8")
    control_panel_sliders = CONTROL_PANEL_SLIDERS.read_text(encoding="utf-8")
    control_panel_system = CONTROL_PANEL_SYSTEM.read_text(encoding="utf-8")
    control_panel_profile = CONTROL_PANEL_PROFILE.read_text(encoding="utf-8")
    control_panel_quick_actions = CONTROL_PANEL_QUICK_ACTIONS.read_text(encoding="utf-8")
    control_panel_media = CONTROL_PANEL_MEDIA.read_text(encoding="utf-8")
    control_panel_content = CONTROL_PANEL_CONTENT.read_text(encoding="utf-8")
    on_screen_keyboard = ON_SCREEN_KEYBOARD.read_text(encoding="utf-8")
    osk_key = OSK_KEY.read_text(encoding="utf-8")
    screen_corners = SCREEN_CORNERS.read_text(encoding="utf-8")
    sidebar_left_content = SIDEBAR_LEFT_CONTENT.read_text(encoding="utf-8")
    sidebar_right_content = SIDEBAR_RIGHT_CONTENT.read_text(encoding="utf-8")
    compact_sidebar_right_content = COMPACT_SIDEBAR_RIGHT_CONTENT.read_text(encoding="utf-8")
    vertical_bar_content = VERTICAL_BAR_CONTENT.read_text(encoding="utf-8")
    vertical_clock_widget = VERTICAL_CLOCK_WIDGET.read_text(encoding="utf-8")
    vertical_date_widget = VERTICAL_DATE_WIDGET.read_text(encoding="utf-8")
    overview_search_bar = OVERVIEW_SEARCH_BAR.read_text(encoding="utf-8")
    overview_search_item = OVERVIEW_SEARCH_ITEM.read_text(encoding="utf-8")
    overview_search_widget = OVERVIEW_SEARCH_WIDGET.read_text(encoding="utf-8")
    overview_action_mode_view = OVERVIEW_ACTION_MODE_VIEW.read_text(encoding="utf-8")
    overview_all_apps_grid = OVERVIEW_ALL_APPS_GRID.read_text(encoding="utf-8")
    overview_dashboard = OVERVIEW_DASHBOARD.read_text(encoding="utf-8")
    dashboard_content = DASHBOARD_CONTENT.read_text(encoding="utf-8")
    overview_niri_widget = OVERVIEW_NIRI_WIDGET.read_text(encoding="utf-8")
    overview_widget = OVERVIEW_WIDGET.read_text(encoding="utf-8")
    welcome = WELCOME.read_text(encoding="utf-8")

    # Runtime must never expose a persisted legacy shell-wide style, even during
    # singleton initialization before ThemeService has normalized config on disk.
    require(
        appearance,
        'readonly property string globalStyle: "material"',
        "Appearance.qml",
    )
    forbid(
        appearance,
        'readonly property string globalStyle: Config?.options?.appearance?.globalStyle ?? "material"',
        "Appearance.qml",
    )

    for token in (
        "readonly property bool alisEverywhere: false",
        "readonly property bool angelEverywhere: false",
        "readonly property bool auroraEverywhere: false",
        "readonly property bool regaliaEverywhere: false",
        "readonly property bool zzzEverywhere: false",
        "readonly property bool cookieEverywhere: false",
    ):
        require(appearance, token, "Appearance.qml compatibility boundary")
    for token in (
        "_auroraLightMode",
        "popupSurfaceTransparentize",
    ):
        forbid(appearance, token, "Appearance.qml retired compatibility")

    for token in (
        'globalStyle === "alis"',
        'globalStyle === "angel"',
        'globalStyle === "aurora"',
        'globalStyle === "regalia"',
        'globalStyle === "cookie"',
    ):
        forbid(appearance, token, "Appearance.qml")

    for token in (
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.angelEverywhere",
        "id: auroraBlurSource",
    ):
        forbid(welcome, token, "welcome.qml")
    for token in (
        "radius: Appearance.rounding.large",
        "color: Appearance.colors.colLayer1Base",
    ):
        require(welcome, token, "welcome.qml Material chrome")

    shared_material_primitives = {
        "MaterialSymbol.qml": material_symbol,
        "ToolbarTextField.qml": toolbar_text_field,
        "ToolbarTabButton.qml": toolbar_tab_button,
        "ToolbarTabBar.qml": toolbar_tab_bar,
        "MaterialTextArea.qml": material_text_area,
        "StyledDropShadow.qml": styled_drop_shadow,
        "CircularProgress.qml": circular_progress,
        "SecondaryTabBar.qml": secondary_tab_bar,
        "ScrollToBottomButton.qml": scroll_to_bottom_button,
        "PagePlaceholder.qml": page_placeholder,
        "SelectionDialog.qml": selection_dialog,
        "ToastNotification.qml": toast_notification,
        "WindowDialog.qml": window_dialog,
        "CheatsheetKeybindRow.qml": cheatsheet_keybind_row,
        "StatusRings.qml": status_rings,
        "QuickLaunch.qml": quick_launch,
        "EventCard.qml": event_card,
        "SysMonWidget.qml": sysmon_widget,
        "Stopwatch.qml": stopwatch,
        "CenterWidgetGroup.qml": center_widget_group,
        "WebAppView.qml": web_app_view,
        "PluginsTab.qml": plugins_tab,
        "Anime.qml": anime,
        "BooruResponse.qml": booru_response,
        "StyledOverlayWidget.qml": styled_overlay_widget,
        "FilterChip.qml": filter_chip,
        "GroupButton.qml": group_button,
        "NavigationRailButton.qml": navigation_rail_button,
        "InputChip.qml": input_chip,
        "SelectionGroupButton.qml": selection_group_button,
        "MaterialPlaceholderMessage.qml": material_placeholder_message,
        "NotificationItem.qml": notification_item,
        "NotificationGroup.qml": notification_group,
        "NotificationActionButton.qml": notification_action_button,
        "NotificationGroupExpandButton.qml": notification_group_expand_button,
        "NotificationAppIcon.qml": notification_app_icon,
        "ContentSubsectionLabel.qml": content_subsection_label,
        "KeyboardFocusRing.qml": keyboard_focus_ring,
        "KeyboardKey.qml": keyboard_key,
        "MaterialShapeWrappedMaterialSymbol.qml": material_shape_symbol,
        "FloatingActionButton.qml": floating_action_button,
        "DatePicker.qml": date_picker,
        "DialogButton.qml": dialog_button,
        "DialogListItem.qml": dialog_list_item,
        "IconToolbarButton.qml": icon_toolbar_button,
        "CollapsibleSection.qml": collapsible_section,
        "ContentSection.qml": content_section,
        "MaterialTextField.qml": material_text_field,
        "StyledTextArea.qml": styled_text_area,
        "ToolbarButton.qml": toolbar_button,
        "NoticeBox.qml": notice_box,
        "RippleButtonWithIcon.qml": ripple_button_with_icon,
        "StyledToolTipContent.qml": styled_tooltip_content,
        "Toolbar.qml": toolbar,
    }
    for source, source_text in shared_material_primitives.items():
        for token in (
            "Appearance.alisEverywhere",
            "Appearance.auroraEverywhere",
            "Appearance.angelEverywhere",
            "Appearance.regaliaEverywhere",
            "Appearance.zzzEverywhere",
            "Appearance.cookieEverywhere",
        ):
            forbid(source_text, token, source)

    for token in (
        "readonly property real effectiveFill: animateFill",
        "enabled: root.animateFill && Appearance.animationsEnabled",
    ):
        require(material_symbol, token, "MaterialSymbol.qml")
    for token in (
        "leftPadding: 10",
        "placeholderTextColor: Appearance.colors.colSubtext",
        "color: Appearance.colors.colOnLayer1",
        "radius: Appearance.rounding.full",
    ):
        require(toolbar_text_field, token, "ToolbarTextField.qml")
    forbid(toolbar_text_field, "RegaliaControlFace {", "ToolbarTextField.qml")
    for token in (
        "implicitHeight: 40",
        "buttonRadius: height / 2",
        "cookieMorphing: false",
        "text: root.text",
        "font.family: Appearance.font.family.main",
    ):
        require(toolbar_tab_button, token, "ToolbarTabButton.qml")
    for token in (
        "height: 40",
        "color: Appearance.colors.colSurfaceContainer",
        "color: Appearance.colors.colSecondaryContainer",
        "implicitHeight: targetItem ? targetItem.implicitHeight : 0",
        "color: Appearance.colors.colPrimary",
    ):
        require(toolbar_tab_bar, token, "ToolbarTabBar.qml")
    for token in (
        "Material.accent: Appearance.colors.colPrimary",
        "Material.background: Appearance.colors.colLayer1",
        "Material.foreground: Appearance.colors.colOnSurface",
        "selectedTextColor: Appearance.colors.colOnSecondaryContainer",
    ):
        require(material_text_area, token, "MaterialTextArea.qml")
    forbid(material_text_area, "RegaliaControlFace {", "MaterialTextArea.qml")
    require(
        styled_drop_shadow,
        "visible: Appearance.effectsEnabled",
        "StyledDropShadow.qml",
    )

    for token in (
        "property color colPrimary: Appearance.colors.colOnSecondaryContainer",
        "property color colSecondary: Appearance.colors.colSecondaryContainer",
    ):
        require(circular_progress, token, "CircularProgress.qml")
    for token in (
        "color: Appearance.colors.colPrimary",
        "color: Appearance.colors.colOutlineVariant",
    ):
        require(secondary_tab_bar, token, "SecondaryTabBar.qml")
    for token in (
        ": Appearance.colors.colSecondary",
        ": Appearance.colors.colSecondaryHover",
        ": Appearance.colors.colSecondaryActive",
        "color: Appearance.colors.colOnSecondary",
    ):
        require(scroll_to_bottom_button, token, "ScrollToBottomButton.qml")
    for token in (
        "spacing: 5",
        "MaterialShapeWrappedMaterialSymbol {",
        "visible: !placeholderMascot.visible",
        "color: Appearance.colors.colOutline",
    ):
        require(page_placeholder, token, "PagePlaceholder.qml")
    forbid(page_placeholder, "Appearance.alis.", "PagePlaceholder.qml")

    for token in (
        "color: Appearance.colors.colSurfaceContainerHigh",
        "radius: Appearance.rounding.normal",
        "color: Appearance.colors.colOnSurface",
        "color: Appearance.colors.colOutline",
    ):
        require(selection_dialog, token, "SelectionDialog.qml")
    for token in (
        "radius: Appearance.rounding.normal",
        "border.color: root.isError ? Appearance.colors.colError : Appearance.colors.colOutlineVariant",
        "implicitWidth: 20",
        "color: root.isError",
        "buttonRadius: Appearance.rounding.small",
        "colRipple: Qt.rgba(0, 0, 0, 0.15)",
    ):
        require(toast_notification, token, "ToastNotification.qml")
    forbid(toast_notification, "CookieFace {", "ToastNotification.qml")

    for token in (
        "radius: Appearance.rounding.large",
        "fallbackColor: Appearance.colors.colSurfaceContainerHigh",
        'border.color: "transparent"',
        "readonly property real contentPad: Math.max(radius, Appearance.sizes.spacingLarge)",
    ):
        require(window_dialog, token, "WindowDialog.qml")
    for token in ("RegaliaPlate {", "ZzzPanelBackdrop {"):
        forbid(window_dialog, token, "WindowDialog.qml")

    for token in (
        "color: hovered ? Appearance.colors.colLayer2Hover",
        "radius: Appearance.rounding.verysmall",
        "color: Appearance.colors.colSubtext",
        "color: Appearance.colors.colOnLayer1",
        "color: Appearance.colors.colOutlineVariant",
        "opacity: 0.3",
    ):
        require(cheatsheet_keybind_row, token, "CheatsheetKeybindRow.qml")
    for token in (
        "ResourceUsage.cpuUsage >= 0.9 ? Appearance.colors.colError",
        "Battery.isCritical ? Appearance.colors.colError",
        "property color ringColor: Appearance.colors.colPrimary",
        "border.color: Appearance.colors.colLayer2",
        "font.weight: Font.Medium",
        "font.italic: false",
    ):
        require(status_rings, token, "StatusRings.qml")
    for token in (
        "buttonRadius: Appearance.rounding.full",
        "colBackground: isRunning ? Appearance.colors.colPrimaryContainer",
        "colBackgroundHover: isRunning",
        "colRipple: isRunning",
        "width: 6",
        "height: 6",
        "radius: 3",
    ):
        require(quick_launch, token, "QuickLaunch.qml")

    for token in (
        "readonly property color colPrimary: Appearance.colors.colPrimary",
        "readonly property color colText: Appearance.colors.colOnLayer1",
        "readonly property color colBadge: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.90)",
        "visible: true",
        "radius: Appearance.rounding.small",
        "colBackgroundHover: Appearance.colors.colLayer1Hover",
    ):
        require(event_card, token, "EventCard.qml")
    forbid(event_card, "AngelPartialBorder {", "EventCard.qml")
    for token in (
        "readonly property color colText: Appearance.colors.colOnLayer1",
        "readonly property color colBg: Appearance.colors.colLayer0",
        "readonly property int borderWidth: 1",
        "readonly property real radius: Appearance.rounding.normal",
        "colBackgroundHover: Appearance.colors.colLayer1Hover",
        "trackColor: Appearance.colors.colSecondaryContainer",
    ):
        require(sysmon_widget, token, "SysMonWidget.qml")

    for token in (
        "color: Appearance.colors.colOnSurface",
        "color: Appearance.colors.colSubtext",
        "color: Appearance.colors.colLayer2",
        "buttonRadius: Appearance.rounding.full",
        "? Appearance.colors.colSecondaryContainer",
        "? Appearance.colors.colOnSecondaryContainer",
        "colBackground: Appearance.colors.colLayer2",
        "colBackgroundHover: Appearance.colors.colLayer2Hover",
        "colRipple: Appearance.colors.colLayer2Active",
    ):
        require(stopwatch, token, "Stopwatch.qml")
    forbid(stopwatch, "Qt5Compat.GraphicalEffects", "Stopwatch.qml")

    for token in (
        "radius: Appearance.rounding.normal",
        "color: Appearance.colors.colLayer1",
        "border.width: 0",
        'border.color: "transparent"',
    ):
        require(center_widget_group, token, "CenterWidgetGroup.qml")
    forbid(center_widget_group, "AngelPartialBorder {", "CenterWidgetGroup.qml")
    for source, source_text in (
        ("WebAppView.qml", web_app_view),
        ("PluginsTab.qml", plugins_tab),
    ):
        for token in (
            "readonly property color colText: Appearance.colors.colOnLayer1",
            "readonly property color colTextSecondary: Appearance.colors.colSubtext",
            "readonly property color colBg: Appearance.colors.colLayer1",
            "readonly property color colBgHover: Appearance.colors.colLayer1Hover",
            "readonly property color colBorder: Appearance.colors.colLayer0Border",
        ):
            require(source_text, token, source)
    require(web_app_view, "border.width: 0", "WebAppView.qml")
    require(web_app_view, "color: Appearance.colors.colLayer0", "WebAppView.qml")
    require(plugins_tab, "border.width: 0", "PluginsTab.qml")
    require(plugins_tab, "color: Appearance.colors.colLayer0", "PluginsTab.qml")

    for token in (
        "colBackground: tagSuggestions.selectedIndex === index",
        "color: Appearance.colors.colOnSecondaryContainer",
        "radius: Appearance.rounding.normal - root.padding",
        "color: Appearance.colors.colLayer2",
        "buttonRadius: Appearance.rounding.small",
        "? Appearance.colors.colOnPrimary",
    ):
        require(anime, token, "Anime.qml")
    for token in (
        'color: cleanLayout ? "transparent" : Appearance.colors.colLayer1',
        "color: Appearance.colors.colSecondaryContainer",
        "colBackground: Appearance.colors.colSurfaceContainerHighest",
        "colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover",
        "colRipple: Appearance.colors.colSurfaceContainerHighestActive",
    ):
        require(booru_response, token, "BooruResponse.qml")

    for token in (
        "property real radius: Appearance.rounding.windowRounding",
        "ColorUtils.applyAlpha(Appearance.colors.colLayer1, root.panelBaseOpacity)",
        "border.width: 1",
        'color: root.fancyBorders ? "transparent" : Appearance.colors.colLayer1',
        "colBackgroundToggled: Appearance.colors.colSecondaryContainer",
        "colRippleToggled: Appearance.colors.colSecondaryContainerActive",
        "GE.OpacityMask {",
    ):
        require(styled_overlay_widget, token, "StyledOverlayWidget.qml")
    for token in (
        "RegaliaPlate {",
        "AngelPartialBorder {",
        "id: widgetBlurWallpaper",
        "MultiEffect {",
        "import QtQuick.Effects",
        "import Quickshell",
    ):
        forbid(styled_overlay_widget, token, "StyledOverlayWidget.qml")

    for token in (
        "+ (icon.visible ? icon.implicitWidth + 6 : 0)",
        "implicitHeight: 30",
        "buttonRadius: height / 2",
        "readonly property color _restFill: root.selected",
        "readonly property color _hoverFill: root.selected",
        "border.width: root.visualFocus ? 2",
        "spacing: icon.visible ? 6 : 0",
    ):
        require(filter_chip, token, "FilterChip.qml")

    for token in (
        "property bool bounce: true",
        "property real baseHeight: contentItem.implicitHeight + verticalPadding * 2",
        "property color colBackgroundHover: Appearance.colors.colLayer1Hover",
        "property color colBackgroundToggled: Appearance.colors.colPrimary",
        "color: root.waveFace ? \"transparent\" : root.color",
        "color: Appearance.colors.colOnLayer0",
    ):
        require(group_button, token, "GroupButton.qml")
    for token in ("RegaliaControlFace {", "CookieFace {", "buttonBackground.cookieFace"):
        forbid(group_button, token, "GroupButton.qml")
    for token in (
        "color: Appearance.colors.colPrimary",
        "radius: Appearance.rounding.full",
        "color: Appearance.colors.colOnPrimary",
        "color: toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1",
        "scale: root.down ? 0.82 : 1",
        "color: Appearance.colors.colOnLayer1",
    ):
        require(navigation_rail_button, token, "NavigationRailButton.qml")
    forbid(navigation_rail_button, "RegaliaControlFace {", "NavigationRailButton.qml")

    for token in (
        "implicitWidth: chipContent.implicitWidth + 20",
        "implicitHeight: 30",
        "radius: height / 2",
        "border.width: 1",
        "Appearance.colors.colSecondaryContainerHover",
        "Appearance.colors.colOnSecondaryContainer",
        "spacing: (root.chipIcon.length > 0 || root.removable) ? 4 : 0",
        "anchors.rightMargin: root.removable ? 24 : 0",
    ):
        require(input_chip, token, "InputChip.qml")
    forbid(input_chip, "RegaliaControlFace {", "InputChip.qml")

    for token in (
        "readonly property bool showZzzPreview: false",
        "buttonPreviewKind",
    ):
        require(selection_group_button, token, "SelectionGroupButton.qml")
    bindings = {}
    paddings = {}
    for name in ("horizontalPadding", "verticalPadding"):
        expression = re.search(r"^    " + name + r": (.+)$", selection_group_button, re.M)
        assert expression, f"SelectionGroupButton missing padding: {name}"
        paddings[name] = expression[1]
    for name in ("colBackground", "colBackgroundHover", "colBackgroundActive"):
        binding = re.search(r"^    " + name + r": (.*(?:\n        .*)*)", selection_group_button, re.M)
        assert binding, f"SelectionGroupButton missing palette binding: {name}"
        bindings[name] = binding[1]
    subprocess.run(["node", "-e", r"""
const vm=require('node:vm'),assert=require('node:assert/strict');
const bindings=JSON.parse(process.argv[1]);
const paddings=JSON.parse(process.argv[2]);
const states=[['colBackground',.1,'colSecondaryContainer'],['colBackgroundHover',.18,'colSecondaryContainerHover'],['colBackgroundActive',.26,'colSecondaryContainerActive']];
for(const family of ['abyss','ii','waffle'])for(const optIn of [true,false])for(const [name,alpha,fallback] of states){
 const colors={colPrimary:'primary',colSecondaryContainer:'normal',colSecondaryContainerHover:'hover',colSecondaryContainerActive:'pressed'};
 const context={root:{useAbyssPillShape:optIn,abyssTaskNavigation:false},Config:{options:{panelFamily:family}},Appearance:{colors,fontSizeScale:1.25},Qt:{alpha:(color,a)=>color+':'+a}};
 const result=vm.runInNewContext(bindings[name],context);
 assert.equal(result,optIn && family==='abyss' ? 'primary:'+alpha : colors[fallback],family+' '+optIn+' '+name);
 assert.equal(vm.runInNewContext(paddings.horizontalPadding,context),11,'generic horizontal padding');
 assert.equal(vm.runInNewContext(paddings.verticalPadding,context),6,'generic vertical padding');
}
console.log('Selection group palette: PASS (18 family/shape/state cases)');
""", json.dumps(bindings), json.dumps(paddings)], check=True)
    for token in ("ZzzCornerPreview", "cornerPreview", "Appearance.zzz."):
        forbid(selection_group_button, token, "SelectionGroupButton.qml")
    for token in (
        "spacing: root.compact ? 6 : 10",
        "implicitWidth: materialShape.implicitWidth",
        "implicitHeight: materialShape.implicitHeight",
        "MaterialShapeWrappedMaterialSymbol {",
        "color: Appearance.colors.colOnSurface",
        "color: Appearance.colors.colSubtext",
    ):
        require(material_placeholder_message, token, "MaterialPlaceholderMessage.qml")
    forbid(material_placeholder_message, "Appearance.alis.", "MaterialPlaceholderMessage.qml")

    for token in (
        "radius: Appearance.rounding.small",
        "Appearance.colors.colLayer3",
        "border.width: 0",
        "color: Appearance.colors.colOnLayer3",
        "Appearance.colors.colSubtext",
    ):
        require(notification_item, token, "NotificationItem.qml")
    forbid(notification_item, "RegaliaPlate {", "NotificationItem.qml")
    for token in (
        "ColorUtils.applyAlpha(Appearance.colors.colLayer2, 1 - Appearance.backgroundTransparency)",
        "radius: Appearance.rounding.normal",
        "border.width: 0",
        "color: root.modernLayout",
        "color: Appearance.colors.colSubtext",
    ):
        require(notification_group, token, "NotificationGroup.qml")
    for token in (
        "ZzzPlate {",
        "RegaliaPlate {",
        "AngelPartialBorder {",
        "notifBlurredWallpaper",
        "MultiEffect {",
        "GE.OpacityMask",
    ):
        forbid(notification_group, token, "NotificationGroup.qml")

    for token in (
        "implicitHeight: 34",
        "buttonRadius: Appearance.rounding.small",
        "? Appearance.colors.colSecondaryContainer",
        ": Appearance.colors.colLayer4",
        "? Appearance.colors.colOnSecondaryContainer",
        ": Appearance.colors.colOnLayer3",
    ):
        require(notification_action_button, token, "NotificationActionButton.qml")
    for token in (
        "buttonRadius: Appearance.rounding.full",
        "ColorUtils.mix(",
        "Appearance.colors.colLayer2Hover",
        "Appearance.colors.colLayer2Active",
        "color: Appearance.colors.colOnLayer2",
    ):
        require(notification_group_expand_button, token, "NotificationGroupExpandButton.qml")
    for token in (
        'color: isUrgent ? Appearance.colors.colPrimaryContainer : "transparent"',
        "Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer",
        "radius: Appearance.rounding.full",
    ):
        require(notification_app_icon, token, "NotificationAppIcon.qml")

    for token in (
        "color: Appearance.colors.colSubtext",
        "font.weight: Font.Normal",
        "font.letterSpacing: 0",
    ):
        require(content_subsection_label, token, "ContentSubsectionLabel.qml")
    for token in (
        "radius: Appearance.rounding.small",
        "border.color: Appearance.colors.colPrimary",
    ):
        require(keyboard_focus_ring, token, "KeyboardFocusRing.qml")
    for token in (
        "property real borderRadius: Appearance.rounding.verysmall",
        "color: Appearance.colors.colSurfaceContainerHigh",
        "color: Appearance.colors.colSurfaceContainer",
        "color: Appearance.colors.colOnSurface",
    ):
        require(keyboard_key, token, "KeyboardKey.qml")
    for token in (
        "color: Appearance.colors.colSecondaryContainer",
        "colSymbol: Appearance.colors.colOnSecondaryContainer",
        "shape: MaterialShape.Shape.Clover4Leaf",
    ):
        require(material_shape_symbol, token, "MaterialShapeWrappedMaterialSymbol.qml")
    for token in (
        "buttonRadius: baseSize / 14 * 4",
        "colBackground: Appearance.colors.colPrimaryContainer",
        "colBackgroundHover: Appearance.colors.colPrimaryContainerHover",
        "colRipple: Appearance.colors.colPrimaryContainerActive",
        "property color colOnBackground: Appearance.colors.colOnPrimaryContainer",
    ):
        require(floating_action_button, token, "FloatingActionButton.qml")
    for token in (
        "readonly property color colText: Appearance.colors.colOnLayer1",
        "readonly property color colTextSecondary: Appearance.colors.colSubtext",
        "readonly property color colPrimary: Appearance.colors.colPrimary",
        "readonly property color colOnPrimary: Appearance.colors.colOnPrimary",
        "readonly property color colCard: Appearance.colors.colLayer1",
        "readonly property color colLayer2: Appearance.colors.colLayer2",
        "readonly property real radius: Appearance.rounding.small",
    ):
        require(date_picker, token, "DatePicker.qml")

    for token in (
        "buttonRadius: Appearance?.rounding.full ?? 9999",
        "property color colEnabled: Appearance.colors.colPrimary",
        "property color colDisabled: Appearance.colors.colOutline",
        "colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3)",
        "text: root.buttonText",
        "font.family: Appearance.font.family.main",
    ):
        require(dialog_button, token, "DialogButton.qml")
    for token in (
        "? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2",
        "? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover",
        "? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active",
        "buttonRadius: Appearance.rounding.normal",
    ):
        require(dialog_list_item, token, "DialogListItem.qml")
    for token in (
        "colBackgroundToggled: Appearance.colors.colSecondaryContainer",
        "colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover",
        "colRippleToggled: Appearance.colors.colSecondaryContainerActive",
        "? Appearance.colors.colOnSecondaryContainer",
        ": Appearance.colors.colOnSurfaceVariant",
        "iconSize: 22",
    ):
        require(icon_toolbar_button, token, "IconToolbarButton.qml")
    for token in (
        "? Appearance.colors.colLayer1Hover",
        "color: Appearance.colors.colOnSecondaryContainer",
    ):
        require(collapsible_section, token, "CollapsibleSection.qml")
    for token in (
        "OptionalMaterialSymbol {",
        "color: SettingsMaterialPreset.titleExpandedColor",
    ):
        require(content_section, token, "ContentSection.qml")
    forbid(content_section, "ZzzSectionHeader {", "ContentSection.qml")

    for token in (
        "Material.accent: Appearance.colors.colPrimary",
        "Material.background: Appearance.colors.colLayer1",
        "Material.foreground: Appearance.colors.colOnSurface",
        "Material.containerStyle: Material.Outlined",
        "selectedTextColor: Appearance.colors.colOnSecondaryContainer",
        "selectionColor: Appearance.colors.colSecondaryContainer",
        "placeholderTextColor: Appearance.colors.colOnLayer1",
    ):
        require(material_text_field, token, "MaterialTextField.qml")
    forbid(material_text_field, "RegaliaControlFace {", "MaterialTextField.qml")
    for token in (
        "selectedTextColor: Appearance.colors.colOnSecondaryContainer",
        "selectionColor: Appearance.colors.colSecondaryContainer",
        "placeholderTextColor: Appearance.colors.colOutline",
    ):
        require(styled_text_area, token, "StyledTextArea.qml")
    require(toolbar_button, "buttonRadius: Appearance.rounding.full", "ToolbarButton.qml")
    for token in (
        "radius: Appearance.rounding.normal",
        "color: Appearance.colors.colSurfaceContainer",
        "color: Appearance.colors.colPrimary",
        "color: Appearance.colors.colOnSurface",
    ):
        require(notice_box, token, "NoticeBox.qml")
    for token in (
        "implicitHeight: 35",
        "horizontalPadding: 10",
        "buttonRadius: Appearance.rounding.small",
        "colBackground: Appearance.colors.colLayer2",
        "spacing: 5",
        "ColorUtils.ensureReadable(Appearance.colors.colOnLayer2",
    ):
        require(ripple_button_with_icon, token, "RippleButtonWithIcon.qml")

    # Shared tooltip content follows the selected shell family. Evaluate its
    # real bindings so Abyss can keep its material while ii/Waffle retain the
    # existing Material fallback in both light and dark palettes.
    tooltip_surface = styled_tooltip_content.split("id: backgroundRectangle", 1)[1].split("StyledText {", 1)[0]
    tooltip_text = styled_tooltip_content.split("id: tooltipTextObject", 1)[1]
    bindings = {}
    for name in ("color", "radius", "border.color"):
        match = re.search(r"^\s*" + re.escape(name) + r":(.*)$", tooltip_surface, re.M)
        assert match, "tooltip surface binding missing: " + name
        bindings[name] = match.group(1)
    bindings["text"] = re.search(r"^\s*color:(.*)$", tooltip_text, re.M).group(1)
    subprocess.run(["node", "-e", r'''
const assert=require('node:assert/strict'),vm=require('node:vm'),bindings=JSON.parse(process.argv[1]);
for(const abyss of [false,true])for(const darkmode of [false,true]) {
 const context={root:{abyss},implicitHeight:30,AbyssStyle:{surface:'abyss',accent:'accent',textColor:'abyss ink'},
  Appearance:{m3colors:{darkmode},colors:{colLayer3:'material',colLayer3Hover:'outline',colOnLayer3:'material ink'},rounding:{verysmall:6}},
  Qt:{alpha:(color,alpha)=>color+'@'+alpha}};
 const evaluate=name=>vm.runInNewContext(bindings[name],context,{timeout:100});
 assert.equal(evaluate('color'),abyss?'abyss':'material');
 assert.equal(evaluate('radius'),abyss?15:6);
 assert.equal(evaluate('border.color'),abyss?'accent@0.28':'outline');
 assert.equal(evaluate('text'),abyss?(darkmode?'abyss ink':'#000000'):'material ink');
}
''', json.dumps(bindings)], check=True)
    require(styled_tooltip_content, "border.width: 1", "StyledToolTipContent.qml")
    for token in ("RegaliaPlate {", "AngelPartialBorder {"):
        forbid(styled_tooltip_content, token, "StyledToolTipContent.qml")
    for token in (
        "active: root.enableShadow && !root.transparent",
        "visible: !root.transparent",
        "fallbackColor: Appearance.colors.colSurfaceContainer",
        "border.width: 0",
        'border.color: "transparent"',
        "radius: height / 2",
        "GlassBackground {",
    ):
        require(toolbar, token, "Toolbar.qml")
    for token in ("ZzzPlate {", "ZzzSurfaceAccent {", "RegaliaPlate {"):
        forbid(toolbar, token, "Toolbar.qml")

    motion_start = appearance.index("property QtObject motion: QtObject {")
    motion_end = appearance.index("m3colors: QtObject {", motion_start)
    motion_contract = appearance[motion_start:motion_end]
    for token in (
        "regaliaEverywhere",
        "cookieEverywhere",
        "zzzEverywhere",
        "angelEverywhere",
        "alisEverywhere",
        "auroraEverywhere",
    ):
        forbid(motion_contract, token, "Appearance.qml popup reveal")
    for token in (
        "property bool enableFade: root.contextualMotionProfile",
        "property bool enableScale: root.contextualMotionProfile",
        "property real closedScale: root.contextualMotionProfile ? 0.90 : 1.0",
        "property list<real> enterBezierCurve: root.animation.elementMoveEnter.bezierCurve",
    ):
        require(motion_contract, token, "Appearance.qml popup reveal")

    require(appearance, "Behavior on shapeT {", "Appearance.qml")
    require(appearance, "enabled: false", "Appearance.qml legacy shape behavior")

    blur_start = appearance.index("function blurBackendFor(")
    blur_end = appearance.index("function useCompositorBlur(", blur_start)
    blur_contract = appearance[blur_start:blur_end]
    for token in (
        "auroraEverywhere",
        "angelEverywhere",
        "zzzEverywhere",
    ):
        forbid(blur_contract, token, "Appearance.qml blur backend")
    require(
        blur_contract,
        'if (area === "islands" || area === "waffle")',
        "Appearance.qml blur backend",
    )

    hover_start = appearance.index("// Stable aliases for the canonical Material interaction fills")
    hover_end = appearance.index("onEffectsEnabledChanged", hover_start)
    hover_contract = appearance[hover_start:hover_end]
    for token in (
        "regaliaEverywhere",
        "cookieEverywhere",
        "zzzEverywhere",
        "angelEverywhere",
        "alisEverywhere",
        "auroraEverywhere",
    ):
        forbid(hover_contract, token, "Appearance.qml interaction aliases")
    for token in (
        "readonly property color colLayer1Hover: colors.colLayer1Hover",
        "readonly property color colLayer2Hover: colors.colLayer2Hover",
        "readonly property color colLayer1Active: colors.colLayer1Active",
    ):
        require(hover_contract, token, "Appearance.qml interaction aliases")

    warning_start = appearance.index("readonly property color colWarning:")
    warning_end = appearance.index("readonly property color colInfo:", warning_start)
    warning_contract = appearance[warning_start:warning_end]
    forbid(warning_contract, "zzzEverywhere", "Appearance.qml warning tokens")
    for token in (
        "root.m3colors.m3tertiary, 0.42",
        "readonly property color colOnWarningContainer: root.m3colors.m3onTertiaryContainer",
    ):
        require(warning_contract, token, "Appearance.qml warning tokens")

    colors_start = appearance.index("colors: QtObject {")
    rounding_start = appearance.index("rounding: QtObject {", colors_start)
    colors_contract = appearance[colors_start:rounding_start]
    for token in (
        "regaliaEverywhere",
        "cookieEverywhere",
        "zzzEverywhere",
        "angelEverywhere",
        "alisEverywhere",
        "auroraEverywhere",
    ):
        forbid(colors_contract, token, "Appearance.qml colors")
    for token in (
        "readonly property bool _needsHighContrast: false",
        "property color colLayer1Base: m3colors.m3surfaceContainerLow",
        "property color colPrimary: m3colors.m3primary",
        "property color colOutline: m3colors.m3outline",
        "property color colError: m3colors.m3error",
        "property color colSuccess: m3colors.m3success",
        "property color colWarningContainer: m3colors.m3tertiaryContainer",
    ):
        require(colors_contract, token, "Appearance.qml colors")
    ink_bindings = {}
    for name in ("colOnSurface", "colOnSurfaceVariant"):
        binding = re.search(r"^        property color " + name + r": (.*(?:\n            .*)*)", colors_contract, re.M)
        assert binding, f"Appearance missing surface ink binding: {name}"
        ink_bindings[name] = binding[1]
    subprocess.run(["node", "-e", r"""
const vm=require('node:vm'),assert=require('node:assert/strict');
const bindings=JSON.parse(process.argv[1]);
for(const darkmode of [true,false])for(const name of Object.keys(bindings)){
 const variant=name.endsWith('Variant'),calls=[];
 const inputs={m3colors:{darkmode,m3onSurface:'surfaceInk',m3onSurfaceVariant:'variantInk',m3surface:'surface',m3surfaceContainer:'container'},_lightInk:'lightInk',_lightInkVariant:'lightVariant',ColorUtils:{ensureReadable:(ink,bg,ratio)=>{calls.push([ink,bg,ratio]);return ink+'Readable'}}};
 const result=vm.runInNewContext(bindings[name],inputs);
 assert.equal(result,darkmode ? (variant ? 'variantInkReadable' : 'surfaceInkReadable') : (variant ? 'lightVariant' : 'lightInk'));
 assert.deepEqual(calls,darkmode ? [[variant ? 'variantInk' : 'surfaceInk',variant ? 'container' : 'surface',4.5]] : []);
}
console.log('Material surface ink: PASS (dark readability and light palette)');
""", json.dumps(ink_bindings)], check=True)

    typography_start = appearance.index("// Typography scale factor from config", rounding_start)
    rounding_contract = appearance[rounding_start:typography_start]
    for token in ("regaliaEverywhere", "cookieEverywhere", "zzzEverywhere"):
        forbid(rounding_contract, token, "Appearance.qml rounding")
    for token in (
        "property real scale: root._themeMeta.roundingScale ?? 1.0",
        "property int full: 9999",
        "property int windowRounding: Math.max(0, Math.round(18 * scale))",
    ):
        require(rounding_contract, token, "Appearance.qml rounding")

    font_strategy_start = appearance.index("// Material typography may still request", typography_start)
    animation_curves_start = appearance.index("animationCurves: QtObject {", font_strategy_start)
    font_contract = appearance[font_strategy_start:animation_curves_start]
    for token in (
        'globalStyle === "alis"',
        'globalStyle === "angel"',
        'globalStyle === "regalia"',
        'globalStyle === "zzz"',
        "regaliaEverywhere",
    ):
        forbid(font_contract, token, "Appearance.qml font dispatch")
    for token in (
        'readonly property bool _forceMono: _themeMeta.fontStyle === "mono"',
        "readonly property bool _useAngelFont: false",
        "readonly property bool _useRegaliaFont: false",
        "readonly property bool _useZzzFont: false",
        'property string numbers: "Rubik"',
        '"wght": 900',
    ):
        require(font_contract, token, "Appearance.qml font dispatch")

    animation_start = appearance.index("animation: QtObject {")
    animation_end = appearance.index("aurora: QtObject {", animation_start)
    animation_contract = appearance[animation_start:animation_end]
    for token in (
        "regaliaEverywhere",
        "cookieEverywhere",
        "zzzEverywhere",
        "angelEverywhere",
        "alisEverywhere",
        "auroraEverywhere",
    ):
        forbid(animation_contract, token, "Appearance.qml animation presets")
    for token in (
        "root.calcEffectiveDuration(180, root.animationSpeed.clickBounce)",
        "root.calcEffectiveDuration(root.contextualMotionProfile ? 520 : 400, root.animationSpeed.enterExit)",
        'root.resolveCurveBezier("enterExit", animationCurves.emphasizedDecel)',
        "root.calcEffectiveDuration(400, root.animationSpeed.clickBounce)",
        'root.resolveCurveBezier("scroll", animationCurves.standardDecel)',
    ):
        require(animation_contract, token, "Appearance.qml animation presets")

    # Persistence migration remains owned by ThemeService: old callers/config may
    # still reach this compatibility boundary, but every value is clamped to Material.
    for token in (
        'readonly property string supportedGlobalStyle: "material"',
        'function normalizeGlobalStyle(): void',
        'Config.setNestedValue("appearance.globalStyle", root.supportedGlobalStyle)',
        'function setGlobalStyle(styleId: string): void',
        'if (styleId !== root.supportedGlobalStyle)',
        'root.normalizeGlobalStyle()',
    ):
        require(theme_service, token, "ThemeService.qml")

    # The compatibility setter may remain for old callers, but it must never
    # persist the requested legacy style or resurrect per-style shell geometry.
    for token in (
        '"appearance.globalStyle": styleId',
        'const cards = styleId === "cards"',
        'case "cards":',
        'case "aurora":',
        'case "alis":',
        'case "angel":',
        'case "regalia":',
        'case "zzz":',
        'case "cookie":',
    ):
        forbid(theme_service, token, "ThemeService.qml")

    # The shared connected-popup path is user-facing runtime, not migration
    # compatibility. It must consume the canonical Material tokens directly.
    for token in (
        'readonly property color _surfaceColor: Appearance.colors.colLayer0',
        'readonly property color _borderColor: Appearance.colors.colLayer0Border',
        'readonly property real _borderWidth: 0',
        'readonly property real _surfaceRadius: PerimeterTokens.popupRadius',
    ):
        require(styled_popup, token, "StyledPopup.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
    ):
        forbid(styled_popup, token, "StyledPopup.qml")

    # Tray menu chrome is active runtime. Legacy Global Theme predicates are
    # inert compatibility aliases and must not survive in this caller.
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
        "ZzzPlate {",
    ):
        forbid(sys_tray_menu, token, "SysTrayMenu.qml")
    for token in (
        "StyledPopup {",
        "popupBackgroundMargin: 0",
        "closeOnOutsideClick: true",
        "keyboardFocus: root.keyboardMode",
    ):
        require(sys_tray_menu, token, "SysTrayMenu.qml")
    for token in (
        "color: Appearance.colors.colLayer0",
        "radius: Appearance.rounding.windowRounding",
        "border.width: 1",
        "border.color: Appearance.colors.colLayer0Border",
    ):
        forbid(sys_tray_menu, token, "SysTrayMenu duplicate popup chrome")

    # ContextMenu is shared by Bar and other active shell controls. Keep its
    # focus/input/close behavior intact while locking visual chrome to Material.
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
        "RegaliaPlate {",
    ):
        forbid(context_menu, token, "ContextMenu.qml")
    for token in (
        "property real sourceEdgeMargin: -implicitHeight",
        'fallbackColor: root.panelFallbackColor',
        "radius: root.panelRadius",
        "border.width: root.panelBorderWidth",
        "border.color: root.panelBorderColor",
        "buttonRadius: Appearance.rounding.small",
        "color: Appearance.colors.colOnSurface",
        "Appearance.motion.popupReveal.enterBezierCurve",
    ):
        require(context_menu, token, "ContextMenu.qml")

    # Shared primitives used by active menu surfaces must not re-route through
    # the frozen legacy Global Theme aliases.
    for source, content in (
        ("GlassBackground.qml", glass_background),
        ("StyledRadioButton.qml", styled_radio_button),
    ):
        for token in (
            "Appearance.zzzEverywhere",
            "Appearance.regaliaEverywhere",
            "Appearance.angelEverywhere",
            "Appearance.alisEverywhere",
            "Appearance.auroraEverywhere",
            "Appearance.cookieEverywhere",
        ):
            forbid(content, token, source)
    for token in (
        'color: root.useWallpaperBackdrop ? "transparent" : root.fallbackColor',
        "saturation: Appearance.effectsEnabled ? root.saturationStrength : 0",
        "blur: Appearance.effectsEnabled ? root.blurStrength : 0",
    ):
        require(glass_background, token, "GlassBackground.qml")
    for token in ("AngelPartialBorder {",):
        forbid(glass_background, token, "GlassBackground.qml")
    for token in (
        "width: 20",
        "border.width: 2",
        "width: checked ? 10 : 4",
        "enabled: Appearance.animationsEnabled",
    ):
        require(styled_radio_button, token, "StyledRadioButton.qml")
    forbid(styled_radio_button, "RegaliaControlFace {", "StyledRadioButton.qml")

    # RippleButton is a shell-wide primitive. Its public knobs stay stable, but
    # the renderer itself must follow the sole Material Global Theme.
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
        "RegaliaControlFace {",
        "CookieFace {",
    ):
        forbid(ripple_button, token, "RippleButton.qml")
    for token in (
        "property int rippleDuration: 1200",
        "property bool rippleEnabled: !abyssStyle",
        'property color colBackground: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.14) : "transparent"',
        "property color colBackgroundHover: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.24) : Appearance.colLayer1Hover",
        "property color colBackgroundToggled: Appearance.colors.colPrimary",
        "border.width: root.visualFocus ? 1 : 0",
        'border.color: root.visualFocus ? Appearance.colors.colPrimary : "transparent"',
        "radius: root.buttonEffectiveRadius",
        "color: Appearance.colors.colOnLayer0",
    ):
        require(ripple_button, token, "RippleButton.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
        "Appearance.zzz.",
        "Appearance.regalia.",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
        "Appearance.cookie.",
        "AuroraBlurCorner",
    ):
        forbid(bar, token, "Bar.qml")
    for token in (
        "readonly property bool rightDeadPixelWorkaround:",
        "readonly property bool bottomDeadPixelWorkaround:",
        "id: barRoot",
        "BackgroundEffect.blurRegion: Region {",
    ):
        require(bar, token, "Bar.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
        "Appearance.zzz.",
        "Appearance.regalia.",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
        "Appearance.cookie.",
        "AuroraBlurCorner",
    ):
        forbid(vertical_bar, token, "VerticalBar.qml")
    forbid(bar, "showBarBackground", "Bar.qml")
    forbid(vertical_bar, "showBarBackground", "VerticalBar.qml")
    for token in (
        "id: barRoot",
        "BackgroundEffect.blurRegion: Region {",
        "item: barContent.nativeBlurActive ? barContent.backgroundItem : emptyMask",
    ):
        require(vertical_bar, token, "VerticalBar.qml")

    # Active Bar controls must not reintroduce frozen Global Theme routing.
    for token in (
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.angel.",
        "Appearance.alis.",
    ):
        forbid(weather_bar, token, "WeatherBar.qml")
    for token in (
        "property color foregroundColor: root.vertical",
        "? Appearance.colors.colOnLayer0",
        ": Appearance.colors.colOnLayer1",
        "color: root.foregroundColor",
    ):
        require(weather_bar, token, "WeatherBar.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.zzz.",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
        "AngelPartialBorder {",
    ):
        forbid(bar_media_popup, token, "BarMediaPopup.qml")
    for token in (
        "PlayerControl {",
        "radius: root.popupRounding",
        "Appearance.colors.colPrimary",
        "Appearance.colors.colLayer2",
        "EqualizerPanel {",
        "active: root.presentationActive && root.visible",
    ):
        require(bar_media_popup, token, "BarMediaPopup.qml")
    for token in (
        "color: Appearance.colors.colLayer0",
        'border.color: "transparent"',
        "color: Appearance.colors.colOnLayer0",
        "color: Appearance.colors.colSubtext",
    ):
        forbid(bar_media_popup, token, "BarMediaPopup duplicate outer chrome")

    for source, label, forbidden_tokens, required_tokens in (
        (
            battery_indicator,
            "BatteryIndicator.qml",
            ("Appearance.alisEverywhere", "Appearance.angelEverywhere",
             "Appearance.alis.", "Appearance.angel."),
            ("Appearance.colors.colError", "Appearance.colors.colOnLayer0"),
        ),
        (
            clock_widget,
            "ClockWidget.qml",
            ("Appearance.alisEverywhere", "Appearance.angelEverywhere",
             "Appearance.alis.", "Appearance.angel."),
            ("color: Appearance.colors.colOnLayer1",),
        ),
        (
            notification_unread_count,
            "NotificationUnreadCount.qml",
            ("Appearance.alisEverywhere", "Appearance.alis."),
            ("radius: Math.min(width, height) / 2",
             "color: Appearance.colors.colOnLayer0",
             "color: Appearance.colors.colLayer0"),
        ),
        (
            active_window,
            "ActiveWindow.qml",
            ("Appearance.alisEverywhere", "Appearance.regaliaEverywhere",
             "Appearance.alis.", "Appearance.regalia."),
            ("property color titleColor: Appearance.colors.colOnLayer0",
             "property color appNameColor: Appearance.colors.colSubtext"),
        ),
    ):
        for token in forbidden_tokens:
            forbid(source, token, label)
        for token in required_tokens:
            require(source, token, label)

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.zzz.",
        "Appearance.alis.",
    ):
        forbid(resource, token, "Resource.qml")
    for token in (
        "visible: true",
        "Appearance.colors.colError",
        "Appearance.colors.colTertiary",
        "Appearance.colors.colOnSurfaceVariant",
        "Appearance.colors.colOnLayer1",
        "font.family: Appearance.font.family.main",
        "font.weight: Font.Normal",
        "font.italic: false",
    ):
        require(resource, token, "Resource.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.zzz.",
        "Appearance.angel.",
    ):
        forbid(clipped_progress_bar, token, "ClippedProgressBar.qml")
    for token in (
        "property color highlightColor: Appearance.colors.colOnSecondaryContainer",
        "property color trackColor: ColorUtils.transparentize(highlightColor, 0.5)",
        "radius: Math.min(width, height) / 2",
        "radius: Appearance.rounding.unsharpen",
    ):
        require(clipped_progress_bar, token, "ClippedProgressBar.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.zzz.",
        "Appearance.angel.",
        "zzzSegments",
    ):
        forbid(styled_progress_bar, token, "StyledProgressBar.qml")
    for token in (
        "property color trackColor: Appearance.colors.colSecondaryContainer",
        "active: root.wavy || root.waveAmplitudeMultiplier > 0",
        "active: !root.wavy && root.waveAmplitudeMultiplier <= 0",
        "radius: height / 2",
        "visible: true",
    ):
        require(styled_progress_bar, token, "StyledProgressBar.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.zzz.",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
    ):
        forbid(timer_indicator, token, "TimerIndicator.qml")
    for token in (
        "Appearance.colors.colTertiary",
        "Appearance.colors.colPrimary",
        "Appearance.colors.colSecondary",
        "Appearance.colors.colOnLayer1",
        "Appearance.colors.colLayer1Active",
        "Appearance.colors.colLayer2Active",
        "Appearance.colors.colLayer2Hover",
        "Appearance.colors.colLayer1Hover",
        "Appearance.colors.colOnLayer1Inactive",
    ):
        require(timer_indicator, token, "TimerIndicator.qml")

    for token in (
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
    ):
        forbid(shell_update_indicator, token, "ShellUpdateIndicator.qml")
    for token in (
        "readonly property color accentColor: Appearance.colors.colPrimary",
        "radius: height / 2",
        "Appearance.colors.colLayer1Active",
        "Appearance.colors.colLayer1Hover",
        'border.color: "transparent"',
        "color: Appearance.colors.colLayer0Border",
    ):
        require(shell_update_indicator, token, "ShellUpdateIndicator.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.zzz.",
        "Appearance.alis.",
        "Appearance.angel.",
        "Appearance.aurora.",
    ):
        forbid(util_buttons, token, "UtilButtons.qml")
    for token in (
        "readonly property color neutralIconColor: Appearance.colors.colOnLayer2",
        "readonly property color dangerIconColor: Appearance.colors.colError",
        ": root.neutralIconColor",
    ):
        require(util_buttons, token, "UtilButtons.qml")

    for token in (
        "Appearance.regaliaEverywhere",
        "Appearance.zzzEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.regalia.",
        "Appearance.zzz.",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
        "ZzzPlate {",
    ):
        forbid(left_sidebar_button, token, "LeftSidebarButton.qml")
    for token in (
        "buttonRadius: Appearance.rounding.full",
        "colBackgroundHover: Appearance.colors.colLayer1Hover",
        "colRipple: Appearance.colors.colLayer1Active",
        "colBackgroundToggled: Appearance.colors.colSecondaryContainer",
        "colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover",
        "colRippleToggled: Appearance.colors.colSecondaryContainerActive",
        "color: root.toggled",
        "? Appearance.colors.colOnSecondaryContainer",
        ": Appearance.colors.colOnLayer0",
        "color: Appearance.colors.colTertiary",
    ):
        require(left_sidebar_button, token, "LeftSidebarButton.qml")

    for token in (
        "root.regaliaEverywhere",
        "root.zzzEverywhere",
        "root.auroraEverywhere",
        "Appearance.regalia.",
        "Appearance.zzz.",
        "Appearance.aurora.",
        "ZzzPlate {",
    ):
        forbid(right_sidebar_block, token, "BarContent right sidebar button")
    for token in (
        "buttonRadius: Appearance.rounding.full",
        "colBackgroundHover: Appearance.colors.colLayer1Hover",
        "colRipple: Appearance.colors.colLayer1Active",
        "colBackgroundToggled: Appearance.colors.colSecondaryContainer",
        "colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover",
        "colRippleToggled: Appearance.colors.colSecondaryContainerActive",
        "Appearance.colors.colOnSecondaryContainer",
        "Appearance.colors.colOnLayer0",
    ):
        require(right_sidebar_block, token, "BarContent right sidebar button")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.zzz.",
        "Appearance.alis.",
        "Appearance.aurora.",
        "Appearance.angel.",
        "Appearance.regalia.",
    ):
        forbid(sys_tray, token, "SysTray.qml")
    for token in (
        "colBackgroundToggled: Appearance.colors.colSecondaryContainer",
        "colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover",
        "colRippleToggled: Appearance.colors.colSecondaryContainerActive",
        "Appearance.colors.colOnSecondaryContainer",
        "Appearance.colors.colOnLayer2",
        "color: Appearance.colors.colSubtext",
    ):
        require(sys_tray, token, "SysTray.qml")

    for token in (
        "useZzzStyle",
        "useAngelStyle",
        "useAuroraStyle",
        "Appearance.zzzEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.zzz.",
        "Appearance.angel.",
        "Appearance.aurora.",
        "ZzzPlate {",
        "Appearance.animationCurves.zzzOvershoot",
    ):
        forbid(workspaces, token, "Workspaces.qml")
    for token in (
        "property bool forceMaterialStyle: false",
        "readonly property color workspaceThemeIndicator: root.workspaceThemePrimary",
        "ColorUtils.transparentize(root.workspaceSecondaryContainer, 0.4)",
        "radius: Math.min(width, height) / 2",
        "color: root.workspaceIndicatorColor",
        "color: root.workspacePrimary",
        "Appearance.animation.elementMoveFast.bezierCurve",
    ):
        require(workspaces, token, "Workspaces.qml")

    for token in (
        "Appearance.regaliaEverywhere",
        "Appearance.regalia.",
    ):
        forbid(bar_group, token, "BarGroup.qml")
    for token in (
        "property real padding: 8",
        "borderless: Config.options?.bar?.borderless ?? false",
        "radiusOverride: -1",
        "elevation: 1",
    ):
        require(bar_group, token, "BarGroup.qml")

    for token in (
        "Appearance.regaliaEverywhere",
        "Appearance.zzzEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.regalia.",
        "Appearance.zzz.",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
        "ZzzPlate {",
    ):
        forbid(circle_util_button, token, "CircleUtilButton.qml")
    for token in (
        "buttonRadius: Appearance.rounding.full",
        'colBackground: "transparent"',
        "colBackgroundHover: Appearance.colors.colLayer1Hover",
        "colRipple: Appearance.colors.colLayer1Active",
    ):
        require(circle_util_button, token, "CircleUtilButton.qml")

    for token in (
        "Appearance.regaliaEverywhere",
        "Appearance.regalia.",
    ):
        forbid(scroll_hint, token, "ScrollHint.qml")
    require(scroll_hint, "color: Appearance.colors.colSubtext", "ScrollHint.qml")

    for source, label in (
        (bar_taskbar_button, "BarTaskbarButton.qml"),
        (bar_taskbar_window_preview, "BarTaskbarWindowPreview.qml"),
    ):
        for token in (
            "Appearance.zzzEverywhere",
            "Appearance.regaliaEverywhere",
            "Appearance.angelEverywhere",
            "Appearance.alisEverywhere",
            "Appearance.auroraEverywhere",
            "Appearance.cookieEverywhere",
            "Appearance.zzz.",
            "Appearance.regalia.",
            "Appearance.angel.",
            "Appearance.alis.",
            "Appearance.aurora.",
            "Appearance.cookie.",
            "Appearance.animationCurves.zzzOvershoot",
        ):
            forbid(source, token, label)

    for token in (
        "buttonRadius: Appearance.rounding.small",
        "colBackgroundHover: Appearance.colors.colLayer1Hover",
        "colRipple: Appearance.colors.colLayer1Active",
        'colBackgroundToggled: "transparent"',
        "ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)",
        "color: Appearance.colors.colOutlineVariant",
    ):
        require(bar_taskbar_button, token, "BarTaskbarButton.qml")
    for token in (
        "radius: Appearance.rounding.small",
        "ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)",
        "ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh, 0.5)",
        "color: Appearance.colors.colOnLayer0",
        "color: root.hovered",
        "? Appearance.colors.colError",
        ": Appearance.colors.colSubtext",
        "color: Appearance.colors.colSurfaceContainerLow",
    ):
        require(bar_taskbar_window_preview, token, "BarTaskbarWindowPreview.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
        "Appearance.zzz.",
        "Appearance.regalia.",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
        "Appearance.cookie.",
        "root.alis",
    ):
        forbid(player_control, token, "PlayerControl.qml")
    for token in (
        "property real radius: Appearance.rounding.large",
        "StyledRectangularShadow { target: card }",
        "radius: root.radius",
        "border.width: 0",
        'border.color: "transparent"',
        "font.weight: Font.Medium",
        "font.italic: false",
        "buttonRadius: Appearance.rounding.full",
        "highlightColor: blendedColors?.colPrimary ?? Appearance.colors.colPrimary",
        "trackColor: blendedColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer",
    ):
        require(player_control, token, "PlayerControl.qml")

    # StyledRectangularShadow is shared by active Media/Overview/Settings
    # surfaces. Keep caller-facing knobs, but render only the Material shadow.
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.cookieEverywhere",
        "Appearance.regalia.",
        "Appearance.angel.",
        "Appearance.cookie.",
    ):
        forbid(styled_rectangular_shadow, token, "StyledRectangularShadow.qml")
    for token in (
        "property bool hovered: false",
        "property real spread: 1",
        "property color color: Appearance.colors.colShadow",
        "property vector2d offset: Qt.vector2d(0.0, 1.0)",
        "visible: !Appearance.gameModeMinimal && Appearance.effectsEnabled",
        "radius: root.radius + root.blur * 0.75",
    ):
        require(styled_rectangular_shadow, token, "StyledRectangularShadow.qml")

    # StyledComboBox is active Settings/shared control chrome. Preserve its
    # public ComboBox/search contract while rendering only the Material fallback.
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
        "RegaliaControlFace {",
        "RegaliaPlate {",
    ):
        forbid(styled_combo_box, token, "StyledComboBox.qml")
    for token in (
        "property real baseHeight: 38",
        "property real radius: abyssStyle ? baseHeight/2 : Appearance.rounding.small",
        "readonly property color _bgColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.08) : Appearance.colors.colLayer2",
        "readonly property color _popupColor: Appearance.colors.colLayer3Base",
        "readonly property color _selectedColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.22) : Appearance.colors.colPrimaryContainer",
        "color: root.down ? root._bgActiveColor",
        "border.width: root.abyssStyle ? 0 : 1",
        "width: root.width - 8",
        "height: 36",
        "radius: Appearance.rounding.unsharpenmore",
        "Layout.leftMargin: 12",
        "Layout.rightMargin: 8",
    ):
        require(styled_combo_box, token, "StyledComboBox.qml")

    # Active shared selectors must not route their popup/control chrome
    # through frozen legacy Global Theme predicates.
    forbid(font_selector, "Appearance.alisEverywhere", "FontSelector.qml")
    for token in (
        "color: Appearance.colors.colLayer2Base",
        "radius: Appearance.rounding.normal",
        "border.color: Appearance.colors.colLayer0Border",
    ):
        require(font_selector, token, "FontSelector.qml")

    forbid(icon_theme_selector, "Appearance.alisEverywhere", "IconThemeSelector.qml")
    for token in (
        "color: Appearance.colors.colLayer2Base",
        "radius: Appearance.rounding.normal",
        "border.color: Appearance.colors.colLayer0Border",
    ):
        require(icon_theme_selector, token, "IconThemeSelector.qml")

    forbid(config_selection_array, "Appearance.regaliaEverywhere", "ConfigSelectionArray.qml")
    require(config_selection_array, "spacing: 2", "ConfigSelectionArray.qml")

    for token in (
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.angel.",
        "Appearance.alis.",
    ):
        forbid(config_spin_box, token, "ConfigSpinBox.qml")
    require(config_spin_box, "color: Appearance.colors.colOnSurface", "ConfigSpinBox.qml")

    for token in (
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
    ):
        forbid(settings_switch, token, "SettingsSwitch.qml")
    for token in (
        "colBackgroundHover: Appearance.colors.colLayer2Hover",
        "colRipple: Appearance.colors.colLayer2Active",
    ):
        require(settings_switch, token, "SettingsSwitch.qml")

    for token in (
        "Appearance.alisEverywhere",
        "Appearance.alis.",
    ):
        forbid(settings_note, token, "SettingsNote.qml")
    for token in (
        "Appearance.colors.colTertiary",
        "Appearance.colors.colSubtext",
    ):
        require(settings_note, token, "SettingsNote.qml")

    for token in (
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.regalia.",
        "Appearance.angel.",
        "Appearance.alis.",
        "RegaliaControlFace {",
    ):
        forbid(styled_spin_box, token, "StyledSpinBox.qml")
    for token in (
        "property real baseHeight: 35",
        "property real radius: Appearance.rounding.small",
        "property real innerButtonRadius: Appearance.rounding.unsharpen",
        "color: Appearance.colors.colLayer2",
        "color: Appearance.colors.colOnLayer2",
        "iconSize: 20",
        "root.down.pressed ? Appearance.colors.colLayer2Active",
        "root.up.pressed ? Appearance.colors.colLayer2Active",
    ):
        require(styled_spin_box, token, "StyledSpinBox.qml")

    for token in (
        "Appearance.angelEverywhere",
        "Appearance.zzzEverywhere",
        "Appearance.cookieEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.angel.",
        "Appearance.zzz.",
        "Appearance.cookie.",
        "Appearance.regalia.",
        "Appearance.alis.",
        "Appearance.aurora.",
        "EscalonadoShadow {",
        "ZzzPlate {",
        "CookieFace {",
        "RegaliaPlate {",
        "AngelPartialBorder {",
        "ZzzDiagonalPattern {",
        "RegaliaControlFace {",
        "ZzzGlyphBadge {",
    ):
        forbid(settings_card_section, token, "SettingsCardSection.qml")
    for token in (
        "visible: Appearance.effectsEnabled",
        "y: card.y + 1.5",
        "color: Appearance.colors.colShadow",
        "color: SettingsMaterialPreset.cardColor",
        'border.width: Config.options?.panelFamily === "abyss" ? 0 : 1',
        "border.color: SettingsMaterialPreset.cardBorderColor",
        "implicitWidth: Appearance.font.pixelSize.larger",
        "text: root.title",
        "font.weight: Font.DemiBold",
        "color: Appearance.colors.colSubtext",
        "enabled: root.expanded",
    ):
        require(settings_card_section, token, "SettingsCardSection.qml")

    for token in (
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.angel.",
        "Appearance.alis.",
    ):
        forbid(config_switch, token, "ConfigSwitch.qml")
    require(config_switch, "color: Appearance.colors.colOnSurface", "ConfigSwitch.qml")

    for token in (
        "Appearance.angelEverywhere",
        "Appearance.zzzEverywhere",
        "Appearance.angel.",
        "Appearance.zzz.",
    ):
        forbid(settings_group, token, "SettingsGroup.qml")
    require(settings_group, "border.width: 0", "SettingsGroup.qml")

    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.zzz.",
    ):
        forbid(styled_text_input, token, "StyledTextInput.qml")
    for token in (
        "color: Appearance.colors.colOnLayer1",
        "selectionColor: Appearance.colors.colSecondaryContainer",
    ):
        require(styled_text_input, token, "StyledTextInput.qml")

    for token in (
        "Appearance.regaliaEverywhere",
        "Appearance.zzzEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.regalia.",
        "Appearance.zzz.",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
    ):
        forbid(styled_slider, token, "StyledSlider.qml")
    for token in (
        "property real handleDefaultWidth: abyssStyle ? 12 : 3",
        "property real handlePressedWidth: abyssStyle ? 14 : 1.5",
        "property color highlightColor: Appearance.colors.colPrimary",
        "property color trackColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.18) : Appearance.colors.colSecondaryContainer",
        "property color handleColor: Appearance.colors.colPrimary",
        "property color dotColor: Appearance.colors.colOnSecondaryContainer",
        "property color dotColorHighlighted: Appearance.colors.colOnPrimary",
        "property real trackWidth: abyssStyle ? 4 : configuration",
        "property bool wavy: configuration === StyledSlider.Configuration.Wavy",
        "readonly property bool usesWaveTrack: !abyssStyle && (wavy || configuration === StyledSlider.Configuration.Wavy)",
        "radius: Math.min(width, height) / 2",
    ):
        require(styled_slider, token, "StyledSlider.qml")

    # The outer Settings panel is active Material runtime, not migration
    # compatibility. Keep legacy style renderers out of this container.
    card_start = settings_overlay.index("id: settingsCard")
    card_end = settings_overlay.index("// Prevent clicks from closing", card_start)
    settings_card = settings_overlay[card_start:card_end]
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "RegaliaPlate {",
        "GlassBackground {",
        "ZzzPanelBackdrop {",
    ):
        forbid(settings_card, token, "SettingsOverlay.qml outer Settings card")
    for token in (
        "radius: Appearance.rounding.windowRounding",
        "Appearance.colors.colLayer0",
        "border.width: 0",
        'border.color: "transparent"',
    ):
        require(settings_card, token, "SettingsOverlay.qml outer Settings card")
    forbid(settings_overlay, "Themes · Global Style", "SettingsOverlay.qml")

    identity_start = settings_overlay.index("id: overlayHeaderIdentity")
    search_start = settings_overlay.index("id: overlaySearchContainer", identity_start)
    actions_start = settings_overlay.index("id: overlayHeaderActions", search_start)
    identity_chrome = settings_overlay[identity_start:search_start]
    search_chrome = settings_overlay[search_start:actions_start]
    for source, chrome in (
        ("SettingsOverlay.qml identity chrome", identity_chrome),
        ("SettingsOverlay.qml search chrome", search_chrome),
    ):
        for token in (
            "Appearance.zzzEverywhere",
            "Appearance.regaliaEverywhere",
            "Appearance.angelEverywhere",
            "Appearance.alisEverywhere",
            "Appearance.auroraEverywhere",
        ):
            forbid(chrome, token, source)
    forbid(identity_chrome, "RegaliaControlFace {", "SettingsOverlay.qml identity chrome")
    for token in (
        "radius: width / 2",
        "color: Appearance.colors.colLayer1",
        "border.width: 1",
    ):
        require(identity_chrome, token, "SettingsOverlay.qml identity chrome")
    for token in (
        "? Appearance.colors.colLayer1",
        ": Appearance.colors.colSurfaceContainerLow",
        "border.width: overlaySearchField.activeFocus ? 2 : 1",
        ": Appearance.colors.colOutlineVariant",
    ):
        require(search_chrome, token, "SettingsOverlay.qml search chrome")

    nav_start = settings_overlay.index("id: navColumn")
    nav_end = settings_overlay.index("id: overlayNavActions", nav_start)
    nav_chrome = settings_overlay[nav_start:nav_end]
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "ZzzPlate {",
    ):
        forbid(nav_chrome, token, "SettingsOverlay.qml navigation rail")
    for token in (
        "rippleEnabled: true",
        "buttonRadius: Math.min(width, height) / 2",
        "colBackgroundHover: Appearance.colors.colLayer1Hover",
        "colBackgroundToggled: Appearance.colors.colPrimaryContainer",
        "colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover",
    ):
        require(nav_chrome, token, "SettingsOverlay.qml navigation rail")
    forbid(nav_chrome, "id: sharedNavIndicator", "SettingsOverlay.qml compact navigation rail")

    actions_start = settings_overlay.index("id: overlayNavActions")
    content_start = settings_overlay.index("id: overlayContentContainer", actions_start)
    search_results_start = settings_overlay.index(
        "id: overlayLiveSearch", content_start
    )
    nav_actions = settings_overlay[actions_start:content_start]
    content_chrome = settings_overlay[content_start:search_results_start]
    for source, chrome in (
        ("SettingsOverlay.qml navigation actions", nav_actions),
        ("SettingsOverlay.qml content container", content_chrome),
    ):
        for token in (
            "Appearance.zzzEverywhere",
            "Appearance.regaliaEverywhere",
            "Appearance.angelEverywhere",
            "Appearance.alisEverywhere",
            "Appearance.auroraEverywhere",
        ):
            forbid(chrome, token, source)
    forbid(content_chrome, "GlassBackground {", "SettingsOverlay.qml content container")
    for token in (
        "radius: Appearance.rounding.normal",
        'color: "transparent"',
        "border.width: 0",
        'border.color: "transparent"',
    ):
        require(content_chrome, token, "SettingsOverlay.qml content container")

    # SettingsOverlay is active v1.0 runtime. Once each scoped chrome
    # block has been collapsed to its Material fallback, no shell-wide legacy
    # style predicate may remain anywhere in the file.
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
    ):
        forbid(settings_overlay, token, "SettingsOverlay.qml")

    # Window-mode Settings uses the same Material-only public contract.
    for token in ("ZzzDiagonalPattern {", "ZzzSurfaceAccent {"):
        forbid(settings_window, token, "settings.qml root chrome")
    for token in (
        'color: "transparent"',
        "id: windowBaseSurface",
        'color: root.uiReady ? Appearance.colors.colLayer0 : "transparent"',
    ):
        require(settings_window, token, "settings.qml root chrome")
    window_search_start = settings_window.index("id: searchContainer")
    window_nav_start = settings_window.index("id: navRail", window_search_start)
    window_search = settings_window[window_search_start:window_nav_start]
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
    ):
        forbid(window_search, token, "settings.qml search chrome")
    for token in (
        "? Appearance.colors.colLayer1",
        ": Appearance.colors.colLayer0",
        "border.width: settingsSearchField.activeFocus ? 2 : 1",
        ": Appearance.m3colors.m3outlineVariant",
    ):
        require(window_search, token, "settings.qml search chrome")

    window_nav_start = settings_window.index("id: navCol")
    window_nav_end = settings_window.index("id: navBottomActions", window_nav_start)
    window_nav = settings_window[window_nav_start:window_nav_end]
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "ZzzPlate {",
    ):
        forbid(window_nav, token, "settings.qml navigation rail")
    for token in (
        "rippleEnabled: true",
        "buttonRadius: Math.min(width, height) / 2",
        "colBackgroundHover: Appearance.colors.colLayer1Hover",
        "colBackgroundToggled: Appearance.colors.colPrimaryContainer",
        "colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover",
    ):
        require(window_nav, token, "settings.qml navigation rail")
    forbid(window_nav, "id: sharedNavIndicator", "settings.qml compact navigation rail")

    # The standalone Settings window is now collapsed entirely to its Material
    # fallbacks, not just root/search/navigation chrome.
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
    ):
        forbid(settings_window, token, "settings.qml")

    window_content_start = settings_window.index("id: contentContainer")
    window_results_start = settings_window.index("id: settingsLiveSearch", window_content_start)
    window_content = settings_window[window_content_start:window_results_start]
    for token in (
        'color: "transparent"',
        "radius: Appearance.rounding.windowRounding - root.contentPadding",
        "border.width: 0",
        'border.color: "transparent"',
        "color: Appearance.m3colors.m3outlineVariant",
    ):
        require(window_content, token, "settings.qml content container")

    require(settings_window, "SettingsLiveSearchResults {",
        "settings.qml shared live-search host")
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
    ):
        forbid(settings_live_search_results, token,
            "SettingsLiveSearchResults.qml")
    for token in (
        "radius: Appearance.rounding.normal",
        "color: Appearance.colors.colLayer1",
        "border.width: 1",
        "border.color: Appearance.m3colors.m3outlineVariant",
        "id: resultsList",
        "buttonRadius: Appearance.rounding.small",
        '? Appearance.colors.colLayer2 : "transparent"',
        "colBackgroundHover: Appearance.colors.colLayer2",
    ):
        require(settings_live_search_results, token,
            "SettingsLiveSearchResults.qml")

    # Small active Control Panel leaves are safe to collapse independently of
    # the larger panel shell. Lock them to the Material fallbacks that were
    # already the terminal branches of their old Global Theme conditionals.
    legacy_style_tokens = (
        "Appearance.zzzEverywhere",
        "Appearance.regaliaEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "Appearance.cookieEverywhere",
        "Appearance.zzz.",
        "Appearance.regalia.",
        "Appearance.angel.",
        "Appearance.alis.",
        "Appearance.aurora.",
        "Appearance.cookie.",
    )
    for source, content in (
        ("controlPanel/DateTimeHeader.qml", control_panel_date_time),
        ("controlPanel/WallpaperSection.qml", control_panel_wallpaper),
        ("controlPanel/WeatherSection.qml", control_panel_weather),
        ("controlPanel/SlidersSection.qml", control_panel_sliders),
        ("controlPanel/SystemSection.qml", control_panel_system),
        ("controlPanel/ProfileHeader.qml", control_panel_profile),
        ("controlPanel/QuickActionsSection.qml", control_panel_quick_actions),
        ("controlPanel/MediaSection.qml", control_panel_media),
        ("controlPanel/ControlPanelContent.qml", control_panel_content),
    ):
        for token in legacy_style_tokens:
            forbid(content, token, source)

    # OSK is shared by ii and Waffle. Its Screen Edge attachment and key
    # delivery stay intact while the body/control/keycap chrome uses Material.
    for source, content in (
        ("onScreenKeyboard/OnScreenKeyboard.qml", on_screen_keyboard),
        ("onScreenKeyboard/OskKey.qml", osk_key),
    ):
        for token in legacy_style_tokens:
            forbid(content, token, source)
    for token in (
        "buttonRadius: Appearance.rounding.normal",
        "color: Appearance.colors.colLayer0",
        "border.width: 0",
        'border.color: "transparent"',
        'joinTop: oskRoot.snappedEdge === "top"',
        'joinBottom: oskRoot.snappedEdge === "bottom"',
        "targetY = 0",
        "targetY = ph - kh",
        "Ydotool.releaseAllKeys()",
        "DragHandler {",
    ):
        require(on_screen_keyboard, token, "onScreenKeyboard/OnScreenKeyboard.qml")
    for token in (
        ": Appearance.colors.colLayer1",
        "? Appearance.colors.colOnPrimary",
        ": Appearance.colors.colOnLayer1",
        "PhysicalKeyboardFeedback.pressedKeycodes",
        "Ydotool.press(root.keycode)",
        "Ydotool.release(root.keycode)",
        "Ydotool.releaseShiftKeys()",
    ):
        require(osk_key, token, "onScreenKeyboard/OskKey.qml")
    osk_bindings = {}
    for name in ("colBackground", "colBackgroundToggled", "buttonRadius"):
        binding = re.search(r"^    " + name + r": (.*(?:\n        .*)*)", osk_key, re.M)
        assert binding, f"Onscreen keyboard missing key binding: {name}"
        osk_bindings[name] = binding[1]
    subprocess.run(["node", "-e", r"""
const vm=require('node:vm'),assert=require('node:assert/strict');
const bindings=JSON.parse(process.argv[1]);
for(const panelFamily of ['abyss','ii','waffle'])for(const shape of ['empty','normal'])for(const showPhysicalPress of [true,false]){
 const abyss=panelFamily==='abyss';const inputs={abyss,shape,showPhysicalPress,Appearance:{colors:{colLayer1:'material',colPrimary:'materialAccent'},colLayer1Active:'materialPressed',rounding:{small:8}},AbyssStyle:{surfaceRaised:'abyss',accent:'accent'},ColorUtils:{transparentize:color=>color+'Transparent'},Qt:{alpha:(color,a)=>color+':'+a}};
 const expected=shape==='empty' ? abyss ? 'transparent' : 'materialTransparent' : abyss ? showPhysicalPress ? 'accent:0.22' : 'abyss' : showPhysicalPress ? 'materialPressed' : 'material';
 assert.equal(vm.runInNewContext(bindings.colBackground,inputs),expected);
 assert.equal(vm.runInNewContext(bindings.colBackgroundToggled,inputs),abyss ? 'accent' : 'materialAccent');
 assert.equal(vm.runInNewContext(bindings.buttonRadius,inputs),8);
}
console.log('Onscreen keyboard palette and key shape: PASS (12 cases)');
""", json.dumps(osk_bindings)], check=True)

    # ScreenCorners is interaction-only; physical corner paint belongs to ScreenEdges.
    for token in legacy_style_tokens:
        forbid(screen_corners, token, "screenCorners/ScreenCorners.qml")
    for token in (
        "GlobalStates.toggleSidebarLeft",
        "GlobalStates.toggleSidebarRight",
        "NiriService.isOverviewHotCornerActive",
        "Brightness.getMonitorForScreen",
        "Audio.incrementVolume()",
        "Audio.decrementVolume()",
    ):
        require(screen_corners, token, "screenCorners/ScreenCorners.qml")
    for token in ("RoundCorner", "fakeScreenRounding", "showFakeRounding", "roundingSize",
                  "GlobalStates.openOrbit(", "shouldShowOrbitHotCorner",
                  "Config.options?.orbit"):
        forbid(screen_corners, token, "screenCorners/ScreenCorners.qml")

    # CompactSidebarRightContent is selected by SidebarHost when sidebar.layout
    # is compact. Preserve its connected surface, explicit island skin, rail/nav,
    # controls ordering, dialogs, notifications and quick actions while using
    # only Material Global Theme chrome.
    for token in legacy_style_tokens:
        forbid(compact_sidebar_right_content, token, "sidebarRight/CompactSidebarRightContent.qml")
    for token in (
        "zzzEverywhere", "angelEverywhere", "alisEverywhere", "auroraEverywhere",
        "ZzzPlate {", "ZzzPanelBackdrop {", "AngelPartialBorder {",
    ):
        forbid(compact_sidebar_right_content, token, "sidebarRight/CompactSidebarRightContent.qml")
    for token in (
        "property bool externalConnectedSurface: false",
        "readonly property color connectedSurfaceColor:",
        "readonly property real connectedSurfaceRadius: bg.radius",
        'readonly property bool islandStyle: surfaceDialect === "island"',
        "RicelinSurface {", "visible: !root.externalConnectedSurface && bg.islandStyle",
        "readonly property color colDarkSurface:",
        "ColorUtils.transparentize(Appearance.colors.colLayer1, 0.22)",
        "readonly property color colDarkSurfaceHover:",
        "readonly property color colDarkSurfaceActive:",
        "Appearance.colors.colPrimary", "Appearance.colors.colOnLayer1",
        "Appearance.colors.colSecondaryContainer", "Appearance.colors.colOnSecondaryContainer",
        'joinLeft: root.attachedEdge === "left"', 'joinRight: root.attachedEdge === "right"',
        'topLeftRadius: root.attachedEdge === "left" ? 0 : radius',
        'topRightRadius: root.attachedEdge === "right" ? 0 : radius',
        "property var controlsSectionOrder:",
        "function moveSectionUp(index: int): void", "function moveSectionDown(index: int): void",
        'Config.setNestedValue("sidebar.right.controlsSectionOrder", order)',
        "WheelHandler {",
        'active: (Config.options?.sidebar?.quickToggles?.style ?? "classic") === "classic"',
        "QuickToggleButton {", "AndroidQuickPanel { editMode: root.editMode }",
        "CalendarWidget {", "WeatherDetailWidget {",
        "Notifications.ensureInitialized()",
        "toggled: Notifications.silent ?? false",
        "onClicked: Notifications.toggleSilent()",
        "Network.rescanWifi()", "Bluetooth.defaultAdapter.discovering = true",
        "function doReload()", "function doSettings()",
        '"region", "screenshot"', '"region", "record"', '"region", "ocr"', '"region", "search"',
        '"/usr/bin/hyprpicker"', '["xdg-open", Quickshell.env("HOME")]',
    ):
        require(compact_sidebar_right_content, token, "sidebarRight/CompactSidebarRightContent.qml")

    # Default SidebarRightContent is the primary right-sidebar content tree.
    # Keep connected-edge geometry, explicit island skin, section reordering/
    # elastic section layout, dialogs and quick-toggle routing with Material chrome.
    for token in legacy_style_tokens:
        forbid(sidebar_right_content, token, "sidebarRight/SidebarRightContent.qml")
    for token in (
        "zzzEverywhere",
        "regaliaEverywhere",
        "angelEverywhere",
        "alisEverywhere",
        "auroraEverywhere",
        "RegaliaPlate {",
        "ZzzPanelBackdrop {",
        "AngelPartialBorder {",
    ):
        forbid(sidebar_right_content, token, "sidebarRight/SidebarRightContent.qml")
    for token in (
        "property bool externalConnectedSurface: false",
        "readonly property color connectedSurfaceColor:",
        "readonly property real connectedSurfaceRadius: sidebarRightBackground.radius",
        'readonly property bool islandStyle: surfaceDialect === "island"',
        "RicelinSurface {",
        "visible: sidebarRightBackground.islandStyle",
        "color: root.externalConnectedSurface",
        "Appearance.colors.colLayer1",
        "Appearance.colors.colLayer0",
        "radius: cardStyle",
        'joinLeft: root.attachedEdge === "left"',
        'joinRight: root.attachedEdge === "right"',
        'topLeftRadius: root.attachedEdge === "left" ? 0 : radius',
        'topRightRadius: root.attachedEdge === "right" ? 0 : radius',
        'Config.setNestedValue("sidebar.right.sectionOrder", newOrder)',
        "startSectionDrag(",
        "updateSectionDrag(",
        "endSectionDrag()",
        "Layout.fillHeight: usesElasticPool",
        "Layout.minimumHeight: !isElastic ? -1",
        "readonly property bool contentCollapsed:",
        "radius: Appearance.rounding.verysmall",
        "Appearance.colors.colLayer1Hover",
        "Appearance.colors.colPrimary",
        "Appearance.colors.colOnLayer1",
        "SidebarProfileHeader {",
        "surfaceDialect: sidebarRightBackground.surfaceDialect",
        "QuickSliders {}",
        "ClassicQuickPanel {}",
        "AndroidQuickPanel { editMode: root.editMode }",
        "readonly property bool usesElasticPool: isElastic && !contentCollapsed",
        "BottomWidgetGroup {}",
        "ToggleDialog {",
        "Network.rescanWifi()",
        "Bluetooth.defaultAdapter.discovering = true",
        "root.requestReload()",
        "root.openSettings()",
    ):
        require(sidebar_right_content, token, "sidebarRight/SidebarRightContent.qml")

    # SidebarLeftContent is hosted by the shared physical-edge SidebarHost.
    # Keep its explicit Ricelin island skin, connected-edge geometry and all
    # tab/content behavior while collapsing normal chrome to Material.
    for token in legacy_style_tokens:
        forbid(sidebar_left_content, token, "sidebarLeft/SidebarLeftContent.qml")
    for token in (
        "zzzEverywhere",
        "regaliaEverywhere",
        "angelEverywhere",
        "alisEverywhere",
        "auroraEverywhere",
        "RegaliaPlate {",
        "ZzzPanelBackdrop {",
        "AngelPartialBorder {",
    ):
        forbid(sidebar_left_content, token, "sidebarLeft/SidebarLeftContent.qml")
    for token in (
        "property bool externalConnectedSurface: false",
        "readonly property color connectedSurfaceColor:",
        "readonly property real connectedSurfaceRadius: sidebarLeftBackground.radius",
        'readonly property bool islandStyle: surfaceDialect === "island"',
        "RicelinSurface {",
        "visible: !root.externalConnectedSurface && sidebarLeftBackground.islandStyle",
        "color: root.externalConnectedSurface",
        "Appearance.colors.colLayer1",
        "Appearance.colors.colLayer0",
        "radius: cardStyle",
        'joinLeft: root.attachedEdge === "left"',
        'joinRight: root.attachedEdge === "right"',
        'topLeftRadius: root.attachedEdge === "left" ? 0 : radius',
        'topRightRadius: root.attachedEdge === "right" ? 0 : radius',
        "anchors.topMargin: sidebarPadding - 4",
        "spacing: sidebarPadding",
        "transparent: false",
        "radius: Appearance.rounding.normal",
        "color: Appearance.colors.colLayer1",
        "border.width: 0",
        'border.color: "transparent"',
        "radius: Appearance.rounding.small",
        'Config.setNestedValue("sidebar.left.tabOrder", order)',
        "Ai.ensureInitialized()",
        "SwipeView {",
        "interactive: !root.tabEditMode",
        "active: SwipeView.isCurrentItem || SwipeView.isNextItem || SwipeView.isPreviousItem",
        "AiChat {}",
        "Translator {}",
        "Anime {}",
        "AnimeScheduleView {}",
        'case "newspaper": return newsComp',
        "NewsView {}",
        "ToolsView {}",
        'case "build": return toolsComp',
    ):
        require(sidebar_left_content, token, "sidebarLeft/SidebarLeftContent.qml")

    forbid(sidebar_left_content, 'case "library_music": return musicComp',
           "sidebarLeft/SidebarLeftContent.qml")
    require(dashboard_content, "DashboardMusic {",
            "dashboard/DashboardContent.qml")

    # VerticalBarContent owns the supported ii vertical Hug chrome. Keep its
    # compositor blur and connected BarContextMenu behavior while ensuring
    # retired Islands/Card/Floating routing cannot become an intermediate path.
    for token in legacy_style_tokens:
        forbid(vertical_bar_content, token, "verticalBar/VerticalBarContent.qml")
    for token in (
        "root.angelEverywhere",
        "root.alisEverywhere",
        "root.auroraEverywhere",
        "root.zzzEverywhere",
        "AngelPartialBorder {",
        "appearanceStyle",
        "isIslands",
        "cardStyleEverywhere",
        "floatingStyle",
    ):
        forbid(vertical_bar_content, token, "verticalBar/VerticalBarContent.qml")
    for token in (
        'Appearance.useCompositorBlur("bar", root.nativeBlurTopology)',
        "readonly property color separatorColor: Appearance.colors.colOutlineVariant",
        "Appearance.colors.colLayer0",
        "Appearance.colors.colLayer1",
        "border.color: Appearance.colors.colLayer0Border",
        "Bar.BarContextMenu {",
        "barContextMenu.requestOpen()",
        "Bar.BarTaskbar {",
        "Bar.SysTray {",
        "buttonRadius: Appearance.rounding.full",
        "colBackgroundToggled: Appearance.colors.colSecondaryContainer",
        "colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover",
        "colRippleToggled: Appearance.colors.colSecondaryContainerActive",
        "GlobalStates.toggleSidebarLeft(root.screen?.name ?? \"\")",
        "GlobalStates.toggleSidebarRight(root.screen?.name ?? \"\")",
        "GlobalStates.toggleOverview(root.screen?.name ?? \"\")",
        "Audio.decrementVolume()",
        "Audio.incrementVolume()",
        "root.brightnessMonitor.setBrightness",
    ):
        require(vertical_bar_content, token, "verticalBar/VerticalBarContent.qml")

    # VerticalBar clock/date leaves are shared by both taskbar layouts.
    # Keep DateTime formatting/layout intact while locking text/stroke chrome to Material.
    for source, content in (
        ("verticalBar/VerticalClockWidget.qml", vertical_clock_widget),
        ("verticalBar/VerticalDateWidget.qml", vertical_date_widget),
    ):
        for token in legacy_style_tokens:
            forbid(content, token, source)
    for token in (
        "DateTime.timeDisplay.split(/[: ]/)",
        "color: Appearance.colors.colOnLayer1",
        'text: modelData.padStart(2, "0")',
    ):
        require(vertical_clock_widget, token, "verticalBar/VerticalClockWidget.qml")
    for token in (
        "DateTime.clock.date",
        "strokeColor: Appearance.colors.colSubtext",
        "color: Appearance.colors.colOnLayer1",
        "dayOfMonth",
        "monthOfYear",
    ):
        require(vertical_date_widget, token, "verticalBar/VerticalDateWidget.qml")

    # Overview cleanup is component-by-component. SearchBar is an active leaf
    # owned by SearchWidget; lock its toolbar chrome to the existing Material
    # fallback while keeping SongRec retired (MUSIC-R01).
    for token in legacy_style_tokens:
        forbid(overview_search_bar, token, "overview/SearchBar.qml")
    forbid(overview_search_bar, "RegaliaControlFace {", "overview/SearchBar.qml")
    forbid(overview_search_bar, "SongRec", "overview/SearchBar.qml")
    for token in (
        "colText: Appearance.colors.colOnSurfaceVariant",
        'colBackground: "transparent"',
        'colBackgroundHover: "transparent"',
        'colRipple: "transparent"',
        "rippleEnabled: false",
        "pressScaleEnabled: false",
        "stateTransitionsEnabled: false",
        "position: \"top\"",
        'text: "image_search"',
    ):
        require(overview_search_bar, token, "overview/SearchBar.qml")
    forbid(overview_search_bar, "background: Item {", "overview/SearchBar.qml")
    forbid(overview_search_bar, "MaterialShape {", "overview/SearchBar.qml")

    # Search result delegates are active for both compositor paths. Preserve
    # execution/keyboard/drag semantics while locking their row chrome to Material.
    for token in legacy_style_tokens:
        forbid(overview_search_item, token, "overview/SearchItem.qml")
    for token in (
        "readonly property color normalTextColor: Appearance.colors.colOnLayer1",
        "readonly property color selectedTextColor: Appearance.colors.colOnLayer1",
        "readonly property color selectedBackgroundColor: root.abyssStyle ? Qt.alpha(Appearance.colors.colLayer2Base,AbyssStyle.cardOpacity) : Appearance.colors.colLayer1",
        "readonly property color hoverBackgroundColor: root.abyssStyle ? Qt.alpha(Appearance.colors.colLayer2Base,AbyssStyle.cardOpacity) : Appearance.colors.colLayer1",
        "readonly property color pressedBackgroundColor: root.abyssStyle ? Qt.alpha(Appearance.colors.colLayer2Base,AbyssStyle.cardOpacity) : Appearance.colors.colLayer1Hover",
        "readonly property color activeRippleColor: Appearance.colors.colLayer1Hover",
        "buttonRadius: Appearance.rounding.normal",
        "radius: Appearance.rounding.full",
        "buttonRadius: Appearance.rounding.full",
        'Drag.keys: ["application/x-alis-desktop-entry"]',
        "root.entry.execute()",
    ):
        require(overview_search_item, token, "overview/SearchItem.qml")

    # SearchWidget owns the cross-compositor search surface. Keep the explicit
    # supported IslandPanel skin, but remove retired shell-wide Global Theme
    # plates/predicates from the normal Material surface.
    for token in legacy_style_tokens:
        forbid(overview_search_widget, token, "overview/SearchWidget.qml")
    for token in (
        "RegaliaPlate {",
        "ZzzGraphicPlate {",
        "ZzzPanelBackdrop {",
        "root.zzzEverywhere",
    ):
        forbid(overview_search_widget, token, "overview/SearchWidget.qml")
    for token in (
        "property bool embeddedSurface: false",
        "readonly property real collapsedHeight:",
        "readonly property bool islandStyle:",
        "RicelinSurface {",
        "visible: !root.embeddedSurface && root.islandStyle",
        'fallbackColor: root.embeddedSurface || root.islandStyle',
        '? "transparent"',
        ": Appearance.colors.colBackgroundSurfaceContainer",
        "&& !root.embeddedSurface && !root.islandStyle",
        "border.width: 0",
        "border.color: Appearance.colors.colLayer0Border",
        "Layout.leftMargin: root.embeddedSurface ? 0 : 10",
        "Layout.rightMargin: root.embeddedSurface ? 0 : 4",
        "Layout.topMargin: verticalPadding",
        "Layout.bottomMargin: verticalPadding",
        "topMargin: 10",
        "bottomMargin: 10",
        "spacing: 2",
        "color: Appearance.colors.colOutlineVariant",
        "ActionModeView {",
        "delegate: SearchItem {",
        "onApplicationDragChanged: active => root.applicationDragActive = active",
    ):
        require(overview_search_widget, token, "overview/SearchWidget.qml")

    # ActionModeView owns the slash-command/category/package result surface.
    # Keep action/package execution and keyboard navigation while collapsing its
    # row/badge/footer presentation to the Material terminal branches.
    for token in legacy_style_tokens:
        forbid(overview_action_mode_view, token, "overview/ActionModeView.qml")
    forbid(overview_action_mode_view, "root.zzzEverywhere", "overview/ActionModeView.qml")
    for token in (
        "spacing: 2",
        "readonly property color normalTextColor: Appearance.colors.colOnLayer1",
        "readonly property color selectedTextColor: Appearance.colors.colOnLayer1",
        "Appearance.colors.colSubtext",
        "readonly property color selectedBackgroundColor: Appearance.colors.colLayer1",
        "readonly property color hoverBackgroundColor: Appearance.colors.colLayer1",
        "readonly property color pressedBackgroundColor: Appearance.colors.colLayer1Hover",
        "property int horizontalMargin: 10",
        "property int buttonHorizontalPadding: 10",
        "property int buttonVerticalPadding: 6",
        "buttonRadius: Appearance.rounding.normal",
        "colRipple: Appearance.colors.colLayer1Hover",
        "radius: Appearance.rounding.full",
        "ColorUtils.transparentize(Appearance.colors.colPrimary, 0.3)",
        "Appearance.colors.colLayer2Hover",
        "Appearance.colors.colSecondaryContainer",
        "Appearance.colors.colOnSecondaryContainer",
        "ColorUtils.transparentize(Appearance.colors.colPrimary, 0.2)",
        "GlobalActions.fuzzyQuery(root.query)",
        "PackageSearch.search(root.packageQuery)",
        "PackageSearch.removePackage(name)",
        "PackageSearch.installPackage(name, pkg?.isAur ?? false)",
        "capturedAction.execute(capturedArgs)",
        "root._executePackageActionStatic(capturedPkg, capturedIsRemove)",
    ):
        require(overview_action_mode_view, token, "overview/ActionModeView.qml")

    # The All Apps grid is an active Overview leaf. Its app model, category
    # grouping, launch and drag behavior stay intact while chrome uses only the
    # terminal Material colors/radii.
    for token in legacy_style_tokens:
        forbid(overview_all_apps_grid, token, "overview/OverviewAllAppsGrid.qml")
    forbid(overview_all_apps_grid, "ZzzPanelBackdrop {", "overview/OverviewAllAppsGrid.qml")
    for token in (
        "readonly property int gridWidth: 760",
        "readonly property color headerAccentColor: Appearance.colors.colPrimary",
        "readonly property color surfaceColor: Appearance.colors.colLayer1",
        "readonly property color surfaceHoverColor: Appearance.colors.colLayer1Hover",
        "readonly property color surfaceActiveColor: Appearance.colors.colLayer1Active",
        "readonly property color surfaceBorderColor: Appearance.colors.colLayer0Border",
        "radius: Appearance.rounding.large",
        "wallpaperBackdropEnabled: root.panelVisible",
        "border.width: 1",
        "anchors.margins: 18",
        'text: Translation.tr("All apps")',
        "color: Appearance.colors.colSubtext",
        "radius: Appearance.rounding.normal",
        "color: Appearance.colors.colLayer2",
        "buttonRadius: Appearance.rounding.normal",
        "buttonRadiusPressed: Appearance.rounding.small",
        "AppSearch.launchEntry(entry)",
        'Drag.keys: ["application/x-alis-desktop-entry"]',
    ):
        require(overview_all_apps_grid, token, "overview/OverviewAllAppsGrid.qml")

    # DashboardContent reuses the established Material shell background. It must
    # not grow a Dashboard-specific wallpaper/global-style renderer.
    for token in (
        "Appearance.zzzEverywhere",
        "Appearance.angelEverywhere",
        "Appearance.alisEverywhere",
        "Appearance.auroraEverywhere",
        "ZzzPlate {",
        "ZzzPanelBackdrop {",
        "ColorQuantizer {",
        "AdaptedMaterialScheme {",
        "id: blurredWallpaper",
        "useWallpaperBackdrop",
    ):
        forbid(dashboard_content, token, "dashboard/DashboardContent.qml")
    for token in (
        'color: root.embeddedSurface ? "transparent" : Appearance.colors.colLayer0',
        'radius: root.embeddedSurface ? 0 : Appearance.rounding.large',
        "border.width: 0",
        'border.color: "transparent"',
        "StyledRectangularShadow {",
        "Qt.alpha(Appearance.m3colors.m3shadow,",
    ):
        require(dashboard_content, token, "dashboard/DashboardContent.qml")

    # Launcher Dashboard is a lean connected host around shared DashboardContent
    # plus the embedded bottom SearchWidget.
    for token in legacy_style_tokens:
        forbid(overview_dashboard, token, "overview/OverviewDashboard.qml")
    for token in (
        "import qs.modules.dashboard",
        "DashboardContent {",
        "SearchWidget {",
        "embeddedSurface: true",
        "Config.options?.dashboard?.widthRatio",
        "Config.options?.dashboard?.heightRatio",
        "property real dashboardProgress: 1",
        "height: root.embeddedSurface ? Math.max(0, root.height - root.editToolbarReserve) : root.presentingSearch",
        "y: root.embeddedSurface ? 0 : (1 - root.revealProgress) * dashContainer.height",
        "opacity: root.dashboardOpacity",
        "resultsOpacity: root.searchResultsOpacity",
        "ConnectedSurfaceAbyssEdgeSurface {",
        'edge: "bottom"',
        "ownerThickness: root.attachmentThickness",
        "root.height + root.attachmentThickness",
        "fillColor: Appearance.colors.colLayer0",
        "color: root.embeddedSurface || root.directBottomAttachment",
        "StyledRectangularShadow {",
        "blur: root.screenEdgeShadowSize",
        "bottomLeftRadius: root.directBottomAttachment ? 0 : radius",
        "bottomRightRadius: root.directBottomAttachment ? 0 : radius",
        "SurfaceMotion.duration",
        "SurfaceMotion.easingType",
    ):
        require(overview_dashboard, token, "overview/OverviewDashboard.qml")

    for token in ("ConnectedSurfaceJoinFlares", "joinFlareRadius"):
        forbid(overview_dashboard, token, "overview/OverviewDashboard.qml")
        forbid(on_screen_keyboard, token, "onScreenKeyboard/OnScreenKeyboard.qml")

    # Niri's Overview workspace/window path is the primary compositor surface.
    # Its workspace/background/context-menu chrome is Material-only while Niri
    # workspace switching, window drag/focus/close and preview capture stay intact.
    for token in legacy_style_tokens:
        forbid(overview_niri_widget, token, "overview/OverviewNiriWidget.qml")
    for token in (
        "property color activeBorderColor: Appearance.colors.colSecondary",
        "StyledRectangularShadow {",
        "target: overviewBackground",
        "radius: root.embeddedSurface ? 0 : (Appearance.rounding.large + padding)",
        'color: root.embeddedSurface ? "transparent"',
        "border.width: root.embeddedSurface ? 0 : 1",
        "ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.68)",
        "? Appearance.colors.colBackgroundSurfaceContainer",
        "Appearance.colors.colBackgroundSurfaceContainer, 0.3",
        "defaultWorkspaceColor, Appearance.colors.colLayer1Hover, 0.1",
        "property color hoveredBorderColor: Appearance.colors.colLayer2Hover",
        "property real largeWorkspaceRadius: Appearance.rounding.large",
        "property real smallWorkspaceRadius: Appearance.rounding.verysmall",
        "ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.74)",
        "Appearance.colors.colOnLayer1, 0.7",
        "readonly property real windowRadius: Appearance.rounding.small",
        "radius: Appearance.rounding.normal",
        "color: Appearance.colors.colLayer4",
        "ColorUtils.transparentize(Appearance.colors.colOutline, 0.5)",
        "buttonRadius: Appearance.rounding.small",
        "colBackgroundHover: Appearance.colors.colLayer4Hover",
        "NiriService.switchToWorkspaceById(nextWorkspace.id)",
        "NiriService.moveWindowToWorkspaceById(\n                                        draggedWindowId, targetWorkspace, false)",
        "NiriService.focusWindow(draggedWindowId)",
        "NiriService.closeWindow(windowItem.windowId)",
        "WindowPreviewService.getPreviewUrl",
    ):
        require(overview_niri_widget, token, "overview/OverviewNiriWidget.qml")

    # Hyprland OverviewWidget keeps its compositor behavior while its visual
    # Global Theme branches collapse to the terminal Material fallbacks.
    for token in legacy_style_tokens:
        forbid(overview_widget, token, "overview/OverviewWidget.qml")
    for token in (
        "property color activeBorderColor: Appearance.colors.colSecondary",
        "property real largeWorkspaceRadius: Appearance.rounding.large",
        "property real smallWorkspaceRadius: Appearance.rounding.verysmall",
        'color: root.embeddedSurface ? "transparent"',
        "border.width: root.embeddedSurface ? 0 : 1",
        "ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.68)",
        "Appearance.colors.colSurfaceContainerHigh, 0.8",
        "defaultWorkspaceColor, Appearance.colors.colLayer1Hover, 0.1",
        "property color hoveredBorderColor: Appearance.colors.colLayer2Hover",
        "ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.74)",
        "Appearance.colors.colOnLayer1, 0.7",
        "property real minRadius: Appearance.rounding.small",
    ):
        require(overview_widget, token, "overview/OverviewWidget.qml")

    forbid(
        control_panel_date_time,
        "AngelPartialBorder {",
        "controlPanel/DateTimeHeader.qml",
    )
    for token in (
        "radius: Appearance.rounding.normal",
        "color: Appearance.colors.colLayer1",
        "border.width: 0",
        "color: Appearance.colors.colPrimary",
        "color: Appearance.colors.colOnLayer1",
        "color: Appearance.colors.colSubtext",
        "DateTime.clock.date",
    ):
        require(control_panel_date_time, token, "controlPanel/DateTimeHeader.qml")

    for token in (
        "radiusOverride: islandSkin ? -1 : Appearance.rounding.normal",
        "color: Appearance.colors.colPrimary",
        "color: Appearance.colors.colOnLayer1",
        "buttonRadius: Appearance.rounding.full",
        "colBackgroundHover: Appearance.colors.colLayer2Hover",
        "color: Appearance.colors.colSubtext",
        "radius: Appearance.rounding.small",
        "onClicked: Wallpapers.randomFromCurrentFolder()",
        'GlobalActions.runLauncher(["wallpaperSelector", "toggle"])',
    ):
        require(control_panel_wallpaper, token, "controlPanel/WallpaperSection.qml")

    forbid(control_panel_weather, "AngelPartialBorder {", "controlPanel/WeatherSection.qml")
    for token in (
        "radiusOverride: islandSkin ? -1 : Appearance.rounding.normal",
        "color: Appearance.colors.colPrimary",
        "color: Appearance.colors.colOnLayer1",
        "buttonRadius: Appearance.rounding.full",
        "colBackgroundHover: Appearance.colors.colLayer2Hover",
        "color: Appearance.colors.colSubtext",
        'onClicked: Config.setNestedValue("waffles.widgetsPanel.weatherHideLocation", !root.hideLocation)',
        "onClicked: Weather.forceRefresh()",
    ):
        require(control_panel_weather, token, "controlPanel/WeatherSection.qml")

    forbid(control_panel_sliders, "AngelPartialBorder {", "controlPanel/SlidersSection.qml")
    for token in (
        "radiusOverride: islandSkin ? -1 : Appearance.rounding.normal",
        "compactSurface: true",
        "property var brightnessMonitor: screen ? Brightness.getMonitorForScreen(screen) : null",
    ):
        require(control_panel_sliders, token, "controlPanel/SlidersSection.qml")

    forbid(control_panel_system, "AngelPartialBorder {", "controlPanel/SystemSection.qml")
    for token in (
        "radiusOverride: islandSkin ? -1 : Appearance.rounding.small",
        "readonly property real _contentHPad: root.compactMode ? 5 : 6",
        'label: "CPU"',
        'label: "RAM"',
        'label: "BAT"',
        "Appearance.colors.colError",
        "Appearance.colors.colSuccess",
        "Appearance.colors.colPrimary",
        "color: Appearance.colors.colSubtext",
        "color: Appearance.colors.colOnLayer1",
        "implicitHeight: root.compactMode ? 3 : 4",
        "color: Appearance.colors.colLayer2",
    ):
        require(control_panel_system, token, "controlPanel/SystemSection.qml")
    for token in ("id: segRail", "visible: Appearance.zzzEverywhere"):
        forbid(control_panel_system, token, "controlPanel/SystemSection.qml")

    for token in ("CookieFace {", "visible: Appearance.cookieEverywhere"):
        forbid(control_panel_profile, token, "controlPanel/ProfileHeader.qml")
    for token in (
        "border.color: Appearance.colors.colPrimary",
        "color: Appearance.colors.colLayer2",
        "color: Appearance.colors.colPrimary",
        "color: Appearance.colors.colOnLayer0",
        "buttonRadius: Appearance.rounding.full",
        "colBackgroundHover: Appearance.colors.colLayer2Hover",
        "color: Appearance.colors.colError",
        "color: Appearance.colors.colSubtext",
        'AppLauncher.launch("manageUser")',
        'Quickshell.shellPath("scripts/alis")',
        "GlobalStates.sessionOpen = true",
    ):
        require(control_panel_profile, token, "controlPanel/ProfileHeader.qml")

    for token in ("AngelPartialBorder {", "RegaliaControlFace {", "CookieFace {"):
        forbid(control_panel_quick_actions, token, "controlPanel/QuickActionsSection.qml")
    for token in (
        "radiusOverride: islandSkin ? -1 : Appearance.rounding.normal",
        "anchors.margins: root.compactMode ? 6 : 8",
        "rowSpacing: root.compactMode ? 4 : 6",
        "Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1",
        "radius: Appearance.rounding.small",
        "Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover",
        "Appearance.colors.colPrimary : Appearance.colors.colLayer2",
        "border.width: 0",
        "border.color: Appearance.colors.colPrimary",
        "Audio.toggleMute()",
        "Audio.toggleMicMute()",
        "Network.toggleWifi()",
        "BluetoothStatus.toggle()",
        "Idle.toggleInhibit()",
        "GameMode.toggle()",
        "GlobalStates.openRegionScreenshot()",
        "GlobalStates.sessionOpen = true",
    ):
        require(control_panel_quick_actions, token, "controlPanel/QuickActionsSection.qml")

    forbid(control_panel_media, "AngelPartialBorder {", "controlPanel/MediaSection.qml")
    for token in (
        "CavaProcess {",
        "active: root.visible && root.hasPlayer && root.effectiveIsPlaying && GlobalStates.controlPanelOpen",
        "ColorQuantizer {",
        "AdaptedMaterialScheme {",
        "radius: Appearance.rounding.normal",
        "color: root.blendedColors?.colLayer0 ?? Appearance.colors.colLayer0",
        "border.width: 0",
        "opacity: root.displayedArtFilePath !== \"\" ? 0.5 : 0",
        "blur: 0.15",
        "saturation: 0.3",
        "WaveVisualizer {",
        "radius: Appearance.rounding.small",
        "highlightColor: root.blendedColors?.colPrimary",
        "trackColor: root.blendedColors?.colSecondaryContainer",
        "buttonRadius: Appearance.rounding.full",
        "onClicked: MprisController.previous()",
        "onClicked: MprisController.togglePlaying()",
        "onClicked: MprisController.next()",
        "onMoved: root.player.position = value * root.player.length",
        "running: root.positionTickerActive",
    ):
        require(control_panel_media, token, "controlPanel/MediaSection.qml")
    for token in (
        "readonly property color jiraCol",
        "Appearance.alis.",
        "Appearance.angel.",
        "Appearance.aurora.",
        "Appearance.zzz.",
    ):
        forbid(control_panel_media, token, "controlPanel/MediaSection.qml")

    for token in (
        "RegaliaPlate {",
        "ZzzPlate {",
        "ZzzPanelBackdrop {",
        "ColorQuantizer {",
        "AdaptedMaterialScheme {",
        "id: blurredWallpaper",
        "useWallpaperBackdrop",
    ):
        forbid(control_panel_content, token, "controlPanel/ControlPanelContent.qml")
    for token in (
        "property int _entranceCascade: GlobalStates.controlPanelOpen ? 99 : -1",
        "interval: 45",
        "root._entranceCascade = -1",
        "entranceCascadeTimer.start()",
        "visible: !root.embeddedSurface && !root.islandStyle && !Appearance.gameModeMinimal",
        "RicelinSurface {",
        "visible: !root.embeddedSurface && root.islandStyle",
        'color: root.embeddedSurface || root.islandStyle ? "transparent" : Appearance.colors.colLayer0',
        "Appearance.rounding.large",
        "border.width: root.embeddedSurface || root.islandStyle ? 0 : 1",
        "border.color: Appearance.colors.colLayer0Border",
        "active: root.showMediaSection",
        "active: root.showWallpaperSection",
        "active: root.showWeatherSection",
        "active: root.showSystemSection",
        "active: root.showSlidersSection",
        "active: root.showQuickActionsSection",
        "asynchronous: true",
        "opacity: root._entranceCascade >= 7 ? 1 : 0",
        "flickable.contentY = Math.max(0, Math.min(",
    ):
        require(control_panel_content, token, "controlPanel/ControlPanelContent.qml")

    print("Material-only global style contract: PASS")


if __name__ == "__main__":
    main()
