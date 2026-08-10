# -*- coding: utf-8 -*-
"""
hapi_engine.py — 对官方 HAPI（hitran-api）的封装层。

提供：数据获取（fetch / import .par）、谱线查询、吸收系数/透过率/吸收谱计算。
所有光谱计算直接调用 HAPI 的线型与配分函数实现，不做算法重写。
"""

import os
import json
import http.client
import urllib.request
import urllib.error

import numpy as np
import hapi

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SETTINGS_FILE = os.path.join(BASE_DIR, 'settings.json')
MOLECULES_FILE = os.path.join(BASE_DIR, 'molecules.json')

KB = 1.380649e-23          # J/K
ATM = 101325.0             # Pa
MAX_POINTS = 40000         # JSON 返回的最大网格点数

_db_ready = False


# ---------------------------------------------------------------- 配置管理

def load_settings():
    if os.path.exists(SETTINGS_FILE):
        with open(SETTINGS_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {"api_key": "", "db_dir": "../data", "host": "127.0.0.1", "port": 5000}


def save_settings(s):
    with open(SETTINGS_FILE, 'w', encoding='utf-8') as f:
        json.dump(s, f, indent=2, ensure_ascii=False)


def data_dir():
    s = load_settings()
    d = s.get('db_dir', '../data')
    if not os.path.isabs(d):
        d = os.path.normpath(os.path.join(BASE_DIR, d))
    os.makedirs(d, exist_ok=True)
    return d


def ensure_db():
    """确保 hapi 指向本地数据目录（每次请求前调用，hapi 全局状态要求）。"""
    global _db_ready
    hapi.db_begin(data_dir())
    _db_ready = True


def list_molecules():
    with open(MOLECULES_FILE, 'r', encoding='utf-8') as f:
        return json.load(f)


def _iso_field(meta, key):
    idx = hapi.ISO_INDEX[key]
    if isinstance(meta, dict):
        return meta.get(idx) if isinstance(idx, str) else meta.get(key)
    try:
        return meta[idx]
    except (IndexError, TypeError, KeyError):
        return None


def list_isotopologues(M):
    """从 hapi 内置元数据列出分子 M 的同位素。"""
    out = []
    for (m, i), meta in hapi.ISO.items():
        if m == M:
            out.append({
                "id": i,
                "iso_name": _iso_field(meta, 'iso_name') or '',
                "abundance": _iso_field(meta, 'abundance'),
            })
    out.sort(key=lambda x: x['id'])
    return out


# ---------------------------------------------------------------- 数据获取

def fetch_table(table_name, M, I, numin, numax):
    """
    从 HITRANonline 下载谱线数据并保存为 hapi 兼容的 .data/.header 表。
    复刻 hapi.queryHITRAN 的 URL 协议，附加 api_key 参数。
    """
    ensure_db()
    iso_id = _iso_field(hapi.ISO[(M, I)], 'id')
    host = hapi.GLOBAL_HOST
    url = ('%s/lbl/api?iso_ids_list=%d&numin=%s&numax=%s'
           % (host, iso_id, numin, numax))
    api_key = load_settings().get('api_key', '').strip()
    if api_key:
        url += '&api_key=' + api_key

    req = urllib.request.Request(url, headers={'User-Agent': 'hitran-viewer/1.0'})
    try:
        resp = urllib.request.urlopen(req, timeout=120)
    except urllib.error.HTTPError as e:
        if e.code == 403:
            raise RuntimeError('HITRAN 返回 403：API key 无效或超出每日请求限额')
        raise RuntimeError('HITRAN 请求失败 (HTTP %d)' % e.code)
    except urllib.error.URLError as e:
        raise RuntimeError('无法连接 %s：%s' % (host, e.reason))

    # 分块读取，容错处理服务器提前截断（IncompleteRead）的情况
    chunks = []
    while True:
        try:
            chunk = resp.read(64 * 1024)
        except http.client.IncompleteRead as e:
            chunks.append(e.partial)
            break
        if not chunk:
            break
        chunks.append(chunk)
    text = b''.join(chunks).decode('utf-8')
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if lines and not text.endswith('\n'):
        lines = lines[:-1]  # 丢弃可能被截断的末行
    if not lines:
        raise RuntimeError('HITRAN 返回空数据，请检查波段范围')

    data_path = os.path.join(data_dir(), table_name + '.data')
    with open(data_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')

    # 生成与 hapi 兼容的 header（默认 .par 160 列参数集）
    par_list = hapi.prepareParlist(pargroups=[], params=[], dotpar=True)
    header = hapi.prepareHeader(par_list)
    header['table_name'] = table_name
    iso_name = _iso_field(hapi.ISO[(M, I)], 'iso_name')
    header['comment'] = 'Contains lines for ' + iso_name
    with open(os.path.join(data_dir(), table_name + '.header'), 'w',
              encoding='utf-8') as f:
        json.dump(header, f, indent=2)

    # 让 hapi 重新加载表索引
    hapi.tableList()
    return len(lines)


def import_par(file_path, table_name):
    """导入 HITRAN 网站下载的 .par（或 .data）文件。"""
    ensure_db()
    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        lines = [ln for ln in f.read().splitlines() if ln.strip()]
    if not lines:
        raise RuntimeError('文件为空')

    with open(os.path.join(data_dir(), table_name + '.data'), 'w',
              encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')

    par_list = hapi.prepareParlist(pargroups=[], params=[], dotpar=True)
    header = hapi.prepareHeader(par_list)
    header['table_name'] = table_name
    header['comment'] = 'Imported from ' + os.path.basename(file_path)
    with open(os.path.join(data_dir(), table_name + '.header'), 'w',
              encoding='utf-8') as f:
        json.dump(header, f, indent=2)

    hapi.tableList()
    return len(lines)


# ---------------------------------------------------------------- 表与谱线

# HITRAN .par 定宽列切片（0 基）
_PAR_FIELDS = [
    ('molecule',     0,   2,  int),
    ('isotopologue', 2,   3,  int),
    ('nu',           3,  15,  float),
    ('sw',           15, 25,  float),
    ('a',            25, 35,  float),
    ('gamma_air',    35, 40,  float),
    ('gamma_self',   40, 45,  float),
    ('elower',       45, 55,  float),
    ('n_air',        55, 59,  float),
    ('delta_air',    59, 67,  float),
    ('global_upper', 67, 82,  str),
    ('global_lower', 82, 97,  str),
    ('local_upper',  97, 112, str),
    ('local_lower', 112, 127, str),
    ('gp',           139, 146, float),
    ('gpp',          146, 153, float),
]


def parse_par_file(path):
    cols = {name: [] for name, *_ in _PAR_FIELDS}
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for ln in f:
            if not ln.strip():
                continue
            for name, a, b, cast in _PAR_FIELDS:
                tok = ln[a:b].strip()
                try:
                    cols[name].append(cast(tok) if tok else None)
                except ValueError:
                    cols[name].append(None)
    return cols


def list_tables():
    ensure_db()
    out = []
    d = data_dir()
    for fn in sorted(os.listdir(d)):
        if not fn.endswith('.data'):
            continue
        name = fn[:-5]
        path = os.path.join(d, fn)
        info = {"name": name, "rows": 0, "nu_min": None, "nu_max": None}
        try:
            first_nu = last_nu = None
            n = 0
            with open(path, 'r', encoding='utf-8', errors='replace') as f:
                for ln in f:
                    if not ln.strip():
                        continue
                    n += 1
                    try:
                        nu = float(ln[3:15])
                    except ValueError:
                        continue
                    if first_nu is None:
                        first_nu = nu
                    last_nu = nu
            info.update(rows=n, nu_min=first_nu, nu_max=last_nu)
        except OSError:
            pass
        out.append(info)
    return out


def get_lines(table, numin=None, numax=None, limit=5000):
    """读取表中谱线参数（用于棒状图与悬停提示）。"""
    ensure_db()
    path = os.path.join(data_dir(), table + '.data')
    if not os.path.exists(path):
        raise RuntimeError('表 %s 不存在' % table)
    cols = parse_par_file(path)
    n = len(cols['nu'])
    mol_names = {m['id']: m for m in list_molecules()}
    lines = []
    for k in range(n):
        nu = cols['nu'][k]
        if nu is None:
            continue
        if numin is not None and nu < numin:
            continue
        if numax is not None and nu > numax:
            continue
        mol = cols['molecule'][k]
        m = mol_names.get(mol, {})
        lines.append({
            'nu': nu,
            'wl_nm': 1e7 / nu if nu else None,
            'sw': cols['sw'][k],
            'gamma_air': cols['gamma_air'][k],
            'elower': cols['elower'][k],
            'n_air': cols['n_air'][k],
            'delta_air': cols['delta_air'][k],
            'molecule': m.get('formula', str(mol)),
            'molecule_name': m.get('name', ''),
            'isotopologue': cols['isotopologue'][k],
            'global_upper': cols['global_upper'][k],
            'global_lower': cols['global_lower'][k],
            'local_upper': cols['local_upper'][k],
            'local_lower': cols['local_lower'][k],
        })
        if len(lines) >= limit:
            break
    return lines


# ---------------------------------------------------------------- 光谱计算

_LINE_SHAPE_FUNCS = {
    'voigt': 'absorptionCoefficient_Voigt',
    'lorentz': 'absorptionCoefficient_Lorentz',
    'gaussian': 'absorptionCoefficient_Doppler',
    'ht': 'absorptionCoefficient_HT',
}

_INSTRUMENTS = ('sinc', 'gaussian', 'rectangular', 'triangular')


def compute_spectrum(spec):
    """
    计算光谱。spec 字段：
      components: [{table, M, I, concentration}]  浓度=摩尔分数
      T(K), p(atm), l(cm)
      spectrum: 'abscoeff' | 'transmittance' | 'absorption'
      lineshape: voigt|lorentz|gaussian|ht
      numin, numax, step
      wing_hw: 线翼（半宽数，默认 50）
      instrument: 'none'|'sinc'|'gaussian'|..., resolution(cm-1)
      diluent: {'air':1.0} 默认
    """
    ensure_db()

    components = spec.get('components') or []
    if isinstance(components, dict):
        components = [components]   # 单组分时 JSON 为对象而非数组
    if not components:
        raise RuntimeError('未指定气体组分')

    T = float(spec.get('T', 296.0))
    p = float(spec.get('p', 1.0))
    path_len = float(spec.get('l', 100.0))
    numin = float(spec['numin'])
    numax = float(spec['numax'])
    step = float(spec.get('step', 0.01))
    wing_hw = float(spec.get('wing_hw', 50.0))
    lineshape = spec.get('lineshape', 'voigt').lower()
    diluent = spec.get('diluent') or {'air': 1.0}
    instrument = (spec.get('instrument') or 'none').lower()
    resolution = float(spec.get('resolution', 0.1))

    if lineshape not in _LINE_SHAPE_FUNCS:
        raise RuntimeError('不支持的线型: %s' % lineshape)
    func = getattr(hapi, _LINE_SHAPE_FUNCS[lineshape])

    if (numax - numin) / step > MAX_POINTS:
        step = (numax - numin) / MAX_POINTS

    n_total = p * ATM / (KB * T) / 1e6   # 总分子数密度 molecules/cm3

    k_total = None
    wavenum = None
    for comp in components:
        table = comp['table']
        M = int(comp['M'])
        I = int(comp['I'])
        x = float(comp.get('concentration', 1.0))
        if not os.path.exists(os.path.join(data_dir(), table + '.data')):
            raise RuntimeError('表 %s 不存在，请先获取数据' % table)

        kwargs = dict(
            Environment={'T': T, 'p': p},
            WavenumberRange=[numin, numax],
            WavenumberStep=step,
            WavenumberWingHW=wing_hw,
            HITRAN_units=True,           # 返回 cm2/molecule 截面
            Diluent=diluent,
        )
        if instrument in _INSTRUMENTS:
            kwargs['Instrument'] = instrument
            kwargs['Resolution'] = resolution

        try:
            nu, xsect = func(((M, I),), table, **kwargs)
        except Exception as e:
            raise RuntimeError('计算表 %s 失败: %s' % (table, e))

        nu = np.asarray(nu, dtype=float)
        xsect = np.asarray(xsect, dtype=float)
        k = xsect * (x * n_total)        # cm^-1
        if k_total is None:
            wavenum, k_total = nu, k
        else:
            m = min(len(k_total), len(k))
            k_total = k_total[:m] + k[:m]
            wavenum = wavenum[:m]

    spectrum_type = spec.get('spectrum', 'abscoeff')
    if spectrum_type == 'transmittance':
        y = np.exp(-k_total * path_len)
    elif spectrum_type == 'absorption':
        y = 1.0 - np.exp(-k_total * path_len)
    else:
        y = k_total

    # 大数组降采样，避免 JSON 过大
    n = len(wavenum)
    if n > MAX_POINTS // 2:
        f = int(np.ceil(n / (MAX_POINTS // 2)))
        wavenum, y = wavenum[::f], y[::f]

    return {
        'wavenumber': wavenum.tolist(),
        'values': y.tolist(),
        'y_unit': {'abscoeff': 'cm^-1',
                   'transmittance': '1',
                   'absorption': '1'}[spectrum_type],
        'n_points': len(wavenum),
    }
