import QtQuick
import QtQuick.Window
import QtTest
Window {id:w;width:200;height:200;visible:true;property point observed:Qt.point(-1,-1)
 MouseArea {id:a;anchors.fill:parent;hoverEnabled:true;onPositionChanged:mouse=>w.observed=Qt.point(mouse.x,mouse.y)}
 TestCase {id:t;when:false;optional:true;function run(){wait(100);for(const x of [16.5,183.5,183,16]){mouseMove(a,x,42);wait(20);console.info("MOUSE_COORDINATE",x,w.observed.x,w.observed.y)}Qt.quit()}}
 Timer {interval:50;running:true;onTriggered:t.run()}
}