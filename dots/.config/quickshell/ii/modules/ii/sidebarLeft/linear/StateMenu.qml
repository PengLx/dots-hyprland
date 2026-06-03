import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Right-click / press-and-hold popup on an IssueCard. Shows the workflow
 * states for the issue's team and lets the user move the issue.
 */
Menu {
    id: root
    property var currentIssue: null

    function openFor(issue, x, y) {
        root.currentIssue = issue
        // Rebuild items
        // Using Repeater inside Menu needs work-around: clear & populate via JS
        root.popup(x, y)
    }

    Repeater {
        model: {
            if (!root.currentIssue) return []
            const teamId = (root.currentIssue.team && root.currentIssue.team.id) || ""
            const team = (Linear.teams || []).find(t => t.id === teamId)
            if (!team) return []
            return team.states || []
        }
        delegate: MenuItem {
            required property var modelData
            text: (modelData.name || "?")
            enabled: !root.currentIssue || !root.currentIssue.state || root.currentIssue.state.id !== modelData.id
            onTriggered: {
                if (root.currentIssue && root.currentIssue.id) {
                    Linear.setIssueState(root.currentIssue.id, modelData.id)
                }
            }
        }
    }
}
