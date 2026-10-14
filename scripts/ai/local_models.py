#!/usr/bin/env python3
"""Finite GGUF/checkpoint inventory. Never download or load a model while scanning."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct

def roots(extra_root=''):
    override=os.environ.get('ALIS_GGUF_ROOTS')
    if override is not None:
        standard=[Path(p).expanduser() for p in json.loads(override)[:8]]
    else:
        home=Path.home()
        # Match Hub's modern cache precedence; retain the older alias as fallback.
        cache=Path(os.environ.get('XDG_CACHE_HOME',str(home/'.cache'))).expanduser()
        hf_home=Path(os.environ.get('HF_HOME',str(cache/'huggingface'))).expanduser()
        hub=Path(os.environ.get('HF_HUB_CACHE',os.environ.get('HUGGINGFACE_HUB_CACHE',str(hf_home/'hub')))).expanduser()
        standard=[hub,home/'.unsloth/studio/exports',home/'.unsloth/studio/library',home/'Models',
            home/'.local/share/alis/models',home/'Downloads']
    if not extra_root:return standard
    if not isinstance(extra_root,str) or len(extra_root)>4096:raise ValueError('Invalid model folder')
    custom=Path(extra_root).expanduser()
    if not custom.is_absolute():raise ValueError('Model folder must be an absolute path')
    return [custom]+[p for p in standard if p!=custom]

def runtime():
    candidates=[shutil.which('llama-server'),str(Path.home()/'.unsloth/llama.cpp/llama-server'),
        str(Path.home()/'.unsloth/llama.cpp/build/bin/llama-server')]
    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate,os.X_OK):return str(Path(candidate).resolve())
    return ''

def thinking_capable(name):
    value=str(name).casefold()
    return bool(re.search(r'(^|[^a-z0-9])qwen3(?:[.\\-_]|$)',value)) or 'gpt-oss' in value or 'deepseek-r1' in value

def valid_file(path):
    try:
        if path.stat().st_size<20*1024*1024:return False
        with path.open('rb') as f:header=f.read(24)
        magic,version,tensors,metadata=struct.unpack('<4sIQQ',header)
        return magic==b'GGUF' and version in (2,3) and 0<tensors<1000000 and 0<metadata<1000000
    except (OSError,ValueError,struct.error):return False

def unique_header(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ValueError('Duplicate checkpoint header key')
        result[key]=value
    return result

def checkpoint_file(path,budget):
    """Recognize bounded Safetensors metadata, never tensor payloads.

    Format: https://github.com/safetensors/safetensors#format
    This is a discovery hint, not model/shard or inference qualification.
    Return (recognized, bytes read) so the inventory has a total byte budget.
    """
    consumed=0
    if budget<8:return False,consumed
    try:
        size=path.stat().st_size
        with path.open('rb') as handle:
            prefix=handle.read(min(8,budget));consumed=len(prefix)
            length=struct.unpack('<Q',prefix)[0]
            if length<2 or length>262144 or length>budget-8 or length>size-8:return False,consumed
            header=handle.read(length);consumed+=len(header)
        if len(header)!=length or not header.startswith(b'{'):return False,consumed
        fields=json.loads(header,object_pairs_hook=unique_header)
        if not isinstance(fields,dict) or len(fields)>4096:return False,consumed
        tensors=0
        for name,value in fields.items():
            if name=='__metadata__':
                if not isinstance(value,dict) or any(not isinstance(v,str) for v in value.values()):return False,consumed
                continue
            if not isinstance(value,dict) or set(value)!=set(('dtype','shape','data_offsets')):return False,consumed
            dtype=value['dtype'];shape=value['shape'];offsets=value['data_offsets']
            if not isinstance(dtype,str) or not re.fullmatch(r'[A-Z0-9_]{1,32}',dtype):return False,consumed
            if not isinstance(shape,list) or len(shape)>16 or any(type(n) is not int or n<0 for n in shape):return False,consumed
            if not isinstance(offsets,list) or len(offsets)!=2 or any(type(n) is not int for n in offsets):return False,consumed
            if not 0<=offsets[0]<=offsets[1]<=size-8-length:return False,consumed
            tensors+=1
        return tensors>0,consumed
    except (OSError,ValueError,TypeError,struct.error,UnicodeError):return False,consumed

def checkpoint_name(directory):
    for parent in [directory]+list(directory.parents)[:3]:
        if parent.name.startswith('models--'):
            return parent.name.removeprefix('models--').replace('--','/')[:160]
    return directory.name[:160]

def inventory(search_roots=None):
    entries=[];seen=set();visited=0;checkpoints=[];checkpoint_seen=set();header_budget=2*1024*1024
    for root in search_roots if search_roots is not None else roots():
        root=Path(root).expanduser()
        if not root.is_dir():continue
        for directory,dirs,files in os.walk(root,followlinks=False):
            visited+=len(dirs)+len(files)
            if visited>12000:break
            depth=len(Path(directory).relative_to(root).parts)
            dirs[:]=sorted(d for d in dirs if depth<6 and d not in ('blobs','.git','node_modules','.venv','build','target','.locks'))
            checkpoint_directory=False
            for name in sorted(files):
                if name.lower().endswith('.safetensors') and not checkpoint_directory and len(checkpoints)<8 and header_budget>=8:
                    link=Path(directory)/name
                    recognized,consumed=checkpoint_file(link,header_budget);header_budget-=consumed
                    if recognized:
                        identity=str(link.resolve())
                        checkpoint_directory=True
                        if identity not in checkpoint_seen:
                            checkpoint_seen.add(identity)
                            checkpoints.append({'id':'checkpoint:'+hashlib.sha256(identity.encode()).hexdigest()[:20],
                                'name':checkpoint_name(link.parent),'format':'safetensors','runnable':False})
                    continue
                if not name.lower().endswith('.gguf') or name.lower().startswith(('mmproj','ggml-vocab')):continue
                link=Path(directory)/name
                if not valid_file(link):continue
                path=link.resolve();identity=str(path)
                if identity in seen:continue
                seen.add(identity)
                projector=next((p for p in sorted(link.parent.glob('mmproj*.gguf')) if valid_file(p)),None)
                quant=re.search(r'(UD-)?(?:IQ|Q|F|BF)\d[\w_]*$',link.stem,re.I)
                entries.append({'id':'gguf:'+hashlib.sha256(identity.encode()).hexdigest()[:20],
                    'name':link.stem[:160],'path':str(link.absolute()),'size':path.stat().st_size,
                    'quantization':quant[0] if quant else '',
                    'projector':str(projector.absolute()) if projector else '',
                    'thinking':thinking_capable(link.stem),
                    'source':'Unsloth' if 'unsloth' in str(link).lower() else 'GGUF'})
                if len(entries)>=32:break
            if len(entries)>=32:break
        if visited>12000 or len(entries)>=32:break
    return {'models':entries,'checkpoints':checkpoints,'runtimePath':runtime(),'scanned':visited}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extra-root',default='',help='additional user-selected model folder; default roots remain')
    args=parser.parse_args()
    try:
        folders=roots(args.extra_root)
        found=inventory(folders)
        if args.extra_root and not folders[0].is_dir():found['error']='Model folder not found'
        print(json.dumps(found,separators=(',',':')))
    except (OSError,ValueError,TypeError):print(json.dumps({'models':[],'runtimePath':'','error':'Model inventory unavailable'}))
