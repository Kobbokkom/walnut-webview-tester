"""Render the agentic hero screenshot (first App Store image) for every locale."""
import html, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOCKS = os.path.dirname(HERE)
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
copy = json.load(open(os.path.join(HERE, "copy.json")))

TERMINAL = [
    ('<b>$</b> walnut-agent session', ''),
    ('<b>›</b> walnut_browser open localhost:8765', '<i>✓ 200</i>'),
    ('<b>›</b> page_interact fill "Email"', '<i>✓</i>'),
    ('<b>›</b> page_interact click "Pay $22.00"', '<i>✓</i>'),
    ('<b>›</b> console_list errors', ''),
    ('<u>✗ payment failed: 422 missing field: shipping_address</u>', ''),
    ('<b>›</b> network_list minStatus=400', ''),
    ('<u>✗ POST /api/checkout → 422</u>', ''),
]

SPEC = {
    "iphone": dict(W=1320, H=2868, ty=150, ts=84, sy=240, ss=46, maxw=1220,
                   term=(80, 320, 1160, 0, 30), dev=(195, 870, 930)),
    "ipad": dict(W=2064, H=2752, ty=160, ts=112, sy=260, ss=62, maxw=1900,
                 term=(232, 350, 1600, 0, 38), dev=(320, 1010, 1424)),
}


def page(loc, dev, p):
    t, s = copy[loc]
    lang = "ko" if loc == "ko" else "en"
    rtl = ' dir="rtl"' if loc in ("ar-SA", "he") else ""
    tx, ty, tw, th, fs = p["term"]
    dx, dy, dw = p["dev"]
    rows = "".join(f'<div class="ln"><span>{a}</span><span>{b}</span></div>' for a, b in TERMINAL)
    return f"""<!doctype html><meta charset="utf-8"><style>
html,body{{margin:0;width:{p['W']}px;height:{p['H']}px;overflow:hidden}}
body{{background:url(bg.png) center/cover no-repeat;font-family:-apple-system,"SF Pro Display","Helvetica Neue",sans-serif;position:relative}}
.t{{position:absolute;left:0;right:0;text-align:center;white-space:nowrap}}
#title{{top:{p['ty'] - p['ts'] * 0.82}px;font-size:{p['ts']}px;font-weight:700;color:#1a1a1a;letter-spacing:-.01em}}
#sub{{top:{p['sy'] - p['ss'] * 0.85}px;font-size:{p['ss']}px;color:#555}}
#term{{position:absolute;left:{tx}px;top:{ty}px;width:{tw}px;background:#0f141b;border-radius:{fs}px;
  box-shadow:0 40px 90px rgba(20,40,80,.35);overflow:hidden;font-family:Menlo,"SF Mono",monospace;font-size:{fs}px;z-index:2}}
#bar{{height:{fs * 2}px;display:flex;align-items:center;gap:{fs * .4}px;padding:0 {fs * .8}px;border-bottom:1px solid #222a35}}
#bar i{{width:{fs * .5}px;height:{fs * .5}px;border-radius:50%;display:block}}
#bar span{{margin-left:{fs * .5}px;color:#8b949e;font-size:{fs * .8}px}}
#body{{padding:{fs * .7}px {fs * .9}px}}
.ln{{display:flex;justify-content:space-between;color:#c9d1d9;line-height:1.55;white-space:nowrap}}
.ln b{{color:#58a6ff;font-weight:500}} .ln i{{color:#3fb950;font-style:normal}} .ln u{{color:#ff7b72;text-decoration:none;white-space:normal}}
#dev{{position:absolute;left:{dx}px;top:{dy}px;width:{dw}px;z-index:1;filter:drop-shadow(0 40px 60px rgba(20,40,80,.25))}}
</style><body>
<div id="title" class="t"{rtl}><span class="fit">{html.escape(t)}</span></div>
<div id="sub" class="t"{rtl}><span class="fit">{html.escape(s)}</span></div>
<div id="term"><div id="bar"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i><span>Terminal — walnut-agent</span></div><div id="body">{rows}</div></div>
<img id="dev" src="mock-{dev}-{lang}.png">
<script>for(const e of document.querySelectorAll('.fit')){{let f=parseFloat(getComputedStyle(e.parentNode).fontSize);while(e.getBoundingClientRect().width>{p['maxw']}&&f>20){{f-=2;e.parentNode.style.fontSize=f+'px'}}}}</script>
</body>"""


os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
for name in ("mock-iphone-en.png", "mock-iphone-ko.png", "mock-ipad-en.png", "mock-ipad-ko.png"):
    dst = os.path.join(HERE, name)
    if not os.path.exists(dst):
        os.symlink(os.path.join(MOCKS, name), dst)
only = sys.argv[1:]
for loc in copy:
    if only and loc not in only:
        continue
    for dev, p in SPEC.items():
        f = os.path.join(HERE, f"tmp-{loc}-{dev}.html")
        open(f, "w").write(page(loc, dev, p))
        out = os.path.join(HERE, "out", f"{loc}-{dev}-hero.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                        f"--window-size={p['W']},{p['H']}", "--virtual-time-budget=3000", f"--screenshot={out}",
                        "--allow-file-access-from-files", "file://" + f], capture_output=True)
        os.remove(f)
        subprocess.run(["magick", out, "-alpha", "off", "-define", "png:color-type=2", out])
    print(loc, end=" ", flush=True)
print()
