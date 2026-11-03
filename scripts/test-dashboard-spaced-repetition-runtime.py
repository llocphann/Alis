#!/usr/bin/env python3
"""Isolated Quickshell + private Niri runtime verification for the Dashboard Spaced Repetition tab."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]

QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.dashboard

Window {
    id: root
    visible: true
    width: 1240
    height: 820
    color: "#171a20"
    Component.onCompleted: Quickshell.watchFiles = false

    QtObject {
        id: fakeMusic
        property var libraryTracks: []
        property var activeQueue: []
        property var playlists: []
        property var localLyricsLines: []
        property var mprisPlayer: null
        property bool available: false
        property string error: ""
    }

    DashboardContent {
        id: dashboard
        anchors.fill: parent
        embeddedSurface: true
        presentationActive: true
        musicBackend: fakeMusic
    }

    TestCase {
        id: test
        when: false
        optional: true
        property int checks: 0
        function check(v, msg) {
            checks++;
            if (!v) throw new Error(msg);
        }

        function run() {
            try {
                tryCompare(Config, "ready", true, 6000);
                tryCompare(SpacedRepetition, "ready", true, 6000);

                if (Quickshell.env("SR_RUNTIME_ACTION") === "restart") {
                    check(SpacedRepetition.cards.some(c => c.term === "Herausforderung" && c.gender === "die" && c.cefrLevel === "B1"),
                        "Added German vocabulary card did not survive restart");
                    check(SpacedRepetition.cards.some(c => c.term === "quintessential" && c.cefrLevel === "C2"),
                        "Bulk-imported C2 English card did not survive restart");
                    check(SpacedRepetition.todayReviewedCount >= 1,
                        "Today reviewed count did not survive restart");
                    console.info("SR_RUNTIME_RESTART_PASS", checks);
                    Qt.quit();
                    return;
                }

                Config.setNestedValues({
                    "performance.reduceAnimations": true,
                    "dashboard.music.enable": false,
                    "dashboard.spacedRepetition.autoLookupOnline": false
                });

                check(dashboard.pageIds.includes("spacedRepetition"),
                    "spacedRepetition missing from DashboardContent.pageIds");
                dashboard.selectPage("spacedRepetition");
                tryCompare(dashboard, "currentPageId", "spacedRepetition", 3000);
                tryVerify(() => Math.abs(findChild(dashboard, "dashboardPages").pagePosition - dashboard.currentPage) < 0.01, 2000);

                const srView = findChild(dashboard, "dashboardSpacedRepetition");
                check(!!srView && srView.visible, "DashboardSpacedRepetition view did not mount");
                check(SpacedRepetition.totalCount >= 86, "Starter cards + 78 Unit 01-04 vocabulary cards were not seeded");
                check(SpacedRepetition.cards.filter(c => (c.deck || "").startsWith("Unit ")).length === 0,
                    "No card should retain 'Unit 01..04' deck; all should be synchronized to 'English Vocabulary'");
                check(SpacedRepetition.cards.filter(c => String(c.id || "").startsWith("sr-unit") && c.deck === "English Vocabulary" && (c.definitionEn || "").length > 0 && (c.meaningVi || "").length > 0 && c.reps === 0 && c.interval === 0 && c.state === "new").length === 78,
                    "All 78 imported vocabulary cards must be under 'English Vocabulary' with both English definitionEn + Vietnamese meaningVi and fresh review state");
                check(SpacedRepetition.hasActiveCard, "Study queue should have an active card");

                // 1. Reveal & Rate & Undo flow
                const firstCardId = SpacedRepetition.currentCard.id;
                const revealBtn = findChild(srView, "srRevealButton");
                check(!!revealBtn && revealBtn.visible, "Reveal button not visible");
                mouseClick(revealBtn);
                tryCompare(SpacedRepetition, "cardRevealed", true, 2000);
                const studyMorphStrip = findChild(srView, "srStudyMorphologyStrip");
                const studyMeaningVi = findChild(srView, "srStudyCardMeaningVi");
                const studyAnswerEn = findChild(srView, "srCardAnswerText");
                const topExampleBox = findChild(srView, "srStudyTopExampleBox");
                const topExampleText = findChild(srView, "srStudyTopExampleText");
                check(!!studyMorphStrip, "Study morphology strip component missing");
                check(!!topExampleBox && topExampleBox.visible && !!topExampleText && topExampleText.text.indexOf("<b><font color=\"#38bdf8\"><u>") !== -1,
                    "Top inline example box must be visible and highlight the target word with bold + color after reveal, got: " + (topExampleText ? topExampleText.text : "null"));
                check(!!studyMeaningVi && studyMeaningVi.visible && studyMeaningVi.text.length > 0 && studyMeaningVi.text.indexOf("🇻🇳") === -1,
                    "Study view must display Vietnamese meaningVi without flag emoji when card is revealed");
                const enViRow = findChild(srView, "srEnViRow");
                const enViSep = findChild(srView, "srEnViSeparator");
                const synAntSep = findChild(srView, "srSynAntSeparator");
                const studySyn = findChild(srView, "srStudyCardSynonyms");
                const studyAnt = findChild(srView, "srStudyCardAntonyms");
                const collocationsRow = findChild(srView, "srCollocationsRow");
                const collocationChip0 = findChild(srView, "srCollocationChip-0");
                const collocationPhrase0 = findChild(srView, "srCollocationPhrase-0");
                check(!!enViRow && enViRow.visible && !!studyAnswerEn && Math.abs(studyAnswerEn.mapToItem(srView, 0, 0).y - studyMeaningVi.mapToItem(srView, 0, 0).y) < 8,
                    "EN definition and VI meaning must sit on the same row in 2 columns in Flashcard mode");
                check(!!enViSep && enViSep.visible && !!synAntSep && synAntSep.visible && !!studySyn && !!studyAnt,
                    "2-column EN|VI and SYN|ANT rows must display vertical separators and dedicated SYN/ANT columns");
                check(!!collocationsRow && collocationsRow.visible && !!collocationChip0 && !!collocationPhrase0 && collocationPhrase0.text.length > 0,
                    "USE collocations row must render structured collocation pills");

                const rateGoodBtn = findChild(srView, "srRateGood");
                check(!!rateGoodBtn && rateGoodBtn.visible, "Rate Good button not visible after reveal");
                mouseClick(rateGoodBtn);
                tryVerify(() => SpacedRepetition.todayReviewedCount >= 1, 2000);
                check(SpacedRepetition.canUndoReview, "Undo stack should be populated after rating");

                const undoBtn = findChild(srView, "srUndoButton");
                check(!!undoBtn && undoBtn.enabled, "Undo button should be enabled");
                mouseClick(undoBtn);
                tryCompare(SpacedRepetition, "todayReviewedCount", 0, 2000);
                check(SpacedRepetition.currentCard.id === firstCardId, "Undo did not restore previous active card");

                // Rate again so we persist 1 review to disk
                SpacedRepetition.revealCard();
                SpacedRepetition.submitRating("good");
                tryCompare(SpacedRepetition, "todayReviewedCount", 1, 2000);

                // Verify Cloze mode target check against {{c1::...}} target and prefix guard
                SpacedRepetition.studyMode = "cloze";
                const clozeInput = findChild(srView, "srClozeInput");
                const checkClozeBtn = findChild(srView, "srCheckClozeButton");
                check(!!clozeInput && !!checkClozeBtn, "Cloze input or check button missing");
                const expectedClozeTarget = SpacedRepetition.extractClozeTarget(SpacedRepetition.currentCard);
                clozeInput.text = expectedClozeTarget.slice(0, 1);
                mouseClick(checkClozeBtn);
                check(srView.clozeCheckState === "miss", "Single-character prefix should not pass as close match");
                srView.resetCardInteraction();
                clozeInput.text = expectedClozeTarget;
                mouseClick(checkClozeBtn);
                check(srView.clozeCheckState === "exact", "Exact {{c1::...}} cloze target did not match as exact");
                SpacedRepetition.studyMode = "flashcard";
                srView.resetCardInteraction();

                // 2. Switch to Capture & Auto-Syntax sub-tab
                const captureTabBtn = findChild(srView, "srSubTabCapture");
                check(!!captureTabBtn, "Capture sub-tab button missing");
                mouseClick(captureTabBtn);
                tryCompare(srView, "activeSubTab", "capture", 2000);

                const composerFront = findChild(srView, "srComposerFront");
                const composerScroll = findChild(srView, "srComposerScrollView");
                const autoCefrBadge = findChild(srView, "srComposerAutoCefr");
                const composerMorphStrip = findChild(srView, "srComposerMorphologyStrip");
                check(!!composerFront && !!composerScroll && !!autoCefrBadge && !!composerMorphStrip,
                    "Composer front field, scroll view, auto-CEFR badge, or morphology strip missing");
                tryVerify(() => composerScroll.width >= 400 && Math.abs(composerFront.width - composerScroll.width) <= 2, 2000);

                // Verify clicking composerFront gives activeFocus + visible cursor and accepts typing
                composerFront.text = "";
                mouseClick(composerFront);
                wait(50);
                check(composerFront.activeFocus === true && composerFront.cursorVisible === true,
                    "Composer front field must show cursor when clicked with mouseClick");
                keyClick(Qt.Key_U);
                keyClick(Qt.Key_B);
                check(composerFront.text.toLowerCase() === "ub", "Typing keys into mouse-clicked composerFront did not append text");

                composerFront.text = "ubiquitous";
                tryCompare(srView, "draftAutoCefr", "C1", 2000);
                check((srView.draftPreview?.phonetics ?? "").length > 0, "Expected auto-populated IPA phonetics in draftPreview");
                check(srView.formatPosLabel(srView.draftPreview?.pos) === "Adjective", "Expected auto-populated POS 'Adjective' in draftPreview");
                check((srView.draftPreview?.synonyms?.length ?? 0) > 0, "Expected auto-populated synonyms in draftPreview");
                check((srView.draftPreview?.antonyms?.length ?? 0) > 0, "Expected auto-populated antonyms in draftPreview");
                check((srView.draftPreview?.morphologyText ?? "").includes("ubique"), "Expected auto-populated morphologyText for 'ubiquitous'");
                check(composerMorphStrip.visible === true, "Composer morphology strip should be visible when morphologyText is present");
                check(srView.composerBack.length > 0, "Expected composerBack to auto-populate meaning for 'ubiquitous'");
                check(srView.composerExample.length > 0, "Expected composerExample to auto-populate example for 'ubiquitous'");

                // Verify German adjective 'nachhaltig' never gets noun article 'der'
                const nachhaltigCard = SpacedRepetition.cards.find(c => c.term === "nachhaltig");
                check(!!nachhaltigCard && nachhaltigCard.front === "nachhaltig" && nachhaltigCard.gender === "",
                    "German adjective 'nachhaltig' must not have noun article 'der'");

                // Verify enrichCardOnline preserves user-authored back/example while filling missing metadata
                const customAdded = SpacedRepetition.addCard({
                    front: "pragmatic",
                    back: "custom user definition",
                    example: "Custom user example for pragmatic.",
                    category: "vocabulary",
                    language: "en"
                });
                check(!!customAdded, "Failed to add custom card");
                SpacedRepetition.enrichCardOnline(customAdded.id);
                const enrichedCustom = SpacedRepetition.cards.find(c => c.id === customAdded.id);
                check(enrichedCustom.back === "custom user definition", "enrichCardOnline overwrote user's custom back");
                check(enrichedCustom.example === "Custom user example for pragmatic.", "enrichCardOnline overwrote user's custom example");

                // Verify Bulk Auto-Syntax Guide button & physical Escape key closing
                const guideBtn = findChild(srView, "srBulkSyntaxGuideButton");
                const guidePanel = findChild(srView, "srBulkSyntaxGuidePanel");
                const guideFooter = findChild(srView, "srBulkSyntaxGuideFooterHint");
                check(!!guideBtn && !!guidePanel && !!guideFooter, "Bulk syntax guide button, panel, or footer hint missing");
                check(srView.bulkShowSyntaxGuide === false && guidePanel.visible === false, "Bulk syntax guide should be hidden by default");
                mouseClick(guideBtn);
                tryCompare(srView, "bulkShowSyntaxGuide", true, 1000);
                check(guidePanel.visible === true && guideFooter.visible === true, "Bulk syntax guide panel and footer hint should be visible when toggled on");
                keyClick(Qt.Key_Escape);
                tryCompare(srView, "bulkShowSyntaxGuide", false, 1000);
                check(guidePanel.visible === false, "Bulk syntax guide panel should close on physical Escape key press");

                // Verify Escape handling: closes manual overrides drawer if open, otherwise returns false so Dashboard closes
                check(srView.handleEscape() === false, "handleEscape() should return false when manual override drawer is closed");
                srView.composerShowManualOverrides = true;
                check(srView.handleEscape() === true, "handleEscape() should return true and close manual override drawer when open");
                check(srView.composerShowManualOverrides === false, "Manual override drawer should be closed after handleEscape()");

                // Quick add German noun with article & example
                const quickField = findChild(srView, "srQuickAddField");
                check(!!quickField, "Quick add field missing");
                quickField.text = "die Herausforderung - challenge; demanding task // Das ist eine große Herausforderung.";
                quickField.accepted();
                tryVerify(() => SpacedRepetition.cards.some(
                    c => c.term === "Herausforderung"
                      && c.gender === "die"
                      && c.cefrLevel === "B1"
                      && c.clozeText === "Das ist eine große {{c1::Herausforderung}}."
                ), 3000);

                // Bulk import
                const bulkArea = findChild(srView, "srBulkInputArea");
                const bulkImportBtn = findChild(srView, "srBulkImportButton");
                check(!!bulkArea && !!bulkImportBtn, "Bulk input controls missing");
                bulkArea.text = "quintessential - representing the most perfect example // Active recall is the quintessential study method.";
                mouseClick(bulkImportBtn);
                tryVerify(() => SpacedRepetition.cards.some(
                    c => c.term === "quintessential" && c.cefrLevel === "C2"
                ), 3000);
                check(bulkArea.text === "", "Bulk input TextArea did not clear after import");

                // 3. Switch to Library sub-tab and verify both service searchQuery and UI srLibrarySearch filter srView.filteredLibraryCards
                const libraryTabBtn = findChild(srView, "srSubTabLibrary");
                mouseClick(libraryTabBtn);
                tryCompare(srView, "activeSubTab", "library", 2000);
                SpacedRepetition.searchQuery = "allot";
                tryVerify(() => SpacedRepetition.filteredLibraryCards.length === 1 && srView.filteredLibraryCards.length === 1, 2000);
                wait(80);

                // Verify Library card shows English definition in 1-line summary by default and reveals Vietnamese meaning + full details on hover
                const firstLibSummaryEn = findChild(srView, "srLibraryCardSummaryDefEn");
                const firstLibHoverDetails = findChild(srView, "srLibraryCardHoverDetails");
                const firstLibMeaningVi = findChild(srView, "srLibraryCardMeaningVi");
                check(!!firstLibSummaryEn && !!firstLibHoverDetails && !!firstLibMeaningVi,
                    "srLibraryCardSummaryDefEn, srLibraryCardHoverDetails, or srLibraryCardMeaningVi missing in library card delegate");
                check(firstLibSummaryEn.text.indexOf("to give a particular share") !== -1,
                    "Un-hovered library card summary must display the English definition, got: " + firstLibSummaryEn.text);
                const firstLibDelegate = firstLibHoverDetails.parent.parent;
                check(firstLibDelegate.detailsVisible === false && firstLibHoverDetails.visible === false,
                    "Library card hover details must be hidden by default when not hovered");
                firstLibDelegate.forceHoverDetail = true;
                check(firstLibDelegate.detailsVisible === true && firstLibHoverDetails.visible === true && firstLibMeaningVi.visible === true,
                    "Library card hover details and Vietnamese meaning must become visible when hovered");
                check(firstLibMeaningVi.text.indexOf("phân bổ") !== -1,
                    "Hovered library card must display Vietnamese definition meaningVi, got: " + firstLibMeaningVi.text);
                firstLibDelegate.forceHoverDetail = false;

                SpacedRepetition.clearFilters();
                const libSearchField = findChild(srView, "srLibrarySearch");
                check(!!libSearchField, "Library search field missing");
                libSearchField.text = "";
                mouseClick(libSearchField);
                wait(50);
                check(libSearchField.activeFocus === true && libSearchField.cursorVisible === true,
                    "Library search field should accept activeFocus and show cursor on mouseClick");
                keyClick(Qt.Key_Q);
                keyClick(Qt.Key_U);
                keyClick(Qt.Key_I);
                keyClick(Qt.Key_N);
                keyClick(Qt.Key_T);
                tryVerify(() => srView.filteredLibraryCards.length === 1 && SpacedRepetition.filteredLibraryCards.length === 1, 2000);
                libSearchField.text = "";

                // Verify switching subTab away from a focused input transfers activeFocus back to srView
                const studyTabBtn = findChild(srView, "srSubTabStudy");
                check(!!studyTabBtn, "Study sub-tab button missing");
                mouseClick(studyTabBtn);
                tryCompare(srView, "activeSubTab", "study", 2000);
                check(libSearchField.activeFocus === false, "Hidden library search field must not retain activeFocus after switching subTab");
                check(srView.activeFocus === true, "srView must reclaim activeFocus when switching to study subTab");

                // Verify Study keyboard shortcuts (Space to reveal only, disabled after reveal; 0-3 to rate; M to cycle mode; Ctrl+Z to undo)
                SpacedRepetition.studyMode = "flashcard";
                srView.resetCardInteraction();
                wait(60);
                check(srView.answerRevealed === false, "Expected answerRevealed === false before pressing Space");
                keyClick(Qt.Key_Space);
                wait(60);
                check(srView.answerRevealed === true, "Pressing Space in Study mode must reveal answer");
                const beforeShortcutReviewCount = SpacedRepetition.todayReviewedCount;
                const activeCardBeforeSpace = SpacedRepetition.currentCard.id;
                keyClick(Qt.Key_Space);
                wait(60);
                check(SpacedRepetition.todayReviewedCount === beforeShortcutReviewCount
                    && srView.answerRevealed === true
                    && SpacedRepetition.currentCard.id === activeCardBeforeSpace,
                    "Pressing Space again after answer is revealed must NOT submit a rating or advance to the next card");
                keyClick(Qt.Key_2);
                wait(60);
                check(SpacedRepetition.todayReviewedCount === beforeShortcutReviewCount + 1 && srView.answerRevealed === false,
                    "Pressing '2' (Good) when answer is revealed must submit 'good' rating and advance card");
                keyClick(Qt.Key_Z, Qt.ControlModifier);
                wait(60);
                check(SpacedRepetition.todayReviewedCount === beforeShortcutReviewCount,
                    "Pressing Ctrl+Z in Study mode must undo last review");
                keyClick(Qt.Key_M);
                wait(60);
                check(SpacedRepetition.studyMode === "reverse", "Pressing 'M' in Study mode must cycle studyMode to 'reverse'");

                // Verify Multiple Choice ('mc') & Reverse Multiple Choice ('rmc') modes (4 options, reveal all 4 answers after selection)
                SpacedRepetition.studyMode = "mc";
                srView.resetCardInteraction();
                wait(60);
                const mcGrid = findChild(srView, "srMultipleChoiceGrid");
                const mcOpt0 = findChild(srView, "srMcOption-0");
                const mcOpt3 = findChild(srView, "srMcOption-3");
                const mcTerm0 = findChild(srView, "srMcOptionTerm-0");
                const mcDef0 = findChild(srView, "srMcOptionDef-0");
                check(!!mcGrid && mcGrid.visible && srView.multipleChoiceOptions.length === 4 && !!mcOpt0 && !!mcOpt3,
                    "Multiple Choice mode must display 4 option buttons instead of Reveal Answer button");
                check(revealBtn.visible === false, "Reveal Answer button must be hidden in Multiple Choice mode");
                check(mcTerm0.visible === false, "Before selecting an option in MC mode, option term should be hidden");
                // Pressing Space before staging any option in MC mode must not reveal
                keyClick(Qt.Key_Space);
                wait(30);
                check(srView.answerRevealed === false && srView.pendingChoiceIndex === -1,
                    "Pressing Space in MC mode when no option is staged must not reveal the answer");
                // Stage option B with '2', then stage option A with 'A', then confirm with Space
                keyClick(Qt.Key_2);
                wait(40);
                check(srView.answerRevealed === false && srView.pendingChoiceIndex === 1,
                    "Pressing '2' in MC mode before reveal must stage option B (index 1) without revealing yet");
                keyClick(Qt.Key_A);
                wait(40);
                const pendingBadge0 = findChild(srView, "srMcOptionPendingBadge-0");
                check(srView.answerRevealed === false && srView.pendingChoiceIndex === 0 && !!pendingBadge0 && pendingBadge0.visible,
                    "Pressing 'A' in MC mode before reveal must stage option A (index 0) and show Space badge");
                keyClick(Qt.Key_Space);
                wait(60);
                check(srView.answerRevealed === true && srView.selectedChoiceIndex === 0,
                    "Pressing Space after staging an option in MC mode must confirm selection and reveal the answer");
                check(enViRow.visible === false,
                    "Bottom EN|VI definition row must be hidden in Multiple Choice mode since options already show definitions");
                for (let idx = 0; idx < 4; idx++) {
                    const optBtn = findChild(srView, "srMcOption-" + idx);
                    const tItem = findChild(srView, "srMcOptionTerm-" + idx);
                    const dItem = findChild(srView, "srMcOptionDef-" + idx);
                    const viItem = findChild(srView, "srMcOptionMeaningVi-" + idx);
                    check(!!tItem && tItem.visible,
                        "After selecting an option in MC mode, all 4 options must show their term (failed at index " + idx + ")");
                    if (optBtn.isRight || optBtn.isChosen) {
                        check(optBtn.detailsExpanded === true && dItem.visible === true,
                            "Chosen and correct options must show their definition by default");
                    } else {
                        check(optBtn.detailsExpanded === false && dItem.visible === false,
                            "Unchosen distractor options must keep their definition hidden until hovered");
                        optBtn.forceHoverDetail = true;
                        check(optBtn.detailsExpanded === true && dItem.visible === true && (!optBtn.modelData.meaningVi || viItem.visible === true),
                            "Hovering an unchosen distractor option must slide open its EN and VI definition lines");
                        optBtn.forceHoverDetail = false;
                    }
                }

                SpacedRepetition.studyMode = "rmc";
                srView.resetCardInteraction();
                wait(60);
                const rmcOpt1 = findChild(srView, "srMcOption-1");
                const rmcTerm1 = findChild(srView, "srMcOptionTerm-1");
                const rmcDef1 = findChild(srView, "srMcOptionDef-1");
                check(srView.multipleChoiceOptions.length === 4 && rmcTerm1.visible === true && rmcDef1.visible === false,
                    "Before selecting an option in Reverse Multiple Choice mode, options must show terms and hide definitions");
                mouseClick(rmcOpt1);
                wait(60);
                check(srView.answerRevealed === true && srView.selectedChoiceIndex === 1,
                    "Clicking an option in RMC mode must reveal the answer");
                for (let idx = 0; idx < 4; idx++) {
                    const optBtn = findChild(srView, "srMcOption-" + idx);
                    const tItem = findChild(srView, "srMcOptionTerm-" + idx);
                    const dItem = findChild(srView, "srMcOptionDef-" + idx);
                    check(!!tItem && tItem.visible,
                        "After selecting an option in RMC mode, all 4 options must show their term (failed at index " + idx + ")");
                    if (optBtn.isRight || optBtn.isChosen) {
                        check(optBtn.detailsExpanded === true && dItem.visible === true,
                            "Chosen and correct options in RMC mode must show their definition by default");
                    } else {
                        check(optBtn.detailsExpanded === false && dItem.visible === false,
                            "Unchosen distractor options in RMC mode must keep their definition hidden until hovered");
                    }
                }

                SpacedRepetition.studyMode = "flashcard";
                srView.resetCardInteraction();

                // Ensure saveToFile completes
                SpacedRepetition.saveToFile();
                tryCompare(SpacedRepetition, "persistenceBusy", false, 4000);

                console.info("SR_RUNTIME_PASS", checks);
            } catch (e) {
                console.error("SR_RUNTIME_FAIL", e.message, e.stack);
            }
            Qt.quit();
        }
    }

    Timer {
        interval: 200
        running: true
        onTriggered: test.run()
    }
}
'''

ABYSS_PERIMETER_QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
import qs.modules.regionSelector

ShellRoot {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false
    AbyssPerimeter { id: perimeter }
    OptionsToolbar { id: testRegionToolbar; visible: false }
    TestCase {
        id: tc
        parent: perimeter.outputHosts.length > 0 ? perimeter.outputHosts[0].contentItem : null
        name: "AbyssPerimeterSRTest"
        when: false
        optional: true
        property int checks: 0
        function check(v, msg) {
            checks++;
            if (!v) throw new Error(msg);
        }
        function runTest() {
            try {
                tryCompare(Config, "ready", true, 5000);
                tryCompare(SpacedRepetition, "ready", true, 5000);
                GlobalStates.shellEntryReady = true;
                GlobalStates.deferredPanelsReady = true;
                tryVerify(() => perimeter.outputHosts.length > 0 && perimeter.outputHosts[0].nativeFieldReady, 6000);
                const win = perimeter.outputHosts[0];
                GlobalStates.dashboardOpen = true;
                tryVerify(() => findChild(win.contentItem, "dashboardSpacedRepetitionPageLoader") !== null, 5000);
                GlobalStates.dashboardPageId = "spacedRepetition";
                tryVerify(() => findChild(win.contentItem, "dashboardSpacedRepetition") !== null, 5000);
                const srView = findChild(win.contentItem, "dashboardSpacedRepetition");
                tryVerify(() => srView.visible && srView.presentationActive, 3000);
                wait(150);
                // Verify Study shortcuts work inside AbyssPerimeter after switching to Spaced Repetition tab
                srView.subTab = "study";
                srView.resetCardInteraction();
                wait(80);
                keyClick(Qt.Key_Space);
                wait(80);
                check(srView.answerRevealed === true,
                    "Space shortcut must reveal flashcard answer inside AbyssPerimeter Study tab");
                srView.resetCardInteraction();
                srView.subTab = "capture";
                const composerFront = findChild(srView, "srComposerFront");
                tryVerify(() => composerFront && composerFront.visible && composerFront.width > 100, 5000);
                wait(150);

                // 1. Click & type into srComposerFront inside AbyssPerimeter without focus theft
                composerFront.text = "";
                mouseClick(composerFront);
                wait(150);
                check(composerFront.activeFocus === true && composerFront.cursorVisible === true,
                    "srComposerFront lost activeFocus or cursorVisible inside AbyssPerimeter");
                check(win.activeWindowFocusItem === composerFront,
                    "AbyssPerimeter.activeWindowFocusItem did not track srComposerFront");
                keyClick(Qt.Key_A);
                keyClick(Qt.Key_L);
                keyClick(Qt.Key_L);
                keyClick(Qt.Key_O);
                keyClick(Qt.Key_T);
                wait(80);
                check(composerFront.text.toLowerCase() === "allot",
                    "keyClick typing into srComposerFront inside AbyssPerimeter failed: " + composerFront.text);

                // 2. Toggle Bulk Syntax Guide and close with physical Escape inside AbyssPerimeter
                const guideBtn = findChild(srView, "srBulkSyntaxGuideButton");
                const guidePanel = findChild(srView, "srBulkSyntaxGuidePanel");
                mouseClick(guideBtn);
                tryCompare(srView, "bulkShowSyntaxGuide", true, 1000);
                check(guidePanel.visible === true, "srBulkSyntaxGuidePanel did not open inside AbyssPerimeter");
                keyClick(Qt.Key_Escape);
                tryCompare(srView, "bulkShowSyntaxGuide", false, 1000);
                check(GlobalStates.dashboardOpen === true, "Escape while closing Bulk Syntax Guide must not close Dashboard");

                // 3. Switch to Library, click & type into srLibrarySearch inside AbyssPerimeter
                srView.subTab = "library";
                const libSearchField = findChild(srView, "srLibrarySearch");
                tryVerify(() => libSearchField && libSearchField.visible && libSearchField.width > 100, 3000);
                wait(100);
                libSearchField.text = "";
                mouseClick(libSearchField);
                wait(150);
                check(libSearchField.activeFocus === true && libSearchField.cursorVisible === true,
                    "srLibrarySearch lost activeFocus or cursorVisible inside AbyssPerimeter");
                check(win.activeWindowFocusItem === libSearchField,
                    "AbyssPerimeter.activeWindowFocusItem did not track srLibrarySearch");
                keyClick(Qt.Key_A);
                keyClick(Qt.Key_L);
                keyClick(Qt.Key_L);
                keyClick(Qt.Key_O);
                keyClick(Qt.Key_T);
                tryVerify(() => srView.filteredLibraryCards.some(c => c.term === "allot" && c.deck === "English Vocabulary"), 2000);

                // 4. Verify OptionsToolbar initializes to Copy/Screenshot (0) + RectCorners/Square (0) and highlights Active Tab immediately
                check(testRegionToolbar.action === 0 && testRegionToolbar.selectionMode === 0,
                    `Expected OptionsToolbar to initialize to action=0 (Screenshot) and selectionMode=0 (Square), got action=${testRegionToolbar.action}, selectionMode=${testRegionToolbar.selectionMode}`);
                const actionTabBar = findChild(testRegionToolbar, "regionActionTabBar");
                const modeTabBar = findChild(testRegionToolbar, "regionModeTabBar");
                const actionIndicator = findChild(actionTabBar, "activeIndicator");
                const modeIndicator = findChild(modeTabBar, "activeIndicator");
                check(!!actionIndicator && actionIndicator.width > 0 && !!modeIndicator && modeIndicator.width > 0,
                    `Expected OptionsToolbar activeIndicator width > 0 on initial open, got action=${actionIndicator?.width}, mode=${modeIndicator?.width}`);
                check(actionIndicator.targetItem?.toggled === true && modeIndicator.targetItem?.toggled === true,
                    "Expected OptionsToolbar active tab buttons to have toggled === true for colPrimaryContainer background");

                // 4b. Verify Edit Dashboard Layout custom tab buttons and Create Custom Tab input cursor/typing inside AbyssPerimeter
                GlobalStates.dashboardPageId = "dashboard";
                const editBtn = findChild(win.contentItem, "dashboardEditLayoutButton");
                const createTabBtn = findChild(win.contentItem, "dashboardCreateCustomTab");
                const renameTabBtn = findChild(win.contentItem, "dashboardRenameCustomTab");
                const deleteTabBtn = findChild(win.contentItem, "dashboardDeleteCustomTab");
                const toolbarCreateBtn = findChild(win.contentItem, "dashboardToolbarActionCreateTab");
                const tabNameInput = findChild(win.contentItem, "dashboardToolbarTabName");
                check(!!editBtn && !!createTabBtn && !!renameTabBtn && !!deleteTabBtn && !!toolbarCreateBtn && !!tabNameInput,
                    "Missing Edit Dashboard Layout custom tab controls or tabNameInput inside AbyssPerimeter");
                editBtn.clicked();
                tryVerify(() => createTabBtn.visible && renameTabBtn.visible && deleteTabBtn.visible && toolbarCreateBtn.visible && toolbarCreateBtn.enabled, 3000);
                wait(100);
                createTabBtn.clicked();
                tryVerify(() => tabNameInput.visible && tabNameInput.width > 80, 2000);
                wait(150);
                check(tabNameInput.activeFocus === true && tabNameInput.cursorVisible === true,
                    "dashboardCustomTabNameInput must retain activeFocus and cursorVisible inside AbyssPerimeter");
                keyClick(Qt.Key_W);
                keyClick(Qt.Key_O);
                keyClick(Qt.Key_R);
                keyClick(Qt.Key_K);
                wait(60);
                check(tabNameInput.text.toLowerCase() === "work",
                    "Typing into dashboardCustomTabNameInput inside AbyssPerimeter did not update text: " + tabNameInput.text);
                keyClick(Qt.Key_Escape);
                wait(60);
                keyClick(Qt.Key_Escape);
                wait(60);

                // 5. Verify WallpaperLauncherContent inside AbyssPerimeter receives focus and navigates with Vim h/j/k/l keys
                GlobalStates.dashboardOpen = false;
                GlobalStates.wallpaperLauncherOpen = true;
                tryVerify(() => findChild(win.contentItem, "wallpaperLauncherContent") !== null, 4000);
                const wallContent = findChild(win.contentItem, "wallpaperLauncherContent");
                const wallCarousel = findChild(wallContent, "wallpaperCarousel");
                const wallSearch = findChild(wallContent, "wallpaperSearch");
                wallCarousel.entries = [
                    { path: "/tmp/wall1.png", name: "wall1.png", relativePath: "wall1.png", folder: "" },
                    { path: "/tmp/wall2.png", name: "wall2.png", relativePath: "wall2.png", folder: "" },
                    { path: "/tmp/wall3.png", name: "wall3.png", relativePath: "wall3.png", folder: "" }
                ];
                wait(250);
                check(wallContent.activeFocus === true && wallSearch.activeFocus === false,
                    "WallpaperLauncherContent should have activeFocus on open (with search unfocused so h/j/k/l navigate)");
                const initialIdx = wallContent.currentIndex;
                keyClick(Qt.Key_L);
                wait(60);
                check(wallContent.currentIndex === initialIdx + 1,
                    `Pressing 'l' in Change Wallpaper should increment currentIndex from ${initialIdx} to ${initialIdx + 1}, got ${wallContent.currentIndex}`);
                keyClick(Qt.Key_H);
                wait(60);
                check(wallContent.currentIndex === initialIdx,
                    `Pressing 'h' in Change Wallpaper should decrement currentIndex back to ${initialIdx}, got ${wallContent.currentIndex}`);
                keyClick(Qt.Key_J);
                wait(60);
                check(wallContent.currentIndex === initialIdx + 1,
                    `Pressing 'j' in Change Wallpaper should increment currentIndex to ${initialIdx + 1}, got ${wallContent.currentIndex}`);
                keyClick(Qt.Key_K);
                wait(60);
                check(wallContent.currentIndex === initialIdx,
                    `Pressing 'k' in Change Wallpaper should decrement currentIndex back to ${initialIdx}, got ${wallContent.currentIndex}`);

                console.info("SR_ABYSS_PERIMETER_PASS", checks);
            } catch (e) {
                console.error("SR_RUNTIME_FAIL", e.message, e.stack);
            }
            Qt.quit();
        }
    }
    Timer { interval: 100; running: true; onTriggered: tc.runTest() }
}
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-sr-runtime-") as tmp:
        folder = Path(tmp)
        for name in (
            "modules",
            "services",
            "GlobalStates.qml",
            "qmldir",
            "assets",
            "scripts",
            "defaults",
            "translations",
        ):
            (folder / name).symlink_to(ROOT / name)
        (folder / "shell.qml").write_text(QML, encoding="utf-8")

        with private_wayland(folder, capture_focus=True) as env:
            if env is None:
                print("SKIP: Spaced Repetition runtime test requires a private Niri backend")
                raise SystemExit(0)

            for cfg_rel in ("config/alis/config.json", "config/illogical-impulse/config.json"):
                cfg_file = folder / cfg_rel
                cfg_file.parent.mkdir(parents=True, exist_ok=True)
                sample = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
                sample["panelFamily"] = "abyss"
                sample["abyss"]["companion"]["enabled"] = False
                cfg_file.write_text(json.dumps(sample), encoding="utf-8")

            result = run_qs(folder, env, timeout=35)
            failures = (
                "SR_RUNTIME_FAIL",
                "ReferenceError:",
                "TypeError:",
                "Binding loop",
                "Unable to assign",
                "Cannot assign to non-existent property",
            )
            def has_failure(log_text: str) -> bool:
                for line in log_text.splitlines():
                    if "@services/Audio.qml" in line:
                        continue
                    if any(phrase in line for phrase in failures):
                        return True
                return False

            if (
                result.returncode
                or "SR_RUNTIME_PASS" not in result.stdout
                or has_failure(result.stdout)
            ):
                print(result.stdout)
                raise SystemExit(1)

            restarted = run_qs(folder, dict(env, SR_RUNTIME_ACTION="restart"), timeout=25)
            if (
                restarted.returncode
                or "SR_RUNTIME_RESTART_PASS" not in restarted.stdout
                or has_failure(restarted.stdout)
            ):
                print(restarted.stdout)
                raise SystemExit(1)

            (folder / "shell.qml").write_text(ABYSS_PERIMETER_QML, encoding="utf-8")
            abyss_res = run_qs(folder, dict(env, QSG_RHI_BACKEND="opengl"), timeout=30)
            if (
                abyss_res.returncode
                or "SR_ABYSS_PERIMETER_PASS" not in abyss_res.stdout
                or has_failure(abyss_res.stdout)
            ):
                print(abyss_res.stdout)
                raise SystemExit(1)

            for line in (result.stdout + restarted.stdout + abyss_res.stdout).splitlines():
                if any(tag in line for tag in ("SR_RUNTIME_PASS", "SR_RUNTIME_RESTART_PASS", "SR_ABYSS_PERIMETER_PASS")):
                    print(line)


if __name__ == "__main__":
    main()

