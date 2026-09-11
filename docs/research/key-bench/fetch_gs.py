"""Download the 40-clip GiantSteps Key subset listed in ground_truth.json (md5-verified).
Sampling was: random.seed(42); 14 'major' + 26 'minor' from annotations/key (subset is committed, so it is stable).
curl on J's MBP cannot resolve www.cp.jku.at through the Tailscale resolver -> pin the A record (dig +short www.cp.jku.at)."""
import os, subprocess, hashlib, json
gt = json.load(open('ground_truth.json'))
os.makedirs('audio', exist_ok=True)
IP = subprocess.run(['dig', '+short', 'www.cp.jku.at'], capture_output=True, text=True).stdout.split()
IP = [x for x in IP if x[0].isdigit()][-1:] or ['140.78.124.154']
ok = 0
for b in sorted(gt):
    out = f'audio/{b}.mp3'
    md = open(f'giantsteps-key-dataset-master/md5/{b}.md5').read().split()[0]
    if not (os.path.exists(out) and hashlib.md5(open(out, 'rb').read()).hexdigest() == md):
        subprocess.run(['curl', '-sfL', '--max-time', '60', '--resolve', f'www.cp.jku.at:443:{IP[0]}', '-o', out,
                        f'https://www.cp.jku.at/datasets/giantsteps/backup/{b}.mp3'])
    got = hashlib.md5(open(out, 'rb').read()).hexdigest() if os.path.exists(out) else 'x'
    ok += got == md
    if got != md: print('MD5 MISMATCH', b)
print(ok, 'of', len(gt), 'clips verified')
