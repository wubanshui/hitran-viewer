% TEST_WORKFLOW  hitran-viewer 端到端工作流验证（无 GUI 部分）
%   验证：后端连接、谱线查询、光谱计算、1653 nm 甲烷峰位、棒状图数据。
%   运行：matlab -batch "cd(fileparts(mfilename('fullpath'))); test_workflow"

disp('=== hitran-viewer workflow test ===');

% 1. 语法检查
files = {'hapi_client.m', 'hitran_gui.m', 'plot_spectrum.m', ...
         'hover_line_info.m', 'export_tools.m'};
nErr = 0;
for k = 1:numel(files)
    msgs = checkcode(files{k});
    if isempty(msgs)
        errs = struct([]);
    else
        % checkcode message fields vary by version; detect syntax errors by message text
        isErr = contains({msgs.message}, {'Syntax', 'Invalid expression'}, ...
            'IgnoreCase', true);
        errs = msgs(isErr);
    end
    fprintf('%s: %d 条提示, %d 个错误\n', files{k}, numel(msgs), numel(errs));
    for j = 1:numel(errs)
        fprintf('  L%d %s\n', errs(j).line, errs(j).message);
    end
    nErr = nErr + numel(errs);
end
assert(nErr == 0, '存在语法错误');

% 2. 后端连接
c = hapi_client('http://127.0.0.1:5000');
h = c.health();
fprintf('后端: HAPI %s, data_dir=%s\n', h.hapi_version, char(h.data_dir));

% 3. 分子/同位素元数据
mols = c.molecules().molecules;
assert(~isempty(mols), '分子列表为空');
iso = c.isotopologues(6).isotopologues;
fprintf('CH4 同位素: %d 种\n', numel(iso));

% 4. 谱线查询（1653 nm 附近）
r = c.lines('CH4_1653', 6040, 6060, 10000);
lns = r.lines;
fprintf('CH4_1653 表谱线数: %d\n', numel(lns));
assert(numel(lns) > 100, '谱线数过少');

% 5. 光谱计算与峰位验证
spec = struct();
spec.components = struct('table', 'CH4_1653', 'M', 6, 'I', 1, ...
    'concentration', 0.01);
spec.T = 296; spec.p = 1; spec.l = 10;
spec.spectrum = 'abscoeff'; spec.lineshape = 'voigt';
spec.numin = 6044; spec.numax = 6050; spec.step = 0.002;
s = c.spectrum(spec);
[~, ipk] = max(s.values);
nuPk = s.wavenumber(ipk);
wlPk = 1e7 / nuPk;
fprintf('吸收系数峰: %.4f cm-1 (%.2f nm), k=%.3e cm-1\n', ...
    nuPk, wlPk, s.values(ipk));
assert(abs(nuPk - 6047) < 0.5, '峰位偏离 1653 nm 标准线');

% 6. 透过率计算
spec.spectrum = 'transmittance';
t = c.spectrum(spec);
fprintf('透过率最小值: %.4f\n', min(t.values));

% 7. 棒状图绘图（离屏验证）
fig = figure('Visible', 'off');
ax1 = subplot(2, 1, 1); ax2 = subplot(2, 1, 2);
plot_spectrum(ax1, ax2, s.wavenumber, s.values, 'CH4 abscoeff', 'cm-1', lns);
hover_line_info(fig);
exportgraphics(fig, fullfile(tempdir, 'hitran_viewer_test.png'), ...
    'Resolution', 150);
fprintf('测试图已保存: %s\n', fullfile(tempdir, 'hitran_viewer_test.png'));
close(fig);

disp('=== 全部测试通过 ===');

% 8. GUI 打开测试（运行时验证）
gapp = hitran_gui();
pause(2);
assert(isvalid(gapp.fig), 'GUI 窗口创建失败');
disp('GUI 打开成功');
close(gapp.fig);

