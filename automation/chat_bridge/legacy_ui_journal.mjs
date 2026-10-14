/* Durable single-attempt journal for a separately approved harmless UI test.
 * Not used by the manager/Scheduler or ordinary task queue.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
const UUID=/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

export function persistHarmlessUiAttempt(record,{
  stateHome=process.env.XDG_STATE_HOME ??
    path.join(os.homedir(),".local","state")
}={}){
  if(!UUID.test(record?.id)||
     record.kind!=="harmless-ui-acceptance"||
     record.outcome!=="indeterminate-once-attempted")
    throw Error("INVALID_ACCEPTANCE_JOURNAL_RECORD");
  const dir=path.join(stateHome,"hadalis-automation",
    "legacy-ui-acceptance-attempts");
  fs.mkdirSync(dir,{recursive:true,mode:0o700});
  const st=fs.lstatSync(dir);
  if(!st.isDirectory()||st.isSymbolicLink()||(st.mode&0o077)!==0)
    throw Error("ACCEPTANCE_JOURNAL_NOT_PRIVATE");
  const file=path.join(dir,record.id+".json");
  let fd;
  try{
    // wx refuses duplicate attempt IDs. This must be durable BEFORE any
    // composer write, regardless of a later click, timeout or process exit.
    fd=fs.openSync(file,"wx",0o600);
    fs.writeFileSync(fd,JSON.stringify({
      id:record.id,kind:record.kind,outcome:record.outcome
    })+"\n");
    fs.fsyncSync(fd);
  } finally {
    if(fd!==undefined)fs.closeSync(fd);
  }
  const directory=fs.openSync(dir,"r");
  try{fs.fsyncSync(directory);}
  finally{fs.closeSync(directory);}
  return {persisted:true};
}
