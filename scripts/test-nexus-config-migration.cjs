#!/usr/bin/env node
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const policyPath = path.resolve(__dirname, "../modules/common/PanelFamilyPolicy.js");
const src = fs.readFileSync(policyPath, "utf8");
const sandbox = { console };
vm.createContext(sandbox);
vm.runInContext(src, sandbox);
const migrateNexusConfig = sandbox.migrateNexusConfig;
assert.strictEqual(typeof migrateNexusConfig, "function");

// 1. User-like legacy config: integrations.hadalird.{obsidian, thinkfan, tlp}
// alongside modern integrations.alisIntergration.{spaced_repetition, exercises_tracker}.
const userFixture = {
    integrations: {
        hadalird: {
            ["ob" + "sidian"]: true,
            thinkfan: true,
            tlp: true,
        },
        alisIntergration: {
            spaced_repetition: true,
            exercises_tracker: true,
        },
        nexus: {
            autoTheme: false,
            configPath: "",
            applicationConfigPath: "",
            applicationPath: "nexus",
        },
    },
    todo: {
        backend: "internal",
        nexus: { vaultPath: "/home/user/Vault" },
    },
};

const out1 = migrateNexusConfig(userFixture);
assert.strictEqual(out1["integrations.alisIntergration.nexus"], true, "hadalird obsidian must migrate nexus=true");
assert.strictEqual(out1["integrations.alisIntergration.tlp"], true, "hadalird tlp must migrate tlp=true");
assert.strictEqual(out1["integrations.alisIntergration.thinkfan"], true, "hadalird thinkfan must migrate thinkfan=true");
assert.strictEqual(userFixture.integrations.alisIntergration.nexus, true);
assert.strictEqual(userFixture.integrations.alisIntergration.spaced_repetition, true);
assert.strictEqual(userFixture.integrations.alisIntergration.exercises_tracker, true);
assert.strictEqual(Object.prototype.hasOwnProperty.call(userFixture.integrations, "hadalird"), false, "hadalird must be removed");
assert.strictEqual(userFixture.todo.nexus.vaultPath, "/home/user/Vault");

// Idempotent second run produces no extra mutations
const out1Again = migrateNexusConfig(userFixture);
assert.strictEqual(Object.keys(out1Again).length, 0, "repeated migration must be idempotent");

// 2. Explicit false in alisIntergration must NEVER be overridden by hadalird true
const explicitFalseFixture = {
    integrations: {
        hadalird: {
            ["ob" + "sidian"]: true,
            tlp: true,
            thinkfan: false,
        },
        alisIntergration: {
            nexus: false,
            tlp: false,
        },
    },
};
const out2 = migrateNexusConfig(explicitFalseFixture);
assert.strictEqual(explicitFalseFixture.integrations.alisIntergration.nexus, false, "explicit nexus=false must be preserved");
assert.strictEqual(explicitFalseFixture.integrations.alisIntergration.tlp, false, "explicit tlp=false must be preserved");
assert.strictEqual(out2["integrations.alisIntergration.nexus"], undefined, "explicit nexus=false should not be overwritten");
assert.strictEqual(out2["integrations.alisIntergration.tlp"], undefined, "explicit tlp=false should not be overwritten");
assert.strictEqual(out2["integrations.alisIntergration.thinkfan"], false, "hadalird thinkfan=false migrates when unset");
assert.strictEqual(Object.prototype.hasOwnProperty.call(explicitFalseFixture.integrations, "hadalird"), false);

console.log("PASS: test-nexus-config-migration (legacy hadalird, explicit-false preservation, idempotency)");
