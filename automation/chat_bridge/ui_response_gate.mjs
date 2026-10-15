/* Alis UI-only completion gate. No transport, CDP, DOM or server APIs.
 * A body-wide marker count is not evidence of an assistant reply: the prompt
 * itself may mention ALIS_LOOP:CONTINUE/ROTATE/etc. Require an assistant-only
 * container anchored to a NEW response toolbar and a stable idle UI.
 */
const MARKER = /^(?:ALIS|HADALIS)_LOOP:(?:CONTINUE|ROTATE|DONE|WAIT_RESULT[ \t]+JOB-[A-Za-z0-9._-]+|CONNECTOR_BLOCKED[ \t]+GITHUB)$/;

export function requireFreshAssistantTurn({
  response, baselineActionCount, currentActionCount, generationActive
} = {}) {
  if (!Number.isInteger(baselineActionCount) || baselineActionCount < 0 ||
      !Number.isInteger(currentActionCount) ||
      currentActionCount <= baselineActionCount ||
      generationActive !== false)
    throw Error("ALIS_UI_ASSISTANT_TURN_NOT_SETTLED");
  if (!response || response.extractionSignal !== "assistant-turn" ||
      response.markerCount !== 1 || typeof response.text !== "string" ||
      !MARKER.test(response.text.trim()))
    throw Error("ALIS_UI_ASSISTANT_IDENTITY_NOT_PROVEN");
  return response;
}
