pragma ComponentBehavior: Bound
import QtQuick
import Qt5Compat.GraphicalEffects as GE
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

Item {
    id:root
    required property var modelData
    required property int index
    required property real cardWidth
    required property real cardHeight
    signal activated(int index)
    readonly property bool current:PathView.isCurrentItem
    readonly property bool applied:modelData.path===(PathView.view?.currentWallpaperPath ?? "")
    implicitWidth:cardWidth;implicitHeight:cardHeight
    scale:current ? 1 : PathView.onPath ? .8 : 0
    opacity:PathView.onPath ? 1 : 0
    z:PathView.z ?? 0
    Behavior on scale {enabled:Appearance.animationsEnabled;NumberAnimation {duration:180;easing.type:Easing.OutCubic}}
    StyledRectangularShadow {target:preview;visible:root.current && Appearance.effectsEnabled;radius:18;blur:12;spread:1;color:Qt.alpha(AbyssStyle.surfaceDeep,.45)}
    Rectangle {
        id:preview
        x:8;y:4;width:parent.width-16;height:width*9/16
        color:AbyssStyle.surfaceRaised;radius:18
        MaterialSymbol {anchors.centerIn:parent;text:modelData.kind==="static" ? "image" : "movie";color:AbyssStyle.textColorMuted;iconSize:38}
        ThumbnailImage {
            id:image;objectName:"wallpaperCardImage";anchors.fill:parent;sourcePath:root.modelData.path
            sourceSize.width:Math.ceil(width*2);sourceSize.height:Math.ceil(height*2)
            fillMode:Image.PreserveAspectCrop;generateThumbnail:true;mipmap:true
            layer.enabled:true
            layer.effect:GE.OpacityMask {maskSource:Rectangle {width:preview.width;height:preview.height;radius:18;color:"white"}}
        }
        Rectangle {visible:root.applied;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:8;width:26;height:26;radius:13;color:AbyssStyle.accent;MaterialSymbol {anchors.centerIn:parent;text:"check";iconSize:18;color:AbyssStyle.surface}}
    }
    AbyssLabel {anchors.top:preview.bottom;anchors.topMargin:8;anchors.horizontalCenter:parent.horizontalCenter;width:parent.width-20;horizontalAlignment:Text.AlignHCenter;objectName:"wallpaperCardLabel";text:root.modelData.name;elide:Text.ElideMiddle;color:root.current ? AbyssStyle.accent : AbyssStyle.textColor}
    MouseArea {anchors.fill:parent;onClicked:root.activated(root.index)}
}
