"""Build the three-image contact sheet from final PNG exports."""
from pathlib import Path
import base64,struct
p=Path(__file__).resolve().parents[1]
s='<svg xmlns="http://www.w3.org/2000/svg" width="2028" height="1434"><rect width="2028" height="1434" fill="#f1f1ef"/>'
for i,n in enumerate(['01-shortcuts','02-computer-status','03-shortcuts']):
 b=(p/f'{n}.png').read_bytes()
 assert struct.unpack('>IIBB',b[16:26])==(1320,2868,8,2)
 s+=f'<image x="{i*684}" y="0" width="660" height="1434" href="data:image/png;base64,{base64.b64encode(b).decode()}"/>'
(p/'preview.svg').write_text(s+'</svg>')
