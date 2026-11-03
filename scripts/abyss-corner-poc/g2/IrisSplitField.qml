pragma ComponentBehavior: Bound

import QtQuick

// G2 split-composition field wrapper.
// Shapes remain in full output-local coordinates, but paintBounds is the only
// raster viewport. This is the key difference from the G1 all-owner field.
Item {
    id: root

    property var shapes: []
    required property rect paintBounds
    property color tint: "#f4c542"
    property real smoothing: 30
    readonly property int capacity: 20
    readonly property bool shaderCompiled: pass.status === ShaderEffect.Compiled
    readonly property string shaderLog: pass.log
    readonly property int shaderStatus: pass.status

    readonly property rect effectivePaintBounds: {
        const left = Math.max(0, Math.floor(root.paintBounds.x))
        const top = Math.max(0, Math.floor(root.paintBounds.y))
        const right = Math.min(root.width,
            Math.ceil(root.paintBounds.x + root.paintBounds.width))
        const bottom = Math.min(root.height,
            Math.ceil(root.paintBounds.y + root.paintBounds.height))
        return Qt.rect(left, top,
            Math.max(0, right - left), Math.max(0, bottom - top))
    }

    Item {
        id: noBackdrop
        visible: false
        width: 1
        height: 1
        layer.enabled: true
    }

    ShaderEffect {
        id: pass
        z: 1

        visible: root.effectivePaintBounds.width > 0
            && root.effectivePaintBounds.height > 0
        x: root.effectivePaintBounds.x
        y: root.effectivePaintBounds.y
        width: root.effectivePaintBounds.width
        height: root.effectivePaintBounds.height
        fragmentShader: Qt.resolvedUrl("IrisField.frag.qsb")
        blending: true

        function shapeAt(i) {
            const shape = root.shapes[i]
            return shape
                ? Qt.vector4d(
                    shape.x + shape.width / 2,
                    shape.y + shape.height / 2,
                    shape.width / 2,
                    shape.height / 2)
                : Qt.vector4d(0, 0, 0, 0)
        }

        function blockValue(block, slot, key, fallback) {
            const shape = root.shapes[block * 4 + slot]
            return shape ? Number(shape[key] ?? fallback) : 0
        }

        function radiusBlock(block) {
            return Qt.vector4d(
                pass.blockValue(block, 0, "radius", 0),
                pass.blockValue(block, 1, "radius", 0),
                pass.blockValue(block, 2, "radius", 0),
                pass.blockValue(block, 3, "radius", 0))
        }

        function fuseBlock(block) {
            return Qt.vector4d(
                pass.blockValue(block, 0, "fuse", root.smoothing),
                pass.blockValue(block, 1, "fuse", root.smoothing),
                pass.blockValue(block, 2, "fuse", root.smoothing),
                pass.blockValue(block, 3, "fuse", root.smoothing))
        }

        readonly property var indexOf: {
            const map = {}
            const list = root.shapes ?? []
            for (let i = 0; i < Math.min(list.length, root.capacity); ++i) {
                if (list[i]?.id)
                    map[list[i].id] = i
            }
            return map
        }

        function joinValue(block, slot, which) {
            const shape = root.shapes[block * 4 + slot]
            const list = !shape || !shape.joins
                ? []
                : Array.isArray(shape.joins) ? shape.joins : [shape.joins]
            const name = list[which]
            if (!name)
                return 0
            const index = pass.indexOf[name]
            return index === undefined ? 0 : index + 1
        }

        function joinBlock(block, which) {
            return Qt.vector4d(
                pass.joinValue(block, 0, which),
                pass.joinValue(block, 1, which),
                pass.joinValue(block, 2, which),
                pass.joinValue(block, 3, which))
        }

        // The upstream shader reconstructs output-space p from this viewport.
        // Shape coordinates therefore stay full-output even though only this
        // local rectangle is rasterized.
        readonly property vector4d viewport: Qt.vector4d(
            pass.x, pass.y, Math.max(1, pass.width), Math.max(1, pass.height))
        readonly property vector2d screen:
            Qt.vector2d(Math.max(1, root.width), Math.max(1, root.height))
        readonly property vector4d field: Qt.vector4d(root.smoothing, 0, 0, 0)
        readonly property color tint: root.tint
        readonly property color rim: "transparent"
        readonly property vector4d edge: Qt.vector4d(0, 0, 0, 0)

        readonly property vector4d shape0: pass.shapeAt(0)
        readonly property vector4d shape1: pass.shapeAt(1)
        readonly property vector4d shape2: pass.shapeAt(2)
        readonly property vector4d shape3: pass.shapeAt(3)
        readonly property vector4d shape4: pass.shapeAt(4)
        readonly property vector4d shape5: pass.shapeAt(5)
        readonly property vector4d shape6: pass.shapeAt(6)
        readonly property vector4d shape7: pass.shapeAt(7)
        readonly property vector4d shape8: pass.shapeAt(8)
        readonly property vector4d shape9: pass.shapeAt(9)
        readonly property vector4d shape10: pass.shapeAt(10)
        readonly property vector4d shape11: pass.shapeAt(11)
        readonly property vector4d shape12: pass.shapeAt(12)
        readonly property vector4d shape13: pass.shapeAt(13)
        readonly property vector4d shape14: pass.shapeAt(14)
        readonly property vector4d shape15: pass.shapeAt(15)
        readonly property vector4d shape16: pass.shapeAt(16)
        readonly property vector4d shape17: pass.shapeAt(17)
        readonly property vector4d shape18: pass.shapeAt(18)
        readonly property vector4d shape19: pass.shapeAt(19)

        readonly property vector4d radiiA: pass.radiusBlock(0)
        readonly property vector4d radiiB: pass.radiusBlock(1)
        readonly property vector4d radiiC: pass.radiusBlock(2)
        readonly property vector4d radiiD: pass.radiusBlock(3)
        readonly property vector4d radiiE: pass.radiusBlock(4)

        readonly property vector4d fuseA: pass.fuseBlock(0)
        readonly property vector4d fuseB: pass.fuseBlock(1)
        readonly property vector4d fuseC: pass.fuseBlock(2)
        readonly property vector4d fuseD: pass.fuseBlock(3)
        readonly property vector4d fuseE: pass.fuseBlock(4)

        readonly property vector4d joinA: pass.joinBlock(0, 0)
        readonly property vector4d alsoA: pass.joinBlock(0, 1)
        readonly property vector4d joinB: pass.joinBlock(1, 0)
        readonly property vector4d alsoB: pass.joinBlock(1, 1)
        readonly property vector4d joinC: pass.joinBlock(2, 0)
        readonly property vector4d alsoC: pass.joinBlock(2, 1)
        readonly property vector4d joinD: pass.joinBlock(3, 0)
        readonly property vector4d alsoD: pass.joinBlock(3, 1)
        readonly property vector4d joinE: pass.joinBlock(4, 0)
        readonly property vector4d alsoE: pass.joinBlock(4, 1)

        readonly property vector4d paintsA: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d paintsB: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d paintsC: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d paintsD: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d paintsE: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d glassA: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d glassB: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d glassC: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d glassD: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d glassE: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d glass: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d edgeWave: Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d waveClock: Qt.vector4d(0, 0, 0, 0)
        readonly property Item backdrop: noBackdrop
    }
}
