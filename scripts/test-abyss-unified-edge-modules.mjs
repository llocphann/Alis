import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

// Exercise the same placement/sizing/profile code consumed by live QML.
const layout = vm.createContext({Math,JSON,Number,Array,Set});
vm.runInContext(
    fs.readFileSync(new URL("../modules/abyss/looks/AbyssLayout.js", import.meta.url), "utf8"),
    layout
);
const clone = value => JSON.parse(JSON.stringify(value));
const edges = ["top","bottom","left","right"];
let checks = 0;
function check(condition, context) { assert.ok(condition,context); checks++; }

check(layout.catalog.filter(kind => layout.isUnifiedKind(kind)).length === 2,
    "one catalog kind per unified launcher");
check(!layout.isUnifiedKind("timer"), "old Bar timer is only an indicator");
for (const kind of ["notesTimers","notificationActivity"]) {
    check(layout.catalog.includes(kind), `catalog includes ${kind}`);
    for (const edge of edges) {
        const source = layout.normalize([
            {id:"existing",kind:"clock",edge,position:.26},
            {id:kind,kind,edge,position:.73,showIcon:false}
        ],edge);
        const fresh = source.find(p => p.kind===kind);
        check(!fresh.showIcon, `hide icon survives normalization ${kind} ${edge}`);
        check(source.find(p=>p.id==="existing").showIcon,
            "old module defaults to visible");

        const options = {edgeThickness:16,edgeThicknesses:{[edge]:0},editing:true};
        const zero = layout.geometry(source,1920,1080,options,1);
        check(zero.some(p=>p.kind===kind && p.span>0),
            `zero-width Edge retains unified launcher hit size ${kind} ${edge}`);
        check(!zero.some(p=>p.kind==="clock"),
            "old legacy inherited module keeps original zero-width policy");

        const visible = layout.checkedBatch(
            source,[kind],"showIcon",true,1920,1080,options,1
        );
        check(!visible.rejected && visible.placements.find(p=>p.kind===kind).showIcon,
            "show icon is an atomic editor transaction");
        check(!visible.placements.find(p=>p.kind==="clock").showIcon === false,
            "unrelated module remains untouched");
        const blocked = layout.checkedBatch(source,["existing"],"showIcon",false,
            1920,1080,options,1);
        check(!!blocked.rejected, "old indicators cannot be edited as launchers");

        const saved = layout.saveProfile(
            {outputLayouts:[{outputName:"B",placements:[{id:"foreign",kind:"clock",edge:"right"}]}]},
            "A",source,8,true
        );
        const profiles = saved["abyss.modules.outputLayouts"];
        check(layout.hasEnabledModule({outputLayouts:profiles},"A",kind),
            `output-scoped unified module recognized ${kind}`);
        check(!layout.hasEnabledModule({outputLayouts:profiles},"B",kind),
            "other output retains old anchor fallback");
        check(!layout.hasEnabledModule({outputLayouts:profiles},"C",kind),
            "unconfigured output retains old anchor fallback");
        check(layout.resolve({outputLayouts:profiles},"A",[]).find(p=>p.kind===kind).showIcon===false,
            "hide icon persists after profile roundtrip");

        const disabled = layout.checkedBatch(source,[kind],"enabled",false,
            1920,1080,options,1);
        check(!layout.hasEnabledModule(
            {outputLayouts:[{outputName:"A",placements:disabled.placements}]},"A",kind),
            "disabled launcher restores legacy fallback");
        check(layout.hasEnabledModule({outputLayouts:profiles},"A",kind),
            "a different disabled profile cannot mutate the original");
        check(clone(source).length===2,"data-preserving non-destructive placements");
    }
}
// Installed Alis config defaults enable automatic replacement even when an
// existing user has never opened Edit Abyss Layout. Per-output migration
// markers protect explicit disable/removal and persist across relaunch.
for (const [mode,original] of [
    ["not configured",{autoUnifiedEdgeLaunchers:true,configured:false}],
    ["pre-existing configured",{autoUnifiedEdgeLaunchers:true,configured:true,
        placements:[{id:"clock",kind:"clock",edge:"top",position:.5}]}],
    ["legacy per-output profile",{autoUnifiedEdgeLaunchers:true,configured:true,
        placements:[],outputLayouts:[{outputName:"eDP-1",
            placements:[{id:"clock",kind:"clock",edge:"left",position:.5}]}]}]
]) {
    const notes=layout.resolve(original,"eDP-1",[]);
    check(layout.hasEnabledModule(original,"eDP-1","notesTimers"),
        `auto-enable notes on ${mode}`);
    check(layout.hasEnabledModule(original,"eDP-1","notificationActivity"),
        `auto-enable notifications on ${mode}`);
    check(notes.filter(p=>layout.isUnifiedKind(p.kind)).length===2,
        "exactly two unified launchers, never duplicates");
    check(original.placements===undefined || !original.placements.some(p=>layout.isUnifiedKind(p.kind)),
        "legacy config source not mutated in place");

    // Saving a module-free output must not add launchers again later.
    const save=layout.saveProfile(original,"eDP-1",[],8,true);
    const configured={...original,outputLayouts:save["abyss.modules.outputLayouts"]};
    check(configured.outputLayouts.find(x=>x.outputName==="eDP-1").unifiedLaunchersConfigured,
        "output configuration is marked explicitly migrated");
    check(!layout.hasEnabledModule(configured,"eDP-1","notesTimers"),
        "owner removal remains removed after restart");
    check(!layout.hasEnabledModule(configured,"eDP-1","notificationActivity"),
        "owner removal cannot trigger duplicate activity surfaces");
    if(original.outputLayouts?.length) {
        check(layout.hasEnabledModule(configured,"HDMI-A-1","notesTimers"),
            "untouched output retains migration eligibility");
    }
}
const globalSave=layout.saveProfile(
    {autoUnifiedEdgeLaunchers:true},"eDP-1",[],8,false);
check(globalSave["abyss.modules.unifiedLaunchersConfigured"]===true,
    "global Done marks a completed migration");
check(layout.resolve(
    {autoUnifiedEdgeLaunchers:true,configured:true,
        unifiedLaunchersConfigured:globalSave["abyss.modules.unifiedLaunchersConfigured"],
        placements:globalSave["abyss.modules.placements"]},
    "HDMI-A-1",[]).length===0,
    "globally removed launchers never resurrect");
console.log("ABYSS_R15_LAYOUT_POLICY_PASS",checks);
