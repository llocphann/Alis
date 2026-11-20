#!/usr/bin/env python3
"""Render registered Abyss Settings routes in an isolated desktop and measure form layout."""
import argparse
import json
import tempfile
from pathlib import Path

from native_test_session import private_wayland, run_qs

QML = r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.settings
import qs.services

Window {
    id: window
    visible: true; width: Number(Quickshell.env("FORM_WIDTH")); height: 990
    Component.onCompleted: Quickshell.watchFiles = false
    Rectangle { id: host; anchors.fill: parent; color: "#11181a" }
    SettingsOverlay { id: overlay; embeddedHost: host; settingsOpen: true }
    TestCase {
        id: testCase
        when: false; optional: true
        function walk(item, fn) {
            if (!item || !item.visible || item.opacity <= 0 || (item.clip && (item.width <= 0 || item.height <= 0))) return
            fn(item)
            for (const child of item.children ?? []) walk(child, fn)
        }
        function box(i) {
        const p=i.mapToItem(host,0,0)
        return [p.x,p.y,i.width,i.height].map(Math.round)
        }
        function inspect(page, index, key) {
            const cards=[], clipped=[], fields={}, tabs=[]
            let pageColumn=null
            walk(page, i => {
                if (i.objectName === 'contentColumn' && !pageColumn) pageColumn=box(i)
                if (i.naturalCardImplicitHeight !== undefined && i.title) {
                    const rect=box(i)
                    cards.push({name:i.title,rect:rect,parent:box(i.parent),
                        naturalH:Math.round(i.naturalCardImplicitHeight),
                        headerH:Math.round(i.headerImplicitHeight ?? 0)})
                }
                if (i.objectName && /^(aquaQuietHours(Start|End)Control|aquaEnableProactive|aquaProactiveFrequencyControl|companionOverviewMemoryOptIn|aquaQuietHoursGrid|aquaReminderSourcesGrid)$/.test(i.objectName)) {
                    const row={rect:box(i),text:i.displayText ?? i.text ?? "",clipped:[]}; fields[i.objectName]=row
                    walk(i, c=>{if(c.truncated && c.text)row.clipped.push(c.text)})
                }
                if (i.truncated && i.text && i.width>0 && typeof i.text === "string" && i.text.length<100) clipped.push(i.text)
                if (i.objectName === 'settingsSectionTabTrack' || i.objectName === 'settingsTaskRail') {
                    tabs.push({name:i.objectName,rect:box(i),parent:box(i.parent)})
                }
            })
            console.info("PAGE_LAYOUT",JSON.stringify({index,key,pageColumn,cards,fields,clipped:[...new Set(clipped)],tabs}))
        }
        function review() { try {
            tryCompare(Config,"ready",true,7000)
            tryCompare(Persistent,"ready",true,7000)
            tryCompare(overlay,"_navigationInitialized",true,9000)
            tryCompare(AlisCompanion,"available",true,8000)
            const selection=Quickshell.env("FORM_PAGES")
            const routes=selection ? selection.split(",").map(Number) : SettingsPageRegistry.navigationPageIndexes(false)
            if (!selection && !routes.includes(40) && SettingsPageRegistry.isPageApplicable(40)) routes.push(40)
            for (const index of routes) {
                overlay.showingHome=false;overlay.overlayCurrentPage=index
                tryVerify(()=>overlay.pageHost?.currentIndex===index && overlay.pageHost.currentItem && !overlay.pageHost.loading,10000)
                const outer=overlay.pageHost.currentItem
                wait(200)
                let page=outer
                if (!page._subTabItems) walk(outer,i=>{if(page===outer && i._subTabItems && !i.embedded)page=i})
                const tabs=(page._subTabItems ?? []).filter(t=>t.pageIndex===index && ["pageSection","task","cardPage","customSubTab"].includes(t.kind))
                const variants=[...new Set([...(SettingsPageRegistry.pages[index]?.subTabs ?? []).map(t=>t.value),...tabs.map(t=>t.value)])]
                if (!variants.length) variants.push("")
                for (const key of variants) {
                    if (key) {
                        const tab=tabs.find(t=>t.value===key)
                        if (tab) page.activateSubTabItem(tab)
                        else overlay.pageHost._applySectionToPage(index,key)
                        tryVerify(()=>page.activeSection===key || page._subTabItems?.some(t=>t.value===key && t.active),4000)
                    }
                    wait(200)
                    inspect(outer,index,key)
                    if (Quickshell.env("FORM_IMAGES")==="1") {
                        let done=false;const name=index+"-"+String(key || "default").replace(/[^a-z0-9_-]/gi,"_")
                        if (!host.grabToImage(im=>{done=im.saveToFile(Quickshell.env("FORM_OUT")+"/"+name+".png")}))throw new Error("grab "+name)
                        tryVerify(()=>done,3500)
                    }
                }
            }
            console.info("FORM_CATALOG_PASS",routes.length)
        } catch(e){console.error("FORM_CATALOG_FAIL",e.message,e.stack)} Qt.quit() }
    }
    Timer {interval:200;running:true;onTriggered:testCase.review()}
}
'''

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--host',type=Path,required=True)
    ap.add_argument('--companion',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--width',type=int,default=1540)
    ap.add_argument('--pages',default='')
    ap.add_argument('--images',action='store_true')
    a=ap.parse_args()
    a.output.mkdir(parents=True,exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='alis-pages-') as temp:
        d=Path(temp)
        for rel in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations','settings.qml']:
            (d/rel).symlink_to(a.host.resolve()/rel)
        (d/'shell.qml').write_text(QML)
        package = d/'optional'/'alis-companion'
        package.mkdir(parents=True)
        comp_root = a.companion.resolve()
        for entry in comp_root.iterdir():
            if entry.name == 'native' and not (comp_root / 'native/bin/alis-companiond').is_file():
                continue
            (package / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
        if not (package / 'native/bin/alis-companiond').is_file():
            built = comp_root / 'native/target/release/alis-companiond'
            if built.is_file():
                (package / 'native/bin').mkdir(parents=True)
                (package / 'native/bin/alis-companiond').symlink_to(built)
        with private_wayland(d) as env:
            if not env or env.get('QT_QPA_PLATFORM')!='wayland':raise RuntimeError('private Wayland unavailable')
            conf=json.loads((a.host/'defaults/config.json').read_text())
            conf['panelFamily']='abyss';conf.setdefault('weather',{})['enable']=False;conf.setdefault('abyss',{}).setdefault('companion',{})['enabled']=False
            for sub in ['alis','illogical-impulse']:
                p=d/'config'/sub/'config.json';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(conf))
            home=d/'home';home.mkdir()
            result=run_qs(d,dict(env,HOME=str(home),DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent',FORM_WIDTH=str(a.width),FORM_PAGES=a.pages,FORM_OUT=str(a.output.resolve()),FORM_IMAGES=str(int(a.images))),timeout=160)
    (a.output/'run.log').write_text(result.stdout)
    rows=[json.loads(l.split('PAGE_LAYOUT ',1)[1]) for l in result.stdout.splitlines() if 'PAGE_LAYOUT {' in l]
    (a.output/'pages.json').write_text(json.dumps(rows,indent=2)+'\n')
    print('Measured',len(rows),'page sections')
    if not rows:
        raise AssertionError("No Settings page sections measured")
    for row in rows:
        if row.get('clipped'):
            raise AssertionError(f"Page {row['index']} ({row['key']}) clipped labels: {row['clipped']}")
        for tab in row.get('tabs', []):
            if tab.get('name') in ('settingsSectionTabTrack', 'settingsTaskRail'):
                rx, _, rw, _ = tab['rect']
                px, _, pw, _ = tab['parent']
                if pw > 0 and rw > 0:
                    diff = abs((rx + rw / 2.0) - (px + pw / 2.0))
                    if diff > 2.0:
                        raise AssertionError(
                            f"Page {row['index']} ({row['key']}) {tab['name']} not centered (diff={diff:.2f}px): {tab}"
                        )
        if row['index'] == 33:
            cards = {card['name']: card['rect'] for card in row['cards']}
            previous = cards['Notifications']
            following = cards['Corner Hover Triggers']
            gap = following[1] - previous[1] - previous[3]
            if not (0 <= gap <= 24) or row['clipped']:
                raise AssertionError(f"Notifications spacing {gap}, clipped labels {row['clipped']}")
        if row['index'] == 37 and not row['cards']:
            raise AssertionError("Optional Companion Settings did not load")
    if result.returncode or 'FORM_CATALOG_PASS' not in result.stdout or 'FORM_CATALOG_FAIL' in result.stdout: raise SystemExit(1)

if __name__=='__main__':main()
