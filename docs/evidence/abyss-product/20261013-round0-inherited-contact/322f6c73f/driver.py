from pathlib import Path
import json,subprocess,os
p=Path(__file__).with_name("receipt.json");m=json.loads(p.read_text());assert subprocess.check_output(["git","rev-parse","HEAD"],cwd=m["clone"],text=True).strip()==m["sha"]
env=os.environ.copy();env["ALIS_ZERO_CAPTURE_DIR"]=str(p.parent/"editor")
m["status"]="RUNNING";p.write_text(json.dumps(m,indent=2)+"\n")
for i,command in enumerate(m["commands"]):
 log=p.parent/(str(i)+".log")
 with log.open("w") as out:q=subprocess.run(command,cwd=m["clone"],env=env,stdout=out,stderr=subprocess.STDOUT)
 m["results"].append({"command":command,"exit":q.returncode,"log":str(log)});p.write_text(json.dumps(m,indent=2)+"\n")
 print(i,q.returncode,log,flush=True)
 if q.returncode: m["status"]="FAIL";p.write_text(json.dumps(m,indent=2)+"\n");raise SystemExit(1)
m["status"]="FOCUSED_PASS_NOT_FULL_CANONICAL";p.write_text(json.dumps(m,indent=2)+"\n")
