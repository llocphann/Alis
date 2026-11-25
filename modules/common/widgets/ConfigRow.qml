import QtQuick
import QtQuick.Layouts

RowLayout {
    property bool uniform: false
    spacing: uniform ? 20 : 16
    uniformCellSizes: uniform
}
