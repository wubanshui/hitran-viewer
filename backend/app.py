# -*- coding: utf-8 -*-
"""
app.py — hitran-viewer 后端 REST 服务。
启动：python backend/app.py  （默认 http://127.0.0.1:5000）
"""

import traceback

from flask import Flask, jsonify, request
from flask_cors import CORS

import hapi_engine as eng

app = Flask(__name__)
CORS(app)


def err(msg, code=400):
    return jsonify({'status': 'error', 'message': str(msg)}), code


# ---------------------------------------------------------------- 基础

@app.route('/api/health')
def health():
    s = eng.load_settings()
    return jsonify({
        'status': 'ok',
        'service': 'hitran-viewer backend',
        'hapi_version': getattr(eng.hapi, 'HAPI_VERSION', 'unknown'),
        'api_key_set': bool(s.get('api_key', '').strip()),
        'data_dir': eng.data_dir(),
    })


@app.route('/api/settings', methods=['GET', 'POST'])
def settings():
    if request.method == 'GET':
        s = eng.load_settings()
        s = dict(s)
        if s.get('api_key'):
            s['api_key'] = s['api_key'][:4] + '****'
        return jsonify({'status': 'ok', 'settings': s})
    data = request.get_json(force=True, silent=True) or {}
    s = eng.load_settings()
    for k in ('api_key', 'db_dir', 'host', 'port'):
        if k in data:
            s[k] = data[k]
    eng.save_settings(s)
    return jsonify({'status': 'ok'})


# ---------------------------------------------------------------- 元数据

@app.route('/api/molecules')
def molecules():
    return jsonify({'status': 'ok', 'molecules': eng.list_molecules()})


@app.route('/api/isotopologues/<int:M>')
def isotopologues(M):
    try:
        return jsonify({'status': 'ok',
                        'isotopologues': eng.list_isotopologues(M)})
    except Exception as e:
        return err(e)


# ---------------------------------------------------------------- 数据

@app.route('/api/tables')
def tables():
    try:
        return jsonify({'status': 'ok', 'tables': eng.list_tables()})
    except Exception as e:
        return err(e)


@app.route('/api/fetch', methods=['POST'])
def fetch():
    d = request.get_json(force=True, silent=True) or {}
    try:
        n = eng.fetch_table(d['table'], int(d['M']), int(d['I']),
                            float(d['numin']), float(d['numax']))
        return jsonify({'status': 'ok', 'rows': n, 'table': d['table']})
    except KeyError as e:
        return err('缺少参数: %s' % e)
    except Exception as e:
        return err(e, 500)


@app.route('/api/import', methods=['POST'])
def import_par():
    d = request.get_json(force=True, silent=True) or {}
    try:
        n = eng.import_par(d['path'], d['table'])
        return jsonify({'status': 'ok', 'rows': n, 'table': d['table']})
    except KeyError as e:
        return err('缺少参数: %s' % e)
    except Exception as e:
        return err(e, 500)


@app.route('/api/lines/<table>')
def lines(table):
    try:
        numin = request.args.get('numin', type=float)
        numax = request.args.get('numax', type=float)
        limit = request.args.get('limit', default=5000, type=int)
        return jsonify({'status': 'ok',
                        'lines': eng.get_lines(table, numin, numax, limit)})
    except Exception as e:
        return err(e)


# ---------------------------------------------------------------- 计算

@app.route('/api/spectrum', methods=['POST'])
def spectrum():
    d = request.get_json(force=True, silent=True) or {}
    try:
        result = eng.compute_spectrum(d)
        result['status'] = 'ok'
        return jsonify(result)
    except Exception as e:
        traceback.print_exc()
        return err(e, 500)


@app.errorhandler(404)
def not_found(_):
    return err('接口不存在', 404)


if __name__ == '__main__':
    s = eng.load_settings()
    host = s.get('host', '127.0.0.1')
    port = int(s.get('port', 5000))
    print('hitran-viewer backend: http://%s:%d' % (host, port))
    app.run(host=host, port=port, debug=False)
