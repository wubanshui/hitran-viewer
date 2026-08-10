% VERIFY_1653NM  1653 nm 甲烷吸收线端到端验证（多气体叠加）
%   工况：296 K、1 atm、光程 100 cm
%   组分：CH4 2 ppm（目标）、H2O 2%、CO2 400 ppm、C2H2 10 ppm、
%         NH3 10 ppm、CO 1 ppm（C2H6 在该波段无 HITRAN 逐线数据）
%   输出：output/verify_1653nm.png、output/verify_1653nm.csv

outdir = fullfile(fileparts(mfilename('fullpath')), '..', 'output');
if ~exist(outdir, 'dir'), mkdir(outdir); end

c = hapi_client('http://127.0.0.1:5000');

% ---------------- 各组分参数 ----------------
gases = struct( ...
    'table',  {'CH4_1653','H2O_1653','CO2_1653','C2H2_1653','NH3_1653','CO_1653'}, ...
    'M',      {6, 1, 2, 26, 11, 5}, ...
    'I',      {1, 1, 1, 1, 1, 1}, ...
    'conc',   {2e-6, 0.02, 4e-4, 1e-5, 1e-5, 1e-6}, ...
    'label',  {'CH4 2ppm','H2O 2%','CO2 400ppm','C2H2 10ppm','NH3 10ppm','CO 1ppm'});

numin = 6044; numax = 6050;
specCommon = struct('T', 296, 'p', 1, 'l', 100, ...
    'spectrum', 'abscoeff', 'lineshape', 'voigt', ...
    'numin', numin, 'numax', numax, 'step', 0.002);

% ---------------- 逐组分计算 ----------------
fig = figure('Visible', 'off', 'Position', [50 50 1000 700]);
ax = axes(fig);
hold(ax, 'on');
colors = lines(numel(gases));
curves = cell(1, numel(gases));

for k = 1:numel(gases)
    spec = specCommon;
    spec.components = struct('table', gases(k).table, 'M', gases(k).M, ...
        'I', gases(k).I, 'concentration', gases(k).conc);
    r = c.spectrum(spec);
    curves{k} = struct('wn', r.wavenumber, 'y', r.values);
    plot(ax, r.wavenumber, r.values, 'Color', colors(k, :), ...
        'LineWidth', 1.2, 'DisplayName', gases(k).label);
    fprintf('%-12s 峰吸收系数 %.3e cm-1\n', gases(k).label, max(r.values));
end

% ---------------- 总和谱 ----------------
wn = curves{1}.wn;
kSum = zeros(size(wn));
for k = 1:numel(curves)
    kSum = kSum + curves{k}.y(1:numel(wn));
end
plot(ax, wn, kSum, 'k-', 'LineWidth', 2, 'DisplayName', '总和谱');

[~, ipk] = max(kSum);
fprintf('\n总和谱峰: %.4f cm-1 (%.2f nm)\n', wn(ipk), 1e7/wn(ipk));

% ---------------- 1653 nm 目标线核对 ----------------
lns = c.lines('CH4_1653', 6046, 6048, 100).lines;
assert(~isempty(lns), '未找到 6047 cm-1 附近 CH4 谱线');
[~, im] = max([lns.sw]);
tgt = lns(im);
fprintf('目标线: %.6f cm-1 (%.2f nm) S=%.3e  上态:%s  下态:%s\n', ...
    tgt.nu, tgt.wl_nm, tgt.sw, char(tgt.global_upper), char(tgt.global_lower));
assert(abs(tgt.nu - 6046.97) < 0.1 || abs(tgt.nu - 6047.0) < 0.5, ...
    '目标线波数与 1653 nm 标准线不符');

xlabel(ax, '波数 cm^{-1}'); ylabel(ax, '吸收系数 cm^{-1}');
title(ax, '1653 nm 甲烷吸收线及干扰气体（296 K, 1 atm, L=100 cm）');
legend(ax, 'Location', 'northeast', 'Interpreter', 'none');
grid(ax, 'on');

% ---------------- 棒状图 ----------------
ax2 = axes(fig, 'Position', [0.13 0.08 0.775 0.2]);
r2 = c.lines('CH4_1653', numin, numax, 5000);
plot_spectrum([], ax2, [], [], '', 'cm-1', r2.lines);

% ---------------- 导出 ----------------
pngFile = fullfile(outdir, 'verify_1653nm.png');
exportgraphics(fig, pngFile, 'Resolution', 200);
fprintf('图已导出: %s\n', pngFile);

T = table(wn(:), 1e7./wn(:), kSum(:), ...
    'VariableNames', {'wavenumber_cm1', 'wavelength_nm', 'abscoeff_cm1'});
csvFile = fullfile(outdir, 'verify_1653nm.csv');
writetable(T, csvFile);
fprintf('数据已导出: %s\n', csvFile);

close(fig);
disp('=== 1653 nm 验证通过 ===');
