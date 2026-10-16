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
  uiOnlyTurnIdentity,
  observeSubmittedPrompt,
  resumeUiChat,
  waitForCompletion
} from "./desktop_driver.mjs";
import {inspectLegacyUiReadOnly, assessLegacyUiReadiness} from "./legacy_ui_probe.mjs";
import {inspectUiSessionIdentity} from "./ui_session_diagnostics.mjs";

function writeJson(payload) {
  fs.writeSync(1, JSON.stringify(payload) + "\n");
}

function writeError(error) {
  const detail = ["HADALIS_DESKTOP_BUSY", "HADALIS_DESKTOP_VIEW_CHANGED"].includes(error?.code)
    ? `${error.code}: ${error.message}` : (error?.stack ?? String(error));
  fs.writeSync(2, detail + "\n");
}

let dispatchIdentity=null;

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin)
    chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

async function main() {
  const command = process.argv[2] ?? "observe";
  if (command === "ui-project-enter") {
    const cdp = process.env.ALIS_CHATGPT_CDP_URL ??
      process.env.HADALIS_CHATGPT_CDP_URL ?? "http://127.0.0.1:9222";
    let loopback = false;
    try {
      const url = new URL(cdp);
      loopback = url.protocol === "http:" &&
        ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) &&
        !url.username && !url.password && url.pathname === "/" &&
        !url.search && !url.hash;
    } catch {}
    if (!loopback) {
      writeJson({
        purpose: "alis-ui-project-navigation", status: "blocked",
        diagnosis: "ALIS_UI_CDP_LOOPBACK_REQUIRED",
        navigation_click_attempted: false,
        message_submission_attempted: false,
        ui_scheduler_authorized: false
      });
      return;
    }
  }
  let { page } = await connectDesktop();

  if (command === "observe") {
    writeJson(await observeDesktop(page));
    return;
  }

  if (command === "handover-check") {
    writeJson(await handoverCheck(page));
    return;
  }

  if (command === "ui-session-inspect") {
    // Read-only diagnosis following an already journaled one-shot Send.
    // Do not expose chat IDs/URLs/titles or make this Scheduler authority.
    if (process.argv.length !== 3)
      throw new Error("ui-session-inspect takes no arguments");
    const project = process.env.ALIS_CHATGPT_PROJECT ??
      process.env.HADALIS_CHATGPT_PROJECT ?? "Automatic Alis";
    writeJson(await inspectUiSessionIdentity(page, project));
    return;
  }

  if (command === "ui-target-check") {
    // A strictly read-only owner preflight. Do not return titles, chat IDs,
    // links, fingerprints or raw DOM contents in a copyable report.
    let stable = false;
    let projectEntryReady = false;
    let diagnosis = "ALIS_UI_CHAT_IDENTITY_UNAVAILABLE";
    // Category-only observations. Never emit current draft, title, IDs,
    // URLs, fingerprints, accessible-tree text, or DOM strings.
    let targetDiagnostics = {inspection: "not_available"};
    try {
      const before = await uiTargetIdentity(page);
      await page.waitForTimeout(250);
      const after = await uiTargetIdentity(page);
      stable = before === after;
      diagnosis = stable ? "ALIS_UI_CHAT_TARGET_OBSERVED" :
        "ALIS_UI_CHAT_TARGET_CHANGED";
    } catch {
      // A truly blank Project composer has no existing conversation ID.
      // Recognize that READ-ONLY phase separately; never interpret it as
      // permission to submit, nor relax continuation's pinned-chat guard.
      try {
        const project = process.env.ALIS_CHATGPT_PROJECT ??
          process.env.HADALIS_CHATGPT_PROJECT ?? "Automatic Alis";
        const observation = await inspectLegacyUiReadOnly(page, project);
        const assessment = assessLegacyUiReadiness(observation);
        projectEntryReady = assessment.read_only_project_entry_ready === true;
        const evidence = assessment.project_landing_visual_evidence;
        const scope = assessment.composer_scope_evidence;
        targetDiagnostics = {
          inspection: "completed",
          project_view_visible: assessment.project_view_visible === true,
          project_landing_visual_evidence: evidence,
          composer_scope_evidence: scope,
          selected_chat_count_capped: observation.selected_target_chat_count_capped,
          project_list_count_capped: observation.target_project_list_count_capped,
          project_badge_count_capped: observation.project_badge_count_capped,
          project_new_chat_action_visible:
            assessment.project_new_chat_action_visible === true,
          composer_count_capped: observation.composer_count_capped,
          draft_present: observation.composer_draft_present,
          generation_busy: observation.stop_count_capped !== 0,
          send_control_state: assessment.send_control_state,
          readiness_issues: assessment.readiness_issues,
        };
        if (projectEntryReady) {
          diagnosis = "ALIS_UI_EMPTY_PROJECT_ENTRY_OBSERVED";
        } else if (observation.selected_target_chat_count_capped > 1) {
          diagnosis = "ALIS_UI_MULTIPLE_SELECTED_CHATS";
        } else if (observation.selected_target_chat_count_capped === 1 &&
                   observation.target_project_list_count_capped === 1) {
          diagnosis = "ALIS_UI_SELECTED_CHAT_KEY_MISSING";
        } else if (observation.stop_count_capped !== 0) {
          diagnosis = "ALIS_UI_GENERATION_NOT_IDLE";
        } else if (observation.composer_draft_present === true) {
          diagnosis = "ALIS_UI_COMPOSER_HAS_DRAFT";
        } else if ((scope === "generic-label-with-other-or-unverified-guard" ||
                    scope === "generic-label-without-project-guard") &&
                   evidence === "project-empty-landing-corroborated") {
          diagnosis = "ALIS_UI_PROJECT_LANDING_COMPOSER_UNSCOPED";
        } else if (!assessment.project_view_visible &&
                   observation.target_project_list_count_capped === 1 &&
                   observation.project_new_chat_action_count_capped === 1 &&
                   observation.selected_target_chat_count_capped === 0 &&
                   observation.project_badge_count_capped === 0 &&
                   observation.composer_count_capped === 1 &&
                   observation.composer_draft_present === false &&
                   observation.composer_disabled === false &&
                   observation.stop_count_capped === 0) {
          // Sidebar Project navigation is visible, but the current editor
          // is still global. The action is for the human, never an auto-click.
          diagnosis = "ALIS_UI_PROJECT_NEW_CHAT_NAVIGATION_REQUIRED";
        } else if (!assessment.project_view_visible) {
          diagnosis = "ALIS_UI_PROJECT_VIEW_UNVERIFIED";
        }
      } catch {
        // Keep a bounded categorical blocker. No raw DOM, URL or draft.
      }
    }
    writeJson({
      purpose: "alis-ui-target-preflight",
      status: "read-only",
      selected_chat_identity_stable: stable,
      empty_project_entry_ready: projectEntryReady,
      diagnosis,
      target_diagnostics: targetDiagnostics,
      recommended_owner_action:
        diagnosis === "ALIS_UI_PROJECT_NEW_CHAT_NAVIGATION_REQUIRED"
          ? "OPEN_NEW_CHAT_IN_CONFIGURED_PROJECT_MANUALLY"
          : "REVIEW_PROJECT_TARGET_WITHOUT_SENDING",
      message_submission_attempted: false,
      server_identity_attested: false,
      ui_scheduler_authorized: false
    });
    return;
  }

  if (command === "ui-project-enter") {
    // This is optional OWNER-APPROVED UI navigation only. It does not
    // touch the composer, create a message, or approve an Automation queue.
    // At most one semantic click; never retry an uncertain navigation.
    if (process.argv.length !== 4 ||
        process.argv[3] !== "--approve-navigation") {
      writeJson({
        purpose: "alis-ui-project-navigation",
        status: "blocked",
        diagnosis: "ALIS_UI_NAVIGATION_APPROVAL_REQUIRED",
        navigation_click_attempted: false,
        message_submission_attempted: false,
        ui_scheduler_authorized: false
      });
      return;
    }
    const project = process.env.ALIS_CHATGPT_PROJECT ??
      process.env.HADALIS_CHATGPT_PROJECT ?? "Automatic Alis";
    const observed = await inspectLegacyUiReadOnly(page, project);
    const assessment = assessLegacyUiReadiness(observed);
    // Only leave an unowned, idle, empty *generic* editor when there is a
    // single visible project-new-chat action and no selected Project chat.
    const safe = observed.target_project_list_count_capped === 1 &&
      observed.project_new_chat_action_count_capped === 1 &&
      observed.selected_target_chat_count_capped === 0 &&
      observed.composer_count_capped === 1 &&
      observed.generic_composer_count_capped === 1 &&
      observed.project_scoped_composer_count_capped === 0 &&
      observed.composer_draft_present === false &&
      observed.composer_disabled === false &&
      observed.stop_count_capped === 0 &&
      observed.send_count_capped <= 1 &&
      (observed.send_count_capped === 0 ||
       observed.send_disabled === true) &&
      assessment.project_view_visible === false;
    if (!safe) {
      writeJson({
        purpose: "alis-ui-project-navigation", status: "blocked",
        diagnosis: "ALIS_UI_NAVIGATION_PRECONDITION_FAILED",
        navigation_click_attempted: false,
        message_submission_attempted: false,
        ui_scheduler_authorized: false
      });
      return;
    }
    const actionChoices = [
      page.getByRole("button", {name: "Start new chat in " + project, exact: true}),
      page.getByRole("button", {name: "New chat in " + project, exact: true})
    ];
    const actions = [];
    let ambiguous = false;
    for (const candidate of actionChoices) {
      const count = await candidate.count();
      if (count > 1) ambiguous = true;
      if (count === 1 && await candidate.isVisible()) actions.push(candidate);
    }
    const exactlyOne = !ambiguous && actions.length === 1 &&
      !(await actions[0].isDisabled());
    const action = actions[0];
    if (!exactlyOne) {
      writeJson({
        purpose: "alis-ui-project-navigation", status: "blocked",
        diagnosis: "ALIS_UI_PROJECT_ACTION_NOT_UNIQUE",
        navigation_click_attempted: false,
        message_submission_attempted: false,
        ui_scheduler_authorized: false
      });
      return;
    }
    // Playwright's evaluate invokes exactly one DOM click, never fills or
    // submits a prompt. A failed/uncertain click is not replayed.
    try {
      await action.evaluate(button => button.click());
    } catch {
      writeJson({
        purpose: "alis-ui-project-navigation", status: "uncertain",
        diagnosis: "ALIS_UI_NAVIGATION_CLICK_UNCERTAIN_NO_RETRY",
        navigation_click_attempted: true,
        message_submission_attempted: false,
        ui_scheduler_authorized: false
      });
      return;
    }
    await page.waitForTimeout(400);
    let ready = false;
    let diagnosis = "ALIS_UI_PROJECT_NAVIGATION_NOT_VERIFIED";
    try {
      const after = await inspectLegacyUiReadOnly(page, project);
      const result = assessLegacyUiReadiness(after);
      ready = result.read_only_project_entry_ready === true;
      if (ready) diagnosis = "ALIS_UI_EMPTY_PROJECT_ENTRY_OBSERVED";
    } catch {
      // Navigation can detach its original renderer; do not click again.
    }
    writeJson({
      purpose: "alis-ui-project-navigation",
      status: ready ? "observed" : "unverified",
      diagnosis,
      empty_project_entry_ready: ready,
      navigation_click_attempted: true,
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

  if(command === "observe-submitted") {
    const prompt=await readStdin();
    if(!prompt.trim())throw Error('ALIS_UI_PENDING_PROMPT_REQUIRED');
    const targetKey=process.argv[3]??null;
    if(targetKey!==null&&!/^[0-9a-f]{64}$/.test(targetKey))throw Error('ALIS_UI_TARGET_ARGUMENT_INVALID');
    if(process.env.ALIS_UI_RESUME_CHAT_LABEL)
      await resumeUiChat(page,process.env.ALIS_UI_RESUME_CHAT_LABEL,
        {targetKey,initialPrompt:targetKey===null?prompt:null});
    if(targetKey===null)await uiOnlyTurnIdentity(page,{initialPrompt:prompt});
    writeJson(await observeSubmittedPrompt(page,prompt,{targetKey}));
    return;
  }

  if (command === "send" || command === "rotate-send") {
    const prompt = await readStdin();
    if (!prompt.trim()) throw new Error("stdin prompt is empty");
    const attempt=process.env.ALIS_UI_ATTEMPT_ID;
    if (/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(attempt ?? ""))
      dispatchIdentity={attempt_id:attempt,
        prompt_sha256:createHash("sha256").update(prompt).digest("hex")};
    const ownerReset=command === "rotate-send" &&
      process.argv[3] === "--owner-chat-reset";
    const unowned=command === "rotate-send" &&
      (process.argv[3] === "--unowned-previous-chat" || ownerReset);
    try {
      if (command === "rotate-send")
        page = await openHadalisNewChat(page, {
          unownedPreviousChat:unowned, ownerChatReset:ownerReset
        });

    // For managed Alis UI mode, require same uniquely selected conversation
    // between turns. A missing/changed chat must block BEFORE composer.fill.
    const expectedTarget = unowned ? null : process.argv[3] || null;
    if (expectedTarget) {
      if (command !== "send" || !/^[0-9a-f]{64}$/.test(expectedTarget))
        throw new Error("ALIS_UI_TARGET_ARGUMENT_INVALID");
      if(process.env.ALIS_UI_RESUME_CHAT_LABEL)
        await resumeUiChat(page,process.env.ALIS_UI_RESUME_CHAT_LABEL,{targetKey:expectedTarget});
      const current = createHash("sha256")
        .update(await uiOnlyTurnIdentity(page)).digest("hex");
      if (current !== expectedTarget)
        throw new Error("ALIS_UI_TARGET_CHANGED_NO_SEND");
    }

    } catch (error) {
      error.uiSendAttempted=false;
      error.uiFailureCode="ALIS_UI_PRE_SEND_FAILED";
      throw error;
    }

    const completionBaseline = await submitPrompt(page, prompt);
    const generation = await waitForCompletion(
      page,
      600000,
      completionBaseline
    );
    await extractLoopResponse(page, {
      baselineResponseActionCount: completionBaseline.responseActionCount
    });

    // After an initial send, the UI may not yet have exposed a persistent
    // chat ID. That is an uncertain mapping: never advance to the next send.
    if(command==='rotate-send')await uiOnlyTurnIdentity(page,{initialPrompt:prompt});
    const observed=await observeSubmittedPrompt(page,prompt,{
      targetKey:command==='send'?(process.argv[3]??null):null});
    if(!observed.completed)throw Error('ALIS_UI_ORIGINAL_ASSISTANT_FINAL_UNVERIFIED');
    writeJson({generation,...observed});
    return;
  }

  throw new Error(`unknown command: ${command}`);
}

main().then(
  () => process.exit(0),
  error => {
    if (dispatchIdentity && error.uiSendAttempted === false)
      writeJson({schema:"alis.ui-dispatch-failure.v1",...dispatchIdentity,
        send_attempted:false,code:error.uiFailureCode});
    else writeError(error);
    process.exit(1);
  }
);
