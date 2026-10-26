# Notifications

How notifications work in Alis, from arrival to display to history.

## How it works

Alis implements the freedesktop notification spec via Quickshell's notification module. Apps send notifications over D-Bus, Alis receives them, shows popups, and stores history.

When Alis starts, it tells the session it's the notification daemon. If another notification daemon is running (mako, dunst, etc.), Alis's ConflictKiller handles the conflict on startup.

## Popups

New notifications appear as popup toasts. Each popup stays visible for 7 seconds by default, then moves to history.

Popup behavior depends on context:

- **Normal**: popup appears, auto-dismisses after timeout
- **Notification center open**: popups are suppressed while history is already visible
- **GameMode active**: popups suppressed if `suppressNotifications` is enabled
- **Critical urgency**: popup stays until manually dismissed

### Rate limiting

Max 20 notifications per second. Spam from misbehaving apps gets throttled instead of flooding your screen.

## Do Not Disturb

Toggle DND from:
- Right sidebar toggle (ii)
- Action center toggle (waffle)
- IPC: `alis notifications toggleSilent`

When DND is on, new notifications still arrive and get stored in history. They just don't show popups.

## Quiet hours

A daily window that suppresses popups without you remembering to toggle DND. Enable it in Settings › Interface › Notifications, or in the config:

```json
"notifications": {
  "quietHours": {
    "enable": true,
    "start": "22:00",
    "end": "08:00"
  }
}
```

Times are 24-hour `HH:MM`. A window whose `end` is earlier than its `start` wraps past midnight, so the example above runs from 10 PM to 8 AM. An unparseable time disables the window rather than guessing.

Like DND, quiet hours only holds back popups — notifications still reach the history.

## History

Notifications persist across shell restarts. History is stored at:

```
~/.local/state/quickshell/user/notifications.json
```

View history in the standalone Notification Center (ii) or the Waffle notification center. Notifications are grouped by app name for easier scanning.

On Material ii, dwell at the physical bottom-right corner to reveal the center. The same surface can be opened explicitly through Settings preview, development navigation, or IPC. Hover ownership is handled by `ScreenCorners.qml`, so Orbit/native hot-corner conflicts and the legacy sidebar corner trigger do not stack competing input windows.

Once more than three notifications are stored, a search field appears above the list. It matches on app name, summary and body, and hides groups with no match.

### Grouping

Notifications from the same app are collected into groups. Each group shows:
- App name and icon
- Number of notifications
- Whether any are critical
- Most recent notification time

The standalone Material center starts history groups expanded so available canvas is used for readable content; overflow scrolls instead of pre-collapsing cards. You can still collapse a group explicitly when you want a denser view.

## Actions

If a notification includes action buttons (like "Reply" or "Open"), they appear on the notification. Clicking an action triggers the corresponding D-Bus callback to the source app.

## Display

### Material ii

Transient popup toasts and notification history are separate surfaces. Popups use the configured `notifications.position`; history lives in the bottom-right Notification Center and is no longer rendered in either normal or compact Right Sidebar.

The center has grouped history, search, mark-read, dismiss-all and DND controls. Settings › Interface › Notifications configures enablement, hover dwell/close grace, corner hit size, popup dimensions, mark-read-on-open behavior and fullscreen access. Because the current backend represents unread state with the transient popup flag, mark-read-on-open also retracts those transient copies. Settings › Monitor Visibility has a dedicated Notification Center output list, independent from transient popup outputs.

### Waffle

Popups appear at the bottom-right (Windows 11 style). The notification center (`wNotificationCenter`) is a panel that slides from the right edge with grouped notification history and an integrated calendar.

## IPC

```bash
alis notification-center toggle     # Toggle the active family's center
alis notification-center open       # Open notification history
alis notification-center close      # Close notification history
alis notification-center status     # Report family/open/output state
alis notifications clearAll         # Clear all notifications
alis notifications toggleSilent     # Toggle DND
```

## Troubleshooting

**No notifications showing up**: check if another notification daemon is running (`pidof mako dunst`). Alis's ConflictKiller should handle this, but if it doesn't, kill the other daemon manually.

**Notifications from specific apps missing**: some apps send notifications to specific categories or with transient hints. Check `alis logs` for notification-related messages.
