"""Reader vs hand counts (Tools/suika/truth.json) on Tests/frames. Usage: python3 -I eval.py"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reader
here = os.path.dirname(os.path.abspath(__file__))
truth = json.load(open(os.path.join(here, 'truth.json')))
tot = 0
for name, want in truth.items():
    f = reader.read(reader.load(os.path.join(here, '../../Tests/frames', name)))
    f = [x for x in f if x[2] > 965]   # not the fruit Will holds
    got = [sum(1 for x in f if x[0] == t) for t in range(11)]
    err = sum(abs(a - b) for a, b in zip(got, want)); tot += err
    print(f'{name:18} err {err:2}  got {got}\n{"":18}         want {want}')
print('TOTAL', tot)
