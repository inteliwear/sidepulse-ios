"""App Store layouts with benefit-led headlines and a magnified hardware detail."""
from pathlib import Path
import base64,json
O=Path(__file__).resolve().parents[1]
def asset(name):return base64.b64encode((O/'renders'/name).read_bytes()).decode()
positions=json.loads((O/'source/dot-projection.json').read_text())
copy=[(1,'01-shortcuts',['Make your','Shortcuts glow.'],['A tiny USB-C light for','your automations.']),(2,'02-computer-status',['Big updates.','Tiny light.'],['Send computer updates','straight to your iPhone.'])]
copy.append((1,'03-shortcuts',['Make your','Shortcuts glow.'],['A tiny USB-C light for','your automations.']))
for index,name,lines,sub in copy:
 x,y=positions[str(index)]
 heading = f'<text x="96" y="252">{lines[0]}</text><text x="96" y="384">{lines[1]}</text>'
 subtitle = f'<g font-family="Avenir Next" font-size="52" font-weight="500" fill="#484b4e"><text x="100" y="484">{sub[0]}</text><text x="100" y="550">{sub[1]}</text></g>'
 if name == '01-shortcuts':
  heading = '<text x="96" y="252">Let your agent</text><text x="96" y="384">talk to you</text><text x="96" y="516">with light.</text>'
  subtitle = f'''<path d="M794 2116 Q760 2395 466 2389" fill="none" stroke="#8cadff" stroke-width="12" stroke-opacity=".2"/>
  <path d="M794 2116 Q760 2395 466 2389" fill="none" stroke="#e7efff" stroke-width="3" stroke-opacity=".9" stroke-dasharray="4 17" stroke-linecap="round"/>
  <image x="714" y="1620" width="576" height="576" href="data:image/png;base64,{asset("agent-wand.png")}"/>'''
 svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="1320" height="2868" viewBox="0 0 1320 2868">
 <defs><clipPath id="zoom"><circle cx="1040" cy="2520" r="230"/></clipPath></defs>
 <image width="1320" height="2868" href="data:image/png;base64,{asset(f'{name}-main.png')}"/>
 <g font-family="Avenir Next" font-weight="600" font-size="112" fill="#202123" letter-spacing="-2">
 {heading}
 </g>
 {subtitle}
 <path d="M{x+35} {y+40} Q{x+120} 2630 825 2600" fill="none" stroke="#777b80" stroke-opacity=".6" stroke-width="2"/>
 <image x="590" y="2070" width="900" height="900" href="data:image/png;base64,{asset(f'{name}-detail.png')}" clip-path="url(#zoom)"/>
 <circle cx="1040" cy="2520" r="230" fill="none" stroke="#ffffff" stroke-opacity=".92" stroke-width="6"/>
 <text x="1040" y="2815" text-anchor="middle" font-family="Avenir Next" font-size="30" font-weight="600" fill="#44464a">SidePulse Dot</text>
 </svg>'''
 (O/f'{name}.svg').write_text(svg)
