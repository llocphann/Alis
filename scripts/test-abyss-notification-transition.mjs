#!/usr/bin/env node
// Regression for the *actual* Abyss transient banner QML expressions.
// This runs without Qt: native presentation/performance acceptance is separate.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>readFileSync(resolve(root,p),'utf8');
const source=read('modules/abyss/AbyssPerimeter.qml');
const bannerContent=read('modules/abyss/content/AbyssNotificationsContent.qml');
const centerPopup=read('modules/notificationCenter/NotificationCenterPopup.qml');
const corners=read('modules/abyss/AbyssCorners.qml');
const adapter=read('modules/abyss/content/AbyssNotificationsContent.qml');

const start=source.indexOf('id: notification\n');
const end=source.indexOf('id: toastBody\n',start);
assert.ok(start>=0 && end>start,'live transient banner host is missing');
const banner=source.slice(start,end);
function expression(before,after) {
    const a=banner.indexOf(before);
    assert.ok(a>=0,'missing banner QML property '+before);
    const b=banner.indexOf(after,a+before.length);
    assert.ok(b>a,'missing expression delimiter '+after);
    return banner.slice(a+before.length,b).trim();
}
const expressions={
    position:expression('readonly property string position:','\n                readonly property string presentationKind:'),
    kind:expression('readonly property string presentationKind:','\n                edge:'),
    edge:expression('\n                edge:','\n                joinedEdge:'),
    open:expression('\n                open:','\n                edgeInsets:'),
    width:expression('readonly property real contentWidth:','\n                readonly property real contentHeight:'),
    height:expression('readonly property real contentHeight:','\n                span:'),
    span:expression('\n                span:','\n                along:'),
    along:expression('\n                along:','\n                depth:'),
    depth:expression('\n                depth:','\n                obstacles:'),
    contentKind:expression('\n                contentKind:','\n                source:')
};
const functions=Object.fromEntries(Object.entries(expressions).map(([key,code])=>[
    key,new Function('Config','GlobalStates','Notifications','window',
        'Appearance','padding','contentItem','field','Geometry','Quickshell',
        'position','presentationKind','edge','span','contentWidth','contentHeight',
        'return ('+code+');')]));
let tests=0;
function same(label,actual,expected) {
    assert.deepEqual(actual,expected,label);
    ++tests;
}
function state({centerOpen=false,toastCount=1,toastHeight=130,
    position='topRight',customCenterWidth=420,customCenterHeight=560,
    outputName='eDP-1',popupLayoutReady=true}={}) {
    const config={options:{
        panelFamily:'abyss',enabledPanels:['abyssNotificationPopup','abyssNotificationCenter'],
        notifications:{position,screenList:[]},
        notificationCenter:{popupWidth:customCenterWidth,popupHeight:customCenterHeight}
    }};
    const gs={notificationCenterOpen:centerOpen,
        notificationCenterPresentationOutput:outputName};
    const notification={popupInhibited:centerOpen,popupList:Array(toastCount).fill({})};
    const window={presented:true,outputName,width:1920,height:1200,
        nativeInsets:{left:16,right:16,top:16,bottom:16},
        positionEdge:(_kind,fallback)=>fallback,
        positionAlong:(_kind,_edge,_span,fallback)=>fallback};
    const ctx=[config,gs,notification,window,
        {sizes:{notificationPopupWidth:360}},14,
        {item:{desiredWidth:360,desiredHeight:toastHeight,popupLayoutReady}},
        {ready:true},{horizontal:e=>e==='top'||e==='bottom',
            targets:()=>true},
        {screens:[{name:'eDP-1'}]}];
    function value(which,...additional){return functions[which](...ctx,...additional)}
    const side=value('position'),kind=value('kind'),edge=value('edge',side,kind);
    const width=value('width',side,kind,edge);
    const height=value('height',side,kind,edge);
    const span=value('span',side,kind,edge,0,width,height);
    return {position:side,kind,edge,width,height,span,
        depth:value('depth',side,kind,edge,span,width,height),
        along:value('along',side,kind,edge,span,width,height),
        contentKind:value('contentKind',side,kind,edge,span,width,height),
        open:value('open',side,kind,edge,span,width,height)};
}
const normal=state();
const openingCenter=state({centerOpen:true});
same('toast visible before center opens',normal.open,true);
same('transient banner waits for a settled layout before opening',
    state({popupLayoutReady:false}).open,false);
same('transient banner measurement preloads content independently of open',
    banner.includes('residentContent: Notifications.popupList.length > 0'),true);
same('transient banner opens from the same host after sizing stabilizes',
    state({popupLayoutReady:true}).open,true);
same('center open dismisses toast request',openingCenter.open,false);
for(const prop of ['position','kind','edge','width','height','span','depth','along','contentKind']) {
    same('opening center MUST NOT mutate closing toast '+prop,openingCenter[prop],normal[prop]);
}
same('transient notification still uses small popup renderer',normal.contentKind,'popup');
same('live top-right banner height',normal.height,158);
same('live banner attaches to top',normal.edge,'top');
const custom=state({centerOpen:true,customCenterWidth:760,customCenterHeight:900});
for(const prop of ['width','height','span','depth','along']) {
    same('custom center size MUST NOT alter closing notification '+prop,custom[prop],normal[prop]);
}
const bottom=state({position:'bottomLeft'});
same('bottom-left banner is still bottom-edge anchored',bottom.edge,'bottom');
same('bottom-left banner begins at 40px tangent margin',bottom.along,40);
same('bottom-left banner stays popup content',bottom.contentKind,'popup');
const noToast=state({toastCount:0});
same('empty banner list cannot leave phantom notification open',noToast.open,false);
const many=state({toastCount:3,toastHeight:320});
same('multi-notification banner height follows its own content',many.height,348);
same('center does not alter multi-notification banner height',
    state({centerOpen:true,toastCount:3,toastHeight:320}).height,348);
same('notification entry is a stable-content-size clipped host',
    banner.includes('stableContentSize: true'),true);
same('transient banner opts into monotonic one-phase motion',
    banner.includes('monotonicNotificationReveal: true'),true);
same('no center/tall-screen branch remains in banner host',
    !banner.includes('centerOnOutput') && !banner.includes('contentKind: centerOnOutput'),
    true);
same('banner Loader only switches to center on kind=center',
    bannerContent.includes('readonly property bool center: kind === "center"'),true);
same('banner does not instantiate history center Loader',
    normal.contentKind==='popup' && bannerContent.includes('active: root.center'),true);
same('actual separately-owned Notification Center remains present',
    corners.includes('NotificationCenterPopup {'),true);
same('custom Notification Center width still binds to public setting',
    centerPopup.includes('Config.options?.notificationCenter?.popupWidth ?? 420'),true);
same('custom Notification Center height still binds to public setting',
    centerPopup.includes('Config.options?.notificationCenter?.popupHeight ?? 560'),true);
// Run the real QML measurement functions against a synthetic Recording saved
// message: its absolute path makes the notification delegate taller only AFTER
// the initial ListView creates and lays out the card. No UI is instantiated.
function qmlMethod(name) {
    const marker='function '+name+'(): void {';
    const start=adapter.indexOf(marker);
    assert.ok(start>=0,'missing '+name);
    const brace=adapter.indexOf('{',start);
    let depth=0,end=-1;
    for(let i=brace;i<adapter.length;i++) {
        if(adapter[i]==='{') depth++;
        if(adapter[i]==='}' && --depth===0){end=i+1;break;}
    }
    assert.ok(end>brace,'unterminated QML method '+name);
    return adapter.slice(start,end).replace('(): void {','() {');
}
const rootState={center:false,settledPopupHeight:0,popupLayoutReady:false};
const recordedPath='/home/tester/Videos/2026-10-10_recorder-test.mp4';
const notificationApi={popupList:[{summary:'Recording saved',body:recordedPath}]};
const popupLoader={item:{contentHeight:0}};
const timer={restarts:0,restart(){this.restarts++}};
const methods=new Function('root','Notifications','popupLoader','popupMeasureTimer',
    qmlMethod('schedulePopupMeasurement')+'\n'
    +qmlMethod('commitPopupMeasurement')+'\n'
    +'return {schedule:schedulePopupMeasurement,commit:commitPopupMeasurement};')(
        rootState,notificationApi,popupLoader,timer);
methods.schedule();
same('no banner reveal while ListView height is provisional',rootState.popupLayoutReady,false);
same('zero ListView height never schedules reveal',timer.restarts,0);
// A first provisional delegate height, followed by the final wrapped file path.
popupLoader.item.contentHeight=62;
methods.schedule();
popupLoader.item.contentHeight=166;
methods.schedule();
same('both provisional changes are batched by one timer',timer.restarts,2);
same('height remains unpublished before settle',rootState.settledPopupHeight,0);
methods.commit();
same('final path card height committed',rootState.settledPopupHeight,166);
same('settled card enables native banner reveal',rootState.popupLayoutReady,true);
popupLoader.item.contentHeight=254;
methods.schedule();
same('already visible popup does not resize until batch settles',
    rootState.settledPopupHeight,166);
methods.commit();
same('subsequent additional notification size committed once',rootState.settledPopupHeight,254);
notificationApi.popupList=[];
popupLoader.item.contentHeight=300;
methods.schedule();
methods.commit();
same('empty popup list cannot resurrect old measurement',
    rootState.settledPopupHeight,254);
rootState.center=true;
notificationApi.popupList=[{summary:'a different notification'}];
methods.schedule();
methods.commit();
same('history-center content cannot override transient sizing',
    rootState.settledPopupHeight,254);
same('actual adapter gates view until measured',
    adapter.includes('property bool popupLayoutReady: false')
        && adapter.includes('readonly property real desiredHeight: root.settledPopupHeight')
        && adapter.includes('target: popupLoader.item')
        && adapter.includes('interval: 75'),true);

// Notification Center IPC/Edgebar: StyledPopup owns the entire reveal curve.
// The shared Abyss host must not double-ease the same opening/closing slide.
const host=read('modules/abyss/AbyssBodyHost.qml');
const hostedSlotStart=source.indexOf('id: styledPopupHost');
const hostedSlotEnd=source.indexOf('onPopupEntryChanged:',hostedSlotStart);
assert.ok(hostedSlotStart >= 0 && hostedSlotEnd > hostedSlotStart,
    'hosted popup slot must remain present');
const hostedSlot=source.slice(hostedSlotStart,hostedSlotEnd);
same('Center-only external motion flag enabled',
    hostedSlot.includes('singleExternalReveal: presentationKind === "notificationCenter"')
    && hostedSlot.includes('|| presentationKind === "notificationActivity"'),true);
same('mature popup still owns reveal',
    hostedSlot.includes('externalProgress: hostedPopup?.revealProgress ?? 0'),true);
same('reveal suppression only disables host availability Behavior',
    host.includes('enabled: root.animatePresentation && AbyssStyle.motionEnabled\n            && !root.singleExternalReveal'),true);
same('single external reveal defaults OFF for unrelated popup and toast hosts',
    host.includes('property bool singleExternalReveal: false')
    && !banner.includes('singleExternalReveal:'),true);
same('generic panel motion remains the default',
    host.includes('property bool monotonicNotificationReveal: false'),true);
same('transient notification omits the overshoot amplitude',
    host.includes('(root.monotonicNotificationReveal ? 0 : AbyssStyle.motionOvershoot)'),true);
same('transient notification skips the entire settle pass',
    host.includes('duration: !root.monotonicNotificationReveal')
    && host.includes('&& root.presented && AbyssStyle.motionOvershoot > 0'),true);
same('transient opening and closing retain opposite cubic easing',
    host.includes('easing.type: root.presented ? Easing.OutCubic : Easing.InCubic'),true);
same('existing availability/readiness guard stays active',
    host.includes('property real availabilityProgress: presented && ready ? 1 : 0'),true);
same('pyramid close and reversal still track normalized external progress',
    host.includes('root.externalProgress') && host.includes('root.pyramidClosing')
    && host.includes('root.pyramidReopening'),true);
const progressMatch=host.match(/property real progress: ([^\n]+\n\s*\?[^\n]+\n\s*:[^\n]+)/);
assert.ok(progressMatch,'missing actual QML combined progress');
const progressFn=new Function('externalProgress','availabilityProgress',
    'return ('+progressMatch[1].trim()+');');
const states=[0,.12,.25,.5,.75,.99,1,.75,.5,.25,.01,0];
for(const p of states) {
    same('single Center reveal follows one driver at '+p,
         progressFn(p,1),p);
}
same('content-not-ready still masks externally driven reveal',
    progressFn(.75,0),0);
same('nonexternal toast keeps its own host animation',
    progressFn(-1,.37),.37);

console.log('PASS: '+tests+' source-executed Abyss Notification Center transition assertions');
