pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id:root
    required property var event
    property bool interactive:true
    readonly property string status:event?.todoLink ? Todo.agendaStatus(event) : ""
    visible:status.length>0
    spacing:4
    MaterialSymbol {text:"link";iconSize:13;color:Appearance.colors.colSubtext}
    StyledText {
        Layout.fillWidth:true
        text:Translation.tr(root.status)
        font.pixelSize:Appearance.font.pixelSize.smallest
        color:Appearance.colors.colSubtext
        elide:Text.ElideRight
    }
    RippleButton {
        visible:root.interactive && root.status==="To-do pending"
        implicitWidth:22;implicitHeight:22;buttonRadius:6
        Accessible.name:Translation.tr("Retry To-do link")
        Keys.onPressed:event=>{if(event.key===Qt.Key_Return || event.key===Qt.Key_Enter){click();event.accepted=true}}
        contentItem:MaterialSymbol {text:"refresh";iconSize:14;color:Appearance.colors.colPrimary}
        onClicked:Todo.retryAgendaLinks()
        StyledToolTip {text:Translation.tr("Retry To-do link")}
    }
    RippleButton {
        visible:root.interactive
        implicitWidth:22;implicitHeight:22;buttonRadius:6
        Accessible.name:Translation.tr("Unlink To-do")
        Keys.onPressed:event=>{if(event.key===Qt.Key_Return || event.key===Qt.Key_Enter){click();event.accepted=true}}
        contentItem:MaterialSymbol {text:"link_off";iconSize:14;color:Appearance.colors.colSubtext}
        onClicked:Events.unlinkTodo(root.event.id)
        StyledToolTip {text:Translation.tr("Keep To-do and unlink Agenda")}
    }
}
