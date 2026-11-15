import json,subprocess,html,os,sys
copy=json.load(open("copy.json")); CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SPEC={"iphone":dict(W=1320,H=2868,ty=150,ts=84,sy=240,ss=48,img=(24,280,1272,2600),maxw=1220),
      "ipad":dict(W=2064,H=2752,ty=160,ts=112,sy=260,ss=64,img=(82,320,1900,2400),maxw=1900)}
only=sys.argv[1:]
os.makedirs("out",exist_ok=True)
for loc,(t,s) in copy.items():
    if only and loc not in only: continue
    lang="ko" if loc=="ko" else "en"
    rtl=' direction="rtl"' if loc in("ar-SA","he") else ""
    for dev,p in SPEC.items():
        x,y,w,h=p["img"]
        doc=f'''<!doctype html><meta charset="utf-8"><style>html,body{{margin:0;background:#fff}}</style>
<svg id="s" width="{p['W']}" height="{p['H']}" viewBox="0 0 {p['W']} {p['H']}" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0%" stop-color="#E8F4FD"/><stop offset="100%" stop-color="#D4E7F7"/></linearGradient></defs>
<rect width="{p['W']}" height="{p['H']}" fill="url(#g)"/>
<text class="fit" x="{p['W']//2}" y="{p['ty']}" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="{p['ts']}" font-weight="700" fill="#1a1a1a" text-anchor="middle"{rtl}>{html.escape(t)}</text>
<text class="fit" x="{p['W']//2}" y="{p['sy']}" font-family="-apple-system, SF Pro Text, Helvetica Neue, sans-serif" font-size="{p['ss']}" font-weight="400" fill="#555555" text-anchor="middle"{rtl}>{html.escape(s)}</text>
<image href="mock-{dev}-{lang}.png" x="{x}" y="{y}" width="{w}" height="{h}" preserveAspectRatio="xMidYMid meet"/>
</svg><script>for(const e of document.querySelectorAll('.fit')){{let f=parseFloat(e.getAttribute('font-size'));while(e.getComputedTextLength()>{p['maxw']}&&f>20){{f-=2;e.setAttribute('font-size',f)}}}}</script>'''
        fn=f"tmp-{loc}-{dev}.html"; open(fn,"w").write(doc)
        out=f"out/{loc}-{dev}.png"
        subprocess.run([CH,"--headless=new","--disable-gpu","--hide-scrollbars","--force-device-scale-factor=1",f"--window-size={p['W']},{p['H']}","--virtual-time-budget=3000",f"--screenshot={os.path.abspath(out)}","file://"+os.path.abspath(fn)],capture_output=True)
        os.remove(fn)
    print(loc,end=" ",flush=True)
