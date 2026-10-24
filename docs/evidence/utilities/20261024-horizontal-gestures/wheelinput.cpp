#include <QObject>
#include <QDateTime>
#include <QCoreApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWheelEvent>
#include <QPointingDevice>
#include <QQmlExtensionPlugin>
#include <qqml.h>
class WheelDriver : public QObject {
 Q_OBJECT
public:
 explicit WheelDriver(QObject *parent=nullptr):QObject(parent){}
 Q_INVOKABLE bool wheel(QQuickItem *item, double x, double y, int px, int py, int ax, int ay, int phase, int modifiers=0) {
  if(!item || !item->window())return false;
  static const QPointingDevice device(QStringLiteral("Alis fixture touchpad"), 0x414c4953,
   QInputDevice::DeviceType::TouchPad,QPointingDevice::PointerType::Finger,
   QInputDevice::Capability::Position | QInputDevice::Capability::PixelScroll,5,0);
  auto *window=item->window();auto pos=item->mapToScene(QPointF(x,y));
  QWheelEvent event(pos,window->mapToGlobal(pos),QPoint(px,py),QPoint(ax,ay),Qt::NoButton,
   Qt::KeyboardModifiers(modifiers),Qt::ScrollPhase(phase),false,Qt::MouseEventSynthesizedByApplication,&device);
  event.setTimestamp(QDateTime::currentMSecsSinceEpoch());
  QCoreApplication::sendEvent(window,&event);return event.isAccepted();
 }
};
class NativeInputPlugin : public QQmlExtensionPlugin {
 Q_OBJECT
 Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
 void registerTypes(const char *uri) override {qmlRegisterType<WheelDriver>(uri,1,0,"WheelDriver");}
};
#include "wheelinput.moc"
