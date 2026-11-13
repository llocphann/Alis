pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.services
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
    readonly property bool favourite:{
        void Wallpapers.favouritesRevision
        return Wallpapers.isFavourite(root.modelData.path)
    }
    width:cardWidth;height:cardHeight
    implicitWidth:cardWidth;implicitHeight:cardHeight
    scale:current ? 1 : PathView.onPath ? .8 : 0
    opacity:PathView.onPath ? 1 : 0
    z:PathView.z ?? 0
    Behavior on scale {enabled:Appearance.animationsEnabled;NumberAnimation {duration:180;easing.type:Easing.OutCubic}}
    StyledRectangularShadow {target:preview;visible:root.current && Appearance.effectsEnabled;radius:18;blur:12;spread:1;color:Qt.alpha(AbyssStyle.surfaceDeep,.45)}
    ClippingRectangle {
        id:preview
        x:8;y:4;width:parent.width-16;height:width*9/16
        color:AbyssStyle.surfaceRaised;radius:18
        MaterialSymbol {anchors.centerIn:parent;text:modelData.kind==="static" ? "image" : "movie";color:AbyssStyle.textColorMuted;iconSize:38}
        ThumbnailImage {
            id:image;objectName:"wallpaperCardImage";anchors.fill:parent;sourcePath:root.modelData.path
            sourceSize.width:Math.max(1,Math.ceil((root.cardWidth-16)*2));sourceSize.height:Math.max(1,Math.ceil((root.cardWidth-16)*9/8))
            fillMode:Image.PreserveAspectCrop;generateThumbnail:true;mipmap:false
        }
        Rectangle {visible:root.applied;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:8;width:26;height:26;radius:13;color:AbyssStyle.accent;MaterialSymbol {anchors.centerIn:parent;text:"check";iconSize:18;color:AbyssStyle.surface}}
        Rectangle {
            id:favBadge
            objectName:"wallpaperCardFavourite"
            visible:root.favourite || root.current || cardMouse.containsMouse || favMouse.containsMouse
            anchors.left:parent.left;anchors.top:parent.top;anchors.margins:8
            width:26;height:26;radius:13
            color:root.favourite ? AbyssStyle.accent : Qt.alpha(AbyssStyle.surfaceDeep,.72)
            border.width:1
            border.color:root.favourite ? "transparent" : Qt.alpha(AbyssStyle.textColor,.18)
            MaterialSymbol {
                anchors.centerIn:parent
                text:"favorite"
                fill:root.favourite ? 1 : 0
                iconSize:16
                color:root.favourite ? AbyssStyle.surface : AbyssStyle.textColor
            }
        }
    }
    AbyssLabel {anchors.top:preview.bottom;anchors.topMargin:8;anchors.horizontalCenter:parent.horizontalCenter;width:parent.width-20;horizontalAlignment:Text.AlignHCenter;objectName:"wallpaperCardLabel";text:root.modelData.name;elide:Text.ElideMiddle;color:root.current ? AbyssStyle.accent : AbyssStyle.textColor}
    MouseArea {id:cardMouse;anchors.fill:parent;hoverEnabled:true;onClicked:root.activated(root.index)}
    MouseArea {
        id:favMouse
        x:preview.x+favBadge.x;y:preview.y+favBadge.y
        width:favBadge.width;height:favBadge.height
        z:3
        hoverEnabled:true
        cursorShape:Qt.PointingHandCursor
        onClicked:mouse=>{
            mouse.accepted=true
            Wallpapers.toggleFavourite(root.modelData.path)
        }
    }
}
