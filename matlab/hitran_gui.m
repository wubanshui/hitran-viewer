function app = hitran_gui()
% HITRAN_GUI  hitran-viewer MATLAB 主界面
%   依赖：后端服务已启动（默认 http://127.0.0.1:5000）
%   运行：在 MATLAB 中执行 hitran_gui
%
%   布局：顶栏为功能区（状态显示 + 连接设置入口），左侧依次为
%   数据、环境与计算参数、操作、导出区块；连接/API key 等低频
%   设置收进"连接设置"弹窗，按需打开。
%
%   功能：fetch HITRAN 数据、吸收系数/透过率/吸收谱计算与绘图、
%   多曲线叠加、谱线棒状图、鼠标悬停显示谱线信息、PNG/CSV 导出。

    fig = uifigure('Name', 'hitran-viewer — 气体吸收线可视化', ...
        'Position', [80 60 1280 780], 'Resize', 'on', ...
        'AutoResizeChildren', 'off');   % 组件像素位置恒定，避免缩放导致布局错位

    % ---------------- 应用状态 ----------------
    app = struct();
    app.fig        = fig;
    app.client     = hapi_client('http://127.0.0.1:5000');
    app.molecules  = [];
    app.tableMeta  = containers.Map();   % 表名 -> struct(M, I)
    app.curves     = {};                 % 已绘制曲线 cell of struct
    fig.UserData   = app;

    % ---------------- 顶栏功能区 ----------------
    bar = uipanel(fig, 'Position', [10 735 1260 38], 'BorderType', 'line', ...
        'BackgroundColor', [0.95 0.96 0.98]);
    uilabel(bar, 'Text', 'hitran-viewer', 'Position', [10 8 105 22], ...
        'FontWeight', 'bold', 'FontSize', 12);
    app.lblStatus = uilabel(bar, 'Text', '未连接', ...
        'Position', [120 8 1000 22], 'FontColor', [0.6 0.6 0.6]);
    app.btnConnSettings = uibutton(bar, 'Text', '设置', ...
        'Position', [1145 6 105 26], 'ButtonPushedFcn', @onConnSettings);

    % ---------------- 左侧面板 ----------------
    pnl = uipanel(fig, 'Position', [10 10 380 720], 'BorderType', 'none');

    % --- 数据区 ---
    grpData = uipanel(pnl, 'Title', '数据', 'Position', [0 485 380 235], ...
        'FontSize', 12, 'FontWeight', 'bold');
    uilabel(grpData, 'Text', '气体', 'Position', [10 178 34 22]);
    app.ddMol = uidropdown(grpData, 'Position', [50 178 150 22], ...
        'Items', {'加载中...'}, 'ItemsData', {0}, ...
        'Tooltip', '目标气体（HITRAN 分子编号 + 化学式 + 中文名）', ...
        'ValueChangedFcn', @onMolChanged);
    uilabel(grpData, 'Text', '同位素', 'Position', [208 178 46 22]);
    app.ddIso = uidropdown(grpData, 'Position', [258 178 112 22], ...
        'Items', {'1'}, 'ItemsData', {1}, ...
        'Tooltip', '同位素编号（1=最丰富同位素，如 CH4 主同位素）');

    uilabel(grpData, 'Text', '波数下限 cm-1', 'Position', [10 148 80 22]);
    app.edNuMin = uieditfield(grpData, 'numeric', 'Value', 6040, ...
        'Position', [95 148 65 22], ...
        'Tooltip', ['光谱范围下限波数 ν（cm⁻¹），正数；' ...
            '换算关系 λ(nm)=1e7/ν；示例：6040'], ...
        'ValueChangedFcn', @onRangeChanged);
    uilabel(grpData, 'Text', '上限', 'Position', [168 148 28 22]);
    app.edNuMax = uieditfield(grpData, 'numeric', 'Value', 6060, ...
        'Position', [200 148 65 22], ...
        'Tooltip', ['光谱范围上限波数 ν（cm⁻¹），需大于下限；' ...
            '示例：6060（对应 ~1653 nm）'], ...
        'ValueChangedFcn', @onRangeChanged);
    app.lblWl = uilabel(grpData, 'Text', '', 'Position', [272 148 98 22], ...
        'FontSize', 10, 'FontColor', [0.3 0.5 0.7]);

    uilabel(grpData, 'Text', '表名', 'Position', [10 118 34 22]);
    app.edTable = uieditfield(grpData, 'text', 'Value', 'CH4_1653', ...
        'Position', [50 118 140 22], ...
        'Tooltip', ['本地数据表名：字母/数字/下划线，不带扩展名；' ...
            '命名建议：气体_波段，如 CH4_1653']);
    app.btnFetch = uibutton(grpData, 'Text', 'Fetch 下载', ...
        'Position', [200 118 95 22], 'ButtonPushedFcn', @onFetch);
    app.btnImport = uibutton(grpData, 'Text', '导入 .par', ...
        'Position', [303 118 67 22], 'ButtonPushedFcn', @onImport);

    uilabel(grpData, 'Text', '本地表', 'Position', [10 88 46 22]);
    app.ddTables = uidropdown(grpData, 'Position', [60 88 240 22], ...
        'Items', {'(刷新)'}, 'ItemsData', {''});
    app.btnRefresh = uibutton(grpData, 'Text', '刷新', ...
        'Position', [308 88 62 22], 'ButtonPushedFcn', @onRefreshTables);

    app.lblTableInfo = uilabel(grpData, 'Text', '', ...
        'Position', [10 58 360 22], 'FontSize', 10, ...
        'FontColor', [0.3 0.5 0.7]);

    % --- 参数区 ---
    grpParam = uipanel(pnl, 'Title', '环境与计算参数', 'Position', [0 280 380 200], ...
        'FontSize', 12, 'FontWeight', 'bold');
    uilabel(grpParam, 'Text', '温度 K', 'Position', [10 142 45 22]);
    app.edT = uieditfield(grpParam, 'numeric', 'Value', 296, ...
        'Position', [60 142 60 22], ...
        'Tooltip', ['气体温度 T（K，开尔文），影响线强与多普勒展宽；' ...
            '室温≈296；格式：正数，示例 296']);
    uilabel(grpParam, 'Text', '压力 atm', 'Position', [135 142 55 22]);
    app.edP = uieditfield(grpParam, 'numeric', 'Value', 1, ...
        'Position', [195 142 60 22], ...
        'Tooltip', ['总压 p（atm，标准大气压），决定碰撞（洛伦兹）展宽；' ...
            '1 atm=101325 Pa；格式：正数']);
    uilabel(grpParam, 'Text', '光程 cm', 'Position', [270 142 45 22]);
    app.edL = uieditfield(grpParam, 'numeric', 'Value', 10, ...
        'Position', [315 142 55 22], ...
        'Tooltip', ['吸收光程 L（cm），仅透过率/吸收谱生效（T=exp(-k·L)）；' ...
            '光声/直接吸收池长度；格式：正数']);

    uilabel(grpParam, 'Text', '浓度(摩尔分数)', 'Position', [10 112 90 22]);
    app.edConc = uieditfield(grpParam, 'numeric', 'Value', 0.01, ...
        'Position', [105 112 75 22], ...
        'Tooltip', ['目标气体摩尔分数 x（0~1 无量纲），' ...
            '1%=0.01，1 ppm=1e-6；格式：0~1 小数']);
    uilabel(grpParam, 'Text', '线型', 'Position', [195 112 30 22]);
    app.ddShape = uidropdown(grpParam, 'Position', [230 112 140 22], ...
        'Items', {'Voigt', 'Lorentz', 'Gaussian(Doppler)', 'HT'}, ...
        'ItemsData', {'voigt', 'lorentz', 'gaussian', 'ht'}, ...
        'Tooltip', ['线型函数：Voigt=常用（碰撞+多普勒卷积）；' ...
            'HT=高速线型（含 Dicke 变窄等效应）'], ...
        'Value', 'voigt');

    uilabel(grpParam, 'Text', '网格步长 cm-1', 'Position', [10 82 85 22]);
    app.edStep = uieditfield(grpParam, 'numeric', 'Value', 0.002, ...
        'Position', [100 82 65 22], ...
        'Tooltip', ['波数网格步长 Δν（cm⁻¹），越小越精细但越慢；' ...
            '建议≤线宽一半；格式：正小数，示例 0.002']);
    uilabel(grpParam, 'Text', '仪器函数', 'Position', [180 82 60 22]);
    app.ddInstr = uidropdown(grpParam, 'Position', [245 82 125 22], ...
        'Items', {'none', 'sinc', 'gaussian', 'rectangular', 'triangular'}, ...
        'Tooltip', ['仪器函数卷积：none=不卷积（激光线宽远小于吸收线时）；' ...
            'sinc=FT 光谱仪，gaussian=常见激光/光栅仪器'], ...
        'Value', 'none', 'ValueChangedFcn', @onInstrChanged);
    app.lblRes = uilabel(grpParam, 'Text', '分辨率 cm-1', ...
        'Position', [180 52 60 22], 'Enable', 'off');
    app.edRes = uieditfield(grpParam, 'numeric', 'Value', 0.1, ...
        'Position', [245 52 65 22], 'Enable', 'off', ...
        'Tooltip', ['仪器分辨率（cm⁻¹），仅仪器函数≠none 时生效；' ...
            '格式：正数，示例 0.1']);

    uilabel(grpParam, 'Text', '光谱类型', 'Position', [10 22 60 22]);
    app.ddSpec = uidropdown(grpParam, 'Position', [75 22 130 22], ...
        'Items', {'吸收系数', '透过率', '吸收谱'}, ...
        'ItemsData', {'abscoeff', 'transmittance', 'absorption'}, ...
        'Tooltip', ['吸收系数 k(ν)（cm⁻¹）；透过率 T=exp(-kL)；' ...
            '吸收谱 A=1-T'], ...
        'Value', 'abscoeff');
    uilabel(grpParam, 'Text', '横轴', 'Position', [215 22 30 22]);
    app.ddXUnit = uidropdown(grpParam, 'Position', [250 22 120 22], ...
        'Items', {'cm-1', 'nm'}, 'Value', 'cm-1', ...
        'Tooltip', '横轴单位：波数 cm⁻¹ 或波长 nm（自动换算并反向坐标轴）');

    % --- 操作区 ---
    grpAct = uipanel(pnl, 'Title', '操作', 'Position', [0 185 380 90], ...
        'FontSize', 12, 'FontWeight', 'bold');
    app.btnCalc = uibutton(grpAct, 'Text', '计算并绘图', ...
        'Position', [10 30 115 26], 'ButtonPushedFcn', @onCalc, ...
        'BackgroundColor', [0.25 0.48 0.75], 'FontColor', [1 1 1]);
    app.btnClear = uibutton(grpAct, 'Text', '清空曲线', ...
        'Position', [135 30 100 26], 'ButtonPushedFcn', @onClear);
    app.btnSticks = uibutton(grpAct, 'Text', '显示谱线', ...
        'Position', [245 30 125 26], 'ButtonPushedFcn', @onSticks);

    % --- 导出区 ---
    grpExp = uipanel(pnl, 'Title', '导出', 'Position', [0 95 380 85], ...
        'FontSize', 12, 'FontWeight', 'bold');
    app.btnPNG = uibutton(grpExp, 'Text', '导出 PNG', ...
        'Position', [10 25 85 26], 'ButtonPushedFcn', @onExportPNG);
    app.btnCSV = uibutton(grpExp, 'Text', '导出 CSV', ...
        'Position', [105 25 85 26], 'ButtonPushedFcn', @onExportCSV);
    app.btnWS = uibutton(grpExp, 'Text', '导入工作区', ...
        'Position', [200 25 170 26], 'ButtonPushedFcn', @onExportWS, ...
        'Tooltip', '将全部已计算曲线以变量 hitran_curves 写入 MATLAB 基础工作区');

    % ---------------- 右侧绘图区（像素位置固定，两图严格左右对齐） ----------------
    app.axSpec = uiaxes(fig, 'Position', [410 300 740 460]);
    title(app.axSpec, '光谱'); grid(app.axSpec, 'on');
    app.axStick = uiaxes(fig, 'Position', [410 40 740 200]);
    title(app.axStick, '谱线棒状图');
    xlabel(app.axStick, '波数 cm^{-1}'); ylabel(app.axStick, '线强 S');

    % 曲线图例（右侧固定文本区，按绘图顺序对应默认色序；
    % 不用 axes legend：其会压缩绘图区导致两坐标区绘图框错位）
    app.legendLabel = uilabel(fig, 'Text', '', ...
        'Position', [1158 300 112 460], 'VerticalAlignment', 'top', ...
        'FontSize', 10, 'FontColor', [0.25 0.25 0.25]);

    % 悬停提示标签（初始隐藏）
    app.tip = uilabel(fig, 'Text', '', 'Position', [0 0 260 90], ...
        'BackgroundColor', [1 1 0.8], 'Visible', 'off', 'HandleVisibility', 'off');

    fig.UserData = app;
    hover_line_info(fig);        % 注册悬停回调

    % 初始化：连接自检 + 加载分子列表
    % （struct 为值传递，初始化函数需返回最新 app 快照）
    app = autoConnect(app);
    app = loadMolecules(app);
    app = updateWlHint(app);
end

% ================================================================
%  回调与辅助函数。状态一律通过 fig.UserData / 显式传参获取，
%  不使用 gcf（创建 uifigure 不会改变当前 figure，gcf 可能
%  指向其它 figure 导致 UserData 为空、点索引报错）。
% ================================================================

function app = getApp(src)
    f = ancestor(src, 'figure');
    app = f.UserData;
end

function setApp(app)
    app.fig.UserData = app;
end

function setStatus(app, txt, color)
    if nargin < 3, color = [0.1 0.5 0.1]; end
    app.lblStatus.Text = txt;
    app.lblStatus.FontColor = color;
    drawnow;
end

% ---------------- 连接设置（顶栏功能区，弹窗按需打开） ----------------
function onConnSettings(src, ~)
    app = getApp(src);
    openConnSettings(app);
end

function openConnSettings(app)
    dlg = uifigure('Name', '设置', 'Position', [480 380 480 230], ...
        'Resize', 'off', 'WindowStyle', 'modal');
    uilabel(dlg, 'Text', '后端地址', 'Position', [20 170 65 22]);
    edSrv = uieditfield(dlg, 'text', 'Value', app.client.BaseURL, ...
        'Position', [90 170 275 22], ...
        'Tooltip', 'Flask 后端服务地址，格式：http://IP:端口，默认 http://127.0.0.1:5000');
    uibutton(dlg, 'Text', '测试连接', 'Position', [375 170 85 22], ...
        'ButtonPushedFcn', @doTest);
    uilabel(dlg, 'Text', 'API key', 'Position', [20 130 65 22]);
    edKey = uieditfield(dlg, 'text', 'Position', [90 130 190 22], ...
        'Placeholder', '留空不修改', ...
        'Tooltip', 'HITRAN API key：免费注册 hitran.org 后在个人主页生成');
    uihyperlink(dlg, 'Text', 'hitran.org 获取 key', ...
        'URL', 'https://hitran.org/profile/', ...
        'Position', [285 130 125 22], ...
        'Tooltip', '打开 HITRAN 个人主页（注册登录后在 Profile 页生成 API key）');
    uibutton(dlg, 'Text', '保存 key', 'Position', [375 130 85 22], ...
        'ButtonPushedFcn', @doSaveKey);
    lblMsg = uilabel(dlg, 'Text', '', 'Position', [20 20 440 90], ...
        'VerticalAlignment', 'top', 'FontColor', [0.2 0.2 0.6]);

    function doTest(~, ~)
        app.client.BaseURL = edSrv.Value;
        try
            r = app.client.health();
            keyStr = '已配置';
            if ~r.api_key_set, keyStr = '未配置（fetch 可能受限）'; end
            msg = sprintf('连接成功：HAPI %s，API key %s', r.hapi_version, keyStr);
            setStatus(app, sprintf('已连接 | HAPI %s | API key: %s', ...
                r.hapi_version, keyStr));
        catch e
            msg = ['连接失败：' e.message];
            setStatus(app, msg, [0.8 0.1 0.1]);
        end
        lblMsg.Text = msg;
        setApp(app);
    end

    function doSaveKey(~, ~)
        if isempty(edKey.Value)
            lblMsg.Text = '未输入 API key';
            return;
        end
        try
            app.client.setApiKey(edKey.Value);
            lblMsg.Text = 'API key 已保存到后端配置';
            setStatus(app, 'API key 已保存');
        catch e
            lblMsg.Text = ['保存失败：' e.message];
            setStatus(app, e.message, [0.8 0.1 0.1]);
        end
        setApp(app);
    end
end

function app = autoConnect(app)
% 启动自检：连不上且疑似本机代理拦截时，自动关闭 MATLAB 内置代理后重试
    try
        r = app.client.health();
        keyStr = '已配置';
        if ~r.api_key_set, keyStr = '未配置'; end
        setStatus(app, sprintf('已连接 | HAPI %s | API key: %s', ...
            r.hapi_version, keyStr));
        setApp(app);
        return;
    catch e
        msg0 = e.message;
    end
    if contains(msg0, {'CURLE', 'proxy', '代理', 'socks'}, 'IgnoreCase', true)
        try
            s = settings; w = s.matlab.web;
            w.UseProxy.PersonalValue = false;   % 新 HTTP 栈不支持 SOCKS 代理
            r = app.client.health();
            keyStr = '已配置';
            if ~r.api_key_set, keyStr = '未配置'; end
            setStatus(app, sprintf(['已连接（已自动关闭 MATLAB 内置代理）' ...
                ' | HAPI %s | API key: %s'], r.hapi_version, keyStr));
            setApp(app);
            return;
        catch e2
            msg0 = e2.message;
        end
    end
    setStatus(app, ['后端未连接：' msg0 '（可点右上角"设置"检查）'], ...
        [0.8 0.1 0.1]);
    setApp(app);
end

function onInstrChanged(src, ~)
    % 分辨率仅在启用仪器函数卷积时才有意义
    app = getApp(src);
    on = ~strcmp(src.Value, 'none');
    app.edRes.Enable = on;
    app.lblRes.Enable = on;
    setApp(app);
end

% ---------------- 数据 ----------------
function app = loadMolecules(app)
    try
        r = app.client.molecules();
        mols = r.molecules;
        items = cell(1, numel(mols));
        ids = cell(1, numel(mols));
        for k = 1:numel(mols)
            items{k} = sprintf('%d %s (%s)', mols(k).id, mols(k).formula, mols(k).name);
            ids{k} = mols(k).id;
        end
        app.molecules = mols;
        app.ddMol.Items = items;
        app.ddMol.ItemsData = ids;
        % 默认选中 CH4
        idx = find([mols.id] == 6, 1);
        if ~isempty(idx), app.ddMol.Value = 6; end
        onMolChanged(app.ddMol, [], app);
        onRefreshTables(app.btnRefresh, []);
    catch e
        app.ddMol.Items = {'后端未连接'};
        setStatus(app, ['加载气体列表失败：' e.message], [0.8 0.1 0.1]);
    end
    setApp(app);
end

function onMolChanged(src, ~, appIn)
    % 可由 loadMolecules 显式传入最新 app（此时 fig.UserData 还是旧快照）
    if nargin >= 3 && ~isempty(appIn)
        app = appIn;
    else
        app = getApp(src);
    end
    M = src.Value;
    if isempty(M) || ~isnumeric(M), return; end
    try
        r = app.client.isotopologues(M);
        iso = r.isotopologues;
        items = cell(1, numel(iso)); ids = cell(1, numel(iso));
        for k = 1:numel(iso)
            items{k} = sprintf('%d %s', iso(k).id, char(iso(k).iso_name));
            ids{k} = iso(k).id;
        end
        app.ddIso.Items = items; app.ddIso.ItemsData = ids;
        app.ddIso.Value = 1;
    catch
    end
    % 自动建议表名
    mols = app.molecules;
    if ~isempty(mols)
        idx = find([mols.id] == M, 1);
        if ~isempty(idx)
            app.edTable.Value = sprintf('%s_%d_%d', mols(idx).formula, M, app.ddIso.Value);
        end
    end
    setApp(app);
end

function onRangeChanged(src, ~)
    app = getApp(src);
    updateWlHint(app);
end

function app = updateWlHint(app)
    try
        n1 = app.edNuMin.Value; n2 = app.edNuMax.Value;
        app.lblWl.Text = sprintf('~%.0f-%.0fnm', 1e7/n2, 1e7/n1);
    catch
    end
    setApp(app);
end

function onRefreshTables(src, ~)
    app = getApp(src);
    try
        r = app.client.tables();
        t = r.tables;
        if isempty(t)
            app.ddTables.Items = {'(无)'}; app.ddTables.ItemsData = {''};
            app.lblTableInfo.Text = '';
        else
            items = cell(1, numel(t)); names = cell(1, numel(t));
            for k = 1:numel(t)
                items{k} = sprintf('%s (%d 线)', t(k).name, t(k).rows);
                names{k} = t(k).name;
            end
            app.ddTables.Items = items; app.ddTables.ItemsData = names;
            app.ddTables.Value = names{end};
            showTableInfo(app, t(end));
        end
    catch e
        setStatus(app, e.message, [0.8 0.1 0.1]);
    end
    setApp(app);
end

function showTableInfo(app, t)
    app.lblTableInfo.Text = sprintf('%.2f ~ %.2f cm-1 (%.0f~%.0f nm)', ...
        t.nu_min, t.nu_max, 1e7/t.nu_max, 1e7/t.nu_min);
end

function onFetch(src, ~)
    app = getApp(src);
    M = app.ddMol.Value; I = app.ddIso.Value;
    numin = app.edNuMin.Value; numax = app.edNuMax.Value;
    tname = app.edTable.Value;
    if isempty(tname)
        uialert(app.fig, '请输入表名', '提示'); return;
    end
    setStatus(app, sprintf('正在从 HITRAN 下载 %s（%d,%d）...', tname, M, I), ...
        [0.8 0.5 0]);
    drawnow;
    try
        r = app.client.fetch(tname, M, I, numin, numax);
        app.tableMeta(tname) = struct('M', M, 'I', I);
        setStatus(app, sprintf('下载完成：%d 条谱线', r.rows));
        onRefreshTables(app.btnRefresh, []);
    catch e
        setStatus(app, e.message, [0.8 0.1 0.1]);
    end
    setApp(app);
end

function onImport(src, ~)
    app = getApp(src);
    [fn, fp] = uigetfile({'*.par;*.data', 'HITRAN 谱线文件 (*.par, *.data)'}, ...
        '选择谱线文件');
    if isequal(fn, 0), return; end
    [~, base, ~] = fileparts(fn);
    dlg = inputdlg('导入后的表名：', '导入', 1, {base});
    if isempty(dlg), return; end
    try
        r = app.client.importPar(fullfile(fp, fn), dlg{1});
        setStatus(app, sprintf('导入完成：%d 条谱线', r.rows));
        onRefreshTables(app.btnRefresh, []);
    catch e
        setStatus(app, e.message, [0.8 0.1 0.1]);
    end
end

% ---------------- 计算与绘图 ----------------
function meta = resolveMeta(app, tname)
    if isKey(app.tableMeta, tname)
        meta = app.tableMeta(tname);
    else
        % 导入的表：从谱线首行推断分子/同位素编号
        r = app.client.lines(tname, [], [], 1);
        ln = r.lines(1);
        mols = app.molecules;
        idx = find(strcmp({mols.formula}, char(ln.molecule)), 1);
        if isempty(idx)
            error('无法确定表 %s 的分子编号，请通过 fetch 创建表', tname);
        end
        meta = struct('M', mols(idx).id, 'I', ln.isotopologue);
        app.tableMeta(tname) = meta;
        setApp(app);
    end
end

function onCalc(src, ~)
    app = getApp(src);
    tname = app.ddTables.Value;
    if isempty(tname), uialert(app.fig, '请先获取或选择数据表', '提示'); return; end
    setStatus(app, '计算中...', [0.8 0.5 0]); drawnow;
    try
        meta = resolveMeta(app, tname);
        conc = app.edConc.Value;
        spec = struct();
        spec.components = struct('table', tname, 'M', meta.M, 'I', meta.I, ...
            'concentration', conc);
        spec.T = app.edT.Value;
        spec.p = app.edP.Value;
        spec.l = app.edL.Value;
        spec.spectrum = app.ddSpec.Value;
        spec.lineshape = app.ddShape.Value;
        spec.numin = app.edNuMin.Value;
        spec.numax = app.edNuMax.Value;
        spec.step = app.edStep.Value;
        if ~strcmp(app.ddInstr.Value, 'none')
            spec.instrument = app.ddInstr.Value;
            spec.resolution = app.edRes.Value;
        end
        r = app.client.spectrum(spec);

        curve = struct('wn', r.wavenumber, 'y', r.values, ...
            'label', sprintf('%s %s T=%.0fK c=%.1e', tname, ...
                app.ddSpec.Items{strcmp(app.ddSpec.ItemsData, spec.spectrum)}, ...
                spec.T, conc), ...
            'table', tname, 'yunit', r.y_unit);
        app.curves{end+1} = curve; %#ok<AGROW>
        setApp(app);
        redrawAll(app);
        setStatus(app, sprintf('计算完成：%d 点', r.n_points));
    catch e
        setStatus(app, e.message, [0.8 0.1 0.1]);
    end
end

function onClear(src, ~)
    app = getApp(src);
    app.curves = {};
    setApp(app);
    % 同步清空光谱与谱线棒状图（含悬停数据）；
    % cla 会重置坐标区边距，显式恢复 Position 保证两图永远对齐
    cla(app.axSpec); title(app.axSpec, '光谱'); grid(app.axSpec, 'on');
    cla(app.axStick); title(app.axStick, '谱线棒状图');
    xlabel(app.axStick, '波数 cm^{-1}'); ylabel(app.axStick, '线强 S');
    set(app.axStick, 'YScale', 'linear');
    app.axStick.UserData = [];
    app.axSpec.Position  = [410 300 740 460];
    app.axStick.Position = [410 40 740 200];
    app.legendLabel.Text = '';
    alignAxes(app);
end

function onSticks(src, ~)
    app = getApp(src);
    tname = app.ddTables.Value;
    if isempty(tname), uialert(app.fig, '请先选择数据表', '提示'); return; end
    try
        r = app.client.lines(tname, app.edNuMin.Value, app.edNuMax.Value, 5000);
        plot_spectrum([], app.axStick, [], [], '', 'cm-1', r.lines);
        alignAxes(app);
        setStatus(app, sprintf('已显示 %d 条谱线（悬停查看详情）', numel(r.lines)));
    catch e
        setStatus(app, e.message, [0.8 0.1 0.1]);
    end
end

function alignAxes(app)
    % 强制两坐标区绘图框（InnerPosition）像素级对齐：
    % InnerPosition 由 Position 与自动边距（刻度标签宽度）共同决定，
    % 故用迭代反馈同时收敛宽度与左沿，并把棒状图横轴范围同步为
    % 当前光谱范围，保证谱线与光谱峰上下严格对位。
    % 先同步横轴范围（刻度标签变化会影响自动边距），再迭代对齐
    if ~isempty(app.curves)
        lim = app.axSpec.XLim;
        if ~isinf(lim(1))
            app.axStick.XLim = lim;
        end
    end
    for iter = 1:3
        drawnow;
        iS = app.axSpec.InnerPosition;
        iK = app.axStick.InnerPosition;
        pK = app.axStick.Position;
        dW = iS(3) - iK(3);
        dL = iS(1) - iK(1);
        if dW == 0 && dL == 0, break; end
        app.axStick.Position = [pK(1) + dL, pK(2), pK(3) + dW, pK(4)];
    end
end

function redrawAll(app)
    cla(app.axSpec); hold(app.axSpec, 'on');
    xunit = app.ddXUnit.Value;
    for k = 1:numel(app.curves)
        c = app.curves{k};
        if strcmp(xunit, 'nm')
            x = 1e7 ./ c.wn;
        else
            x = c.wn;
        end
        plot(app.axSpec, x, c.y, 'LineWidth', 1.2);
    end
    if ~isempty(app.curves)
        ylabel(app.axSpec, sprintf('(%s)', app.curves{end}.yunit));
        % 图例写入右侧固定文本区（行序=绘图顺序=默认色序）
        items = cell(1, numel(app.curves));
        for k = 1:numel(app.curves)
            c = app.curves{k};
            items{k} = sprintf('%d. %s (T=%.0fK)', k, c.table, ...
                str2double(regexp(c.label, 'T=(\d+)K', 'tokens', 'once')));
        end
        app.legendLabel.Text = strjoin(items, newline);
    else
        app.legendLabel.Text = '';
    end
    if strcmp(xunit, 'nm')
        xlabel(app.axSpec, '波长 nm'); set(app.axSpec, 'XDir', 'reverse');
    else
        xlabel(app.axSpec, '波数 cm^{-1}'); set(app.axSpec, 'XDir', 'normal');
    end
    grid(app.axSpec, 'on');
    alignAxes(app);
end

% ---------------- 导出 ----------------
function onExportPNG(src, ~)
    app = getApp(src);
    export_tools('png', app);
end

function onExportCSV(src, ~)
    app = getApp(src);
    export_tools('csv', app);
end

function onExportWS(src, ~)
    % 将全部曲线写入基础工作区变量 hitran_curves
    app = getApp(src);
    if isempty(app.curves)
        uialert(app.fig, '暂无曲线数据，请先计算并绘图', '提示');
        return;
    end
    out = struct('table', {}, 'label', {}, 'yunit', {}, ...
        'wavenumber_cm1', {}, 'wavelength_nm', {}, 'value', {});
    for k = 1:numel(app.curves)
        c = app.curves{k};
        out(k).table = c.table;
        out(k).label = c.label;
        out(k).yunit = c.yunit;
        out(k).wavenumber_cm1 = c.wn(:);
        out(k).wavelength_nm  = 1e7 ./ c.wn(:);
        out(k).value = c.y(:);
    end
    assignin('base', 'hitran_curves', out);
    setStatus(app, sprintf('已导出 %d 条曲线到工作区变量 hitran_curves', ...
        numel(out)));
end
