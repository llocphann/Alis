#!/usr/bin/env node
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ctx=vm.createContext({});
vm.runInContext(readFileSync(new URL('../modules/sidebarRight/notepad/MarkdownNote.js',import.meta.url),'utf8'),ctx);
let count=0;
function eq(actual,expected,msg){assert.deepEqual(JSON.parse(JSON.stringify(actual)),expected,msg);count++;}
eq(ctx.format('hello',0,5,'bold'),{from:0,to:5,insert:'**hello**',selectionStart:2,selectionEnd:7});
eq(ctx.format('**hello**',2,7,'bold'),{from:0,to:9,insert:'hello',selectionStart:0,selectionEnd:5});
eq(ctx.format('**hello**',0,9,'bold'),{from:0,to:9,insert:'hello',selectionStart:0,selectionEnd:5});
eq(ctx.format('text',2,2,'italic'),{from:2,to:2,insert:'**',selectionStart:3,selectionEnd:3});
eq(ctx.format('abc',0,3,'link'),{from:0,to:3,insert:'[abc](https://)',selectionStart:6,selectionEnd:14});
eq(ctx.format('abc',1,1,'link'),{from:1,to:1,insert:'[](https://)',selectionStart:2,selectionEnd:2});
eq(ctx.format('abc',0,3,'unknown'),null);
assert.equal(ctx.safeReading('# Title\n**bold**\n![remote](https://bad.example/a.png)').includes('!['),false);count++;
assert.equal(ctx.safeReading('<img src="https://bad.example/x">').includes('<img'),false);count++;
const fence=String.fromCharCode(96).repeat(3);
assert.equal(ctx.safeReading(fence+'\n![literal](https://no.fetch)\n'+fence).includes('![literal]'),true);count++;
const dir='/tmp/test/notepad-attachments',hash='a'.repeat(64);
eq(ctx.attachmentUrls('![ok](file:///tmp/test/notepad-attachments/'+hash+'.png) ![not](file:///etc/passwd)',dir),['file:///tmp/test/notepad-attachments/'+hash+'.png']);
eq(ctx.attachmentUrls('![no](https://bad.example/image.png)',dir),[]);
console.log('QUICK_NOTES_MARKDOWN_POLICY_PASS',count,'cases');
