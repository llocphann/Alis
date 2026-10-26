pragma ComponentBehavior: Bound

import QtQuick

// Minimal Alis developer wrapper around the exact Abyss v2.31.0 field shader.
// Upstream: snowarch/Alis@9574fa424c0d1008e927454e933a7fbe292f9fb2
// Source/QSB: modules/abyss/field/AbyssField.frag(.qsb), GPL-3.0.
// This wrapper intentionally keeps only the generic shape/join field contract.
Item {
    id: root

    property var shapes: []
    property color tint: "#f4c542"
    property real smoothing: 8
    readonly property int capacity: 20
    readonly property real reach: root.smoothing + 2

    readonly property rect bounds: {
        const list = root.shapes ?? []
        if (list.length === 0)
            return Qt.rect(0, 0, 0, 0)
        let left = Infinity
        let top = Infinity
        let right = -Infinity
        let bottom = -Infinity
        for (const shape of list) {
            left = Math.min(left, shape.x - root.reach)
            top = Math.min(top, shape.y - root.reach)
            right = Math.max(right, shape.x + shape.width + root.reach)
            bottom = Math.max(bottom, shape.y + shape.height + root.reach)
        }
        const x = Math.max(0, Math.floor(left))
        const y = Math.max(0, Math.floor(top))
        return Qt.rect(
            x,
            y,
            Math.max(0, Math.ceil(Math.min(root.width, right)) - x),
            Math.max(0, Math.ceil(Math.min(root.height, bottom)) - y)
        )
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

        visible: root.bounds.width > 0 && root.bounds.height > 0
        x: root.bounds.x
        y: root.bounds.y
        width: root.bounds.width
        height: root.bounds.height
        fragmentShader: Qt.resolvedUrl("AbyssField.frag.qsb")
        blending: true

        function shapeAt(i) {
            const shape = root.shapes[i]
            return shape
                ? Qt.vector4d(
                    shape.x + shape.width / 2,
                    shape.y + shape.height / 2,
                    shape.width / 2,
                    shape.height / 2
                )
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
                pass.blockValue(block, 3, "radius", 0)
            )
        }

        function fuseBlock(block) {
            return Qt.vector4d(
                pass.blockValue(block, 0, "fuse", root.smoothing),
                pass.blockValue(block, 1, "fuse", root.smoothing),
                pass.blockValue(block, 2, "fuse", root.smoothing),
                pass.blockValue(block, 3, "fuse", root.smoothing)
            )
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
                pass.joinValue(block, 3, which)
            )
        }

        readonly property vector4d viewport:
            Qt.vector4d(pass.x, pass.y, Math.max(1, pass.width), Math.max(1, pass.height))
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

        // The upstream shader keeps these blocks in its ABI. The PoC is solid
        // material only, so every slot deliberately uses zero/default material.
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
