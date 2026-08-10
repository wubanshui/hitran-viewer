classdef hapi_client < handle
    % HAPI_CLIENT  hitran-viewer 后端 HTTP 客户端
    %   封装与 Flask 后端的所有 JSON 通信，MATLAB 端不直接调用 Python，
    %   规避 pyrunfile/Engine 的类型转换与调试困难。
    %
    %   用法：
    %     c = hapi_client('http://127.0.0.1:5000');
    %     c.health()
    %     c.fetch('CH4_1653', 6, 1, 6040, 6060)
    %     s = c.spectrum(spec)

    properties
        BaseURL = 'http://127.0.0.1:5000'
        Timeout = 300        % 秒（fetch/计算可能较慢）
    end

    methods
        function obj = hapi_client(baseURL)
            if nargin > 0
                obj.BaseURL = baseURL;
            end
        end

        % ---------------- 基础 ----------------
        function r = health(obj)
            r = obj.get('/api/health');
        end

        function r = molecules(obj)
            r = obj.get('/api/molecules');
        end

        function r = isotopologues(obj, M)
            r = obj.get(sprintf('/api/isotopologues/%d', M));
        end

        function r = tables(obj)
            r = obj.get('/api/tables');
        end

        % ---------------- 数据 ----------------
        function r = fetch(obj, tableName, M, I, numin, numax)
            body = struct('table', tableName, 'M', M, 'I', I, ...
                          'numin', numin, 'numax', numax);
            r = obj.post('/api/fetch', body);
        end

        function r = importPar(obj, filePath, tableName)
            body = struct('path', filePath, 'table', tableName);
            r = obj.post('/api/import', body);
        end

        function r = lines(obj, tableName, numin, numax, limit)
            if nargin < 5, limit = 5000; end
            url = sprintf('/api/lines/%s?limit=%d', tableName, limit);
            if nargin >= 3 && ~isempty(numin)
                url = [url sprintf('&numin=%.6f', numin)];
            end
            if nargin >= 4 && ~isempty(numax)
                url = [url sprintf('&numax=%.6f', numax)];
            end
            r = obj.get(url);
        end

        function r = setApiKey(obj, key)
            r = obj.post('/api/settings', struct('api_key', key));
        end

        % ---------------- 计算 ----------------
        function r = spectrum(obj, spec)
            % spec 为 struct，字段见后端 /api/spectrum 文档
            r = obj.post('/api/spectrum', spec);
        end
    end

    methods (Access = private)
        function r = get(obj, path)
            opts = weboptions('Timeout', obj.Timeout);
            try
                r = webread([obj.BaseURL path], opts);
            catch e
                error('hapi_client:http', 'GET %s 失败：%s', path, errMsg(e));
            end
            checkStatus(r);
        end

        function r = post(obj, path, body)
            opts = weboptions('MediaType', 'application/json', ...
                              'RequestMethod', 'post', ...
                              'Timeout', obj.Timeout);
            try
                r = webwrite([obj.BaseURL path], jsonencode(body), opts);
            catch e
                error('hapi_client:http', 'POST %s 失败：%s', path, errMsg(e));
            end
            checkStatus(r);
        end
    end
end

function checkStatus(r)
    if isstruct(r) && isfield(r, 'status') && strcmp(r.status, 'error')
        msg = '未知错误';
        if isfield(r, 'message'), msg = r.message; end
        error('hapi_client:server', '%s', msg);
    end
end

function m = errMsg(e)
    m = e.message;
    if ~isempty(e.cause)
        m = [m ' | ' e.cause{1}.message]; %#ok<AGROW>
    end
end
