#!/usr/bin/env python3
"""Audit only the independent repository's tracked public source."""
import pathlib,re,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[1]
if not (root/".git").exists() or pathlib.Path(subprocess.check_output(["git","rev-parse","--show-toplevel"],cwd=root,text=True).strip()).resolve()!=root:
    sys.exit("Independent Git root required; refusing to audit parent repository")
allowed_roots={"Sources","Tests","scripts","docs",".github"}
allowed_files={".gitignore","Package.swift","Package.resolved","AGENTS.md","README.md","LICENSE","SECURITY.md","CHANGELOG.md"}
paths=list(filter(None,subprocess.check_output(["git","ls-files","-z"],cwd=root).decode().split("\0")))
issues=[]
for name in paths:
    p=pathlib.PurePosixPath(name)
    if not ((len(p.parts)==1 and name in allowed_files) or p.parts[0] in allowed_roots): issues.append("Unexpected tracked path: "+name)
    if any(x in p.parts for x in ("history-session","private-evidence",".codex",".env")): issues.append("Private path: "+name)
    if p.suffix.lower() not in {"",".swift",".md",".py",".sh",".yml",".yaml",".json"}: issues.append("Unreviewed file type: "+name)
    text=(root/name).read_text(errors="replace")
    for rule in (r"sk-(?:proj-)?[A-Za-z0-9_-]{24,}",r"gh[pousr]_[A-Za-z0-9]{30,}",r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",r"/Users/[A-Za-z0-9._-]+/(?:my-project|\.codex)"):
        if re.search(rule,text): issues.append("Sensitive content pattern: "+name)
if not paths: issues.append("No tracked files")
if issues: sys.exit("\n".join(issues))
print("PUBLIC_AUDIT_PASS:",len(paths),"tracked text files; no private logs/binaries/parent history")
