#!/usr/bin/env python3
"""
Extract the weights of models/deeptemp-k16-3.pb into models/deeptemp-k16-3.npz for tempocnn_np.py.

Reads the TensorFlow GraphDef straight from the protobuf wire format (no tensorflow / protobuf
package needed), then walks the graph to prove the layer structure tempocnn_np.py assumes:

  12 x [Conv (1 x k over time, SAME) + bias -> ReLU -> BatchNorm(eps)]  with a 2x2 max-pool
  after conv 1, 3, 5, 7, 9 and a 1x2 (time) max-pool after conv 11,
  then 1x1 conv to 256 + bias -> ReLU -> mean over (mels, time) -> softmax.

Any deviation raises, so a different model file can't be silently mis-ported.
Usage: python3 extract-tempocnn-weights.py models/deeptemp-k16-3.pb models/deeptemp-k16-3.npz
"""
import struct
import sys

import numpy as np

DT = {1: np.float32, 2: np.float64, 3: np.int32, 9: np.int64, 10: np.bool_}


def _varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1
        r |= (c & 0x7f) << s; s += 7
        if c < 0x80:
            return r, i


def _fields(b):
    i = 0
    while i < len(b):
        key, i = _varint(b, i)
        fn, wt = key >> 3, key & 7
        if wt == 0:
            v, i = _varint(b, i)
        elif wt == 1:
            v = b[i:i + 8]; i += 8
        elif wt == 2:
            n, i = _varint(b, i); v = b[i:i + n]; i += n
        elif wt == 5:
            v = b[i:i + 4]; i += 4
        else:
            raise ValueError(f"wire type {wt}")
        yield fn, wt, v


def _signed(x):
    return x - (1 << 64) if x >= (1 << 63) else x


def _shape(b):
    return [_signed(v2) for fn, _, v in _fields(b) if fn == 2 for f2, _, v2 in _fields(v) if f2 == 1]


def _tensor(b):
    dtype, dims, content, fvals, ivals = 1, [], None, [], []
    for fn, wt, v in _fields(b):
        if fn == 1:
            dtype = v
        elif fn == 2:
            dims = _shape(v)
        elif fn == 4:
            content = v
        elif fn == 5:
            fvals += list(struct.unpack('<%df' % (len(v) // 4), v)) if wt == 2 else [struct.unpack('<f', v)[0]]
        elif fn in (7, 10):
            if wt == 2:
                j = 0
                while j < len(v):
                    x, j = _varint(v, j); ivals.append(_signed(x))
            else:
                ivals.append(_signed(v))
    dt = DT[dtype]
    n = int(np.prod(dims)) if dims else 1
    if content is not None:
        a = np.frombuffer(content, dtype=dt).copy()
    else:
        vals = fvals if dt in (np.float32, np.float64) else ivals
        a = np.array(vals if vals else [0], dtype=dt)
        if a.size == 1 and n > 1:
            a = np.full(n, a[0], dtype=dt)
    return a.reshape(dims) if dims else a.reshape(())


def _attr(b):
    for fn, wt, v in _fields(b):
        if fn == 2: return v.decode()
        if fn == 3: return _signed(v)
        if fn == 4: return struct.unpack('<f', v)[0]
        if fn == 5: return bool(v)
        if fn == 6: return ('dtype', v)
        if fn == 7: return ('shape', _shape(v))
        if fn == 8: return _tensor(v)
        if fn == 1:
            out = []
            for f2, w2, v2 in _fields(v):
                if f2 == 2:
                    out.append(v2.decode())
                elif f2 == 3:
                    if w2 == 2:
                        j = 0
                        while j < len(v2):
                            x, j = _varint(v2, j); out.append(x)
                    else:
                        out.append(v2)
            return out
    return None


def read_graph(path):
    nodes = {}
    for fn, _, v in _fields(open(path, 'rb').read()):
        if fn != 1:
            continue
        nd = {'name': None, 'op': None, 'input': [], 'attr': {}}
        for f2, _, v2 in _fields(v):
            if f2 == 1: nd['name'] = v2.decode()
            elif f2 == 2: nd['op'] = v2.decode()
            elif f2 == 3: nd['input'].append(v2.decode())
            elif f2 == 5:
                k = val = None
                for f3, _, v3 in _fields(v2):
                    if f3 == 1: k = v3.decode()
                    elif f3 == 2: val = _attr(v3)
                nd['attr'][k] = val
        nodes[nd['name']] = nd
    return nodes


def main(pb, out):
    N = read_graph(pb)

    def src(name, op=None):
        """Follow Identity / Transpose / Split / Reshape pass-throughs back to the producing node."""
        n = N[name.split(':')[0]]
        while n['op'] in ('Identity', 'Transpose', 'Split', 'Reshape') and (op is None or n['op'] != op):
            data_in = n['input'][1] if n['op'] == 'Split' else n['input'][0]
            n = N[data_in.split(':')[0]]
        return n

    def const(name):
        n = src(name)
        assert n['op'] == 'Const', (name, n['op'])
        return n['attr']['value']

    W = {}
    expected_pool_after = {1: [1, 2, 2, 1], 3: [1, 2, 2, 1], 5: [1, 2, 2, 1], 7: [1, 2, 2, 1],
                           9: [1, 2, 2, 1], 11: [1, 1, 2, 1]}
    pools = {}
    for mp in (n for n in N.values() if n['op'] == 'MaxPool'):
        assert mp['attr']['padding'] == 'VALID' and mp['attr']['data_format'] == 'NHWC'
        assert list(mp['attr']['ksize']) == list(mp['attr']['strides'])
        bn = src(mp['input'][0])
        assert bn['op'] == 'AddV2' and bn['name'].startswith('BN'), bn['name']
        pools[int(bn['name'][2:].split('/')[0])] = list(mp['attr']['ksize'])
    assert pools == expected_pool_after, pools

    prev_out = 1
    for i in range(12):
        # BN{i}/add_1 = relu * mul + (beta - mean * mul),  mul = rsqrt(var + eps) * gamma
        add1 = N[f'BN{i}/add_1']
        mul1, sub = N[add1['input'][0]], N[add1['input'][1]]
        assert mul1['op'] == 'Mul' and sub['op'] == 'Sub'
        relu = src(mul1['input'][0])
        assert relu['op'] == 'Relu', relu
        bias_add = src(relu['input'][0])
        assert bias_add['op'] == 'Add', bias_add
        conv = src(bias_add['input'][0])
        assert conv['op'] == 'Conv2D' and conv['attr']['padding'] == 'SAME'
        assert list(conv['attr']['strides']) == [1, 1, 1, 1] and list(conv['attr']['dilations']) == [1, 1, 1, 1]
        kern = src(conv['input'][1].split(':')[0])
        assert kern['op'] == 'Const' and kern['name'].startswith(f'Conv{i}/kernel'), kern['name']
        k = kern['attr']['value']                                # ONNX OIHW: (out, in, 1, k)
        b = const(bias_add['input'][1])
        mul = N[f'BN{i}/mul']
        rsq = N[mul['input'][0]]
        assert rsq['op'] == 'Rsqrt'
        varadd = N[rsq['input'][0]]
        gamma = const(mul['input'][1])
        var = const(varadd['input'][0])
        eps = const(varadd['input'][1])
        mul2 = N[sub['input'][1]]
        assert mul2['op'] == 'Mul' and mul2['input'][1] == f'BN{i}/mul'
        beta = const(sub['input'][0])
        mean = const(mul2['input'][0])
        assert k.ndim == 4 and k.shape[2] == 1 and k.shape[1] == prev_out, (i, k.shape)
        C = k.shape[0]
        for a in (b, gamma, beta, mean, var):
            assert a.shape == (C,), (i, a.shape)
        W[f'conv{i}_w'] = k[:, :, 0, :].astype(np.float32)       # (out, in, k) over time
        W[f'conv{i}_b'] = b.astype(np.float32)
        W[f'bn{i}_gamma'], W[f'bn{i}_beta'] = gamma.astype(np.float32), beta.astype(np.float32)
        W[f'bn{i}_mean'], W[f'bn{i}_var'] = mean.astype(np.float32), var.astype(np.float32)
        W[f'bn{i}_eps'] = np.float32(eps)
        prev_out = C

    # head: 1x1 conv -> relu -> mean over spatial axes -> softmax
    sm = N['output']
    assert sm['op'] == 'Softmax'
    mean_node = src(sm['input'][0])
    assert mean_node['op'] == 'Mean' and mean_node['attr']['keep_dims'], mean_node
    relu = src(mean_node['input'][0])
    assert relu['op'] == 'Relu'
    bias_add = src(relu['input'][0])
    conv = src(bias_add['input'][0])
    assert conv['op'] == 'Conv2D'
    k = src(conv['input'][1].split(':')[0])['attr']['value']
    assert k.shape == (256, prev_out, 1, 1), k.shape
    W['head_w'] = k[:, :, 0, 0].astype(np.float32)               # (256, 128)
    W['head_b'] = const(bias_add['input'][1]).astype(np.float32)
    inp = N['input']
    assert inp['op'] == 'Placeholder' and inp['attr']['shape'][1] == [-1, 40, -1, 1]

    np.savez_compressed(out, **W)
    print(f"wrote {out}: {len(W)} arrays, {sum(v.size for v in W.values())} parameters")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
