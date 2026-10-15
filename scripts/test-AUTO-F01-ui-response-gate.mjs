#!/usr/bin/env node
import assert from "node:assert/strict";
import {requireFreshAssistantTurn} from "../automation/chat_bridge/ui_response_gate.mjs";

const valid = {
  response: {
    extractionSignal: "assistant-turn", markerCount: 1,
    text: "ALIS_LOOP:CONTINUE"
  },
  baselineActionCount: 2, currentActionCount: 3,
  generationActive: false
};
assert.equal(requireFreshAssistantTurn(valid).text, "ALIS_LOOP:CONTINUE");

for (const marker of [
  "ALIS_LOOP:DONE",
  "ALIS_LOOP:WAIT_RESULT JOB-001",
  "ALIS_LOOP:CONNECTOR_BLOCKED GITHUB",
  "HADALIS_LOOP:ROTATE"
]) {
  assert.equal(requireFreshAssistantTurn({
    ...valid, response: {...valid.response, text: marker}
  }).text, marker);
}
const rejected = [
  {...valid, response: {...valid.response, extractionSignal: "post-submit-marker-delta"}},
  {...valid, response: {...valid.response, extractionSignal: "ancestor-text"}},
  {...valid, response: {...valid.response, markerCount: 2}},
  {...valid, response: null},
  {...valid, response: {...valid.response, text: "ALIS_LOOP:CONTINUE\\nALIS_LOOP:DONE"}},
  {...valid, response: {...valid.response, text: "ALIS_LOOP:WAIT_RESULT"}},
  {...valid, response: {...valid.response, text: "ALIS_LOOP:WAIT_RESULT JOB-../../x"}},
  {...valid, baselineActionCount: 3},
  {...valid, baselineActionCount: -1},
  {...valid, generationActive: true},
];
for (const item of rejected)
  assert.throws(() => requireFreshAssistantTurn(item), /ALIS_UI_ASSISTANT_/);
console.log("PASS: Alis requires a unique fresh assistant-only UI reply, not a marker in its own prompt");
