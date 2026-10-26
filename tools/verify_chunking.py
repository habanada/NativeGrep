from random import Random


def scan(data, pattern, block):
    offset, stored, out = 0, b'', []
    while True:
        current = stored + data[offset + len(stored):offset + len(stored) + block]
        got = len(current) - len(stored)
        final = got == 0
        if not current:
            break
        lim = len(current) if final else max(0, len(current) - len(pattern) + 1)
        pos = 0
        while pos < lim:
            idx = current.find(pattern, pos)
            if idx < 0 or idx >= lim:
                break
            out.append(offset + idx)
            pos = idx + 1
        stored = current[lim:]
        offset += lim
        if final:
            break
    return out


def validate():
    rng = Random(991241)
    tested = 0
    for _ in range(24000):
        n = rng.randrange(0, 500)
        m = rng.randrange(1, 130)
        b = rng.randrange(1, 90)
        data = bytes(rng.randrange(0, 4) for _ in range(n))
        pattern = bytes(rng.randrange(0, 4) for _ in range(m))
        expected = [x for x in range(max(0, len(data) - len(pattern) + 1)) if data[x:x + len(pattern)] == pattern]
        actual = scan(data, pattern, b)
        if actual != expected:
            raise AssertionError((n, m, b, expected, actual))
        tested += 1
    return tested


if __name__ == '__main__':
    print(f'chunk-model randomized cases: {validate()} PASS')
