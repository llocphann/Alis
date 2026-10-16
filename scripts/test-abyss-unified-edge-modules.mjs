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
// Switching sources must be exclusive and must not rewrite module records or
// reset per-output icon preference. Every physical edge follows the same rule.
check(layout.unifiedLauncherMode({})==="module","fresh installations prefer modules");
check(layout.unifiedLauncherMode({launcherMode:"garbage"})==="module",
    "unknown legacy mode fails safe to module");
check(layout.unifiedLauncherMode({launcherMode:"edgebar"})==="edgebar",
    "legacy hover mode explicitly selected");
for(const edge of edges) {
    const original=layout.normalize([
        {id:"mNotes",kind:"notesTimers",edge,position:.2,showIcon:false},
        {id:"clock",kind:"clock",edge,position:.5},
        {id:"mCenter",kind:"notificationActivity",edge,position:.8,showIcon:true}
    ],edge);
    const before=JSON.stringify(original);
    const moduleMode=layout.livePlacements(original,{launcherMode:"module"},false);
    const cornerMode=layout.livePlacements(original,{launcherMode:"edgebar"},false);
    check(moduleMode.filter(p=>layout.isUnifiedKind(p.kind)).length===2,
        `both module launchers own hover on ${edge}`);
    check(cornerMode.length===1 && cornerMode[0].kind==="clock",
        `legacy Edgebar hover completely unmounts both launchers on ${edge}`);
    check(layout.livePlacements(original,{launcherMode:"edgebar"},true).length===3,
        "editor keeps saved module handles selectable in hover mode");
    check(layout.livePlacements(original,{launcherMode:"module"},false)
        .find(p=>p.kind==="notesTimers").showIcon===false,
        "owner's explicit hide icon survives switching back");
    check(JSON.stringify(original)===before,
        "transient launcher mode never writes historical saved placements");
}
const preservedProfile={configured:true,launcherMode:"edgebar",placements:[
    {id:"first",kind:"notesTimers",edge:"left",position:.4,showIcon:true},
    {id:"second",kind:"notificationActivity",edge:"right",position:.7,showIcon:false}
]};
const oldEntries=layout.resolve(preservedProfile,"eDP-1",[]);
check(layout.livePlacements(oldEntries,preservedProfile,false).length===0,
    "legacy mode has zero invisible mouse sources");
check(layout.livePlacements(oldEntries,
    {...preservedProfile,launcherMode:"module"},false).length===2,
    "re-entering module mode uses original output positions");
// Each feature independently switches module ownership, even on a single
// output, and legacy saved one-switch profiles retain their old intent.
const modes=layout.normalize([
    {id:"nt",kind:"notesTimers",edge:"top",position:.15,showIcon:true},
    {id:"na",kind:"notificationActivity",edge:"right",position:.2,showIcon:true},
    {id:"clock",kind:"clock",edge:"bottom",position:.5}
],"top");
for(const notesMode of ["module","edgebar"])for(const activityMode of ["module","edgebar"]) {
    const settings={launcherMode:"edgebar",notesTimersMode:notesMode,
        notificationActivityMode:activityMode};
    const live=layout.livePlacements(modes,settings,false);
    check(live.some(p=>p.kind==="notesTimers")===(notesMode==="module"),
        "QuickNotes launcher follows its own mode");
    check(live.some(p=>p.kind==="notificationActivity")===(activityMode==="module"),
        "Notifications launcher follows its own mode");
    check(live.some(p=>p.kind==="clock"),"unrelated bar module preserved");
    check(layout.livePlacements(modes,settings,true).length===3,
        "layout editor still sees both saved source locations");
}
check(layout.livePlacements(modes,{launcherMode:"edgebar"},false).length===1,
    "old one-switch edgebar profile remains supported");
check(layout.livePlacements(modes,{launcherMode:"module"},false).length===3,
    "old one-switch icon profile remains supported");
check(layout.unifiedLauncherMode({launcherMode:"edgebar",notesTimersMode:"module"},
    "notesTimers")==="module","new Notes override wins legacy global choice");
check(layout.unifiedLauncherMode({launcherMode:"module",notificationActivityMode:"edgebar"},
    "notificationActivity")==="edgebar","new Notifications override wins legacy choice");

// Tiny local launcher bumps must not distort window padding on *any* side.
// Real module geometry must still generate a bounded local paint Surface.
for(const edge of edges) {
    const local=layout.normalize([
        {id:"nt",kind:"notesTimers",edge,position:.22,showIcon:true},
        {id:"na",kind:"notificationActivity",edge,position:.78,showIcon:true}
    ],edge);
    const opts={edgeThickness:16,edgeThicknesses:{top:16,right:16,bottom:16,left:16},
        edgeWidthAffectsModules:{top:true,right:true,bottom:true,left:true},
        singleModuleExpansion:{top:"edge",right:"edge",bottom:"edge",left:"edge"}};
    const width=1920,height=1080;
    const values=layout.edgeInsetsForModules(local,opts,1,16,48,false);
    const reserved=layout.edgeInsetsForModules(local,opts,1,16,48,true);
    for(const side of edges) {
        check(values[side]===16,`local ${edge} icon cannot change ${side} paint padding`);
        check(reserved[side]===16,`local ${edge} icon cannot change ${side} window padding`);
    }
    const records=layout.geometry(local,width,height,opts,1);
    const surfaces=layout.localSurfaces(records,width,height,opts,1,48);
    check(surfaces.filter(p=>p.edge===edge).length>=1,
        `icon bodies still have localized screen-edge paint on ${edge}`);
}
console.log("ABYSS_R15_LAYOUT_POLICY_PASS",checks);
