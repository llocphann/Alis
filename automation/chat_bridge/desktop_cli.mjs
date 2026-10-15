#!/usr/bin/env node

import fs from "node:fs";
import {createHash} from "node:crypto";

import {
  connectDesktop,
  extractLoopResponse,
  handoverCheck,
  managedBaseline,
  managedPoll,
  observeDesktop,
  openHadalisNewChat,
  retryFailedStream,
  submitPrompt,
  uiTargetIdentity,
  waitForCompletion
} from "./desktop_driver.mjs";

function writeJson(payload) {
  fs.writeSync(1, JSON.stringify(payload) + "\n");
}

function writeError(error) {
  const detail = ["HADALIS_DESKTOP_BUSY", "HADALIS_DESKTOP_VIEW_CHANGED"].includes(error?.code)
    ? `${error.code}: ${error.message}` : (error?.stack ?? String(error));
  fs.writeSync(2, detail + "\n");
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin)
    chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

async function main() {
  const command = process.argv[2] ?? "observe";
  let { page } = await connectDesktop();

  if (command === "observe") {
    writeJson(await observeDesktop(page));
    return;
  }

  if (command === "handover-check") {
    writeJson(await handoverCheck(page));
    return;
  }

  if (command === "ui-target-check") {
    // A strictly read-only owner preflight. Do not return titles, chat IDs,
    // links, fingerprints or raw DOM contents in a copyable report.
    let stable = false;
    let diagnosis = "ALIS_UI_CHAT_IDENTITY_UNAVAILABLE";
    try {
      const before = await uiTargetIdentity(page);
      await page.waitForTimeout(250);
      const after = await uiTargetIdentity(page);
      stable = before === after;
      diagnosis = stable ? "ALIS_UI_CHAT_TARGET_OBSERVED" :
        "ALIS_UI_CHAT_TARGET_CHANGED";
    } catch {
      stable = false;
    }
    writeJson({
      purpose: "alis-ui-target-preflight",
      status: "read-only",
      selected_chat_identity_stable: stable,
      diagnosis,
      message_submission_attempted: false,
      server_identity_attested: false,
      ui_scheduler_authorized: false
    });
    return;
  }

  if (command === "new-chat") {
    if (process.argv[3] && process.argv[3] !== "--unowned-previous-chat")
      throw new Error("unknown new-chat option");
    page = await openHadalisNewChat(page, {
      unownedPreviousChat: process.argv[3] === "--unowned-previous-chat"
    });
    writeJson(await observeDesktop(page));
    return;
  }

  if (command === "managed-baseline") {
    writeJson(await managedBaseline(page));
    return;
  }

  if (command === "managed-submit") {
    const expected = Number(process.argv[3]);
    if (!Number.isInteger(expected) || expected < 0)
      throw new Error("managed-submit requires a non-negative response baseline");
    const before = await managedBaseline(page);
    if (before.responseActionCount !== expected)
      throw new Error("response baseline changed before submission");
    const prompt = await readStdin();
    if (!prompt.trim())
      throw new Error("stdin prompt is empty");
    const receipt = await submitPrompt(page, prompt);
    writeJson({ submitted: true, receipt });
    return;
  }

  if (command === "managed-poll") {
    const expected = Number(process.argv[3]);
    writeJson(await managedPoll(page, { responseActionCount: expected }));
    return;
  }

  if (command === "managed-retry") {
    const expected = Number(process.argv[3]);
    writeJson(await retryFailedStream(page, { responseActionCount: expected }));
    return;
  }

  if (command === "await-current") {
    try {
      const response = await extractLoopResponse(page, { allowMarkerOnly: true });
      writeJson({
        generation: { attachedToCompleted: true },
        response
      });
      return;
    } catch {}

    const generation = await waitForCompletion(page);
    const response = await extractLoopResponse(page, { allowMarkerOnly: true });
    writeJson({ generation, response });
    return;
  }

  if (command === "send" || command === "rotate-send") {
    if (command === "rotate-send")
      page = await openHadalisNewChat(page);

    // For managed Alis UI mode, require same uniquely selected conversation
    // between turns. A missing/changed chat must block BEFORE composer.fill.
    const expectedTarget = process.argv[3] || null;
    if (expectedTarget) {
      if (command !== "send" || !/^[0-9a-f]{64}$/.test(expectedTarget))
        throw new Error("ALIS_UI_TARGET_ARGUMENT_INVALID");
      const current = createHash("sha256")
        .update(await uiTargetIdentity(page)).digest("hex");
      if (current !== expectedTarget)
        throw new Error("ALIS_UI_TARGET_CHANGED_NO_SEND");
    }

    const prompt = await readStdin();
    if (!prompt.trim())
      throw new Error("stdin prompt is empty");

    const completionBaseline = await submitPrompt(page, prompt);
    const generation = await waitForCompletion(
      page,
      600000,
      completionBaseline
    );
    const response = await extractLoopResponse(page, {
      baselineResponseActionCount: completionBaseline.responseActionCount
    });

    // After an initial send, the UI may not yet have exposed a persistent
    // chat ID. That is an uncertain mapping: never advance to the next send.
    const uiTarget = createHash("sha256")
      .update(await uiTargetIdentity(page)).digest("hex");
    writeJson({ generation, response, ui_target_key: uiTarget });
    return;
  }

  throw new Error(`unknown command: ${command}`);
}

main().then(
  () => process.exit(0),
  error => {
    writeError(error);
    process.exit(1);
  }
);
