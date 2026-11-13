#!/usr/bin/env python3
"""Contract & unit test suite for the Dashboard Spaced Repetition tab, SM-2+ engine,
automated zero-markup syntax parser, and English/German CEFR (A1-C2) lexicon."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_node_engine_tests() -> None:
    node_script = r"""
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

const lexiconCode = fs.readFileSync("services/SpacedRepetitionLexicon.js", "utf8")
    .replace(/^\.pragma\s+library\s*$/m, "");
const engineCode = fs.readFileSync("services/SpacedRepetitionEngine.js", "utf8")
    .replace(/^\.pragma\s+library\s*$/m, "")
    .replace(/^\.import\s+"SpacedRepetitionLexicon\.js"\s+as\s+Lexicon\s*$/m, "");

const sandbox = { console, Math, Date, JSON, Array, Object, String, Number, Boolean, RegExp };
vm.createContext(sandbox);
vm.runInContext(lexiconCode, sandbox, { filename: "SpacedRepetitionLexicon.js" });
sandbox.Lexicon = sandbox;
vm.runInContext(engineCode, sandbox, { filename: "SpacedRepetitionEngine.js" });

// 1. Test English CEFR A1-C2 Lexicon & Heuristics
const enExpected = {
    book: "A1",
    available: "A2",
    achieve: "B1",
    sustainable: "B2",
    inevitable: "B2",
    alleviate: "C1",
    ubiquitous: "C1",
    ephemeral: "C1",
    quintessential: "C2",
    corroborate: "C2"
};
for (const [word, expectedLevel] of Object.entries(enExpected)) {
    const info = sandbox.analyzeTerm(word, "en");
    assert.strictEqual(info.language, "en", `Expected language 'en' for ${word}`);
    assert.strictEqual(info.cefrLevel, expectedLevel, `Expected ${expectedLevel} for ${word}, got ${info.cefrLevel}`);
    assert.ok(info.phonetics.length > 0, `Expected phonetics for curated word ${word}`);
    assert.ok(info.pos.length > 0, `Expected POS for curated word ${word}`);
    assert.ok(Array.isArray(info.synonyms) && info.synonyms.length > 0, `Expected synonyms for curated word ${word}`);
    assert.ok(Array.isArray(info.antonyms), `Expected antonyms array for curated word ${word}`);
    if (word !== "book") {
        assert.ok(info.antonyms.length > 0, `Expected non-empty antonyms for ${word}`);
    }
}

// 2. Test German CEFR A1-C2 Lexicon + Gender/Article + Suffix Inference
const deExpected = {
    "der Bahnhof": { level: "A1", gender: "der", headword: "Bahnhof", hasAntonyms: false },
    "die Sehenswürdigkeit": { level: "A2", gender: "die", headword: "Sehenswürdigkeit", hasAntonyms: false },
    "die Herausforderung": { level: "B1", gender: "die", headword: "Herausforderung", hasAntonyms: true },
    "die Erkenntnis": { level: "B2", gender: "die", headword: "Erkenntnis", hasAntonyms: true },
    "beeinträchtigen": { level: "C1", gender: "", headword: "beeinträchtigen", hasAntonyms: true },
    "unabdingbar": { level: "C2", gender: "", headword: "unabdingbar", hasAntonyms: true }
};
for (const [term, exp] of Object.entries(deExpected)) {
    const info = sandbox.analyzeTerm(term, "");
    assert.strictEqual(info.language, "de", `Expected auto-detected 'de' for ${term}`);
    assert.strictEqual(info.cefrLevel, exp.level, `Expected ${exp.level} for ${term}, got ${info.cefrLevel}`);
    assert.strictEqual(info.gender, exp.gender, `Expected gender '${exp.gender}' for ${term}, got '${info.gender}'`);
    assert.strictEqual(info.headword, exp.headword, `Expected headword '${exp.headword}' for ${term}`);
    assert.ok(info.phonetics.length > 0, `Expected phonetics for curated German word ${term}`);
    assert.ok(info.pos.length > 0, `Expected POS for curated German word ${term}`);
    assert.ok(Array.isArray(info.synonyms) && info.synonyms.length > 0, `Expected synonyms for curated German word ${term}`);
    assert.ok(Array.isArray(info.antonyms), `Expected antonyms array for curated German word ${term}`);
    if (exp.hasAntonyms) {
        assert.ok(info.antonyms.length > 0, `Expected non-empty antonyms for ${term}`);
    }
}

// German suffix gender inference for uncurated nouns
assert.strictEqual(sandbox.inferGermanArticle("Freundschaft"), "die");
assert.strictEqual(sandbox.inferGermanArticle("Mädchen"), "das");
assert.strictEqual(sandbox.inferGermanArticle("Eigentum"), "das");
assert.strictEqual(sandbox.inferGermanArticle("Kapitalismus"), "der");

// Heuristic fallback for unknown English/German words and edge cases
const emptyAnalysis = sandbox.analyzeTerm("", "en");
assert.strictEqual(emptyAnalysis.cefrLevel, "");
const heuristicC1 = sandbox.analyzeTerm("unquestionably", "en");
assert.ok(["B2", "C1", "C2"].includes(heuristicC1.cefrLevel), `Expected B2-C2 for 'unquestionably', got ${heuristicC1.cefrLevel}`);

// 3. Test Auto-Cloze Generation (zero manual markup needed, including German umlaut boundaries & separable verbs)
const autoClozeEn = sandbox.autoGenerateCloze("ephemeral", "Fashion is by nature ephemeral.");
assert.strictEqual(autoClozeEn, "Fashion is by nature {{c1::ephemeral}}.");
const autoClozeDe = sandbox.autoGenerateCloze("die Herausforderung", "Der Klimawandel ist eine globale Herausforderung.");
assert.strictEqual(autoClozeDe, "Der Klimawandel ist eine globale {{c1::Herausforderung}}.");
const autoClozeUmlautStart = sandbox.autoGenerateCloze("der Überblick", "Das Dashboard gibt einen klaren Überblick über alle Karten.", "der");
assert.strictEqual(autoClozeUmlautStart, "Das Dashboard gibt einen klaren {{c1::Überblick}} über alle Karten.");
const autoClozeEszettEnd = sandbox.autoGenerateCloze("groß", "Der Erfolg war groß.", "");
assert.strictEqual(autoClozeEszettEnd, "Der Erfolg war {{c1::groß}}.");
const autoClozeSeparable1 = sandbox.autoGenerateCloze("sich auseinandersetzen mit", "Er setzt sich intensiv mit dem Thema auseinander.", "sich");
assert.strictEqual(autoClozeSeparable1, "Er {{c1::setzt}} sich intensiv mit dem Thema {{c2::auseinander}}.");
const autoClozeSeparable2 = sandbox.autoGenerateCloze("widerspiegeln", "Die Statistiken spiegeln deinen täglichen Lernfortschritt genau wider.", "");
assert.strictEqual(autoClozeSeparable2, "Die Statistiken {{c1::spiegeln}} deinen täglichen Lernfortschritt genau {{c2::wider}}.");
assert.strictEqual(JSON.stringify(sandbox.extractAllClozeTargets(autoClozeSeparable1)), JSON.stringify(["setzt", "auseinander"]));

// Reflexive German verb with governed preposition preserves 'sich' and matches C1 lexicon
const reflexiveInfo = sandbox.analyzeTerm("sich auseinandersetzen mit", "de");
assert.strictEqual(reflexiveInfo.cefrLevel, "C1");
assert.strictEqual(reflexiveInfo.levelConfidence, "verified");
assert.strictEqual(reflexiveInfo.displayTerm, "sich auseinandersetzen mit");
const reflexiveCard = sandbox.normalizeCard({
    front: "sich auseinandersetzen mit",
    back: "to grapple with",
    example: "Er setzt sich intensiv mit dem Thema auseinander.",
    language: "de"
});
assert.strictEqual(reflexiveCard.front, "sich auseinandersetzen mit");
assert.strictEqual(reflexiveCard.cefrLevel, "C1");
assert.strictEqual(reflexiveCard.clozeText, "Er {{c1::setzt}} sich intensiv mit dem Thema {{c2::auseinander}}.");

// mergeOnlineLookup must not overwrite verified local CEFR level with offline heuristic fallback
const verifiedLocal = sandbox.analyzeTerm("der Zusammenhang", "de");
assert.strictEqual(verifiedLocal.cefrLevel, "B1");
assert.strictEqual(verifiedLocal.levelConfidence, "verified");
const mergedWithFallback = sandbox.mergeOnlineLookup(verifiedLocal, {
    ok: false,
    cefrLevel: "B2",
    cefrSource: "DWDS / Goethe Heuristic",
    levelConfidence: "heuristic"
});
assert.strictEqual(mergedWithFallback.cefrLevel, "B1", "Heuristic fallback must not overwrite verified B1 level");
assert.strictEqual(mergedWithFallback.levelConfidence, "verified");

// autoLookupLevel: false must suppress automatic CEFR assignment unless user explicitly sets cefrLevel
const suppressedLevelCard = sandbox.normalizeCard({
    front: "ubiquitous",
    back: "present everywhere"
}, Date.UTC(2026, 10, 2, 12, 0, 0), { autoLookupLevel: false, autoCloze: true });
assert.strictEqual(suppressedLevelCard.cefrLevel, "");

// 4. Test Zero-Markup Natural Input & Legacy Nexus SR Parser
const batchInput = [
    "# Sample comment line ignored",
    "ubiquitous - present, appearing, or found everywhere // Smartphones have become ubiquitous.",
    "die Herausforderung - challenge; demanding task // Das ist eine große Herausforderung.",
    "What is active recall? :: Actively retrieving information from memory strengthens retention.",
    "Term A ::: Definition A",
    "The mitochondrion is the ==powerhouse== of the cell.",
    "Legacy scheduled card :: Preserved schedule <!--SR:!2026-11-20,15,270-->",
    "Multi-line question",
    "?",
    "Multi-line answer line 1",
    "Multi-line answer line 2"
].join("\n");

const parsed = sandbox.parseQuickInput(batchInput, "Academic", "en", "vocabulary");
// Note: ::: produces 2 bidirectional cards, plus 6 other cards (indices 0..7) = 8 cards total
assert.strictEqual(parsed.length, 8, `Expected 8 parsed cards, got ${parsed.length}`);
assert.strictEqual(parsed[0].cefrLevel, "C1");
assert.strictEqual(parsed[0].clozeText, "Smartphones have become {{c1::ubiquitous}}.");
assert.strictEqual(parsed[1].language, "de");
assert.strictEqual(parsed[1].gender, "die");
assert.strictEqual(parsed[1].cefrLevel, "B1");
assert.strictEqual(parsed[2].category, "knowledge");
assert.strictEqual(parsed[3].front, "Term A");
assert.strictEqual(parsed[4].front, "Definition A");
assert.strictEqual(parsed[5].category, "cloze");
assert.strictEqual(parsed[5].clozeText, "The mitochondrion is the {{c1::powerhouse}} of the cell.");
assert.strictEqual(parsed[6].dueDate, "2026-11-20");
assert.strictEqual(parsed[6].interval, 15);
assert.strictEqual(parsed[6].ease, 270);
assert.ok(!parsed[6].back.includes("<!--SR:"), "Nexus HTML comment must be stripped from visible back");
assert.strictEqual(parsed[7].front, "Multi-line question");

const multiline = sandbox.parseQuickInput("Explain spaced repetition\n?\nReviewing at expanding intervals.", "Default", "en", "knowledge");
assert.strictEqual(multiline.length, 1);
assert.strictEqual(multiline[0].front, "Explain spaced repetition");
assert.strictEqual(multiline[0].back, "Reviewing at expanding intervals.");

// 5. Test SM-2+ Scheduling, Boost Multiplier, Lapse Retention & Leech Detection
const nowMs = Date.UTC(2026, 10, 2, 12, 0, 0);
let card = sandbox.normalizeCard({
    id: "test-1",
    front: "resilient",
    back: "able to recover quickly",
    example: "Children are remarkably resilient."
}, nowMs);

const baseOpts = sandbox.normalizeOptions({
    boostMultiplier: 1.0,
    lapseMultiplier: 0.5,
    leechThreshold: 3,
    loadBalance: false
});
const boostedOpts = sandbox.normalizeOptions({
    boostMultiplier: 1.5,
    lapseMultiplier: 0.5,
    leechThreshold: 3,
    loadBalance: false
});

const initialPreview = sandbox.previewIntervals(card, nowMs, baseOpts);
assert.strictEqual(initialPreview.again, "<10m");
assert.strictEqual(initialPreview.hard, "1d");
assert.strictEqual(initialPreview.good, "2d");
assert.strictEqual(initialPreview.easy, "3d");

const step1Hard = sandbox.scheduleReview(card, "hard", baseOpts, {}, nowMs);
const step1Good = sandbox.scheduleReview(card, "good", baseOpts, {}, nowMs);
const step1Easy = sandbox.scheduleReview(card, "easy", baseOpts, {}, nowMs);
assert.strictEqual(step1Hard.interval, 1);
assert.strictEqual(step1Good.reps, 1);
assert.strictEqual(step1Good.interval, 2);
assert.strictEqual(step1Easy.interval, 3);

const step2Hard = sandbox.scheduleReview(step1Good, "hard", baseOpts, {}, nowMs);
const step2Good = sandbox.scheduleReview(step1Good, "good", baseOpts, {}, nowMs);
const step2Easy = sandbox.scheduleReview(step1Good, "easy", baseOpts, {}, nowMs);
assert.ok(step2Hard.interval < step2Good.interval && step2Good.interval < step2Easy.interval,
    `Expected strictly increasing intervals Hard < Good < Easy on step 2, got ${step2Hard.interval} / ${step2Good.interval} / ${step2Easy.interval}`);
const step2Boosted = sandbox.scheduleReview(step1Good, "good", boostedOpts, {}, nowMs);
assert.ok(step2Boosted.interval > step2Good.interval, "Boost multiplier 1.5x must increase scheduled interval");

// Mature card lapse retention (50% of 20d = 10d instead of resetting to 1d)
const matureCard = Object.assign({}, step2Good, { interval: 20, reps: 5, lapses: 2, state: "mature", ease: 250 });
const lapsedCard = sandbox.scheduleReview(matureCard, "again", baseOpts, {}, nowMs);
assert.strictEqual(lapsedCard.interval, 10, `Expected 50% lapse retention (10d), got ${lapsedCard.interval}`);
assert.strictEqual(lapsedCard.lapses, 3);
assert.strictEqual(lapsedCard.isLeech, true, "Card reaching leechThreshold (3) must be flagged as leech");

// Subsequent 'good' review on a relearning card with retained interval (10d) must scale up from 10d, not reset to 1d
const recoveredCard = sandbox.scheduleReview(lapsedCard, "good", baseOpts, {}, nowMs);
assert.ok(recoveredCard.interval > lapsedCard.interval, `Expected recovered interval > ${lapsedCard.interval}, got ${recoveredCard.interval}`);

// 6. Test Study Queue Builder & Boost Modes (ahead / hard / cram)
const futureDate = sandbox.addDaysKey(sandbox.todayKey(nowMs), 2, nowMs);
const futureCard = Object.assign({}, step2Good, { id: "future-1", dueDate: futureDate, state: "young" });
const normalQueue = sandbox.buildStudyQueue([futureCard], {
    options: baseOpts,
    boostMode: ""
}, nowMs);
assert.strictEqual(normalQueue.length, 0, "Future card should not appear in normal due queue");

const aheadQueue = sandbox.buildStudyQueue([futureCard], {
    options: baseOpts,
    boostMode: "ahead",
    aheadDays: 3
}, nowMs);
assert.strictEqual(aheadQueue.length, 1, "Future card within +3d must appear in Boost Ahead queue");

const hardQueue = sandbox.buildStudyQueue([lapsedCard, futureCard], {
    options: baseOpts,
    boostMode: "hard"
}, nowMs);
assert.strictEqual(hardQueue.length, 1, "Boost Hard queue must select leech/low-ease/lapsed cards");
assert.strictEqual(hardQueue[0].id, lapsedCard.id);

// 7. Test Idempotent Storage Migration & Legacy Data Preservation
const freshMigrated = sandbox.migrateStorage(null, nowMs);
assert.strictEqual(freshMigrated.schemaVersion, 4);
assert.strictEqual(freshMigrated.cards.length, 86, "Fresh storage should seed 8 starter EN/DE/knowledge cards + 78 Unit 01-04 vocabulary cards");
const unitDecks = new Set(freshMigrated.cards.filter(c => c.deck.startsWith("Unit ")).map(c => c.deck));
assert.strictEqual(unitDecks.size, 0, "No card should retain 'Unit 01..04' deck name; all English vocabulary cards must be unified under 'English Vocabulary'");
const allotCard = freshMigrated.cards.find(c => c.term === "allot");
assert.ok(allotCard, "Expected allot card in fresh storage");
assert.strictEqual(allotCard.deck, "English Vocabulary");
assert.strictEqual(allotCard.definitionEn, "to give a particular share of time, money, or resources to someone or something");
assert.strictEqual(allotCard.back, "to give a particular share of time, money, or resources to someone or something");
assert.ok(allotCard.meaningVi.includes("phân bổ"), `Expected Vietnamese meaningVi for allot, got: ${allotCard.meaningVi}`);
assert.strictEqual(allotCard.state, "new");
assert.strictEqual(allotCard.reps, 0);
assert.strictEqual(allotCard.interval, 0);
assert.strictEqual(allotCard.ease, 250);

// Upgrading a schemaVersion 3 payload with old Unit 01 cards and non-zero reps resets Unit cards to fresh state and English Vocabulary deck
const v3UserWithUnit = sandbox.migrateStorage({
    schemaVersion: 3,
    nextId: 100,
    historyByDay: { "2026-11-02": 4 },
    cards: [{
        id: "sr-unit01-1-allot",
        deck: "Unit 01",
        category: "vocabulary",
        language: "en",
        term: "allot",
        front: "allot",
        meaning: "phân bổ — chia, phân bổ, phân phối (thời gian, nguồn lực cho mục đích cụ thể)",
        back: "phân bổ — chia, phân bổ, phân phối (thời gian, nguồn lực cho mục đích cụ thể)",
        state: "young",
        reps: 3,
        interval: 16,
        ease: 290,
        dueDate: "2026-11-18"
    }]
}, nowMs);
assert.strictEqual(v3UserWithUnit.schemaVersion, 4);
assert.strictEqual(Object.keys(v3UserWithUnit.historyByDay).length, 0);
const upgradedAllot = v3UserWithUnit.cards.find(c => c.term === "allot");
assert.strictEqual(upgradedAllot.deck, "English Vocabulary");
assert.strictEqual(upgradedAllot.definitionEn, "to give a particular share of time, money, or resources to someone or something");
assert.strictEqual(upgradedAllot.back, "to give a particular share of time, money, or resources to someone or something");
assert.ok(upgradedAllot.meaningVi.includes("phân bổ"));
assert.strictEqual(upgradedAllot.state, "new");
assert.strictEqual(upgradedAllot.reps, 0);
assert.strictEqual(upgradedAllot.interval, 0);
assert.strictEqual(upgradedAllot.ease, 250);
const v3UserTwice = sandbox.migrateStorage(v3UserWithUnit, nowMs);
assert.strictEqual(JSON.stringify(v3UserWithUnit), JSON.stringify(v3UserTwice), "Schema v4 migration must be idempotent");

const legacyV1 = {
    cards: [
        {
            id: "legacy-card-42",
            front: "die Erkenntnis",
            back: "insight, realization",
            example: "Das ist eine wichtige Erkenntnis.",
            interval: 14,
            ease: 260,
            reps: 4,
            dueDate: "2026-11-01"
        }
    ]
};
const migratedOnce = sandbox.migrateStorage(legacyV1, nowMs);
const migratedTwice = sandbox.migrateStorage(migratedOnce, nowMs);
assert.strictEqual(migratedOnce.cards.length, 1);
assert.strictEqual(migratedOnce.cards[0].id, "legacy-card-42");
assert.strictEqual(migratedOnce.cards[0].cefrLevel, "B2");
assert.strictEqual(migratedOnce.cards[0].gender, "die");
assert.strictEqual(migratedOnce.cards[0].interval, 14);
assert.strictEqual(migratedOnce.cards[0].dueDate, "2026-11-01");
assert.ok(migratedOnce.cards[0].synonyms.length > 0, "Legacy card should backfill synonyms from lexicon");
assert.ok(migratedOnce.cards[0].antonyms.length > 0, "Legacy card should backfill antonyms from lexicon");
assert.ok(migratedOnce.cards[0].morphologyText.includes("er-"), "Legacy German card should backfill morphologyText");
assert.strictEqual(JSON.stringify(migratedOnce), JSON.stringify(migratedTwice), "Migration must be idempotent");

// 8. Regression: German adjectives (e.g. nachhaltig, wichtig, freundlich) must never get article 'der'
const nachhaltigInfo = sandbox.analyzeTerm("nachhaltig", "de");
assert.strictEqual(nachhaltigInfo.pos, "adj");
assert.strictEqual(nachhaltigInfo.article, "");
assert.strictEqual(nachhaltigInfo.displayTerm, "nachhaltig");
assert.strictEqual(sandbox.inferGermanArticle("nachhaltig"), "");
assert.strictEqual(sandbox.inferGermanArticle("wichtig"), "");
assert.strictEqual(sandbox.inferGermanArticle("freundlich"), "");

// Pre-patch stored card with bogus 'der nachhaltig' and empty synonyms/antonyms must be repaired on migration
const prePatchBogus = sandbox.migrateStorage({
    schemaVersion: 2,
    nextId: 10,
    cards: [{
        id: "sr-seed-de-b2",
        category: "vocabulary",
        language: "de",
        term: "nachhaltig",
        front: "der nachhaltig",
        article: "der",
        gender: "der",
        pos: "adj",
        meaning: "sustainable; lasting",
        synonyms: [],
        antonyms: []
    }]
}, nowMs);
assert.strictEqual(prePatchBogus.cards[0].article, "");
assert.strictEqual(prePatchBogus.cards[0].gender, "");
assert.strictEqual(prePatchBogus.cards[0].front, "nachhaltig");
assert.ok(prePatchBogus.cards[0].synonyms.length > 0, "Empty synonyms[] on pre-patch card must backfill");
assert.ok(prePatchBogus.cards[0].antonyms.length > 0, "Empty antonyms[] on pre-patch card must backfill");

// 9. Test Morphology / Etymology Breakdown (EN + DE curated & heuristic fallback)
const ubiqInfo = sandbox.analyzeTerm("ubiquitous", "en");
assert.ok(Array.isArray(ubiqInfo.morphology) && ubiqInfo.morphology.length >= 2);
assert.ok(ubiqInfo.morphologyText.includes("ubique (everywhere") && ubiqInfo.morphologyText.includes("-ous"),
    `Unexpected ubiquitous morphologyText: ${ubiqInfo.morphologyText}`);

const delibInfo = sandbox.analyzeTerm("deliberate", "en");
assert.ok(delibInfo.morphologyText.includes("de- (completely)") && delibInfo.morphologyText.includes("librare (libra) (weigh, balance)"),
    `Unexpected deliberate morphologyText: ${delibInfo.morphologyText}`);

const sehenInfo = sandbox.analyzeTerm("die Sehenswürdigkeit", "de");
assert.ok(sehenInfo.morphologyText.includes("sehens- (of seeing)") && sehenInfo.morphologyText.includes("würdig (worthy)") && sehenInfo.morphologyText.includes("-keit"),
    `Unexpected Sehenswürdigkeit morphologyText: ${sehenInfo.morphologyText}`);

const heuristicEn = sandbox.analyzeTerm("unbelievable", "en");
assert.ok(heuristicEn.morphologyText.includes("un- (not, reverse)") && heuristicEn.morphologyText.includes("-able (able to be)"),
    `Expected heuristic morphology for unbelievable, got: ${heuristicEn.morphologyText}`);

const heuristicDe = sandbox.analyzeTerm("Freundlichkeit", "de");
assert.ok(heuristicDe.morphologyText.includes("freund") && heuristicDe.morphologyText.includes("-lichkeit"),
    `Expected heuristic morphology for Freundlichkeit, got: ${heuristicDe.morphologyText}`);

// 10. Test Nexus Unit Markdown Bulk Parser (ignores exercises & reading comprehension)
const sampleUnitMd = [
    "---",
    "Date: 2026-09-12",
    'Unit: "[[Unit_03]]"',
    "---",
    "Ví dụ cho câu mới: Because the **data** was corrupted,...",
    "",
    "# 📝 Danh sách từ vựng: [[Unit_03]]",
    "",
    "The **____** (noun — ngành vi sinh vật học) laboratory conducts research on microscopic organisms.",
    "??",
    "**microbiology** (C1) (/ˌmaɪ.kroʊ.baɪˈɑː.lə.dʒi/)",
    "- **Nghĩa:** ngành nghiên cứu về vi sinh vật",
    "- **Collocations:**",
    "  - *clinical microbiology* - vi sinh vật học lâm sàng",
    "  - *study microbiology* - nghiên cứu vi sinh vật học",
    "<!--SR:!2026-10-08,16,290-->",
    "",
    "#### **Exercise 1**",
    "1. Question one?",
    "* a. option a",
    "* b. option b",
    "**Reading Comprehension**",
    "**The Mystery of Terahertz Waves**"
].join("\n");
const parsedUnitCards = sandbox.parseQuickInput(sampleUnitMd, { category: "vocabulary", language: "en" }, sandbox.analyzeTerm);
assert.strictEqual(parsedUnitCards.length, 1, `Expected exactly 1 vocabulary card from Unit markdown (ignoring Exercise & Reading), got ${parsedUnitCards.length}`);
assert.strictEqual(parsedUnitCards[0].term, "microbiology");
assert.strictEqual(parsedUnitCards[0].deck, "English Vocabulary");
assert.strictEqual(parsedUnitCards[0].cefrLevel, "C1");
assert.strictEqual(parsedUnitCards[0].pos, "noun");
assert.strictEqual(parsedUnitCards[0].phonetics, "/ˌmaɪ.kroʊ.baɪˈɑː.lə.dʒi/");
assert.strictEqual(parsedUnitCards[0].definitionEn, "the scientific study of microorganisms such as bacteria, viruses, and fungi");
assert.strictEqual(parsedUnitCards[0].back, "the scientific study of microorganisms such as bacteria, viruses, and fungi");
assert.ok(parsedUnitCards[0].meaningVi.includes("ngành vi sinh vật học"));
assert.strictEqual(parsedUnitCards[0].state, "new");
assert.strictEqual(parsedUnitCards[0].reps, 0);
assert.strictEqual(parsedUnitCards[0].interval, 0);
assert.strictEqual(parsedUnitCards[0].ease, 250);
assert.strictEqual(parsedUnitCards[0].collocations.length, 2);
assert.ok(parsedUnitCards[0].clozeText.includes("{{c1::microbiology::noun — ngành vi sinh vật học}}"));

// 11. Test Legacy Mode Normalization (Reverse Flashcard & Reverse Multiple Choice -> Matching)
for (const legacy of ["reverse", "reverse_flashcard", "reverseFlashcard", "rmc", "reverse_mcq", "reverseMultipleChoice", "matching"]) {
    assert.strictEqual(sandbox.normalizeStudyMode(legacy), "matching", `Expected '${legacy}' to normalize to 'matching'`);
}
assert.strictEqual(sandbox.normalizeStudyMode("mcq"), "mc");
assert.strictEqual(sandbox.normalizeStudyMode("cloze"), "cloze");
assert.strictEqual(sandbox.normalizeStudyMode("flashcard"), "flashcard");

const migratedLegacyMode = sandbox.migrateStorage({
    schemaVersion: 4,
    reviewMode: "reverse_mcq",
    studyMode: "reverse_flashcard",
    cards: freshMigrated.cards.slice(0, 6)
}, nowMs);
assert.strictEqual(migratedLegacyMode.retainedStorageFields.reviewMode, "matching");
assert.strictEqual(migratedLegacyMode.retainedStorageFields.studyMode, "matching");
assert.strictEqual(sandbox.normalizeOptions({ studyDirection: "reverse_mcq" }).studyDirection, "matching");
assert.strictEqual(sandbox.normalizeOptions({ studyDirection: "reverse_flashcard" }).studyDirection, "matching");

// 12. Test Smart Mode Rotation (Combines Matching, Multiple Choice, Cloze Reading; Flashcard as Last Resort)
const sixDueCards = freshMigrated.cards.slice(0, 6);
let smartState = { bag: [], lastMode: "" };
const seenActiveModes = new Set();
for (let i = 0; i < 12; i++) {
    const res = sandbox.selectNextStudyMode(sixDueCards, freshMigrated.cards, smartState);
    smartState = res.state;
    assert.ok(["matching", "mc", "cloze"].includes(res.mode), `Expected one of matching/mc/cloze when multiple cards are due, got ${res.mode}`);
    assert.notStrictEqual(res.mode, "flashcard", "Flashcard must not be chosen when active modes are available");
    seenActiveModes.add(res.mode);
}
assert.strictEqual(seenActiveModes.size, 3, "Smart Mix must combine all 3 active modes (matching, mc, cloze) over a multi-card session");

// Fallback to Flashcard as last resort when only 1 card exists in the entire deck without cloze/example
const singleBareCard = [{
    id: "bare-1",
    term: "isolated",
    front: "isolated",
    meaning: "alone",
    back: "alone",
    definitionEn: "alone",
    example: "",
    clozeText: ""
}];
const fallbackPick = sandbox.selectNextStudyMode(singleBareCard, singleBareCard, { bag: [], lastMode: "" });
assert.strictEqual(fallbackPick.mode, "flashcard", "Flashcard must be selected as last resort when neither matching, mc, nor cloze can be constructed");

// 13. Test Matching Round Builder (5 Left Words + 6 Right Definitions with 1 Distractor + Padding when <5 Due)
const roundFull = sandbox.buildMatchingRound(sixDueCards, freshMigrated.cards);
assert.strictEqual(roundFull.leftWords.length, 5, "Matching round must have 5 vocabulary words on the left");
assert.strictEqual(roundFull.rightDefinitions.length, 6, "Matching round must have 6 definitions on the right");
assert.strictEqual(roundFull.leftWords.filter(w => w.inQueue).length, 5, "All 5 left words should come from due queue when >= 5 cards are due");
assert.strictEqual(roundFull.rightDefinitions.filter(d => d.isDistractor).length, 1, "Right column must contain exactly 1 distractor definition");
for (const w of roundFull.leftWords) {
    assert.ok(roundFull.rightDefinitions.some(d => !d.isDistractor && d.pairId === w.id), `Missing matching definition for left word ${w.term}`);
}

const twoDueCards = freshMigrated.cards.slice(0, 2);
const roundPadded = sandbox.buildMatchingRound(twoDueCards, freshMigrated.cards);
assert.strictEqual(roundPadded.leftWords.length, 5, "Matching round must pad to 5 left words from the deck when only 2 cards are due");
assert.strictEqual(roundPadded.leftWords.filter(w => w.inQueue).length, 2, "Exactly 2 left words should be marked inQueue");
assert.strictEqual(roundPadded.leftWords.filter(w => !w.inQueue).length, 3, "Remaining 3 left words should be padded from the deck");
assert.strictEqual(roundPadded.rightDefinitions.length, 6, "Padded matching round must still have 6 definitions on the right");
assert.strictEqual(roundPadded.rightDefinitions.filter(d => d.isDistractor).length, 1, "Padded matching round must have 1 distractor definition");

const roundEmpty = sandbox.buildMatchingRound([], freshMigrated.cards);
assert.strictEqual(roundEmpty.leftWords.length, 0, "Empty studyQueue must return empty leftWords so caught-up screen appears");
assert.strictEqual(roundEmpty.rightDefinitions.length, 0, "Empty studyQueue must return empty rightDefinitions");

// 14. Regression: Cards reviewed yesterday with Hard (1d), Normal/Good (2d), or Easy (3d) must respect scheduled intervals
const day0EveningMs = new Date(2026, 10, 7, 22, 0, 0).getTime(); // 2026-11-07 22:00 local
const day1MorningMs = new Date(2026, 10, 8, 8, 30, 0).getTime(); // 2026-11-08 08:30 local (next morning)
const day1EveningMs = new Date(2026, 10, 8, 22, 30, 0).getTime(); // 2026-11-08 22:30 local (next evening)
const day2MorningMs = new Date(2026, 10, 9, 9, 0, 0).getTime();  // 2026-11-09 09:00 local (+2 days)
const day3MorningMs = new Date(2026, 10, 10, 9, 0, 0).getTime(); // 2026-11-10 09:00 local (+3 days)

const baseCardA = Object.assign({}, freshMigrated.cards[0], { id: "rev-hard", dueAt: day0EveningMs, dueDate: "2026-11-07" });
const baseCardB = Object.assign({}, freshMigrated.cards[1], { id: "rev-normal", dueAt: day0EveningMs, dueDate: "2026-11-07" });
const baseCardC = Object.assign({}, freshMigrated.cards[2], { id: "rev-easy", dueAt: day0EveningMs, dueDate: "2026-11-07" });

const ratedHard = sandbox.scheduleReview(baseCardA, "hard", day0EveningMs, baseOpts, {}).card;
const ratedNormal = sandbox.scheduleReview(baseCardB, "normal", day0EveningMs, baseOpts, {}).card;
const ratedEasy = sandbox.scheduleReview(baseCardC, "easy", day0EveningMs, baseOpts, {}).card;
const ratedZero = sandbox.scheduleReview(baseCardA, 0, day0EveningMs, baseOpts, {}).card;

assert.strictEqual(ratedHard.interval, 1);
assert.strictEqual(ratedHard.dueDate, "2026-11-08");
assert.strictEqual(ratedNormal.interval, 2);
assert.strictEqual(ratedNormal.dueDate, "2026-11-09");
assert.strictEqual(ratedEasy.interval, 3);
assert.strictEqual(ratedEasy.dueDate, "2026-11-10");
assert.strictEqual(ratedZero.state, "learning", "Numeric rating 0 must be treated as Again, not Good");
assert.strictEqual(ratedZero.reps, 0);

// Same day after review: none of Hard/Normal/Easy may reappear
const sameDayQueue = sandbox.buildStudyQueue([ratedHard, ratedNormal, ratedEasy], { options: baseOpts }, day0EveningMs + 60000);
assert.strictEqual(sameDayQueue.length, 0, "Cards rated Hard/Normal/Easy must not reappear on the same day");

// Next day (2026-11-08) morning & evening: ONLY Hard (1d) is due; Normal (2d) and Easy (3d) must NOT reappear next day
for (const checkMs of [day1MorningMs, day1EveningMs]) {
    const nextDayQueue = sandbox.buildStudyQueue([ratedHard, ratedNormal, ratedEasy], { options: baseOpts }, checkMs);
    assert.strictEqual(JSON.stringify(nextDayQueue.map(c => c.id)), JSON.stringify(["rev-hard"]),
        `On 2026-11-08, only Hard (1d) card should be due; Normal (2d) and Easy (3d) must not reappear next day`);
    const nextDayAnalytics = sandbox.computeAnalytics([ratedHard, ratedNormal, ratedEasy], {}, checkMs, baseOpts);
    assert.strictEqual(nextDayAnalytics.dueToday, 1, "computeAnalytics.dueToday on next morning must match civil dueDate");
}

// Day +2 (2026-11-09): Normal (2d) becomes due
const day2Queue = sandbox.buildStudyQueue([ratedNormal, ratedEasy], { options: baseOpts }, day2MorningMs);
assert.strictEqual(JSON.stringify(day2Queue.map(c => c.id)), JSON.stringify(["rev-normal"]));

// Day +3 (2026-11-10): Easy (3d) becomes due
const day3Queue = sandbox.buildStudyQueue([ratedEasy], { options: baseOpts }, day3MorningMs);
assert.strictEqual(JSON.stringify(day3Queue.map(c => c.id)), JSON.stringify(["rev-easy"]));

// Sub-day learning card (<10m) rated Again must go to the end of the queue behind other due/new cards
const learningAgain = Object.assign({}, ratedZero, { level: "A1", cefrLevel: "A1" });
const newC1Card = Object.assign({}, freshMigrated.cards[5], { id: "new-c1", level: "C1", cefrLevel: "C1", state: "new", reps: 0 });
const orderedWithLearning = sandbox.buildStudyQueue([learningAgain, newC1Card], { options: baseOpts }, day0EveningMs + 1000);
assert.strictEqual(JSON.stringify(orderedWithLearning.map(c => c.id)), JSON.stringify(["new-c1", learningAgain.id]),
    "In-session <10m learning card with dueAt > now must wait behind other due/new cards instead of jumping to index 0");

// Smart Mix must NOT select 5-word Matching mode when < 5 cards remain in studyQueue and MC/Cloze are available
const threeRemainingQueue = freshMigrated.cards.slice(0, 3);
let tailState = { bag: ["matching", "mc", "cloze"], lastMode: "" };
for (let i = 0; i < 8; i++) {
    const pick = sandbox.selectNextStudyMode(threeRemainingQueue, freshMigrated.cards, tailState);
    tailState = pick.state;
    assert.ok(["mc", "cloze"].includes(pick.mode),
        `When < 5 cards remain in studyQueue, Smart Mix must use mc/cloze instead of 5-word matching, got ${pick.mode}`);
}

// When Matching is explicitly built with < 5 due cards, padding must prefer unreviewed cards over yesterday's reviewed cards
const deckWithReviewedAndNew = [
    ratedNormal,
    ratedEasy,
    ...freshMigrated.cards.slice(10, 16)
];
const paddedRound = sandbox.buildMatchingRound(freshMigrated.cards.slice(10, 12), deckWithReviewedAndNew);
assert.strictEqual(paddedRound.leftWords.length, 5);
assert.ok(!paddedRound.leftWords.some(w => w.id === "rev-normal" || w.id === "rev-easy"),
    "Padded Matching left column must prefer unreviewed cards over cards reviewed yesterday");

// Schema migration must preserve user-reviewed sr-unit* cards (lastReviewedAt > 0)
const v3ReviewedUnit = sandbox.migrateStorage({
    schemaVersion: 3,
    nextId: 210,
    cards: [{
        id: "sr-unit01-1-allot",
        deck: "English Vocabulary",
        category: "vocabulary",
        language: "en",
        term: "allot",
        front: "allot",
        meaning: "to give a particular share of time, money, or resources to someone or something",
        back: "to give a particular share of time, money, or resources to someone or something",
        state: "young",
        reps: 2,
        interval: 5,
        ease: 265,
        dueAt: day2MorningMs,
        dueDate: "2026-11-09",
        lastReviewedAt: day0EveningMs
    }]
}, day1MorningMs);
const migratedReviewedAllot = v3ReviewedUnit.cards.find(c => c.id === "sr-unit01-1-allot");
assert.strictEqual(migratedReviewedAllot.reps, 2, "User-reviewed unit card (lastReviewedAt > 0) must keep its reps across migration");
assert.strictEqual(migratedReviewedAllot.interval, 5, "User-reviewed unit card must keep its interval across migration");
assert.strictEqual(migratedReviewedAllot.dueDate, "2026-11-09", "User-reviewed unit card must keep its scheduled dueDate across migration");

// 15. Regression: buildStudyQueue must sort before slicing to dailyNewLimit/dailyReviewLimit so cohort order is stable as cards are reviewed
const quotaPool = [
    Object.assign({}, freshMigrated.cards[0], { id: "new-c2-1", level: "C2", cefrLevel: "C2", state: "new", reps: 0, dueAt: 1000 }),
    Object.assign({}, freshMigrated.cards[1], { id: "new-c1-2", level: "C1", cefrLevel: "C1", state: "new", reps: 0, dueAt: 2000 }),
    Object.assign({}, freshMigrated.cards[2], { id: "new-b1-3", level: "B1", cefrLevel: "B1", state: "new", reps: 0, dueAt: 3000 }),
    Object.assign({}, freshMigrated.cards[3], { id: "new-a2-4", level: "A2", cefrLevel: "A2", state: "new", reps: 0, dueAt: 4000 })
];
const quotaOpts = Object.assign({}, baseOpts, { dailyNewLimit: 2, prioritizeOrder: "level_asc" });
const initialQuotaQueue = sandbox.buildStudyQueue(quotaPool, { statsToday: { newStudied: 0, reviewsDone: 0 }, options: quotaOpts }, day1MorningMs);
assert.strictEqual(JSON.stringify(initialQuotaQueue.map(c => c.id)), JSON.stringify(["new-a2-4", "new-b1-3"]),
    "buildStudyQueue must sort all new cards by CEFR level before slicing to dailyNewLimit");
const afterFirstReviewedPool = [
    quotaPool[0],
    quotaPool[1],
    quotaPool[2],
    sandbox.scheduleReview(quotaPool[3], "good", day1MorningMs, quotaOpts, {}).card
];
const nextQuotaQueue = sandbox.buildStudyQueue(afterFirstReviewedPool, { statsToday: { newStudied: 1, reviewsDone: 0 }, options: quotaOpts }, day1MorningMs + 5000);
assert.strictEqual(JSON.stringify(nextQuotaQueue.map(c => c.id)), JSON.stringify(["new-b1-3"]),
    "After reviewing 1 of 2 daily new cards, the remaining card in today's cohort must stay 'new-b1-3'");

// 16. Regression: Card rated Again (<10m) at 23:55 local time must keep its 10-minute dueAt across normalizeCard and remain in today's session queue at 23:56
const lateNightMs = new Date(2026, 10, 7, 23, 55, 0).getTime(); // 2026-11-07 23:55 local
const lateAgainCard = sandbox.scheduleReview(baseCardA, "again", lateNightMs, baseOpts, {}).card;
assert.strictEqual(lateAgainCard.dueDate, "2026-11-07", "Sub-day <10m learning card rated at 23:55 must keep today's civil dueDate");
assert.strictEqual(lateAgainCard.dueAt, lateNightMs + 10 * 60000, "Sub-day <10m learning card must be due in 10 minutes (00:05 next day)");
const normalizedLateAgain = sandbox.normalizeCard(lateAgainCard, 1, lateNightMs + 60000, baseOpts, null);
assert.strictEqual(normalizedLateAgain.dueAt, lateNightMs + 10 * 60000, "normalizeCard must not overwrite sub-day <10m dueAt when dueAt crosses midnight");
const lateQueueBeforeMidnight = sandbox.buildStudyQueue([normalizedLateAgain], { options: baseOpts }, lateNightMs + 60000);
assert.strictEqual(lateQueueBeforeMidnight.length, 1, "Sub-day learning card rated at 23:55 must remain in session queue at 23:56");

console.log("SR_ENGINE_UNIT_PASS");
"""
    res = subprocess.run(["node", "-e", node_script], cwd=ROOT, capture_output=True, text=True, check=False)
    if res.returncode != 0 or "SR_ENGINE_UNIT_PASS" not in res.stdout:
        print(res.stdout, file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        raise AssertionError("Node SpacedRepetitionEngine unit tests failed")


def run_cli_lookup_tests() -> None:
    cli = ROOT / "scripts" / "spaced-repetition" / "lookup_word_level.py"
    assert cli.exists(), "lookup_word_level.py missing"

    # Single-word offline lookup
    res_en = subprocess.run(
        [sys.executable, str(cli), "--word", "ubiquitous", "--lang", "en", "--offline"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    payload_en = json.loads(res_en.stdout)
    assert payload_en["language"] == "en"
    assert payload_en["cefrLevel"] in ("B1", "B2", "C1", "C2")
    assert "ubique (everywhere" in payload_en.get("morphologyText", "")
    assert len(payload_en.get("morphology", [])) >= 2

    # German noun with article
    res_de = subprocess.run(
        [sys.executable, str(cli), "--word", "die Sehenswürdigkeit", "--lang", "de", "--offline"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    payload_de = json.loads(res_de.stdout)
    assert payload_de["language"] == "de"
    assert payload_de["gender"] == "die"
    assert payload_de["headword"] == "Sehenswürdigkeit"
    assert payload_de["cefrLevel"] in ("A1", "A2", "B1", "B2", "C1", "C2")
    assert "sehens- (of seeing)" in payload_de.get("morphologyText", "")

    # Batch mode
    batch_items = json.dumps([
        {"word": "sustainable", "lang": "en"},
        {"word": "die Herausforderung", "lang": "de"},
    ])
    res_batch = subprocess.run(
        [sys.executable, str(cli), "--batch", batch_items, "--offline"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    batch_out = json.loads(res_batch.stdout)
    assert len(batch_out["results"]) == 2
    assert batch_out["results"][1]["gender"] == "die"
    assert len(batch_out["results"][0].get("morphology", [])) >= 2

    # Unit-test Oxford HTML, German Wiktionary & Etymology parser helpers directly
    sys.path.insert(0, str(cli.parent))
    import lookup_word_level as lwl  # type: ignore
    ox_parsed = lwl.parse_oxford_english_html(
        '<span class="pos">adjective</span><span class="phon">/təˈneɪʃəs/</span>'
        '<span class="def">determined</span><span class="x">a tenacious grip</span>'
    )
    assert ox_parsed["pos"] == "adj"
    assert ox_parsed["phonetic"] == "/təˈneɪʃəs/"
    assert ox_parsed["meaning"] == "determined"
    assert ox_parsed["example"] == "a tenacious grip"

    wiki_parsed = lwl.parse_german_wiktionary_wikitext(
        "{{Wortart|Substantiv|Deutsch}}, {{f}}\n"
        "{{Lautschrift|ˈt͡suːfɛɐ̯ˌlɛsɪçkaɪ̯t}}\n"
        "{{Herkunft}}\n:[1] Ableitung von [[zuverlässig]] mit dem Suffix [[-keit]]\n"
        "{{Bedeutungen}}\n:[1] das [[Zuverlässigsein]]<ref>Quellenangabe</ref>\n"
        "{{Beispiele}}\n:[1] „Zuverlässigkeit zählt.“<ref name=\"x\"/>\n"
        "{{Gegenwörter}}\n:[1] [[Wankelmut]]; ''[[technisch]]er Bereich:'' [[Versagen]]\n"
    )
    assert wiki_parsed["article"] == "die"
    assert "<ref" not in wiki_parsed["meaning"]
    assert "<ref" not in wiki_parsed["example"]
    assert wiki_parsed["antonyms"] == ["Wankelmut", "Versagen"]
    assert len(wiki_parsed.get("morphology", [])) >= 1

    etym_affix = lwl.parse_wiktionary_etymology("From {{affix|en|un-|t1=not|believe|-able|t3=capable of}}.", "unbelievable", "en")
    assert len(etym_affix["morphology"]) == 3
    assert lwl.format_morphology(etym_affix) == "un- (not) + believe + -able (capable of)"

    dwds_wb = lwl.parse_dwds_wortbildung(
        '<div class="dwdswb-ft-block"><span>Wortbildung</span>'
        '<dd><a>nach-</a> + <a>halten</a> + <a>-ig</a></dd></div>'
    )
    assert len(dwds_wb.get("morphology", [])) == 3
    assert "nach- (after, following)" in dwds_wb.get("morphologyText", "")
    assert "DWDS Wortbildung:" in dwds_wb.get("etymology", "")
    assert bool(payload_de.get("etymology"))


def verify_qml_and_config_contracts() -> None:
    services_qmldir = (ROOT / "services" / "qmldir").read_text(encoding="utf-8")
    dash_qmldir = (ROOT / "modules" / "dashboard" / "qmldir").read_text(encoding="utf-8")
    settings_qmldir = (ROOT / "modules" / "settings" / "qmldir").read_text(encoding="utf-8")
    config_qml = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
    defaults_json = json.loads((ROOT / "defaults" / "config.json").read_text(encoding="utf-8"))
    dash_content = (ROOT / "modules" / "dashboard" / "DashboardContent.qml").read_text(encoding="utf-8")
    dash_header = (ROOT / "modules" / "dashboard" / "DashboardHeader.qml").read_text(encoding="utf-8")
    sr_qml = (ROOT / "modules" / "dashboard" / "DashboardSpacedRepetition.qml").read_text(encoding="utf-8")
    sr_settings = (ROOT / "modules" / "settings" / "DashboardSpacedRepetitionSettings.qml").read_text(encoding="utf-8")
    dash_config = (ROOT / "modules" / "settings" / "DashboardConfig.qml").read_text(encoding="utf-8")

    assert "singleton SpacedRepetition 1.0 SpacedRepetition.qml" in services_qmldir
    assert "DashboardSpacedRepetition 1.0 DashboardSpacedRepetition.qml" in dash_qmldir
    assert "DashboardSpacedRepetitionSettings 1.0 DashboardSpacedRepetitionSettings.qml" in settings_qmldir

    assert "property JsonObject spacedRepetition: JsonObject {" in config_qml
    assert "spacedRepetition" in defaults_json["dashboard"]["pageOrder"]
    assert defaults_json["dashboard"]["spacedRepetition"]["enable"] is True
    assert defaults_json["dashboard"]["spacedRepetition"]["boostMultiplier"] == 100
    assert defaults_json["dashboard"]["spacedRepetition"]["lapseMultiplier"] == 50

    assert 'id: spacedRepetitionPage' in dash_content
    assert 'objectName: "dashboardSpacedRepetitionPageLoader"' in dash_content
    assert 'if(id==="spacedRepetition") return Translation.tr("Spaced Repetition")' in dash_header

    for token in (
        'objectName: "dashboardSpacedRepetition"',
        'objectName: "srSubTabStudy"',
        'objectName: "srSubTabCapture"',
        'objectName: "srSubTabLibrary"',
        'objectName: "srBoostToggleButton"',
        'objectName: "srRevealButton"',
        'objectName: "srMatchingBoard"',
        'objectName: "srMatchingLeftColumn"',
        'objectName: "srMatchingCorridor"',
        'objectName: "srMatchingRightColumn"',
        'objectName: "srMatchingLinesCanvas"',
        'objectName: "srMatchingContinueButton"',
        'objectName: "srClozeWordBank"',
        'objectName: "srStudyMode-smart"',
        'objectName: "srStudyMode-" + modelData.id',
        '{ id: "matching",',
        '{ id: "mc",',
        '{ id: "cloze",',
        '{ id: "flashcard",',
        'objectName: "srStudyTrackerAnalyticsColumn"',
        'objectName: "srConsistencyCard"',
        'objectName: "srActivityHeatmapCard"',
        'objectName: "srAnalyticsBreakdownCard"',
        'objectName: "srAnalyticsForecastCard"',
        'readonly property color colAnalyticsColumnBg:',
        'readonly property color colAnalyticsCardBg:',
        'readonly property color colAnalyticsSubBoxBg:',
        '"srRateAgain"',
        '"srRateHard"',
        '"srRateGood"',
        '"srRateEasy"',
        'objectName: "srComposerFront"',
        'objectName: "srLookupOnlineButton"',
        'objectName: "srBulkInputArea"',
        'objectName: "srBulkImportButton"',
        'objectName: "srBulkSyntaxGuideButton"',
        'objectName: "srBulkSyntaxGuidePanel"',
        'objectName: "srBulkSyntaxGuideFooterHint"',
        'Press Esc or click Guide again to return to the editor.',
        'morphology: Array.from(root.draftPreview?.morphology ?? []),',
        'objectName: "srLibraryCardSummaryDefEn"',
        'objectName: "srLibraryCardHoverDetails"',
        'objectName: "srLibraryCardMeaningVi"',
        'objectName: "srStudyCardMeaningVi"',
        'objectName: "srStudyMorphologyStrip"',
        'objectName: "srComposerMorphologyStrip"',
        'component MorphologyStrip: Rectangle {',
        'cursorVisible: activeFocus',
        'selectByMouse: true',
        'id: answerScrollView',
        'id: composerScrollView',
        'width: composerScrollView.width',
    ):
        assert token in sr_qml, f"Missing token {token} in DashboardSpacedRepetition.qml"

    for removed_token in (
        'objectName: "srStudyMode-reverse"',
        'objectName: "srStudyMode-rmc"',
        'Translation.tr("Reverse MC")',
    ):
        assert removed_token not in sr_qml, f"Removed mode token {removed_token} must not remain in DashboardSpacedRepetition.qml"

    for token in (
        "dashboard.spacedRepetition.enable",
        "dashboard.spacedRepetition.dailyNewLimit",
        "dashboard.spacedRepetition.dailyReviewLimit",
        "dashboard.spacedRepetition.boostMultiplier",
        "dashboard.spacedRepetition.lapseMultiplier",
        "dashboard.spacedRepetition.leechThreshold",
        "dashboard.spacedRepetition.loadBalance",
        "dashboard.spacedRepetition.autoLookupLevel",
        "dashboard.spacedRepetition.autoLookupOnline",
        "dashboard.spacedRepetition.autoCloze",
    ):
        assert token in sr_settings, f"Missing config binding {token} in DashboardSpacedRepetitionSettings.qml"

    assert "DashboardSpacedRepetitionSettings {" not in dash_config
    dock_config = (ROOT / "modules" / "settings" / "DockConfig.qml").read_text(encoding="utf-8")
    registry_data = (ROOT / "modules" / "settings" / "SettingsPageRegistryData.qml").read_text(encoding="utf-8")
    integration_plugins = json.loads((ROOT / "defaults" / "integration-plugins.json").read_text(encoding="utf-8"))
    alis_intergration_qml = (ROOT / "services" / "AlisIntergration.qml").read_text(encoding="utf-8")
    assert "DashboardSpacedRepetitionSettings {" not in dock_config
    assert 'value:"spacedRepetition"' in dock_config
    assert 'section: Translation.tr("Spaced Repetition")' in registry_data
    assert "spaced_repetition" in integration_plugins["integrations"]
    assert any(p.get("id") == "spaced_repetition" for p in integration_plugins["plugins"])
    assert "readonly property bool spacedRepetitionEnabled:" in alis_intergration_qml
    assert "function spacedRepetitionDashboardSource(): string" in alis_intergration_qml
    assert 'objectName: "srOpenSettingsButton"' in sr_qml
    assert 'component DetailTag: Rectangle {' in sr_qml
    for emoji in ("🇻🇳", "🔗", "🌱"):
        assert emoji not in sr_qml, f"Emoji {emoji} must not appear in DashboardSpacedRepetition.qml"

    perimeter = (ROOT / "modules" / "abyss" / "AbyssPerimeter.qml").read_text(encoding="utf-8")
    settings_overlay = (ROOT / "modules" / "settings" / "SettingsOverlay.qml").read_text(encoding="utf-8")
    assert "id: perimeterInteractiveEscapeShortcut" in perimeter
    assert "onActivated: perimeterEscapeFallback.triggerEscape()" in perimeter
    assert "readonly property Item activeWindowFocusItem: window.contentItem?.Window.activeFocusItem" in perimeter
    assert "onActiveFocusChanged: if (!activeFocus) Qt.callLater(window.ensureEscapeFocus)" not in perimeter
    assert "if (root.overlaySearchText.length > 0)" in settings_overlay
    assert "GlobalStates.overviewOpen = false;" in dash_header
    assert "root.forceActiveFocus()" in sr_qml
    assert "readonly property bool studyShortcutsActive:" in sr_qml
    assert "readonly property bool studyDigitShortcutsActive:" in sr_qml
    assert "readonly property bool clozeNumericTypingActive:" in sr_qml
    assert "property string _lastShortcutAction: \"\"" in sr_qml
    assert "readonly property color matchedStrokeColor: ColorUtils.mix(Appearance.colors.colPrimary, \"#10b981\", 0.45)" in sr_qml
    assert "readonly property color mismatchStrokeColor: Appearance.colors.colError" in sr_qml
    assert "readOnly: root.answerRevealed" in sr_qml
    assert "function selectClozeChoice(index: int): bool" in sr_qml
    assert "function triggerStudyShortcut(action, allowFromClozeInput = false): bool" in sr_qml
    assert 'sequences: ["Space"]' in sr_qml
    assert "function focusPrimarySurface(): void" in sr_qml
    assert "function focusPrimarySurface(): void" in dash_content


def main() -> None:
    run_node_engine_tests()
    run_cli_lookup_tests()
    verify_qml_and_config_contracts()
    print("DASHBOARD_SPACED_REPETITION_CONTRACT_PASS: engine, CEFR A1-C2 lexicon, auto-syntax, and QML/Settings contracts verified")


if __name__ == "__main__":
    main()


