## TempoCNN eval, run `ft1`

Fine-tuned model: `deeptemp-k16-3-ft1.npz`. Scored by tempocnn_np.py (shipped numpy TempoCNN). Acc1 = within 4 %; Acc2 = also x2, x1/2, x3, x1/3.

| set | n | original Acc1 | fine-tuned Acc1 | original Acc2 | fine-tuned Acc2 |
|---|---:|---:|---:|---:|---:|
| (a) held-out test, all | 130 | 66.2% | 86.2% | 99.2% | 100.0% |
| (a) held-out test, beat | 65 | 61.5% | 83.1% | 98.5% | 100.0% |
| (a) held-out test, mix | 65 | 70.8% | 89.2% | 100.0% | 100.0% |
| (c) ALL rows, beat (train+test) | 243 | 62.1% | 87.7% | 97.1% | 98.8% |
| (c) ALL rows, mix (train+test) | 240 | 69.2% | 87.5% | 97.1% | 98.8% |
| (b) bpm-bench | 40 | 87.5% | 82.5% | 100.0% | 100.0% |

key-bench (40 clips): no tempo ground truth, accuracy skipped. Fine-tuned gives the same BPM as the original on 85% of clips, within 4 % on 98%.
