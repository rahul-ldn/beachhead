# Assembles landingham-prompt-install.sh: the installer's logic with every payload file embedded, so one file is the
# whole install on any machine. Run it after changing anything in payload/.
import os
files=['starship.toml','landingham-status','landingham-prompt-palette','landingham-prompt.fish','tmux.conf','prompt-palette.toml']
parts=[open('installer-head.sh',encoding='utf-8').read()]
for f in files:
    body=open('payload/'+f,encoding='utf-8').read()
    assert 'LANDINGHAM_PAYLOAD_END' not in body
    parts.append(f"payload_{f.replace('.','_').replace('-','_')}() {{\ncat <<'LANDINGHAM_PAYLOAD_END'\n{body}LANDINGHAM_PAYLOAD_END\n}}\n\n")
parts.append(open('installer-tail.sh',encoding='utf-8').read())
open('install.sh','w',encoding='utf-8').write(''.join(parts)); os.chmod('install.sh',0o755); print('built install.sh')
