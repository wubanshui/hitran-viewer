function app = hitran_gui()
% HITRAN_GUI  hitran-viewer MATLAB 主界面
%   依赖：后端服务已启动（默认 http://127.0.0.1:5000）
%   运行：在 MATLAB 中执行 hitran_gui
%
%   功能：fetch HITRAN 数据、吸收系数/透过率/吸收谱计算与绘图、
%   多曲线叠加、谱线棒状图、鼠标悬停显示谱线信息、PNG/CSV 导出。

    fig = uifigure('Name', 'hitran-viewer — 气体吸收线可视化', ...
        'Position', [80 60 1280 780], 'Resize', 'on');

    % ---------------- 应用状态 ----------------
    app = struct();
    app.fig        = fig;
    app.client     = hapi_client('http://127.0.0.1:5000');
    app.molecules  = [];
    app.tableMeta  = containers.Map();   % 表名 -> struct(M, I)
    app.curves     = {};                 % 已绘制曲线 cell of struct
    fig.UserData   = app;

    % ---------------- 左侧面板 ----------------
    pnl = uipanel(fig, 'Position', [10 10 340 760], 'BorderType', 'none');

    % --- 连接区 ---
    grpConn = uipanel(pnl, 'Title', '连接', 'Position', [0 660 340 100]);
    uilabel(grpConn, 'Text', '后端地址', 'Position', [10 40 60 22]);
    app.edServer = uieditfield(grpConn, 'text', ...
        'Value', 'http://127.0.0.1:5000', 'Position', [75 40 155 22]);
    app.btnTest = uibutton(grpConn, 'Text', '测试连接', ...
        'Position', [240 40 90 22], 'ButtonPushedFcn', @onTestConn);
    app.lblStatus = uilabel(grpConn, 'Text', '未连接', ...
        'Position', [10 8 320 22], 'FontColor', [0.6 0.6 0.6]);

    % --- 数据区 ---
    grpData = uipanel(pnl, 'Title', '数据', 'Position', [0 420 340 235]);
    uilabel(grpData, 'Text', '气体', 'Position', [10 178 34 22]);
    app.ddMol = uidropdown(grpData, 'Position', [50 178 130 22], ...
        'Items', {'加载中...'}, 'ItemsData', {0}, ...
        'ValueChangedFcn', @onMolChanged);
    uilabel(grpData, 'Text', '同位素', 'Position', [188 178 46 22]);
    app.ddIso = uidropdown(grpData, 'Position', [236 178 94 22], ...
        'Items', {'1'}, 'ItemsData', {1});

    uilabel(grpData, 'Text', '波数下限 cm-1', 'Position', [10 148 80 22]);
    app.edNuMin = uieditfield(grpData, 'numeric', 'Value', 6040, ...
        'Position', [95 148 65 22], 'ValueChangedFcn', @onRangeChanged);
    uilabel(grpData, 'Text', '上限', 'Position', [168 148 28 22]);
    app.edNuMax = uieditfield(grpData, 'numeric', 'Value', 6060, ...
        'Position', [200 148 65 22], 'ValueChangedFcn', @onRangeChanged);
    app.lblWl = uilabel(grpData, 'Text', '', 'Position', [272 148 60 22], ...
        'FontSize', 10, 'FontColor', [0.3 0.5 0.7]);

    uilabel(grpData, 'Text', '表名', 'Position', [10 118 34 22]);
    app.edTable = uieditfield(grpData, 'text', 'Value', 'CH4_1653', ...
        'Position', [50 118 120 22]);
    app.btnFetch = uibutton(grpData, 'Text', 'Fetch 下载', ...
        'Position', [180 118 90 22], 'ButtonPushedFcn', @onFetch);
    app.btnImport = uibutton(grpData, 'Text', '导入 .par', ...
        'Position', [278 118 52 22], 'ButtonPushedFcn', @onImport);

    uilabel(grpData, 'Text', '本地表', 'Position', [10 88 46 22]);
    app.ddTables = uidropdown(grpData, 'Position', [60 88 200 22], ...
        'Items', {'(刷新)'}, 'ItemsData', {''});
    app.btnRefresh = uibutton(grpData, 'Text', '刷新', ...
        'Position', [268 88 62 22], 'ButtonPushedFcn', @onRefreshTables);

    app.lblTableInfo = uilabel(grpData, 'Text', '', ...
        'Position', [10 58 320 22], 'FontSize', 10, ...
        'FontColor', [0.3 0.5 0.7]);
    app.btnSetKey = uibutton(grpData, 'Text', '设置 API key', ...
        'Position', [10 10 100 22], 'ButtonPushedFcn', @onSetKey);

    % --- 参数区 ---
    grpParam = uipanel(pnl, 'Title', '环境与计算参数', 'Position', [0 215 340 200]);
    uilabel(grpParam, 'Text', '温度 K', 'Position', [10 142 50 22]);
    app.edT = uieditfield(grpParam, 'numeric', 'Value', 296, ...
        'Position', [65 142 60 22]);
    uilabel(grpParam, 'Text', '压力 atm', 'Position', [140 142 60 22]);
    app.edP = uieditfield(grpParam, 'numeric', 'Value', 1, ...
        'Position', [205 142 55 22]);
    uilabel(grpParam, 'Text', '光程 cm', 'Position', [268 142 50 22]);
    app.edL = uieditfield(grpParam, 'numeric', 'Value', 10, ...
        'Position', [318 142 55 22]);

    uilabel(grpParam, 'Text', '浓度(摩尔分数)', 'Position', [10 112 90 22]);
    app.edConc = uieditfield(grpParam, 'numeric', 'Value', 0.01, ...
        'Position', [105 112 70 22]);
    uilabel(grpParam, 'Text', '线型', 'Position', [185 112 30 22]);
    app.ddShape = uidropdown(grpParam, 'Position', [218 112 110 22], ...
        'Items', {'Voigt', 'Lorentz', 'Gaussian(Doppler)', 'HT'}, ...
        'ItemsData', {'voigt', 'lorentz', 'gaussian', 'ht'}, ...
        'Value', 'voigt');

    uilabel(grpParam, 'Text', '网格步长 cm-1', 'Position', [10 82 85 22]);
    app.edStep = uieditfield(grpParam, 'numeric', 'Value', 0.002, ...
        'Position', [100 82 60 22]);
    uilabel(grpParam, 'Text', '仪器函数', 'Position', [170 82 60 22]);
    app.ddInstr = uidropdown(grpParam, 'Position', [235 82 95 22], ...
        'Items', {'none', 'sinc', 'gaussian', 'rectangular', 'triangular'}, ...
        'Value', 'none');
    app.edRes = uieditfield(grpParam, 'numeric', 'Value', 0.1, ...
        'Position', [235 52 60 22], 'Enable', 'off');
    app.lblRes = uilabel(grpParam, 'Text', '分辨率 cm-1', ...
        'Position', [160 52 70 22], 'Enable', 'off');

    uilabel(grpParam, 'Text', '光谱类型', 'Position', [10 22 60 22]);
    app.ddSpec = uidropdown(grpParam, 'Position', [75 22 120 22], ...
        'Items', {'吸收系数', '透过率', '吸收谱'}, ...
        'ItemsData', {'abscoeff', 'transmittance', 'absorption'}, ...
        'Value', 'abscoeff');
    uilabel(grpParam, 'Text', '横轴', 'Position', [205 22 30 22]);
    app.ddXUnit = uidropdown(grpParam, 'Position', [240 22 90 22], ...
        'Items', {'cm-1', 'nm'}, 'Value', 'cm-1');

    % --- 操作区 ---
    grpAct = uipanel(pnl, 'Title', '操作', 'Position', [0 120 340 90]);
    app.btnCalc = uibutton(grpAct, 'Text', '计算并绘图', ...
        'Position', [10 30 110 26], 'ButtonPushedFcn', @onCalc);
    app.btnClear = uibutton(grpAct, 'Text', '清空曲线', ...
        'Position', [130 30 90 26], 'ButtonPushedFcn', @onClear);
    app.btnSticks = uibutton(grpAct, 'Text', '显示谱线', ...
        'Position', [230 30 100 26], 'ButtonPushedFcn', @onSticks);

    % --- 导出区 ---
    grpExp = uipanel(pnl, 'Title', '导出', 'Position', [0 30 340 85]);
    app.btnPNG = uibutton(grpExp, 'Text', '导出 PNG', ...
        'Position', [10 25 100 26], 'ButtonPushedFcn', @onExportPNG);
    app.btnCSV = uibutton(grpExp, 'Text', '导出 CSV', ...
        'Position', [120 25 100 26], 'ButtonPushedFcn', @onExportCSV);

    % ---------------- 右侧绘图区 ----------------
    app.axSpec = uiaxes(fig, 'Position', [380 300 880 460]);
    title(app.axSpec, '光谱'); grid(app.axSpec, 'on');
    app.axStick = uiaxes(fig, 'Position', [380 40 880 200]);
    title(app.axStick, '谱线棒状图');
    xlabel(app.axStick, '波数 cm^{-1}'); ylabel(app.axStick, '线强 S');

    % 悬停提示标签（初始隐藏）
    app.tip = uilabel(fig, 'Text', '', 'Position', [0 0 260 90], ...
        'BackgroundColor', [1 1 0.8], 'Visible', 'off', 'HandleVisibility', 'off');

    fig.UserData = app;
    hover_line_info(fig);        % 注册悬停回调

    % 初始化：加载分子列表
    loadMolecules();
    updateWlHint();
end

% ================================================================
%  回调与辅助函数（嵌套于主函数，共享 app 所在作用域不可行——
%  此处通过 fig.UserData 传递状态）
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

% ---------------- 连接 ----------------
function onTestConn(src, ~)
    app = getApp(src);
    app.client.BaseURL = app.edServer.Value;
    try
        r = app.client.health();
        keyStr = '已配置';
        if ~r.api_key_set, keyStr = '未配置（fetch 可能受限）'; end
        setStatus(app, sprintf('已连接 | HAPI %s | API key: %s', ...
            r.hapi_version, keyStr));
    catch e
        setStatus(app, ['连接失败：' e.message], [0.8 0.1 0.1]);
    end
    setApp(app);
end

function onSetKey(src, ~)
    app = getApp(src);
    dlg = inputdlg('输入 HITRAN API key（hitran.org 个人主页生成）：', ...
        'API key', 1, {''});
    if ~isempty(dlg) && ~isempty(dlg{1})
        try
            app.client.setApiKey(dlg{1});
            setStatus(app, 'API key 已保存');
        catch e
            setStatus(app, e.message, [0.8 0.1 0.1]);
        end
    end
    setApp(app);
end

% ---------------- 数据 ----------------
function loadMolecules()
    f = gcf; app = f.UserData;
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
        onMolChanged(app.ddMol, []);
    catch e
        app.ddMol.Items = {'后端未连接'};
        app.lblStatus.Text = e.message;
    end
    setApp(app);
end

function onMolChanged(src, ~)
    app = getApp(src);
    M = src.Value;
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
    idx = find([mols.id] == M, 1);
    if ~isempty(idx)
        app.edTable.Value = sprintf('%s_%d_%d', mols(idx).formula, M, app.ddIso.Value);
    end
    setApp(app);
end

function onRangeChanged(~, ~)
    updateWlHint();
end

function updateWlHint()
    f = gcf; app = f.UserData;
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
        onRefreshTables(src, []);
        app = getApp(src);
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
        onRefreshTables(src, []);
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
        spec = struct();
        spec.components = struct('table', tname, 'M', meta.M, 'I', meta.I, ...
            'concentration', app.edConc.Value);
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
                spec.T, spec.concentration), ...
            'table', tname, 'yunit', r.y_unit);
        app.curves{end+1} = curve; %#ok<AGROW>
        setApp(app);
        redrawAll();
        setStatus(app, sprintf('计算完成：%d 点', r.n_points));
    catch e
        setStatus(app, e.message, [0.8 0.1 0.1]);
    end
end

function onClear(src, ~)
    app = getApp(src);
    app.curves = {};
    setApp(app);
    cla(app.axSpec); title(app.axSpec, '光谱');
end

function onSticks(src, ~)
    app = getApp(src);
    tname = app.ddTables.Value;
    if isempty(tname), uialert(app.fig, '请先选择数据表', '提示'); return; end
    try
        r = app.client.lines(tname, app.edNuMin.Value, app.edNuMax.Value, 5000);
        plot_spectrum([], app.axStick, [], [], '', 'cm-1', r.lines);
        setStatus(app, sprintf('已显示 %d 条谱线（悬停查看详情）', numel(r.lines)));
    catch e
        setStatus(app, e.message, [0.8 0.1 0.1]);
    end
end

function redrawAll()
    f = gcf; app = f.UserData;
    cla(app.axSpec); hold(app.axSpec, 'on');
    xunit = app.ddXUnit.Value;
    labels = {};
    for k = 1:numel(app.curves)
        c = app.curves{k};
        if strcmp(xunit, 'nm')
            x = 1e7 ./ c.wn;
        else
            x = c.wn;
        end
        plot(app.axSpec, x, c.y, 'LineWidth', 1.2);
        labels{end+1} = c.label; %#ok<AGROW>
    end
    if ~isempty(app.curves)
        ylabel(app.axSpec, sprintf('(%s)', app.curves{end}.yunit));
        legend(app.axSpec, labels, 'Interpreter', 'none', 'Location', 'best');
    end
    if strcmp(xunit, 'nm')
        xlabel(app.axSpec, '波长 nm'); set(app.axSpec, 'XDir', 'reverse');
    else
        xlabel(app.axSpec, '波数 cm^{-1}'); set(app.axSpec, 'XDir', 'normal');
    end
    grid(app.axSpec, 'on');
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
