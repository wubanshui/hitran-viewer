function app = hitran_gui()
% HITRAN_GUI  hitran-viewer MATLAB 主界面（SpectraPlot 风格）
%   参照 spectraplot.com Absorption 工具的交互范式：
%   - 深藏青导航条 + 左侧参数卡片 + 右侧绘图区（白色卡片风格）
%   - ν/λ 双向联动输入（λ(um)=1e4/ν(cm-1)）
%   - Y 轴单位切换 Absorbance/Transmission（前端换算 T=exp(-A)）
%   - SHOW SUM 叠加曲线、曲线图例表格（显隐/删除）
%   - 双 X 轴：下波数 cm-1，上波长 um（反向）
%   保留本工程特色：谱线棒状图、悬停谱线信息、本地表管理、
%   PNG/CSV/工作区导出、后端连接设置。
%
%   依赖：后端服务已启动（默认 http://127.0.0.1:5000）

    NAVY = [0.090 0.110 0.408];      % SpectraPlot 主题色 #171C68
    CARD = [1 1 1];                  % 卡片白
    BG   = [0.91 0.92 0.94];         % 页面浅灰底

    fig = uifigure('Name', 'hitran-viewer · Absorption', ...
        'Position', [60 40 1280 800], 'Resize', 'on', ...
        'AutoResizeChildren', 'off', 'Color', BG);

    % ---------------- 应用状态 ----------------
    app = struct();
    app.fig         = fig;
    app.client      = hapi_client('http://127.0.0.1:5000');
    app.molecules   = [];
    app.tableMeta   = containers.Map();   % 表名 -> struct(M, I)
    app.curves      = {};                 % 曲线 cell of struct（y 恒按 Absorbance 存储）
    app.palette     = [NAVY; 0.42 0.05 0.14; 0.13 0.57 0.64; ...
                       0.85 0.33 0.10; 0.29 0.49 0.20; 0.47 0.32 0.66; ...
                       0.80 0.60 0.10; 0.10 0.42 0.70; 0.70 0.15 0.45; ...
                       0.45 0.45 0.45; 0.00 0.53 0.53; 0.55 0.65 0.15];
    app.selRow      = [];                 % 图例表格当前选中行
    app.rangeGuard  = false;              % ν/λ 联动防递归
    fig.UserData    = app;

    % ---------------- 顶部导航条（深藏青） ----------------
    nav = uipanel(fig, 'Position', [0 760 1280 40], 'BorderType', 'none', ...
        'BackgroundColor', NAVY);
    uilabel(nav, 'Text', 'hitran-viewer', 'Position', [14 9 110 22], ...
        'FontColor', [1 1 1], 'FontWeight', 'bold', 'FontSize', 13);
    uilabel(nav, 'Text', 'Absorption', 'Position', [130 9 90 22], ...
        'FontColor', [0.78 0.82 0.95], 'FontSize', 11);
    app.lblStatus = uilabel(nav, 'Text', '未连接', ...
        'Position', [230 9 860 22], 'FontColor', [0.78 0.82 0.95]);
    app.btnConnSettings = uibutton(nav, 'Text', '设置', ...
        'Position', [1165 7 100 26], 'ButtonPushedFcn', @onConnSettings, ...
        'BackgroundColor', [0.16 0.18 0.52], 'FontColor', [1 1 1]);

    % ---------------- 左侧参数卡片 ----------------
    card = uipanel(fig, 'Position', [10 10 310 740], 'BorderType', 'line', ...
        'BorderWidth', 1, 'BackgroundColor', CARD, ...
        'ForegroundColor', [0.82 0.84 0.87], 'Title', '模拟参数', ...
        'FontSize', 12, 'FontWeight', 'bold');

    rowH = 30;  y = 560;  labW = 88;  fldX = 102;  fldW = 196;
    % 分子
    uilabel(card, 'Text', 'Species', 'Position', [12 y labW 22]);
    app.ddMol = uidropdown(card, 'Position', [fldX y fldW 22], ...
        'Items', {'加载中...'}, 'ItemsData', {0}, ...
        'Tooltip', '目标气体（HITRAN 分子编号 + 化学式 + 名称）', ...
        'ValueChangedFcn', @onMolChanged);
    y = y - rowH;
    % 同位素
    uilabel(card, 'Text', '同位素', 'Position', [12 y labW 22]);
    app.ddIso = uidropdown(card, 'Position', [fldX y fldW 22], ...
        'Items', {'1'}, 'ItemsData', {1}, ...
        'Tooltip', '同位素编号（1=最丰富同位素）');
    y = y - rowH;
    % 温度
    uilabel(card, 'Text', 'T (K)', 'Position', [12 y labW 22]);
    app.edT = uieditfield(card, 'numeric', 'Value', 296, ...
        'Position', [fldX y fldW 22], ...
        'Tooltip', ['气体温度 T（K），影响线强与多普勒展宽；' ...
            '室温≈296；格式：正数']);
    y = y - rowH;
    % 压力
    uilabel(card, 'Text', 'P (atm)', 'Position', [12 y labW 22]);
    app.edP = uieditfield(card, 'numeric', 'Value', 1, ...
        'Position', [fldX y fldW 22], ...
        'Tooltip', ['总压 P（atm），决定碰撞（洛伦兹）展宽；' ...
            '1 atm=101325 Pa；格式：正数']);
    y = y - rowH;
    % 摩尔分数
    app.lblConc = uilabel(card, 'Text', 'χ (摩尔分数)', 'Position', [12 y labW 22]);
    app.edConc = uieditfield(card, 'numeric', 'Value', 0.01, ...
        'Position', [fldX y fldW 22], ...
        'Tooltip', ['目标气体摩尔分数 χ（0~1 无量纲）；' ...
            '1%=0.01，1 ppm=1e-6']);
    y = y - rowH;
    % 光程
    uilabel(card, 'Text', 'L (cm)', 'Position', [12 y labW 22]);
    app.edL = uieditfield(card, 'numeric', 'Value', 10, ...
        'Position', [fldX y fldW 22], ...
        'Tooltip', ['吸收光程 L（cm），A=k·χ·P·L；' ...
            '格式：正数']);
    y = y - rowH - 8;
    % 波数范围
    uilabel(card, 'Text', 'νstart (cm⁻¹)', 'Position', [12 y labW 22]);
    app.edNuMin = uieditfield(card, 'numeric', 'Value', 6040, ...
        'Position', [fldX y fldW 22], ...
        'Tooltip', '光谱范围下限波数 ν（cm⁻¹）；λ(μm)=1e4/ν', ...
        'ValueChangedFcn', @onNuChanged);
    y = y - rowH;
    uilabel(card, 'Text', 'νend (cm⁻¹)', 'Position', [12 y labW 22]);
    app.edNuMax = uieditfield(card, 'numeric', 'Value', 6060, ...
        'Position', [fldX y fldW 22], ...
        'Tooltip', '光谱范围上限波数 ν（cm⁻¹），需大于 νstart', ...
        'ValueChangedFcn', @onNuChanged);
    y = y - rowH;
    uilabel(card, 'Text', 'νstep (cm⁻¹)', 'Position', [12 y labW 22]);
    app.edStep = uieditfield(card, 'numeric', 'Value', 0.002, ...
        'Position', [fldX y fldW 22], ...
        'Tooltip', ['波数网格步长 Δν（cm⁻¹），越小越精细但越慢；' ...
            '建议≤线宽一半']);
    y = y - rowH;
    % 波长范围（与波数联动，只读显示）
    uilabel(card, 'Text', 'λstart (μm)', 'Position', [12 y labW 22], ...
        'FontColor', [0.35 0.40 0.55]);
    app.edWlMin = uieditfield(card, 'numeric', 'Position', [fldX y fldW 22], ...
        'Enable', 'off', 'Tooltip', '与 νend 联动：λ=1e4/ν');
    y = y - rowH;
    uilabel(card, 'Text', 'λend (μm)', 'Position', [12 y labW 22], ...
        'FontColor', [0.35 0.40 0.55]);
    app.edWlMax = uieditfield(card, 'numeric', 'Position', [fldX y fldW 22], ...
        'Enable', 'off', 'Tooltip', '与 νstart 联动：λ=1e4/ν');
    y = y - rowH - 10;
    % 主按钮
    app.btnAdd = uibutton(card, 'Text', 'ADD TO PLOT', ...
        'Position', [12 y fldW + labW 30], 'ButtonPushedFcn', @onAddToPlot, ...
        'BackgroundColor', NAVY, 'FontColor', [1 1 1], ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'Tooltip', '计算并添加到绘图（自动下载所需谱线数据）');
    y = y - rowH - 6;
    % 高级选项
    uilabel(card, 'Text', '线型', 'Position', [12 y labW 22]);
    app.ddShape = uidropdown(card, 'Position', [fldX y fldW 22], ...
        'Items', {'Voigt', 'Lorentz', 'Gaussian(Doppler)', 'HT'}, ...
        'ItemsData', {'voigt', 'lorentz', 'gaussian', 'ht'}, ...
        'Tooltip', ['线型函数：Voigt=常用（碰撞+多普勒卷积）；' ...
            'HT=高速线型（含 Dicke 变窄等效应）'], ...
        'Value', 'voigt');
    y = y - rowH;
    uilabel(card, 'Text', '光谱类型', 'Position', [12 y labW 22]);
    app.ddSpec = uidropdown(card, 'Position', [fldX y fldW 22], ...
        'Items', {'吸收谱 Absorbance', '吸收系数 Absorption coef'}, ...
        'ItemsData', {'absorption', 'abscoeff'}, ...
        'Tooltip', ['吸收谱 A=1-exp(-kL)，可与透过率互换显示；' ...
            '吸收系数 k(ν)（cm⁻¹）不参与单位换算'], ...
        'Value', 'absorption');
    y = y - rowH;
    uilabel(card, 'Text', '仪器函数', 'Position', [12 y labW 22]);
    app.ddInstr = uidropdown(card, 'Position', [fldX y fldW 22], ...
        'Items', {'none', 'sinc', 'gaussian', 'rectangular', 'triangular'}, ...
        'Tooltip', ['仪器函数卷积：none=不卷积；' ...
            'sinc=FT 光谱仪，gaussian=常见激光/光栅仪器'], ...
        'Value', 'none', 'ValueChangedFcn', @onInstrChanged);
    y = y - rowH;
    app.lblRes = uilabel(card, 'Text', '分辨率 (cm⁻¹)', ...
        'Position', [12 y labW 22], 'Enable', 'off');
    app.edRes = uieditfield(card, 'numeric', 'Value', 0.1, ...
        'Position', [fldX y fldW 22], 'Enable', 'off', ...
        'Tooltip', '仪器分辨率（cm⁻¹），仅仪器函数≠none 时生效');

    % ---------------- 数据面板（本地表管理） ----------------
    pnlData = uipanel(fig, 'Position', [10 10 310 150], 'BorderType', 'line', ...
        'BorderWidth', 1, 'BackgroundColor', CARD, ...
        'ForegroundColor', [0.82 0.84 0.87], 'Title', '数据', ...
        'FontSize', 12, 'FontWeight', 'bold');
    uilabel(pnlData, 'Text', '本地表', 'Position', [12 90 50 22]);
    app.ddTables = uidropdown(pnlData, 'Position', [66 90 170 22], ...
        'Items', {'(刷新)'}, 'ItemsData', {''});
    app.btnRefresh = uibutton(pnlData, 'Text', '刷新', ...
        'Position', [244 90 54 22], 'ButtonPushedFcn', @onRefreshTables);
    app.edTable = uieditfield(pnlData, 'text', 'Value', 'CH4_1653', ...
        'Position', [66 58 110 22], ...
        'Tooltip', ['表名：字母/数字/下划线；ADD TO PLOT 自动命名下载，' ...
            '也可手动指定后 Fetch']);
    app.btnFetch = uibutton(pnlData, 'Text', 'Fetch', ...
        'Position', [184 58 52 22], 'ButtonPushedFcn', @onFetch, ...
        'Tooltip', '按当前气体/范围下载谱线到指定表名');
    app.btnImport = uibutton(pnlData, 'Text', '导入.par', ...
        'Position', [244 58 54 22], 'ButtonPushedFcn', @onImport);
    app.lblTableInfo = uilabel(pnlData, 'Text', '', ...
        'Position', [12 26 286 22], 'FontSize', 10, ...
        'FontColor', [0.3 0.5 0.7]);

    % 参数卡片与数据面板衔接：卡片底部到 165
    card.Position = [10 165 310 585];

    % ---------------- 右侧绘图区 ----------------
    % 图下控件行
    ctlY = 726;
    uilabel(fig, 'Text', 'Y Axis', 'Position', [345 ctlY+3 42 22]);
    app.ddYUnit = uidropdown(fig, 'Position', [390 ctlY 130 22], ...
        'Items', {'Absorbance', 'Transmission'}, 'Value', 'Absorbance', ...
        'Tooltip', 'Y 轴单位：前端换算 T=exp(-A)、A=-ln(T)，无需重新计算', ...
        'ValueChangedFcn', @onYUnitChanged);
    app.cbSum = uicheckbox(fig, 'Text', 'SHOW SUM', ...
        'Position', [540 ctlY+2 95 22], ...
        'Tooltip', ['叠加曲线：Absorbance 模式逐点相加 ΣA，' ...
            'Transmission 模式逐点相乘 ΠT（吸收系数曲线不参与）'], ...
        'ValueChangedFcn', @onSumToggled);
    app.cbSticks = uicheckbox(fig, 'Text', '谱线棒状图', ...
        'Position', [650 ctlY+2 100 22], 'Value', true, ...
        'Tooltip', '显示/隐藏当前所选数据表的谱线棒状图', ...
        'ValueChangedFcn', @onSticksToggled);
    uibutton(fig, 'Text', 'CLEAR PLOTS', 'Position', [765 ctlY 100 24], ...
        'ButtonPushedFcn', @onClear);
    uibutton(fig, 'Text', 'SAVE PNG', 'Position', [875 ctlY 88 24], ...
        'ButtonPushedFcn', @onExportPNG);
    uibutton(fig, 'Text', 'SAVE CSV', 'Position', [971 ctlY 88 24], ...
        'ButtonPushedFcn', @onExportCSV);
    uibutton(fig, 'Text', '导入工作区', 'Position', [1067 ctlY 88 24], ...
        'ButtonPushedFcn', @onExportWS, ...
        'Tooltip', '将全部已计算曲线以变量 hitran_curves 写入 MATLAB 基础工作区');

    % 坐标区（像素位置固定，双图严格左右对齐）
    app.axSpec = uiaxes(fig, 'Position', [345 300 920 410]);
    xlabel(app.axSpec, 'Frequency (cm^{-1})');
    ylabel(app.axSpec, 'Absorbance');
    grid(app.axSpec, 'on');
    app = setupUpperWlAxis(app);     % 上轴：波长 μm（反向）

    app.axStick = uiaxes(fig, 'Position', [345 170 920 110]);
    ylabel(app.axStick, '线强 S');

    % 图例表格（SpectraPlot 曲线管理表）
    uilabel(fig, 'Text', '曲线列表', 'Position', [345 146 80 20], ...
        'FontSize', 11, 'FontWeight', 'bold');
    app.tblLegend = uitable(fig, 'Position', [345 10 790 132], ...
        'ColumnName', {'颜色', '分子', '参数', '状态'}, ...
        'ColumnWidth', {60, 110, 480, 90}, 'Data', {}, ...
        'ColumnEditable', [false false false false], ...
        'Tooltip', '点击选中行后，可用右侧按钮隐藏/显示或删除该曲线', ...
        'CellSelectionCallback', @onRowSelected);
    uibutton(fig, 'Text', '显隐', 'Position', [1145 118 120 26], ...
        'ButtonPushedFcn', @onToggleVisible, ...
        'Tooltip', '切换选中曲线的显示/隐藏');
    uibutton(fig, 'Text', '删除', 'Position', [1145 84 120 26], ...
        'ButtonPushedFcn', @onDeleteCurve, ...
        'Tooltip', '删除选中曲线');

    % 悬停提示标签（初始隐藏）
    app.tip = uilabel(fig, 'Text', '', 'Position', [0 0 260 90], ...
        'BackgroundColor', [1 1 0.8], 'Visible', 'off', 'HandleVisibility', 'off');

    % hover_line_info 依赖的横轴单位字段：主 X 轴恒为波数 cm-1
    app.ddXUnit = uidropdown(fig, 'Position', [0 0 1 1], ...
        'Items', {'cm-1', 'nm'}, 'Value', 'cm-1', 'Visible', 'off');

    fig.UserData = app;
    hover_line_info(fig);        % 注册悬停回调

    % 初始化：连接自检 + 加载分子列表 + 波长联动
    % （struct 为值传递，初始化函数需返回最新 app 快照）
    app = autoConnect(app);
    app = loadMolecules(app);
    app = syncRangeFields(app);
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
    if nargin < 3, color = [0.6 0.9 0.6]; end   % 深底上用浅色
    try
        app.lblStatus.Text = txt;
        app.lblStatus.FontColor = color;
        drawnow;
    catch
        fprintf('[status] %s\n', txt);
    end
end

function setStatusErr(app, txt)
    setStatus(app, txt, [1 0.65 0.65]);
end

% ---------------- 双 X 轴（上轴波长 μm，反向，随缩放联动） ----------------
function app = setupUpperWlAxis(app)
    % uiaxes 不提供第二个 X 标尺，叠加透明 axes 实现上侧波长轴：
    % 绘图框与 axSpec 像素对齐，λ=1e4/ν 仿射映射保证刻度上下对位
    ax = app.axSpec;
    app.axWl = axes(app.fig, 'Units', 'pixels', ...
        'Position', ax.Position, ...
        'ActivePositionProperty', 'position', ...
        'Color', 'none', 'Box', 'off', ...
        'XAxisLocation', 'top', 'YColor', 'none', ...
        'XDir', 'reverse', 'FontSize', ax.FontSize, ...
        'PickableParts', 'none');
    xlabel(app.axWl, 'Wavelength (μm)');
    addlistener(ax, 'XLim', 'PostSet', @(~, ~) syncUpperWlAxis(app));
    syncUpperWlAxis(app);
end

function syncUpperWlAxis(app)
    try
        axW = app.axWl;
        axW.Position = app.axSpec.InnerPosition;
        lim = app.axSpec.XLim;
        if ~isfinite(lim(1)) || lim(1) <= 0
            axW.XLim = [0 1];
            axW.XAxis.TickLabels = {};
            return;
        end
        axW.XLim = [1e4 / lim(2), 1e4 / lim(1)];
        t = axW.XAxis.TickValues;
        axW.XAxis.TickLabels = arrayfun(@(v) sprintf('%.5g', v), t, ...
            'UniformOutput', false);
    catch
    end
end

% ---------------- ν ↔ λ 联动（λ(μm) = 1e4/ν(cm⁻¹)） ----------------
function onNuChanged(src, ~)
    app = getApp(src);
    if app.rangeGuard, return; end
    app = syncRangeFields(app);
    setApp(app);
end

function app = syncRangeFields(app)
    try
        app.rangeGuard = true;
        n1 = app.edNuMin.Value; n2 = app.edNuMax.Value;
        app.edWlMin.Value = round(1e4 / n2, 5);   % λstart 对应 νend
        app.edWlMax.Value = round(1e4 / n1, 5);   % λend 对应 νstart
    catch
    end
    app.rangeGuard = false;
    setApp(app);
end

% ---------------- 连接设置（导航条，弹窗按需打开） ----------------
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
            setStatusErr(app, msg);
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
            setStatusErr(app, e.message);
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
    setStatusErr(app, ['后端未连接：' msg0 '（可点右上角"设置"检查）']);
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

% ---------------- 分子与本地表 ----------------
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
        onRefreshTables(app.btnRefresh, [], app);
    catch e
        app.ddMol.Items = {'后端未连接'};
        setStatusErr(app, ['加载气体列表失败：' e.message]);
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
    % SpectraPlot 风格浓度标签：χ[formula]
    mols = app.molecules;
    if ~isempty(mols)
        idx = find([mols.id] == M, 1);
        if ~isempty(idx)
            app.lblConc.Text = sprintf('χ[%s] (摩尔分数)', mols(idx).formula);
        end
    end
    setApp(app);
end

function currentFormula = getFormula(app)
    currentFormula = '';
    mols = app.molecules;
    if isempty(mols), return; end
    idx = find([mols.id] == app.ddMol.Value, 1);
    if ~isempty(idx), currentFormula = char(mols(idx).formula); end
end

function onRefreshTables(src, ~, appIn)
    if nargin >= 3 && ~isempty(appIn)
        app = appIn;
    else
        app = getApp(src);
    end
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
        setStatusErr(app, e.message);
    end
    setApp(app);
end

function showTableInfo(app, t)
    app.lblTableInfo.Text = sprintf('%.2f ~ %.2f cm⁻¹（%.0f~%.0f nm）', ...
        t.nu_min, t.nu_max, 1e7 / t.nu_max, 1e7 / t.nu_min);
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
        [1 0.85 0.5]);
    drawnow;
    try
        r = app.client.fetch(tname, M, I, numin, numax);
        app.tableMeta(tname) = struct('M', M, 'I', I);
        setStatus(app, sprintf('下载完成：%d 条谱线', r.rows));
        onRefreshTables(app.btnRefresh, [], app);
    catch e
        setStatusErr(app, e.message);
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
        onRefreshTables(app.btnRefresh, [], app);
    catch e
        setStatusErr(app, e.message);
    end
end

% ---------------- 计算与绘图（ADD TO PLOT） ----------------
function tname = autoTableName(app)
    f = getFormula(app);
    tname = sprintf('%s_%d_%d', f, round(app.edNuMin.Value), ...
        round(app.edNuMax.Value));
end

function [tname, app] = ensureTable(app, tname, M, I, numin, numax)
    % 本地已有表则直接返回，否则自动从 HITRAN 下载（SpectraPlot 式体验）
    % struct 为值传递，tableMeta 更新必须随 app 返回
    try
        r = app.client.tables();
        names = {r.tables.name};
        if any(strcmp(names, tname))
            return;
        end
    catch
    end
    setStatus(app, sprintf('自动下载谱线数据 %s...', tname), [1 0.85 0.5]);
    drawnow;
    r = app.client.fetch(tname, M, I, numin, numax);
    app.tableMeta(tname) = struct('M', M, 'I', I);
    setStatus(app, sprintf('已下载 %d 条谱线', r.rows));
    setApp(app);
end

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

function onAddToPlot(src, ~)
    app = getApp(src);
    M = app.ddMol.Value; I = app.ddIso.Value;
    numin = app.edNuMin.Value; numax = app.edNuMax.Value;
    if numax <= numin
        uialert(app.fig, 'νend 必须大于 νstart', '提示'); return;
    end
    tname = autoTableName(app);
    setStatus(app, '计算中...', [1 0.85 0.5]); drawnow;
    try
        [tname, app] = ensureTable(app, tname, M, I, numin, numax);
        meta = resolveMeta(app, tname);
        conc = app.edConc.Value;
        T = app.edT.Value; P = app.edP.Value; L = app.edL.Value;
        spec = struct();
        spec.components = struct('table', tname, 'M', meta.M, 'I', meta.I, ...
            'concentration', conc);
        spec.T = T; spec.p = P; spec.l = L;
        spec.spectrum = app.ddSpec.Value;
        spec.lineshape = app.ddShape.Value;
        spec.numin = numin; spec.numax = numax;
        spec.step = app.edStep.Value;
        if ~strcmp(app.ddInstr.Value, 'none')
            spec.instrument = app.ddInstr.Value;
            spec.resolution = app.edRes.Value;
        end

        % 去重：完全相同的参数组合不重复添加（同 SpectraPlot）
        key = sprintf('%s|%g|%g|%g|%g|%g|%g|%s', tname, conc, T, P, L, ...
            numin, numax, spec.spectrum);
        for k = 1:numel(app.curves)
            if isfield(app.curves{k}, 'key') && strcmp(app.curves{k}.key, key)
                setStatus(app, '相同参数的曲线已在图中（去重）');
                return;
            end
        end

        r = app.client.spectrum(spec);
        ci = mod(numel(app.curves), size(app.palette, 1)) + 1;
        f = getFormula(app);
        % 图例格式同 SpectraPlot：CO, HITRAN: χ=0.01, T=300K, P=1atm, L=1cm
        legendTxt = sprintf('%s, HITRAN: χ=%.3g, T=%gK, P=%gatm, L=%gcm', ...
            f, conc, T, P, L);
        curve = struct( ...
            'wn', r.wavenumber, 'y', r.values, 'yunit', r.y_unit, ...
            'stype', spec.spectrum, 'color', app.palette(ci, :), ...
            'visible', true, 'key', key, 'table', tname, ...
            'formula', f, 'legend', legendTxt, 'label', legendTxt);
        app.curves{end+1} = curve;
        setApp(app);
        redrawAll(app);
        if app.cbSticks.Value
            drawSticks(app, tname);
        end
        setStatus(app, sprintf('已添加：%s（%d 点）', legendTxt, r.n_points));
    catch e
        setStatusErr(app, e.message);
    end
end

function drawSticks(app, tname)
    try
        r = app.client.lines(tname, app.edNuMin.Value, app.edNuMax.Value, 5000);
        plot_spectrum([], app.axStick, [], [], '', 'cm-1', r.lines);
        alignAxes(app);
    catch e
        setStatusErr(app, e.message);
    end
end

% ---------------- Y 轴单位切换（前端换算，无需重新计算） ----------------
% 本后端 absorption 定义为 A=1-exp(-kL)，透过率 T=exp(-kL)，
% 故换算关系为 T=1-A、A=1-T（与 SpectraPlot 光深约定 exp(-τ) 不同）。
function onYUnitChanged(src, ~)
    app = getApp(src);
    if isempty(app.curves)
        setApp(app); return;
    end
    hasAbscoeff = false;
    for k = 1:numel(app.curves)
        if strcmp(app.curves{k}.stype, 'abscoeff'), hasAbscoeff = true; end
    end
    redrawAll(app);
    if hasAbscoeff
        setStatus(app, ['已切换 Y 轴；注意：吸收系数曲线不参与换算，' ...
            '仍按原单位显示']);
    end
    setApp(app);
end

% ---------------- SHOW SUM（Absorbance 相加 / Transmission 相乘） ----------------
function onSumToggled(src, ~)
    app = getApp(src);
    redrawAll(app);
    setApp(app);
end

function plotSum(app)
    % 公共网格取第一条可见吸收谱曲线的波数轴，其余线性插值后叠加
    idx = find(cellfun(@(c) strcmp(c.stype, 'absorption') && c.visible, ...
        app.curves));
    if numel(idx) < 2, return; end
    wn = app.curves{idx(1)}.wn;
    trans = strcmp(app.ddYUnit.Value, 'Transmission');
    s = zeros(size(wn));
    if trans, s(:) = 1; end
    for j = idx
        c = app.curves{j};
        v = interp1(c.wn, c.y, wn, 'linear', 'extrap');
        if trans
            s = s .* (1 - v);     % ΠT = Π(1-A)
        else
            s = s + v;            % ΣA
        end
    end
    if trans
        sumName = 'Total Transmission';
    else
        sumName = 'Absorbance Sum';
    end
    plot(app.axSpec, wn, s, 'Color', [0 0.53 0.53], 'LineWidth', 1.6, ...
        'LineStyle', '--', 'DisplayName', sumName);
end

% ---------------- 清空 ----------------
function onClear(src, ~)
    app = getApp(src);
    app.curves = {};
    app.selRow = [];
    app.cbSum.Value = false;
    setApp(app);
    % 同步清空光谱与谱线棒状图（含悬停数据）；
    % cla 会重置坐标区边距，显式恢复 Position 保证两图永远对齐
    cla(app.axSpec); grid(app.axSpec, 'on');
    xlabel(app.axSpec, 'Frequency (cm^{-1})');
    ylabel(app.axSpec, 'Absorbance');
    cla(app.axStick); ylabel(app.axStick, '线强 S');
    set(app.axStick, 'YScale', 'linear');
    app.axStick.UserData = [];
    app.axSpec.Position  = [345 300 920 410];
    app.axStick.Position = [345 170 920 110];
    app.tblLegend.Data = {};
    syncUpperWlAxis(app);
    alignAxes(app);
    setStatus(app, '已清空全部曲线');
end

function onSticksToggled(src, ~)
    app = getApp(src);
    if src.Value
        tname = app.ddTables.Value;
        if isempty(tname)
            setStatusErr(app, '请先选择数据表');
            src.Value = false;
            setApp(app);
            return;
        end
        drawSticks(app, tname);
    else
        cla(app.axStick); ylabel(app.axStick, '线强 S');
        app.axStick.UserData = [];
        setApp(app);
    end
end

% ---------------- 重绘 ----------------
function redrawAll(app)
    cla(app.axSpec); hold(app.axSpec, 'on');
    trans = strcmp(app.ddYUnit.Value, 'Transmission');
    for k = 1:numel(app.curves)
        c = app.curves{k};
        if ~c.visible, continue; end
        y = c.y;
        if strcmp(c.stype, 'absorption')
            if trans, y = 1 - y; end      % A -> T
        end
        plot(app.axSpec, c.wn, y, 'Color', c.color, 'LineWidth', 1.3);
    end
    if app.cbSum.Value
        plotSum(app);
    end
    xlabel(app.axSpec, 'Frequency (cm^{-1})');
    if trans
        ylabel(app.axSpec, 'Transmission');
    else
        ylabel(app.axSpec, 'Absorbance');
    end
    grid(app.axSpec, 'on');
    syncUpperWlAxis(app);       % cla 会重置坐标区属性，重新同步上轴
    updateLegendTable(app);
    alignAxes(app);
    setApp(app);
end

function alignAxes(app)
    % 强制两坐标区绘图框（InnerPosition）像素级对齐：
    % InnerPosition 由 Position 与自动边距（刻度标签宽度）共同决定，
    % 故用迭代反馈同时收敛宽度与左沿，并把棒状图横轴范围同步为
    % 当前光谱范围，保证谱线与光谱峰上下严格对位。
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

% ---------------- 曲线图例表格 ----------------
function updateLegendTable(app)
    n = numel(app.curves);
    data = cell(n, 4);
    for k = 1:n
        c = app.curves{k};
        data{k, 1} = sprintf('#%02X%02X%02X', round(c.color * 255));
        data{k, 2} = c.formula;
        data{k, 3} = c.legend;
        if c.visible
            data{k, 4} = '显示';
        else
            data{k, 4} = '隐藏';
        end
    end
    app.tblLegend.Data = data;
end

function onRowSelected(src, ev)
    fig0 = ancestor(src, 'figure');
    app = fig0.UserData;
    if isempty(ev.Indices)
        app.selRow = [];
    else
        app.selRow = ev.Indices(1, 1);
    end
    setApp(app);
end

function onToggleVisible(src, ~)
    app = getApp(src);
    k = app.selRow;
    if isempty(k) || k > numel(app.curves)
        uialert(app.fig, '请先在曲线列表中点击选择一条曲线', '提示');
        return;
    end
    app.curves{k}.visible = ~app.curves{k}.visible;
    setApp(app);
    redrawAll(app);
end

function onDeleteCurve(src, ~)
    app = getApp(src);
    k = app.selRow;
    if isempty(k) || k > numel(app.curves)
        uialert(app.fig, '请先在曲线列表中点击选择一条曲线', '提示');
        return;
    end
    app.curves(k) = [];
    app.selRow = [];
    setApp(app);
    redrawAll(app);
    setStatus(app, sprintf('已删除曲线，剩余 %d 条', numel(app.curves)));
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
        uialert(app.fig, '暂无曲线数据，请先 ADD TO PLOT', '提示');
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
