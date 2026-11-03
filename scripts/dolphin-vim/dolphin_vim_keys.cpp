#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEvent>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLineEdit>
#include <QMetaObject>
#include <QObject>
#include <QPlainTextEdit>
#include <QPoint>
#include <QTextEdit>
#include <QTimer>
#include <QUrl>
#include <QWidget>
#include <QWindow>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <errno.h>

namespace {

bool isTextEditingWidget(QWidget *w) {
    for (QWidget *cur = w; cur != nullptr; cur = cur->parentWidget()) {
        if (qobject_cast<QLineEdit *>(cur) ||
            qobject_cast<QTextEdit *>(cur) ||
            qobject_cast<QPlainTextEdit *>(cur) ||
            cur->inherits("KItemListRoleEditor") ||
            cur->inherits("Konsole::TerminalDisplay") ||
            cur->inherits("QAbstractSpinBox")) {
            return true;
        }
    }
    return false;
}

bool isKItemListContainer(QWidget *w) {
    if (!w) {
        return false;
    }
    return w->inherits("KItemListContainer") || w->objectName() == QLatin1String("KItemListContainer");
}

bool hasActiveInlineEditor(QWidget *container) {
    const auto children = container->findChildren<QWidget *>();
    for (QWidget *child : children) {
        if (child && child->isVisible() &&
            (child->inherits("KItemListRoleEditor") ||
             qobject_cast<QLineEdit *>(child) ||
             qobject_cast<QTextEdit *>(child) ||
             qobject_cast<QPlainTextEdit *>(child))) {
            return true;
        }
    }
    return false;
}

bool triggerWindowShortcut(QWidget *focusW, const QKeySequence &seq, const char *actionName = nullptr) {
    if (!focusW || !focusW->window()) {
        return false;
    }
    QWidget *win = focusW->window();

    auto collectActions = [&]() {
        QList<QAction *> result;
        for (QWidget *cur = focusW; cur != nullptr; cur = cur->parentWidget()) {
            for (QAction *act : cur->actions()) {
                if (act && !result.contains(act)) {
                    result.append(act);
                }
            }
        }
        for (QAction *act : win->findChildren<QAction *>()) {
            if (act && !result.contains(act)) {
                result.append(act);
            }
        }
        const auto widgets = win->findChildren<QWidget *>();
        for (QWidget *w : widgets) {
            if (!w) {
                continue;
            }
            for (QAction *act : w->actions()) {
                if (act && !result.contains(act)) {
                    result.append(act);
                }
            }
        }
        return result;
    };

    const QList<QAction *> allActions = collectActions();

    if (actionName) {
        const QLatin1String targetName(actionName);
        for (QAction *act : allActions) {
            if (act->objectName() == targetName && act->isEnabled()) {
                act->trigger();
                return true;
            }
        }
    }

    if (!seq.isEmpty()) {
        for (QAction *act : allActions) {
            if (!act->isEnabled()) {
                continue;
            }
            const auto shortcuts = act->shortcuts();
            for (const QKeySequence &sc : shortcuts) {
                if (sc == seq) {
                    act->trigger();
                    return true;
                }
            }
        }
    }

    if (actionName) {
        for (QWidget *cur = focusW; cur != nullptr; cur = cur->parentWidget()) {
            if (cur->inherits("DolphinView")) {
                if (std::strcmp(actionName, "go_up") == 0 &&
                    QMetaObject::invokeMethod(cur, "goUpRequested")) {
                    return true;
                }
                if (std::strcmp(actionName, "go_back") == 0 &&
                    QMetaObject::invokeMethod(cur, "goBackRequested")) {
                    return true;
                }
                if (std::strcmp(actionName, "go_forward") == 0 &&
                    QMetaObject::invokeMethod(cur, "goForwardRequested")) {
                    return true;
                }
            }
        }
    }

    return false;
}

QWidget *findDolphinViewAncestor(QWidget *w) {
    for (QWidget *cur = w; cur != nullptr; cur = cur->parentWidget()) {
        if (cur->inherits("DolphinView") || cur->objectName() == QLatin1String("DolphinView")) {
            return cur;
        }
    }
    return nullptr;
}

QWidget *findSplitViewScope(QWidget *currentContainer) {
    if (!currentContainer) {
        return nullptr;
    }
    QWidget *scope = nullptr;
    for (QWidget *cur = currentContainer; cur != nullptr; cur = cur->parentWidget()) {
        if (cur->inherits("DolphinTabPage") || cur->inherits("QSplitter")) {
            scope = cur;
            if (cur->inherits("DolphinTabPage")) {
                break;
            }
        }
    }
    return scope ? scope : currentContainer->window();
}

QList<QWidget *> collectOtherSplitContainers(QWidget *currentContainer) {
    QList<QWidget *> result;
    QWidget *scope = findSplitViewScope(currentContainer);
    if (!scope) {
        return result;
    }
    const auto allWidgets = scope->findChildren<QWidget *>();
    for (QWidget *cand : allWidgets) {
        if (cand && cand != currentContainer && isKItemListContainer(cand) &&
            cand->isVisible() && cand->width() > 0 && cand->height() > 0) {
            if (!result.contains(cand)) {
                result.append(cand);
            }
        }
    }
    return result;
}

bool switchSplitViewPane(QWidget *currentContainer, int key) {
    QWidget *scope = findSplitViewScope(currentContainer);
    if (!scope) {
        return false;
    }
    const QList<QWidget *> others = collectOtherSplitContainers(currentContainer);
    if (others.isEmpty()) {
        return false;
    }

    const QPoint curCenter = currentContainer->mapTo(scope, currentContainer->rect().center());
    QWidget *bestTarget = nullptr;
    int bestDist = INT_MAX;

    for (QWidget *cand : others) {
        const QPoint candCenter = cand->mapTo(scope, cand->rect().center());
        const int dx = candCenter.x() - curCenter.x();
        const int dy = candCenter.y() - curCenter.y();
        bool matchesDirection = false;
        int dist = std::abs(dx) + std::abs(dy);

        switch (key) {
            case Qt::Key_H:
                matchesDirection = (dx < -8);
                break;
            case Qt::Key_L:
                matchesDirection = (dx > 8);
                break;
            case Qt::Key_K:
                matchesDirection = (dy < -8);
                break;
            case Qt::Key_J:
                matchesDirection = (dy > 8);
                break;
            default:
                break;
        }

        if (matchesDirection && dist < bestDist) {
            bestDist = dist;
            bestTarget = cand;
        }
    }

    // If the split is on the perpendicular axis (e.g. pressing Alt+J/K in a left-right split),
    // or only one other split pane exists, switch to the other pane.
    if (!bestTarget) {
        bestTarget = others.first();
    }

    if (!bestTarget) {
        return false;
    }

    QWidget *targetView = findDolphinViewAncestor(bestTarget);
    QWidget *currentView = findDolphinViewAncestor(currentContainer);

    if (targetView) {
        const QMetaObject *mo = targetView->metaObject();
        if (mo && mo->indexOfMethod("activate()") >= 0) {
            QMetaObject::invokeMethod(targetView, "activate");
        }
        if (mo && mo->indexOfMethod("activated()") >= 0) {
            QMetaObject::invokeMethod(targetView, "activated");
        }
    } else if (currentView) {
        const QMetaObject *mo = currentView->metaObject();
        if (mo && mo->indexOfMethod("toggleActiveViewRequested()") >= 0) {
            QMetaObject::invokeMethod(currentView, "toggleActiveViewRequested");
        }
    }

    bestTarget->setFocus(Qt::OtherFocusReason);
    if (QWidget *proxy = bestTarget->focusProxy()) {
        proxy->setFocus(Qt::OtherFocusReason);
    }
    return true;
}

class DolphinVimFilter final : public QObject {
public:
    explicit DolphinVimFilter(QObject *parent = nullptr) : QObject(parent) {
        m_gTimer.invalidate();
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (m_sendingSynthetic || !watched || !watched->isWidgetType()) {
            return false;
        }

        const QEvent::Type type = event->type();
        if (type != QEvent::KeyPress && type != QEvent::ShortcutOverride) {
            return false;
        }

        auto *w = qobject_cast<QWidget *>(watched);
        if (!isKItemListContainer(w)) {
            return false;
        }

        QWidget *focusW = QApplication::focusWidget();
        if ((focusW && isTextEditingWidget(focusW)) || hasActiveInlineEditor(w)) {
            m_insertPassthrough = false;
            return false;
        }

        auto *ke = static_cast<QKeyEvent *>(event);
        const int key = ke->key();
        const Qt::KeyboardModifiers mods =
            ke->modifiers() & (Qt::ShiftModifier | Qt::ControlModifier | Qt::AltModifier | Qt::MetaModifier);

        if (key == Qt::Key_Escape && mods == Qt::NoModifier) {
            if (m_insertPassthrough) {
                m_insertPassthrough = false;
                event->accept();
                return true;
            }
            m_gTimer.invalidate();
            return false;
        }

        if (m_insertPassthrough) {
            return false;
        }

        if (mods == Qt::AltModifier &&
            (key == Qt::Key_H || key == Qt::Key_J || key == Qt::Key_K || key == Qt::Key_L)) {
            m_gTimer.invalidate();
            if (!collectOtherSplitContainers(w).isEmpty()) {
                if (type == QEvent::ShortcutOverride) {
                    event->accept();
                    return true;
                }
                if (switchSplitViewPane(w, key)) {
                    event->accept();
                    return true;
                }
            }
            return false;
        }

        if (mods != Qt::NoModifier && mods != Qt::ShiftModifier) {
            m_gTimer.invalidate();
            return false;
        }

        int targetKey = 0;
        Qt::KeyboardModifiers targetMods = Qt::NoModifier;
        const char *actionName = nullptr;
        QKeySequence actionSeq;
        const char *fallbackActionName = nullptr;
        QKeySequence fallbackActionSeq;

        if (mods == Qt::NoModifier) {
            switch (key) {
                case Qt::Key_H:
                    actionName = "go_up";
                    actionSeq = QKeySequence(Qt::ALT | Qt::Key_Up);
                    fallbackActionName = "go_back";
                    fallbackActionSeq = QKeySequence(Qt::ALT | Qt::Key_Left);
                    break;
                case Qt::Key_J:
                    targetKey = Qt::Key_Down;
                    break;
                case Qt::Key_K:
                    targetKey = Qt::Key_Up;
                    break;
                case Qt::Key_L:
                    targetKey = Qt::Key_Return;
                    break;
                case Qt::Key_U:
                    targetKey = Qt::Key_PageUp;
                    break;
                case Qt::Key_D:
                    targetKey = Qt::Key_PageDown;
                    break;
                case Qt::Key_Minus:
                    actionName = "go_up";
                    actionSeq = QKeySequence(Qt::ALT | Qt::Key_Up);
                    fallbackActionName = "go_back";
                    fallbackActionSeq = QKeySequence(Qt::ALT | Qt::Key_Left);
                    break;
                case Qt::Key_Slash:
                    actionName = "show_filter_bar";
                    actionSeq = QKeySequence(Qt::CTRL | Qt::Key_I);
                    break;
                case Qt::Key_I:
                    if (type == QEvent::KeyPress) {
                        m_insertPassthrough = true;
                    }
                    event->accept();
                    return true;
                case Qt::Key_G:
                    if (type == QEvent::ShortcutOverride) {
                        event->accept();
                        return true;
                    }
                    if (m_gTimer.isValid() && m_gTimer.elapsed() < 450) {
                        m_gTimer.invalidate();
                        targetKey = Qt::Key_Home;
                    } else {
                        m_gTimer.start();
                        event->accept();
                        return true;
                    }
                    break;
                default:
                    m_gTimer.invalidate();
                    return false;
            }
        } else if (mods == Qt::ShiftModifier) {
            switch (key) {
                case Qt::Key_H:
                    actionName = "go_back";
                    actionSeq = QKeySequence(Qt::ALT | Qt::Key_Left);
                    fallbackActionName = "go_up";
                    fallbackActionSeq = QKeySequence(Qt::ALT | Qt::Key_Up);
                    break;
                case Qt::Key_L:
                    actionName = "go_forward";
                    actionSeq = QKeySequence(Qt::ALT | Qt::Key_Right);
                    targetKey = Qt::Key_Return;
                    break;
                case Qt::Key_K:
                    actionName = "go_up";
                    actionSeq = QKeySequence(Qt::ALT | Qt::Key_Up);
                    break;
                case Qt::Key_J:
                    targetKey = Qt::Key_PageDown;
                    break;
                case Qt::Key_G:
                    targetKey = Qt::Key_End;
                    break;
                default:
                    m_gTimer.invalidate();
                    return false;
            }
        }

        if (targetKey == 0 && !actionName && actionSeq.isEmpty()) {
            return false;
        }

        m_gTimer.invalidate();

        if (type == QEvent::ShortcutOverride) {
            event->accept();
            return true;
        }

        if (actionName || !actionSeq.isEmpty()) {
            if (triggerWindowShortcut(w, actionSeq, actionName)) {
                event->accept();
                return true;
            }
            if ((fallbackActionName || !fallbackActionSeq.isEmpty()) &&
                triggerWindowShortcut(w, fallbackActionSeq, fallbackActionName)) {
                event->accept();
                return true;
            }
        }

        if (targetKey != 0) {
            m_sendingSynthetic = true;
            QKeyEvent syntheticPress(QEvent::KeyPress, targetKey, targetMods, QString(), ke->isAutoRepeat(), 1);
            QCoreApplication::sendEvent(w, &syntheticPress);
            QKeyEvent syntheticRelease(QEvent::KeyRelease, targetKey, targetMods, QString(), ke->isAutoRepeat(), 1);
            QCoreApplication::sendEvent(w, &syntheticRelease);
            m_sendingSynthetic = false;
            event->accept();
            return true;
        }

        return false;
    }

private:
    bool m_sendingSynthetic = false;
    bool m_insertPassthrough = false;
    QElapsedTimer m_gTimer;
};

void installDolphinVimFilter() {
    if (!qApp) {
        return;
    }
    qApp->installEventFilter(new DolphinVimFilter(qApp));
}

__attribute__((constructor))
void onLibraryLoaded() {
    if (!program_invocation_short_name || std::strcmp(program_invocation_short_name, "dolphin") != 0) {
        return;
    }
    unsetenv("LD_PRELOAD");
    qAddPreRoutine(installDolphinVimFilter);
}

} // namespace
