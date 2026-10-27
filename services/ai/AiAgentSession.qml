pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "AiReasoning.js" as Reasoning

// Versioned agent-turn session owned by a consumer of Ai (such as Companion).
// Supports structured schema tool calls and token usage reporting while keeping
// main AI history/state isolated and never executing raw prose as tools.
QtObject {
    id: root
    readonly property int contractVersion: 1
    required property var ai
    property bool busy: false
    property string error: ""
    property string token: ""
    property int serial: 0
    property bool cancelled: false
    property bool timedOut: false
    property int httpStatus: 0
    property var payload: null
    property var strategy: null
    property var message: null
    property var modelSnapshot: null
    property var toolCalls: []
    property var tokenUsage: ({inputTokens: 0, outputTokens: 0, totalTokens: 0})
    signal finished(string token, string text, var toolCalls, var tokenUsage, string error)

    function start(requestToken, modelId, messages, systemPrompt, tools, effort): bool {
        if (busy || transport.running) return false
        ai.ensureInitialized()
        const model = ai.models[String(modelId)]
        if (!ai.modelCanRun(model)) {
            error = "Choose an available model in AI settings."
            return false
        }
        if (effort === "instant" && !ai.supportsInstant(model)) {
            error = "Choose a verified local LM Studio model for Instant mode."
            return false
        }
        if (modelSnapshot) modelSnapshot.destroy()
        if (strategy) strategy.destroy()
        if (message) message.destroy()
        const snapshot = {}
        for (const key of ["name", "model", "endpoint", "api_format", "auth_scheme", "provider_id",
                "requires_key", "key_id", "gguf_path", "runtime_path", "local", "free",
                "max_output_tokens", "capabilities", "extraParams", "local_verified", "local_fingerprint"])
            snapshot[key] = model[key]
        snapshot.extraParams = JSON.parse(JSON.stringify(model.extraParams ?? {}))
        snapshot.capabilities = JSON.parse(JSON.stringify(model.capabilities ?? {}))
        if (effort === "instant") {
            snapshot.endpoint = Reasoning.instantEndpoint(model)
            snapshot.api_format = "openai-response"
        }
        modelSnapshot = ai.aiModelComponent.createObject(root, snapshot)
        strategy = ai.createStrategy(root, modelSnapshot.api_format)
        if (!strategy) { error = "This AI protocol is unavailable."; return false }
        strategy.reset()
        message = ai.aiMessageComponent.createObject(root, {role: "assistant", model: String(modelId),
            content: "", rawContent: "", thinking: true, done: false})
        const rows = (messages ?? []).filter(row => ["user", "assistant", "tool"].includes(row?.role)
            && typeof row.content === "string").slice(-16)
            .map(row => ({
                role: row.role,
                rawContent: row.content.slice(0, 2400),
                functionName: String(row.functionName ?? ""),
                functionResponse: String(row.functionResponse ?? ""),
                functionCall: row.functionCall ?? null
            }))
        const schemaTools = Array.isArray(tools) ? tools : []
        const data = ai.buildChatRequest(modelSnapshot, strategy, rows,
            String(systemPrompt).slice(0, 8000), .35, schemaTools, "", effort)
        if (schemaTools.length === 0) {
            delete data.tools; delete data.tool_choice; delete data.functions; delete data.function_call
        }
        if (modelSnapshot.api_format === "openai-response") {
            data.store = false
            delete data.previous_response_id
            data.max_output_tokens = 384
        }
        const request = ai.textTransport(modelSnapshot, strategy, data, effort)
        transport.environment = request.environment
        transport.command = request.command
        payload = request.payload
        toolCalls = []
        tokenUsage = {inputTokens: 0, outputTokens: 0, totalTokens: 0}
        error = ""; httpStatus = 0; cancelled = false; timedOut = false
        token = String(requestToken); busy = true
        const generation = ++serial
        Qt.callLater(() => {
            if (root.busy && !root.cancelled && generation === root.serial)
                transport.running = true
        })
        return true
    }

    function cancel(): void {
        cancelled = true; ++serial; deadline.stop()
        if (transport.running) transport.signal(15)
        else { busy = false; payload = null }
    }

    function complete(exitCode): void {
        deadline.stop()
        if (!busy) return
        if (!cancelled) {
            try {
                const fin = strategy.onRequestFinished(message)
                if (fin?.functionCall && fin.functionCall.name) {
                    toolCalls = toolCalls.concat([{
                        toolCallId: String(fin.functionCall.id || ("call_" + (toolCalls.length + 1))),
                        name: String(fin.functionCall.name),
                        args: fin.functionCall.args ?? ({})
                    }])
                }
            } catch (e) { error = "AI reply could not be decoded." }
            if (timedOut) error = "AI request timed out."
            else if (httpStatus >= 400) error = "AI request failed (HTTP " + httpStatus + "). Check AI settings."
            else if (exitCode !== 0 && !error) error = "AI request could not finish."
            else if (!String(message?.content ?? "").trim() && toolCalls.length === 0 && !error)
                error = "The model returned no text."
        }
        const result = String(message?.content ?? "").slice(0, 6000)
        const requestToken = token
        const currentCalls = toolCalls.slice()
        const currentUsage = Object.assign({}, tokenUsage)
        const ignored = cancelled
        busy = false; payload = null
        if (message) { message.done = true; message.thinking = false }
        if (!ignored) finished(requestToken, result, currentCalls, currentUsage, error)
    }

    property Timer deadline: Timer {
        interval: 80000
        onTriggered: {
            root.timedOut = true
            if (transport.running) transport.signal(15)
            else root.complete(-1)
        }
    }

    property Process transport: Process {
        id: transport
        stdinEnabled: true
        onStarted: { write(JSON.stringify(root.payload) + "\n"); deadline.restart() }
        stdout: SplitParser {
            onRead: line => {
                if (root.cancelled || !root.busy || !line) return
                if (line.startsWith("__ALIS_HTTP_STATUS__:")) {
                    root.httpStatus = Number(line.slice(21).trim()) || 0
                    return
                }
                if (line.length > 65536 || root.message.rawContent.length > 24000) {
                    root.error = "AI reply exceeded the conversation limit."
                    transport.signal(15); return
                }
                try {
                    const json = JSON.parse(line.replace(/^data:\s*/, ""))
                    if (json.error) root.error = "The AI provider rejected this request. Check AI settings."
                } catch (e) {}
                try {
                    const result = root.strategy.parseResponseLine(line, root.message)
                    if (result?.functionCall && result.functionCall.name) {
                        root.toolCalls = root.toolCalls.concat([{
                            toolCallId: String(result.functionCall.id || ("call_" + (root.toolCalls.length + 1))),
                            name: String(result.functionCall.name),
                            args: result.functionCall.args ?? ({})
                        }])
                    }
                    if (result?.tokenUsage) {
                        root.tokenUsage = {
                            inputTokens: Math.max(0, Number(result.tokenUsage.input ?? 0)),
                            outputTokens: Math.max(0, Number(result.tokenUsage.output ?? 0)),
                            totalTokens: Math.max(0, Number(result.tokenUsage.total ?? 0))
                        }
                    }
                } catch (e) { root.error = "AI reply could not be decoded." }
            }
        }
        onExited: (code, status) => root.complete(code)
    }
}
