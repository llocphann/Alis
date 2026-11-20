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

        // Settings exclusively owns launcher icon visibility. The live
        // layout editor cannot override an explicit global icon choice.
        const unsupported = layout.checkedBatch(
            source,[kind],"showIcon",true,1920,1080,options,1
        );
        check(!!unsupported.rejected,
            "live editor cannot mutate Settings-only icon preference");
        check(source.find(p=>p.kind===kind).showIcon===false,
            "unsupported transaction leaves placement visibility intact");

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

// Active Module-Icon Edgebar launchers keep the painted edge strip thin
// while reserving enough Wayland exclusiveZone spacing on their active edge
// so application windows never overlap their local bump; in Edgebar hover
// mode ("edgebar"), both paint and reservation return to thin edge width.
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
    const records=layout.geometry(local,width,height,opts,1);
    const surfaces=layout.localSurfaces(records,width,height,opts,1,48);
    const edgeSurfaces=surfaces.filter(p=>p.edge===edge);
    check(edgeSurfaces.length>=1,
        `icon bodies still have localized screen-edge paint on ${edge}`);
    const maxBumpDepth=Math.max(...edgeSurfaces.map(s=>s.depth));
    for(const side of edges) {
        check(values[side]===16,`local ${edge} icon cannot change ${side} paint padding`);
        if(side===edge) {
            check(reserved[side]>=Math.ceil(maxBumpDepth),
                `active Edgebar launcher on ${edge} must reserve >= painted bump depth (${maxBumpDepth}), got ${reserved[side]}`);
            check(reserved[side]===Math.ceil(maxBumpDepth),
                `active Edgebar launcher on ${edge} must match painted bump depth (${Math.ceil(maxBumpDepth)}), got ${reserved[side]}`);
        } else {
            check(reserved[side]===16,`local ${edge} icon cannot change unrelated ${side} window padding`);
        }
    }
    // Thin 10px Edge still reserves exact compact bump depth (~36px, below 48px)
    const thinOpts={...opts,edgeThickness:10,edgeThicknesses:{top:10,right:10,bottom:10,left:10}};
    const thinPaint=layout.edgeInsetsForModules(local,thinOpts,1,10,48,false);
    const thinReserved=layout.edgeInsetsForModules(local,thinOpts,1,10,48,true);
    const thinSurfaces=layout.localSurfaces(layout.geometry(local,width,height,thinOpts,1),width,height,thinOpts,1,48).filter(p=>p.edge===edge);
    const thinBump=Math.max(...thinSurfaces.map(s=>s.depth));
    check(thinPaint[edge]===10,`10px Edge paint remains thin (10px), got ${thinPaint[edge]}`);
    check(thinReserved[edge]>=Math.ceil(thinBump)&&thinReserved[edge]<48,
        `10px Edge reserves compact bump depth (${thinBump} < 48), got ${thinReserved[edge]}`);
    const hoverOpts={...opts,launcherMode:"edgebar"};
    const hoverValues=layout.edgeInsetsForModules(local,hoverOpts,1,16,48,false);
    const hoverReserved=layout.edgeInsetsForModules(local,hoverOpts,1,16,48,true);
    for(const side of edges) {
        check(hoverValues[side]===16,`edgebar hover paint padding must stay 16 on ${side}`);
        check(hoverReserved[side]===16,`edgebar hover reservation must stay 16 on ${side}`);
    }
    // Regular scaled or protruding modules (even with 0px edge) must reserve >= local bump depth
    const regular=layout.normalize([
        {id:"clk",kind:"clock",edge,position:.5,size:1.5,protrudeOffset:10}
    ],edge);
    const regOpts={edgeThickness:0,edgeThicknesses:{top:0,right:0,bottom:0,left:0},
        edgeWidthAffectsModules:{top:false,right:false,bottom:false,left:false}};
    const regRecords=layout.geometry(regular,width,height,regOpts,1);
    const regSurfaces=layout.localSurfaces(regRecords,width,height,regOpts,1,48);
    const regReserved=layout.edgeInsetsForModules(regular,regOpts,1,0,48,true);
    const regMaxDepth=Math.max(...regSurfaces.map(s=>s.depth));
    check(regReserved[edge]>=Math.ceil(regMaxDepth),
        `scaled/protruding module on ${edge} must reserve >= painted bump depth (${regMaxDepth}), got ${regReserved[edge]}`);
}
// The persisted JsonAdapter values must override old per-output icon settings
// without changing physical placement or silently throwing away a legacy
// "hidden" preference when the user has not yet made a Settings choice.
for(const value of ["show","hide","inherit",true,false,"true","false"]) {
    const expected=value==="show"||value===true||value==="true" ? true
        : value==="hide"||value===false||value==="false" ? false : null;
    check(layout.iconVisibilityPreference(
        {iconVisibility:{notesTimers:value}},"notesTimers")===expected,
        "JSON schema icon override accepts "+String(value));
}
const persisted={
    autoUnifiedEdgeLaunchers:true,configured:true,placements:[],
    outputLayouts:[{outputName:"eDP-1",unifiedLaunchersConfigured:true,
        placements:[
            {id:"notes-id",kind:"notesTimers",edge:"left",position:.3,showIcon:true},
            {id:"notice-id",kind:"notificationActivity",edge:"right",position:.7,showIcon:false}
        ]}],
    iconVisibility:{notesTimers:"hide",notificationActivity:"show"}
};
let resolved=layout.resolve(persisted,"eDP-1",[]);
check(resolved.find(p=>p.kind==="notesTimers").showIcon===false,
    "Settings hide propagates to an already-saved per-output Note launcher");
check(resolved.find(p=>p.kind==="notificationActivity").showIcon===true,
    "Settings show propagates to an already-saved per-output Notification launcher");
check(resolved.find(p=>p.kind==="notesTimers").edge==="left",
    "Settings icon change does not move the launcher");
const baseProfile=clone(persisted);
baseProfile.iconVisibility={notesTimers:"inherit",notificationActivity:"inherit"};
resolved=layout.resolve(baseProfile,"eDP-1",[]);
check(resolved.find(p=>p.kind==="notesTimers").showIcon===true,
    "inherit retains legacy visible Notes icon");
check(resolved.find(p=>p.kind==="notificationActivity").showIcon===false,
    "inherit retains legacy hidden Notification icon");

// Regression: a mini module's own local paint reaches 48px or more from the
// attached edge; feeding that local surface back into its popup clearance
// artificially moved the popup body inward. Other modules remain obstacles.
for(const edge of edges) {
    const saved=layout.normalize([
        {id:"notes",kind:"notesTimers",edge,position:.24,showIcon:true},
        {id:"notice",kind:"notificationActivity",edge,position:.78,showIcon:true}
    ],edge);
    const opts={edgeThickness:16,edgeThicknesses:{top:16,right:16,bottom:16,left:16},
        edgeWidthAffectsModules:{top:true,right:true,bottom:true,left:true}};
    const local=layout.localSurfaces(
        layout.geometry(saved,1920,1080,opts,1),1920,1080,opts,1,48);
    check(local.filter(p=>p.kind==="notesTimers").length===1,
        "Notes local geometry retains its owner kind on "+edge);
    check(local.filter(p=>p.kind==="notificationActivity").length===1,
        "Notification local geometry retains its owner kind on "+edge);
    for(const kind of ["notesTimers","notificationActivity"]) {
        const own=local.find(p=>p.kind===kind);
        const base={top:16,right:16,bottom:16,left:16};
        const oldInsets=layout.clearanceInsets(base,local,edge,own.along,own.span);
        const fixed=layout.clearanceInsets(base,local,edge,own.along,own.span,kind);
        check(oldInsets[edge]>=48,
            "pre-fix popup was displaced by its own local launcher on "+edge);
        check(fixed[edge]===16,
            "own Edge launcher is excluded from popup clearance on "+edge);
        for(const otherEdge of edges.filter(e=>e!==edge)) {
            check(fixed[otherEdge]===16,
                "popup side clearance must not thicken unrelated "+otherEdge);
        }
    }
}
// ABYSS-R15 final UX: Show icon is NOT a graphics-only preference.
// Settings sends module/edgebar into exactly the same per-feature mode key
// as Module Behavior. Live module source counts must be 1 or 0 (never an
// invisible hover region) while each legacy corner owns the inverse mode.
const twoModules=layout.normalize([
    {id:"n",kind:"notesTimers",edge:"left",position:.18,showIcon:false},
    {id:"a",kind:"notificationActivity",edge:"right",position:.87,showIcon:false},
    {id:"clock",kind:"clock",edge:"top",position:.5}
],"top");
for(const notesChecked of [false,true])for(const notificationsChecked of [false,true]) {
    const profile={
        notesTimersMode:notesChecked?"module":"edgebar",
        notificationActivityMode:notificationsChecked?"module":"edgebar",
        iconVisibility:{notesTimers:"hide",notificationActivity:"hide"}
    };
    const active=layout.livePlacements(twoModules,profile,false);
    const activeRecords=layout.geometry(active,1920,1080,profile,1);
    const activeSurfaces=layout.localSurfaces(activeRecords,1920,1080,profile,1,36);
    check(active.some(p=>p.kind==="notesTimers")===notesChecked,
        "Quick Notes Show icon drives actual active module lifecycle");
    check(active.some(p=>p.kind==="notificationActivity")===notificationsChecked,
        "Notifications Show icon drives actual active module lifecycle");
    check(activeSurfaces.some(p=>p.kind==="notesTimers")===notesChecked,
        "Quick Notes in module mode always gets Screen Edge localSurface despite legacy showIcon=false");
    check(activeSurfaces.some(p=>p.kind==="notificationActivity")===notificationsChecked,
        "Notifications in module mode always gets Screen Edge localSurface despite legacy showIcon=false");
    check(layout.unifiedLauncherMode(profile,"notesTimers")===(notesChecked?"module":"edgebar"),
        "Notes Module Behavior reflects same toggle");
    check(layout.unifiedLauncherMode(profile,"notificationActivity")===(notificationsChecked?"module":"edgebar"),
        "Notifications Module Behavior reflects same toggle");
    check(active.some(p=>p.kind==="clock"),
        "switching individual hover owner never affects unrelated modules");
    check(layout.livePlacements(twoModules,profile,true).length===3,
        "switching to Edgebar does not delete stored output placements");
}
for(const selectedKind of ["notesTimers","notificationActivity"]) {
    const hiddenLegacy={launcherMode:"module",iconVisibility:{[selectedKind]:"hide"}};
    check(layout.unifiedLauncherMode(hiddenLegacy,selectedKind)==="edgebar",
        "pre-existing Settings hide preference migrates to true Edgebar mode");
    check(layout.livePlacements(twoModules,hiddenLegacy,false)
        .every(p=>p.kind!==selectedKind),
        "migrated legacy hide preference unmounts invisible module");
    const selected={...hiddenLegacy,[selectedKind+"Mode"]:"module"};
    check(layout.unifiedLauncherMode(selected,selectedKind)==="module",
        "explicit Show icon on overrides obsolete hide preference");
    check(layout.livePlacements(twoModules,selected,false)
        .some(p=>p.kind===selectedKind),
        "explicit Show icon on remounts saved module at prior position");
}
// The actual ScreenCorners popup host must be exclusive with the chosen
// module owner, including when the Bar is closed, auto-hidden or has no
// currently mounted icon. The mode (not barOpen) owns the entire decision.
for (const kind of ["notesTimers","notificationActivity"]) {
    for (const mode of ["module","edgebar"]) {
        const options={
            launcherMode:"edgebar",
            notesTimersMode:kind==="notesTimers" ? mode : "edgebar",
            notificationActivityMode:kind==="notificationActivity" ? mode : "edgebar"
        };
        const expected=mode==="module";
        for (const family of ["abyss","ii","waffle"]) {
            check(layout.moduleOwnsCornerHover(options,family,kind)
                ===(family==="abyss" && expected),
                `ScreenCorners exclusive owner ${kind} mode=${mode} family=${family}`);
        }
        // Neither an empty output profile nor a disabled placement may
        // resurrect legacy ScreenCorners while Module Icon was selected.
        const missingOutput={...options,configured:true,placements:[],
            unifiedLaunchersConfigured:true};
        check(layout.moduleOwnsCornerHover(missingOutput,"abyss",kind)===expected,
            "missing/disabled module cannot change Settings hover ownership");
    }
}
for (const settings of [
    {notesTimersMode:"module",notificationActivityMode:"edgebar"},
    {notesTimersMode:"edgebar",notificationActivityMode:"module"},
    {notesTimersMode:"module",notificationActivityMode:"module"},
    {notesTimersMode:"edgebar",notificationActivityMode:"edgebar"}
]) {
    const n=layout.moduleOwnsCornerHover(settings,"abyss","notesTimers");
    const a=layout.moduleOwnsCornerHover(settings,"abyss","notificationActivity");
    check(n===(settings.notesTimersMode==="module"),"Quick Notes corner owner independent");
    check(a===(settings.notificationActivityMode==="module"),"Notification corner owner independent");
}
check(layout.moduleOwnsCornerHover({launcherMode:"module"},"ii","notesTimers")===false,
    "classic ii stays fully backward-compatible");
// Regression: Panels > Tools Quick Notes enable control was removed, but
// configs with its old value false still exist. The explicit Abyss Edgebar
// selection is now the authoritative way to restore the live hover surface.
for (const kind of ["notesTimers","notificationActivity"]) {
    for (const mode of ["module","edgebar"]) {
        const cfg={
            notesTimersMode:kind==="notesTimers" ? mode : "module",
            notificationActivityMode:kind==="notificationActivity" ? mode : "module",
            quickNotes:{enable:false,monitorMode:"primary"},
            notificationCenter:{enable:false,hoverEnable:false,screenList:["old-output"]}
        };
        const legacyAllowed=layout.edgebarOwnsCornerHover(cfg,"abyss",kind);
        const iconAllowed=layout.moduleOwnsCornerHover(cfg,"abyss",kind);
        check(legacyAllowed===(mode==="edgebar"),
            `Abyss Edgebar restores ${kind} despite disabled legacy settings`);
        check(iconAllowed===(mode==="module"),
            `Abyss Module Icon takes exclusive ownership for ${kind}`);
        check(iconAllowed!==legacyAllowed,
            `Abyss modes must never leave both sources active or both disabled ${kind}`);
        check(!layout.edgebarOwnsCornerHover(cfg,"ii",kind),
            "ii family not controlled by Abyss access mode");
        check(!layout.edgebarOwnsCornerHover(cfg,"waffle",kind),
            "waffle family not controlled by Abyss access mode");
    }
}

// Resizing QuickNotes or Notifications must scale the Screen Edge / Corner bump
// continuously alongside the icon, rather than clamping depth flat at 48px.
for (const edge of edges) {
    for (const kind of ["notesTimers", "notificationActivity"]) {
        for (const thickness of [10, 16]) {
            let prevDepth = 0, prevSpan = 0;
            for (const scale of [0.6, 0.8, 1.0, 1.4, 1.8]) {
                const mod = layout.normalize([{ id: kind, kind, edge, position: 0.1, showIcon: true, joinCorner: false }], edge);
                const opts = {
                    edgeThickness: thickness,
                    edgeThicknesses: { [edge]: -1 },
                    edgeSizes: { [edge]: scale },
                    edgeWidthAffectsModules: { [edge]: false },
                    size: 1
                };
                const records = layout.geometry(mod, 1920, 1080, opts, 1);
                const surfaces = layout.localSurfaces(records, 1920, 1080, opts, 1, 48);
                check(surfaces.length === 1, `unified resize surface missing ${kind} ${edge}`);
                const s = surfaces[0];
                const surfaceSpan = edge === "top" || edge === "bottom" ? s.surface.width : s.surface.height;
                check(s.depth > prevDepth && surfaceSpan > prevSpan,
                    `unified surface must grow monotonically at thickness=${thickness} scale=${scale} (${s.depth} vs ${prevDepth})`);
                if (thickness === 16 && scale === 1.0)
                    check(Math.abs(s.depth - 48) < 0.01, "default 16px/1.0x depth preserves 48px baseline");
                prevDepth = s.depth;
                prevSpan = surfaceSpan;
            }
        }
        // Custom size overrides on a unified corner-joined module must also scale depth.
        let prevCustomDepth = 0;
        for (const custom of [0.6, 1.0, 1.5]) {
            const cornerMod = layout.normalize([{ id: kind, kind, edge, position: 0.05, customSize: true, size: custom, joinCorner: true }], edge);
            const opts = { edgeThickness: 10, edgeWidthAffectsModules: { [edge]: false } };
            const records = layout.geometry(cornerMod, 1920, 1080, opts, 1);
            const surfaces = layout.localSurfaces(records, 1920, 1080, opts, 1, 48);
            check(surfaces.length === 1 && surfaces[0].depth > prevCustomDepth,
                `corner-joined unified customSize=${custom} did not scale bump depth`);
            prevCustomDepth = surfaces[0].depth;
        }
    }
}
console.log("ABYSS_R15_LAYOUT_POLICY_PASS",checks);
